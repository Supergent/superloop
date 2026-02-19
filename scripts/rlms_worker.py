#!/usr/bin/env python3
"""
Superloop RLMS worker with sandboxed REPL execution.

This worker treats the long context as external state and asks a root model
for Python code in bounded iterations. The generated code runs in a constrained
sandbox with helper APIs for file access, regex scanning, and controlled
sub-LLM CLI calls.
"""

from __future__ import annotations

import argparse
import ast
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from contextlib import redirect_stdout
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

MAX_CITATIONS = 120
MAX_HIGHLIGHTS = 80
MAX_SNIPPET_LEN = 220
MAX_HISTORY_ITEMS = 8
MAX_PROMPT_FILE_LIST = 160
MAX_SUBCALL_PROMPT_CHARS = 120_000


class RLMSWorkerError(RuntimeError):
    """Base class for worker failures."""


class LimitError(RLMSWorkerError):
    """Raised when configured limits are exceeded."""


class SandboxViolation(RLMSWorkerError):
    """Raised when generated code violates sandbox policy."""


class ModelInvocationError(RLMSWorkerError):
    """Raised when root/subcall CLI invocation fails."""


@dataclass
class Document:
    path: str
    text: str
    lines: List[str]

    @property
    def line_count(self) -> int:
        return len(self.lines)

    @property
    def char_count(self) -> int:
        return len(self.text)


@dataclass
class CliConfig:
    command: List[str]
    args: List[str]
    prompt_mode: str
    label: str


@dataclass
class ExecutionState:
    started_at_monotonic: float
    max_steps: int
    max_depth: int
    timeout_seconds: int
    max_subcalls: int
    step_count: int = 0
    subcall_count: int = 0
    history: List[Dict[str, Any]] = field(default_factory=list)

    def elapsed_seconds(self) -> float:
        return time.monotonic() - self.started_at_monotonic

    def check_timeout(self) -> None:
        if self.timeout_seconds > 0 and self.elapsed_seconds() > self.timeout_seconds:
            raise LimitError(f"timeout exceeded ({self.timeout_seconds}s)")

    def tick_step(self) -> None:
        self.step_count += 1
        if self.max_steps > 0 and self.step_count > self.max_steps:
            raise LimitError(f"step limit exceeded ({self.max_steps})")
        self.check_timeout()

    def next_subcall(self, depth: int) -> None:
        if depth < 1:
            raise LimitError("subcall depth must be >= 1")
        if depth > self.max_depth:
            raise LimitError(f"subcall depth exceeded ({depth} > max_depth={self.max_depth})")
        self.subcall_count += 1
        if self.subcall_count > self.max_subcalls:
            raise LimitError(f"subcall limit exceeded ({self.max_subcalls})")
        self.check_timeout()

    def remaining_timeout(self) -> Optional[float]:
        if self.timeout_seconds <= 0:
            return None
        remaining = self.timeout_seconds - self.elapsed_seconds()
        if remaining <= 0:
            raise LimitError(f"timeout exceeded ({self.timeout_seconds}s)")
        # Give subprocess at least one second to start.
        return max(1.0, remaining)


SAFE_BUILTINS: Dict[str, Any] = {
    "len": len,
    "min": min,
    "max": max,
    "sum": sum,
    "sorted": sorted,
    "range": range,
    "enumerate": enumerate,
    "str": str,
    "int": int,
    "float": float,
    "bool": bool,
    "list": list,
    "dict": dict,
    "set": set,
    "tuple": tuple,
    "abs": abs,
    "any": any,
    "all": all,
    "print": print,
}


ALLOWED_AST_NODES: Tuple[type, ...] = (
    ast.Module,
    ast.Expr,
    ast.Assign,
    ast.AugAssign,
    ast.Name,
    ast.Attribute,
    ast.Load,
    ast.Store,
    ast.Constant,
    ast.List,
    ast.Tuple,
    ast.Set,
    ast.Dict,
    ast.Subscript,
    ast.Slice,
    ast.BinOp,
    ast.UnaryOp,
    ast.BoolOp,
    ast.Compare,
    ast.If,
    ast.For,
    ast.While,
    ast.Break,
    ast.Continue,
    ast.Pass,
    ast.Call,
    ast.keyword,
    ast.ListComp,
    ast.SetComp,
    ast.DictComp,
    ast.GeneratorExp,
    ast.comprehension,
    ast.FunctionDef,
    ast.arguments,
    ast.arg,
    ast.Return,
    ast.IfExp,
    ast.JoinedStr,
    ast.FormattedValue,
    ast.Add,
    ast.Sub,
    ast.Mult,
    ast.Div,
    ast.FloorDiv,
    ast.Mod,
    ast.Pow,
    ast.And,
    ast.Or,
    ast.Not,
    ast.UAdd,
    ast.USub,
    ast.Eq,
    ast.NotEq,
    ast.Lt,
    ast.LtE,
    ast.Gt,
    ast.GtE,
    ast.In,
    ast.NotIn,
    ast.Is,
    ast.IsNot,
)


PATTERNS: List[Tuple[str, re.Pattern[str]]] = [
    ("class", re.compile(r"^\s*class\s+[A-Za-z_][A-Za-z0-9_]*")),
    ("python_def", re.compile(r"^\s*def\s+[A-Za-z_][A-Za-z0-9_]*")),
    (
        "function",
        re.compile(
            r"^\s*(?:export\s+)?(?:async\s+)?function\s+[A-Za-z_][A-Za-z0-9_]*"
        ),
    ),
    (
        "arrow_function",
        re.compile(r"^\s*(?:export\s+)?const\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*\("),
    ),
    ("test", re.compile(r"\b(?:describe|it|test)\s*\(")),
    ("todo", re.compile(r"\b(?:TODO|FIXME)\b")),
    ("error", re.compile(r"\b(?:error|fail|exception)\b", re.IGNORECASE)),
]

SAFE_METHOD_CALLS: set[str] = {
    # list-like
    "append",
    "extend",
    "insert",
    "pop",
    "clear",
    "copy",
    "count",
    "index",
    "sort",
    "reverse",
    # dict-like
    "get",
    "keys",
    "values",
    "items",
    "update",
    "setdefault",
    # string-like
    "strip",
    "lstrip",
    "rstrip",
    "split",
    "splitlines",
    "join",
    "replace",
    "lower",
    "upper",
    "startswith",
    "endswith",
    "format",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def estimate_tokens(char_count: int) -> int:
    if char_count <= 0:
        return 0
    return (char_count + 3) // 4


def compact_text(text: str, max_len: int = MAX_SNIPPET_LEN) -> str:
    line = " ".join(str(text).strip().split())
    if len(line) <= max_len:
        return line
    return line[: max_len - 3] + "..."


def load_metadata(metadata_file: str) -> Dict[str, Any]:
    if not metadata_file or not os.path.exists(metadata_file):
        return {}
    try:
        with open(metadata_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def load_context_files(context_file_list: str, repo: str) -> List[Document]:
    docs: List[Document] = []
    seen: set[str] = set()
    if not os.path.exists(context_file_list):
        return docs

    with open(context_file_list, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            candidate = raw.strip()
            if not candidate or candidate in seen:
                continue
            seen.add(candidate)
            if not os.path.isfile(candidate):
                continue

            rel = to_rel(candidate, repo)
            try:
                with open(candidate, "r", encoding="utf-8", errors="ignore") as cf:
                    text = cf.read()
            except Exception:
                text = ""
            docs.append(Document(path=rel, text=text, lines=text.splitlines()))
    return docs


def to_rel(path: str, repo: str) -> str:
    try:
        rel = os.path.relpath(path, repo)
        if not rel.startswith(".."):
            return rel
    except Exception:
        pass
    return path


def parse_json_string_array(name: str, raw: str) -> List[str]:
    if raw is None or raw == "":
        return []
    try:
        value = json.loads(raw)
    except Exception as exc:  # pragma: no cover - defensive
        raise RLMSWorkerError(f"{name} must be valid JSON array: {exc}")
    if not isinstance(value, list):
        raise RLMSWorkerError(f"{name} must be a JSON array")
    out: List[str] = []
    for idx, item in enumerate(value):
        if not isinstance(item, str):
            raise RLMSWorkerError(f"{name}[{idx}] must be a string")
        out.append(item)
    return out


def parse_prompt_mode(raw: str, default: str = "stdin") -> str:
    mode = (raw or default or "stdin").strip().lower()
    if mode not in {"stdin", "file"}:
        return default
    return mode


def expand_placeholders(arg: str, repo: str, prompt_file: str, last_message_file: str) -> str:
    out = arg.replace("{repo}", repo)
    out = out.replace("{prompt_file}", prompt_file)
    out = out.replace("{last_message_file}", last_message_file)
    return out


def invoke_cli(
    cli: CliConfig,
    prompt: str,
    repo: str,
    timeout_seconds: Optional[float],
) -> Dict[str, Any]:
    if not cli.command:
        raise ModelInvocationError(f"{cli.label}: command is empty")

    start = time.monotonic()
    prompt_path = ""
    last_message_path = ""
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as prompt_file:
            prompt_file.write(prompt)
            prompt_path = prompt_file.name

        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as msg_file:
            last_message_path = msg_file.name

        expanded: List[str] = []
        for part in cli.command:
            expanded.append(expand_placeholders(part, repo, prompt_path, last_message_path))
        for part in cli.args:
            expanded.append(expand_placeholders(part, repo, prompt_path, last_message_path))

        run_kwargs: Dict[str, Any] = {
            "cwd": repo,
            "text": True,
            "capture_output": True,
            "timeout": timeout_seconds,
        }
        if cli.prompt_mode == "stdin":
            run_kwargs["input"] = prompt

        proc = subprocess.run(expanded, **run_kwargs)
        duration_ms = int((time.monotonic() - start) * 1000)
        return {
            "ok": proc.returncode == 0,
            "returncode": int(proc.returncode),
            "stdout": proc.stdout or "",
            "stderr": proc.stderr or "",
            "duration_ms": duration_ms,
            "command": expanded,
        }
    except subprocess.TimeoutExpired as exc:
        raise ModelInvocationError(
            f"{cli.label}: command timed out after {int(timeout_seconds or 0)}s"
        ) from exc
    except FileNotFoundError as exc:
        raise ModelInvocationError(f"{cli.label}: command not found: {cli.command[0]}") from exc
    except Exception as exc:  # pragma: no cover - defensive
        raise ModelInvocationError(f"{cli.label}: command failed: {exc}") from exc
    finally:
        try:
            os.unlink(prompt_path)
        except Exception:
            pass
        try:
            os.unlink(last_message_path)
        except Exception:
            pass


def extract_python_code(text: str) -> str:
    raw = text.strip()
    if not raw:
        raise RLMSWorkerError("root model returned empty response")

    fenced = re.findall(r"```(?:python)?\s*(.*?)```", raw, flags=re.IGNORECASE | re.DOTALL)
    if fenced:
        # Favor the longest fenced block.
        block = sorted(fenced, key=len, reverse=True)[0].strip()
        if block:
            return block
    return raw


def normalize_signal(value: Any) -> str:
    text = compact_text(str(value or "reference"), 48)
    if not text:
        return "reference"
    return text


def normalize_citation(raw: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(raw, dict):
        return None
    path = str(raw.get("path") or "").strip()
    if not path:
        return None

    start = raw.get("start_line", raw.get("line", 1))
    end = raw.get("end_line", start)
    try:
        start_i = max(1, int(start))
        end_i = max(start_i, int(end))
    except Exception:
        start_i = 1
        end_i = 1

    snippet = compact_text(str(raw.get("snippet") or ""), MAX_SNIPPET_LEN)
    signal = normalize_signal(raw.get("signal"))

    return {
        "path": path,
        "start_line": start_i,
        "end_line": end_i,
        "signal": signal,
        "snippet": snippet,
    }


def dedupe_citations(items: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen: set[Tuple[str, int, int, str, str]] = set()
    out: List[Dict[str, Any]] = []
    for item in items:
        key = (
            item.get("path", ""),
            int(item.get("start_line", 1)),
            int(item.get("end_line", 1)),
            item.get("signal", "reference"),
            item.get("snippet", ""),
        )
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
        if len(out) >= MAX_CITATIONS:
            break
    return out


def collect_structural_signals(docs: Sequence[Document]) -> Tuple[Dict[str, int], List[Dict[str, Any]]]:
    totals = {name: 0 for name, _ in PATTERNS}
    citations: List[Dict[str, Any]] = []

    for doc in docs:
        for idx, line in enumerate(doc.lines, start=1):
            for signal, pattern in PATTERNS:
                if pattern.search(line):
                    totals[signal] += 1
                    if len(citations) < MAX_CITATIONS:
                        citations.append(
                            {
                                "path": doc.path,
                                "start_line": idx,
                                "end_line": idx,
                                "signal": signal,
                                "snippet": compact_text(line),
                            }
                        )
    return totals, citations


def build_file_summaries(docs: Sequence[Document]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for doc in docs:
        out.append(
            {
                "path": doc.path,
                "line_count": doc.line_count,
                "char_count": doc.char_count,
            }
        )
    return out


def summarize_history(history: Sequence[Dict[str, Any]]) -> str:
    if not history:
        return "(none)"
    rows: List[str] = []
    for item in history[-MAX_HISTORY_ITEMS:]:
        rows.append(
            f"step={item.get('step')} rc={item.get('returncode')} code={compact_text(item.get('code_preview', ''), 120)} stdout={compact_text(item.get('stdout_preview', ''), 120)}"
        )
    return "\n".join(rows)


def build_root_prompt(
    *,
    role: str,
    loop_id: str,
    iteration: int,
    docs: Sequence[Document],
    metadata: Dict[str, Any],
    state: ExecutionState,
) -> str:
    files = docs[:MAX_PROMPT_FILE_LIST]
    file_lines = "\n".join(
        f"- {doc.path} ({doc.line_count} lines, {estimate_tokens(doc.char_count)} est tokens)"
        for doc in files
    )
    if len(docs) > MAX_PROMPT_FILE_LIST:
        file_lines += f"\n- ... ({len(docs) - MAX_PROMPT_FILE_LIST} more files omitted)"

    metadata_line = json.dumps(metadata or {}, ensure_ascii=True)

    return (
        "You are the root model in a recursive language model scaffold.\n"
        "Output only Python code. No prose.\n"
        "\n"
        f"Loop: {loop_id}\n"
        f"Role: {role}\n"
        f"Iteration: {iteration}\n"
        f"Step: {state.step_count}/{state.max_steps}\n"
        f"Elapsed seconds: {state.elapsed_seconds():.2f}\n"
        f"Subcalls used: {state.subcall_count}/{state.max_subcalls}\n"
        f"Max subcall depth: {state.max_depth}\n"
        "\n"
        "Context is external; use helper functions to inspect it.\n"
        "Available helpers:\n"
        "- list_files() -> list[str]\n"
        "- read_file(path, start_line=1, end_line=None) -> str\n"
        "- grep(pattern, path=None, max_matches=80, flags='') -> list[{path,start_line,end_line,signal,snippet}]\n"
        "- slice_text(text, start=0, end=None) -> str\n"
        "- append_highlight(text)\n"
        "- add_citation(path, start_line, end_line, signal='reference', snippet='')\n"
        "- sub_rlm(prompt, depth=1) -> str\n"
        "- set_final(value)  # call this when done\n"
        "\n"
        "Rules:\n"
        "- Do not use import statements.\n"
        "- Do not access files or network directly.\n"
        "- Keep the code compact and deterministic.\n"
        "- If finished, call set_final({...}) with highlights and citations.\n"
        "\n"
        "Current metadata JSON:\n"
        f"{metadata_line}\n"
        "\n"
        "Context file index:\n"
        f"{file_lines if file_lines else '(no files)'}\n"
        "\n"
        "Recent execution history:\n"
        f"{summarize_history(state.history)}\n"
    )


class SandboxEnvironment:
    def __init__(
        self,
        *,
        docs: Sequence[Document],
        state: ExecutionState,
        subcall_cli: CliConfig,
        repo: str,
    ) -> None:
        self.docs_by_path: Dict[str, Document] = {doc.path: doc for doc in docs}
        self.state = state
        self.subcall_cli = subcall_cli
        self.repo = repo

        self.highlights: List[str] = []
        self.citations: List[Dict[str, Any]] = []
        self.final_value: Any = None

        self._bindings: Dict[str, Any] = {
            "CONTEXT": {doc.path: doc.text for doc in docs},
            "list_files": self.list_files,
            "read_file": self.read_file,
            "grep": self.grep,
            "slice_text": self.slice_text,
            "append_highlight": self.append_highlight,
            "add_citation": self.add_citation,
            "sub_rlm": self.sub_rlm,
            "set_final": self.set_final,
        }
        self.locals: Dict[str, Any] = dict(self._bindings)

    def _refresh_bindings(self) -> None:
        for name, value in self._bindings.items():
            self.locals[name] = value

    def list_files(self) -> List[str]:
        self.state.check_timeout()
        return sorted(self.docs_by_path.keys())

    def read_file(self, path: str, start_line: int = 1, end_line: Optional[int] = None) -> str:
        self.state.check_timeout()
        key = str(path)
        doc = self.docs_by_path.get(key)
        if doc is None:
            raise SandboxViolation(f"unknown path in read_file: {key}")

        try:
            start = max(1, int(start_line))
        except Exception:
            start = 1
        if end_line is None:
            end = doc.line_count
        else:
            try:
                end = max(start, int(end_line))
            except Exception:
                end = doc.line_count
        if start > doc.line_count:
            return ""
        return "\n".join(doc.lines[start - 1 : end])

    def grep(
        self,
        pattern: str,
        path: Optional[str] = None,
        max_matches: int = 80,
        flags: str = "",
    ) -> List[Dict[str, Any]]:
        self.state.check_timeout()

        try:
            limit = max(1, int(max_matches))
        except Exception:
            limit = 80
        limit = min(limit, 500)

        flag_value = 0
        if "i" in str(flags):
            flag_value |= re.IGNORECASE
        if "m" in str(flags):
            flag_value |= re.MULTILINE

        try:
            regex = re.compile(str(pattern), flag_value)
        except re.error as exc:
            raise SandboxViolation(f"invalid regex: {exc}") from exc

        if path is None:
            targets = sorted(self.docs_by_path.items(), key=lambda kv: kv[0])
        else:
            doc = self.docs_by_path.get(str(path))
            if doc is None:
                raise SandboxViolation(f"unknown path in grep: {path}")
            targets = [(doc.path, doc)]

        out: List[Dict[str, Any]] = []
        for rel_path, doc in targets:
            for line_no, line in enumerate(doc.lines, start=1):
                if regex.search(line):
                    out.append(
                        {
                            "path": rel_path,
                            "start_line": line_no,
                            "end_line": line_no,
                            "signal": "regex_match",
                            "snippet": compact_text(line),
                        }
                    )
                    if len(out) >= limit:
                        return out
        return out

    def slice_text(self, text: Any, start: int = 0, end: Optional[int] = None) -> str:
        self.state.check_timeout()
        src = str(text)
        try:
            s = int(start)
        except Exception:
            s = 0
        if end is None:
            return src[s:]
        try:
            e = int(end)
        except Exception:
            return src[s:]
        return src[s:e]

    def append_highlight(self, text: Any) -> None:
        value = compact_text(str(text), 240)
        if not value:
            return
        if value not in self.highlights:
            self.highlights.append(value)
        if len(self.highlights) > MAX_HIGHLIGHTS:
            self.highlights = self.highlights[:MAX_HIGHLIGHTS]

    def add_citation(
        self,
        path: Any,
        start_line: Any,
        end_line: Any,
        signal: Any = "reference",
        snippet: Any = "",
    ) -> None:
        citation = normalize_citation(
            {
                "path": str(path),
                "start_line": start_line,
                "end_line": end_line,
                "signal": signal,
                "snippet": snippet,
            }
        )
        if citation is None:
            return

        if citation["path"] not in self.docs_by_path:
            raise SandboxViolation(f"citation path not in context: {citation['path']}")

        self.citations.append(citation)
        if len(self.citations) > MAX_CITATIONS:
            self.citations = self.citations[:MAX_CITATIONS]

    def set_final(self, value: Any) -> None:
        self.final_value = value

    def sub_rlm(self, prompt: Any, depth: int = 1) -> str:
        prompt_text = str(prompt)
        if len(prompt_text) > MAX_SUBCALL_PROMPT_CHARS:
            prompt_text = prompt_text[:MAX_SUBCALL_PROMPT_CHARS]

        self.state.next_subcall(depth)
        timeout = self.state.remaining_timeout()
        response = invoke_cli(self.subcall_cli, prompt_text, self.repo, timeout)

        preview = compact_text(response.get("stdout", ""), 180)
        self.state.history.append(
            {
                "step": self.state.step_count,
                "type": "subcall",
                "returncode": response.get("returncode", -1),
                "duration_ms": response.get("duration_ms", 0),
                "stdout_preview": preview,
            }
        )
        if len(self.state.history) > 200:
            self.state.history = self.state.history[-200:]

        if not response.get("ok"):
            stderr = compact_text(response.get("stderr", ""), 220)
            raise ModelInvocationError(
                f"subcall command failed (rc={response.get('returncode')}): {stderr or 'no stderr'}"
            )
        return response.get("stdout", "").strip()

    def _validate_ast(self, code: str) -> ast.Module:
        try:
            tree = ast.parse(code, mode="exec")
        except SyntaxError as exc:
            raise SandboxViolation(f"syntax error: {exc}") from exc

        parent_map: Dict[ast.AST, ast.AST] = {}
        for parent in ast.walk(tree):
            for child in ast.iter_child_nodes(parent):
                parent_map[child] = parent

        defined_functions = {
            node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)
        }
        allowed_callables = set(SAFE_BUILTINS.keys()) | set(self._bindings.keys()) | defined_functions

        def is_allowed_method_call_target(attr_node: ast.Attribute) -> bool:
            # Allow a narrow subset of non-dunder method calls used for
            # container/string transformations in generated analysis code.
            attr_name = attr_node.attr
            if not attr_name or attr_name.startswith("__"):
                return False
            if attr_name not in SAFE_METHOD_CALLS:
                return False
            base = attr_node.value
            if isinstance(base, ast.Name):
                return not base.id.startswith("__")
            if isinstance(base, ast.Constant):
                return isinstance(base.value, str)
            if isinstance(base, ast.Call):
                # Allow chaining on outputs of approved helpers/safe builtins.
                call_target = base.func
                if isinstance(call_target, ast.Name):
                    return call_target.id in allowed_callables
                return False
            return False

        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom, ast.With, ast.AsyncWith, ast.ClassDef, ast.Lambda, ast.Global, ast.Nonlocal, ast.Delete, ast.Try, ast.Raise, ast.Assert, ast.AsyncFunctionDef, ast.Await, ast.Yield, ast.YieldFrom, ast.Match)):
                raise SandboxViolation(f"node type not allowed: {type(node).__name__}")
            if not isinstance(node, ALLOWED_AST_NODES):
                raise SandboxViolation(f"node type not allowed: {type(node).__name__}")
            if isinstance(node, ast.Attribute):
                parent = parent_map.get(node)
                if not (isinstance(parent, ast.Call) and parent.func is node and is_allowed_method_call_target(node)):
                    raise SandboxViolation("attribute access is not allowed")
            if isinstance(node, ast.Name) and node.id.startswith("__"):
                raise SandboxViolation("dunder names are not allowed")
            if isinstance(node, ast.Call):
                if isinstance(node.func, ast.Name):
                    if node.func.id not in allowed_callables:
                        raise SandboxViolation(f"call target not allowed: {node.func.id}")
                elif isinstance(node.func, ast.Attribute):
                    if not is_allowed_method_call_target(node.func):
                        raise SandboxViolation("method call target not allowed")
                else:
                    raise SandboxViolation("only direct or safe method calls are allowed")
            if isinstance(node, ast.keyword) and node.arg and node.arg.startswith("__"):
                raise SandboxViolation("dunder keyword args are not allowed")

        return tree

    def execute(self, code: str) -> Dict[str, Any]:
        tree = self._validate_ast(code)
        self._refresh_bindings()

        stdout_buffer = io.StringIO()
        with redirect_stdout(stdout_buffer):
            exec(compile(tree, "<rlms-root>", "exec"), {"__builtins__": SAFE_BUILTINS}, self.locals)

        stdout_text = stdout_buffer.getvalue()
        return {
            "stdout": stdout_text,
            "stdout_preview": compact_text(stdout_text, 220),
            "code_preview": compact_text(code, 220),
        }


def merge_highlights(final_value: Any, sandbox_highlights: Sequence[str], fallback_signals: Dict[str, int], file_count: int) -> List[str]:
    out: List[str] = []

    if isinstance(final_value, dict):
        raw = final_value.get("highlights", [])
        if isinstance(raw, list):
            for item in raw:
                value = compact_text(str(item), 240)
                if value and value not in out:
                    out.append(value)

    for item in sandbox_highlights:
        if item and item not in out:
            out.append(item)

    if not out:
        out.append(f"Processed {file_count} file(s) via REPL RLMS")
        if fallback_signals.get("class", 0) > 0:
            out.append(f"Detected {fallback_signals['class']} class declaration(s)")
        if fallback_signals.get("python_def", 0) + fallback_signals.get("function", 0) > 0:
            out.append(
                f"Detected {fallback_signals.get('python_def', 0) + fallback_signals.get('function', 0)} named function definition(s)"
            )

    return out[:MAX_HIGHLIGHTS]


def merge_citations(final_value: Any, sandbox_citations: Sequence[Dict[str, Any]], fallback_citations: Sequence[Dict[str, Any]], require_citations: bool, docs: Sequence[Document]) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []

    if isinstance(final_value, dict):
        raw = final_value.get("citations", [])
        if isinstance(raw, list):
            for item in raw:
                citation = normalize_citation(item)
                if citation is not None:
                    items.append(citation)

    for item in sandbox_citations:
        citation = normalize_citation(item)
        if citation is not None:
            items.append(citation)

    if not items:
        for item in fallback_citations[:MAX_CITATIONS]:
            citation = normalize_citation(item)
            if citation is not None:
                items.append(citation)

    if require_citations and not items:
        for doc in docs[:8]:
            items.append(
                {
                    "path": doc.path,
                    "start_line": 1,
                    "end_line": 1,
                    "signal": "file_reference",
                    "snippet": "Fallback citation generated because no explicit citation was produced",
                }
            )

    return dedupe_citations(items)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Superloop RLMS worker")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--loop-id", required=True)
    parser.add_argument("--role", required=True)
    parser.add_argument("--iteration", required=True, type=int)
    parser.add_argument("--context-file-list", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--max-steps", required=True, type=int)
    parser.add_argument("--max-depth", required=True, type=int)
    parser.add_argument("--timeout-seconds", required=True, type=int)

    parser.add_argument("--root-command-json", required=False, default="[]")
    parser.add_argument("--root-args-json", required=False, default="[]")
    parser.add_argument("--root-prompt-mode", required=False, default="stdin")
    parser.add_argument("--subcall-command-json", required=False, default="[]")
    parser.add_argument("--subcall-args-json", required=False, default="[]")
    parser.add_argument("--subcall-prompt-mode", required=False, default="stdin")

    parser.add_argument("--require-citations", required=False, default="true")
    parser.add_argument("--format", required=False, default="json")
    parser.add_argument("--metadata-file", required=False, default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    metadata = load_metadata(args.metadata_file)
    docs = load_context_files(args.context_file_list, args.repo)

    try:
        root_command = parse_json_string_array("root_command_json", args.root_command_json)
        root_args = parse_json_string_array("root_args_json", args.root_args_json)
        sub_command = parse_json_string_array("subcall_command_json", args.subcall_command_json)
        sub_args = parse_json_string_array("subcall_args_json", args.subcall_args_json)
    except RLMSWorkerError as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "generated_at": utc_now(),
                    "loop_id": args.loop_id,
                    "role": args.role,
                    "iteration": args.iteration,
                    "error": str(exc),
                    "error_code": "invalid_config",
                    "metadata": metadata or None,
                },
                separators=(",", ":"),
                ensure_ascii=True,
            )
        )
        return 2

    root_prompt_mode = parse_prompt_mode(args.root_prompt_mode, "stdin")
    sub_prompt_mode = parse_prompt_mode(args.subcall_prompt_mode, "stdin")

    if not root_command:
        result = {
            "ok": False,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "error": "root command is empty",
            "error_code": "missing_root_command",
            "metadata": metadata or None,
        }
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 2

    if not sub_command:
        sub_command = list(root_command)
    if not sub_args:
        sub_args = list(root_args)

    root_cli = CliConfig(command=root_command, args=root_args, prompt_mode=root_prompt_mode, label="root")
    sub_cli = CliConfig(command=sub_command, args=sub_args, prompt_mode=sub_prompt_mode, label="subcall")

    state = ExecutionState(
        started_at_monotonic=time.monotonic(),
        max_steps=max(1, int(args.max_steps)),
        max_depth=max(1, int(args.max_depth)),
        timeout_seconds=max(1, int(args.timeout_seconds)),
        max_subcalls=max(1, int(args.max_steps) * 2),
    )

    require_citations = parse_bool(args.require_citations)
    total_chars = sum(doc.char_count for doc in docs)
    total_lines = sum(doc.line_count for doc in docs)
    structural_signals, structural_citations = collect_structural_signals(docs)

    sandbox = SandboxEnvironment(docs=docs, state=state, subcall_cli=sub_cli, repo=args.repo)

    try:
        while sandbox.final_value is None:
            state.tick_step()
            prompt = build_root_prompt(
                role=args.role,
                loop_id=args.loop_id,
                iteration=args.iteration,
                docs=docs,
                metadata=metadata,
                state=state,
            )

            response = invoke_cli(root_cli, prompt, args.repo, state.remaining_timeout())
            if not response.get("ok"):
                stderr = compact_text(response.get("stderr", ""), 260)
                raise ModelInvocationError(
                    f"root command failed (rc={response.get('returncode')}): {stderr or 'no stderr'}"
                )

            code = extract_python_code(str(response.get("stdout", "")))
            execution = sandbox.execute(code)

            state.history.append(
                {
                    "step": state.step_count,
                    "type": "root",
                    "returncode": int(response.get("returncode", 0)),
                    "duration_ms": int(response.get("duration_ms", 0)),
                    "code_preview": execution.get("code_preview", ""),
                    "stdout_preview": execution.get("stdout_preview", ""),
                }
            )
            if len(state.history) > 200:
                state.history = state.history[-200:]

            if sandbox.final_value is None and state.step_count >= state.max_steps:
                raise LimitError("final value was not set before max_steps")

        highlights = merge_highlights(sandbox.final_value, sandbox.highlights, structural_signals, len(docs))
        citations = merge_citations(
            sandbox.final_value,
            sandbox.citations,
            structural_citations,
            require_citations,
            docs,
        )

        result: Dict[str, Any] = {
            "ok": True,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "format": args.format,
            "limits": {
                "max_steps": int(args.max_steps),
                "max_depth": int(args.max_depth),
                "timeout_seconds": int(args.timeout_seconds),
                "max_subcalls": state.max_subcalls,
            },
            "stats": {
                "file_count": len(docs),
                "line_count": total_lines,
                "char_count": total_chars,
                "estimated_tokens": estimate_tokens(total_chars),
                "step_count": state.step_count,
                "subcall_count": state.subcall_count,
                "elapsed_seconds": round(state.elapsed_seconds(), 3),
            },
            "signals": structural_signals,
            "highlights": highlights,
            "citations": citations,
            "files": build_file_summaries(docs),
            "trace": state.history[-MAX_HISTORY_ITEMS:],
            "final": sandbox.final_value,
            "metadata": metadata or None,
        }

        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 0
    except LimitError as exc:
        result = {
            "ok": False,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "error": str(exc),
            "error_code": "limit_exceeded",
            "stats": {
                "step_count": state.step_count,
                "subcall_count": state.subcall_count,
                "elapsed_seconds": round(state.elapsed_seconds(), 3),
            },
            "trace": state.history[-MAX_HISTORY_ITEMS:],
            "metadata": metadata or None,
        }
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 2
    except SandboxViolation as exc:
        result = {
            "ok": False,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "error": str(exc),
            "error_code": "sandbox_violation",
            "stats": {
                "step_count": state.step_count,
                "subcall_count": state.subcall_count,
                "elapsed_seconds": round(state.elapsed_seconds(), 3),
            },
            "trace": state.history[-MAX_HISTORY_ITEMS:],
            "metadata": metadata or None,
        }
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 1
    except ModelInvocationError as exc:
        result = {
            "ok": False,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "error": str(exc),
            "error_code": "model_invocation_failed",
            "stats": {
                "step_count": state.step_count,
                "subcall_count": state.subcall_count,
                "elapsed_seconds": round(state.elapsed_seconds(), 3),
            },
            "trace": state.history[-MAX_HISTORY_ITEMS:],
            "metadata": metadata or None,
        }
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 1
    except Exception as exc:  # pragma: no cover - defensive path
        result = {
            "ok": False,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "error": str(exc),
            "error_code": "worker_failure",
            "stats": {
                "step_count": state.step_count,
                "subcall_count": state.subcall_count,
                "elapsed_seconds": round(state.elapsed_seconds(), 3),
            },
            "trace": state.history[-MAX_HISTORY_ITEMS:],
            "metadata": metadata or None,
        }
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 1


if __name__ == "__main__":
    sys.exit(main())
