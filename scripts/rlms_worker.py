#!/usr/bin/env python3
"""
Deterministic RLMS worker for Superloop.

This worker does not call an LLM directly. It builds a recursive, bounded
analysis tree over context files and emits structured summaries + citations.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, List, Tuple

LINE_SPLIT_THRESHOLD = 400
MAX_CITATIONS_PER_NODE = 8

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


class LimitError(RuntimeError):
    pass


@dataclass
class AnalysisState:
    started_at_monotonic: float
    max_steps: int
    timeout_seconds: int
    step_count: int = 0

    def tick(self) -> None:
        self.step_count += 1
        if self.max_steps > 0 and self.step_count > self.max_steps:
            raise LimitError(f"step limit exceeded ({self.max_steps})")
        elapsed = time.monotonic() - self.started_at_monotonic
        if self.timeout_seconds > 0 and elapsed > self.timeout_seconds:
            raise LimitError(f"timeout exceeded ({self.timeout_seconds}s)")


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def estimate_tokens(char_count: int) -> int:
    if char_count <= 0:
        return 0
    return (char_count + 3) // 4


def load_metadata(metadata_file: str) -> Dict:
    if not metadata_file:
        return {}
    if not os.path.exists(metadata_file):
        return {}
    try:
        with open(metadata_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def load_context_files(context_file_list: str) -> List[str]:
    files: List[str] = []
    seen = set()
    if not os.path.exists(context_file_list):
        return files
    with open(context_file_list, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            candidate = raw.strip()
            if not candidate:
                continue
            if candidate in seen:
                continue
            seen.add(candidate)
            if os.path.isfile(candidate):
                files.append(candidate)
    return files


def empty_signals() -> Dict[str, int]:
    return {name: 0 for name, _ in PATTERNS}


def add_signals(into: Dict[str, int], extra: Dict[str, int]) -> Dict[str, int]:
    for k, v in extra.items():
        into[k] = int(into.get(k, 0)) + int(v)
    return into


def compact_line(text: str, max_len: int = 180) -> str:
    one_line = " ".join(text.strip().split())
    if len(one_line) <= max_len:
        return one_line
    return one_line[: max_len - 3] + "..."


def analyze_leaf(path: str, lines: List[str], start_line: int) -> Dict:
    signals = empty_signals()
    citations: List[Dict] = []

    for offset, line in enumerate(lines):
        line_no = start_line + offset
        for signal_name, pattern in PATTERNS:
            if pattern.search(line):
                signals[signal_name] += 1
                if len(citations) < MAX_CITATIONS_PER_NODE:
                    citations.append(
                        {
                            "path": path,
                            "start_line": line_no,
                            "end_line": line_no,
                            "signal": signal_name,
                            "snippet": compact_line(line),
                        }
                    )

    char_count = sum(len(l) + 1 for l in lines)
    highlights: List[str] = []
    if signals["class"] > 0:
        highlights.append(f"{signals['class']} class declaration(s)")
    if signals["python_def"] > 0 or signals["function"] > 0:
        highlights.append(
            f"{signals['python_def'] + signals['function']} named function definition(s)"
        )
    if signals["todo"] > 0:
        highlights.append(f"{signals['todo']} TODO/FIXME marker(s)")
    if signals["error"] > 0:
        highlights.append(f"{signals['error']} error/failure marker(s)")
    if not highlights:
        highlights.append("No high-signal structural markers in this segment")

    return {
        "path": path,
        "start_line": start_line,
        "end_line": start_line + max(len(lines) - 1, 0),
        "line_count": len(lines),
        "char_count": char_count,
        "signals": signals,
        "highlights": highlights,
        "citations": citations,
        "children": [],
    }


def analyze_segment(
    path: str,
    lines: List[str],
    start_line: int,
    depth: int,
    max_depth: int,
    state: AnalysisState,
) -> Dict:
    state.tick()
    if depth >= max_depth or len(lines) <= LINE_SPLIT_THRESHOLD:
        return analyze_leaf(path, lines, start_line)

    mid = len(lines) // 2
    left = analyze_segment(path, lines[:mid], start_line, depth + 1, max_depth, state)
    right = analyze_segment(
        path, lines[mid:], start_line + mid, depth + 1, max_depth, state
    )

    signals = empty_signals()
    add_signals(signals, left.get("signals", {}))
    add_signals(signals, right.get("signals", {}))
    citations = (left.get("citations", []) + right.get("citations", []))[
        : MAX_CITATIONS_PER_NODE * 2
    ]

    highlights: List[str] = []
    if signals["class"] > 0:
        highlights.append(f"{signals['class']} class declaration(s) in subtree")
    if signals["python_def"] + signals["function"] > 0:
        highlights.append(
            f"{signals['python_def'] + signals['function']} named function definition(s) in subtree"
        )
    if signals["test"] > 0:
        highlights.append(f"{signals['test']} test marker(s) in subtree")
    if not highlights:
        highlights.append("Subtree split for breadth; no dominant marker")

    return {
        "path": path,
        "start_line": start_line,
        "end_line": start_line + max(len(lines) - 1, 0),
        "line_count": len(lines),
        "char_count": left.get("char_count", 0) + right.get("char_count", 0),
        "signals": signals,
        "highlights": highlights,
        "citations": citations,
        "children": [left, right],
    }


def collect_file_summary(tree: Dict) -> Dict:
    return {
        "path": tree.get("path"),
        "line_count": int(tree.get("line_count", 0)),
        "char_count": int(tree.get("char_count", 0)),
        "signals": tree.get("signals", {}),
        "highlights": tree.get("highlights", []),
        "citations": tree.get("citations", [])[:12],
    }


def flatten_citations(file_summaries: List[Dict], max_items: int = 60) -> List[Dict]:
    out: List[Dict] = []
    for fs in file_summaries:
        for c in fs.get("citations", []):
            out.append(c)
            if len(out) >= max_items:
                return out
    return out


def build_global_highlights(signals: Dict[str, int], file_count: int) -> List[str]:
    highlights: List[str] = [f"Processed {file_count} file(s) with recursive segmentation"]
    if signals.get("class", 0) > 0:
        highlights.append(f"Detected {signals['class']} class declaration(s)")
    if signals.get("python_def", 0) + signals.get("function", 0) > 0:
        highlights.append(
            f"Detected {signals.get('python_def', 0) + signals.get('function', 0)} named function definition(s)"
        )
    if signals.get("test", 0) > 0:
        highlights.append(f"Detected {signals['test']} test marker(s)")
    if signals.get("todo", 0) > 0:
        highlights.append(f"Detected {signals['todo']} TODO/FIXME marker(s)")
    if signals.get("error", 0) > 0:
        highlights.append(f"Detected {signals['error']} error/failure marker(s)")
    return highlights


def to_rel(path: str, repo: str) -> str:
    try:
        rel = os.path.relpath(path, repo)
        if not rel.startswith(".."):
            return rel
    except Exception:
        pass
    return path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Superloop RLMS worker")
    p.add_argument("--repo", required=True)
    p.add_argument("--loop-id", required=True)
    p.add_argument("--role", required=True)
    p.add_argument("--iteration", required=True, type=int)
    p.add_argument("--context-file-list", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--max-steps", required=True, type=int)
    p.add_argument("--max-depth", required=True, type=int)
    p.add_argument("--timeout-seconds", required=True, type=int)
    p.add_argument("--require-citations", required=False, default="true")
    p.add_argument("--format", required=False, default="json")
    p.add_argument("--metadata-file", required=False, default="")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    metadata = load_metadata(args.metadata_file)
    files = load_context_files(args.context_file_list)
    rel_files = [to_rel(path, args.repo) for path in files]

    state = AnalysisState(
        started_at_monotonic=time.monotonic(),
        max_steps=max(1, args.max_steps),
        timeout_seconds=max(1, args.timeout_seconds),
    )

    try:
        trees: List[Dict] = []
        total_signals = empty_signals()
        total_lines = 0
        total_chars = 0

        for abs_path, rel_path in zip(files, rel_files):
            with open(abs_path, "r", encoding="utf-8", errors="ignore") as f:
                text = f.read()
            lines = text.splitlines()
            total_lines += len(lines)
            total_chars += len(text)
            tree = analyze_segment(
                rel_path, lines, start_line=1, depth=0, max_depth=max(0, args.max_depth), state=state
            )
            trees.append(tree)
            add_signals(total_signals, tree.get("signals", {}))

        file_summaries = [collect_file_summary(t) for t in trees]
        citations = flatten_citations(file_summaries)
        require_citations = parse_bool(args.require_citations)
        if require_citations and not citations:
            for rel in rel_files[:8]:
                citations.append(
                    {
                        "path": rel,
                        "start_line": 1,
                        "end_line": 1,
                        "signal": "file_reference",
                        "snippet": "Fallback citation generated because no pattern match was found",
                    }
                )

        result = {
            "ok": True,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "format": args.format,
            "limits": {
                "max_steps": args.max_steps,
                "max_depth": args.max_depth,
                "timeout_seconds": args.timeout_seconds,
            },
            "stats": {
                "file_count": len(files),
                "line_count": total_lines,
                "char_count": total_chars,
                "estimated_tokens": estimate_tokens(total_chars),
                "step_count": state.step_count,
            },
            "signals": total_signals,
            "highlights": build_global_highlights(total_signals, len(files)),
            "citations": citations,
            "files": file_summaries,
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
            "stats": {"step_count": state.step_count},
            "metadata": metadata or None,
        }
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 2
    except Exception as exc:  # pragma: no cover - defensive path
        result = {
            "ok": False,
            "generated_at": utc_now(),
            "loop_id": args.loop_id,
            "role": args.role,
            "iteration": args.iteration,
            "error": str(exc),
            "error_code": "worker_failure",
            "stats": {"step_count": state.step_count},
            "metadata": metadata or None,
        }
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=True))
        return 1


if __name__ == "__main__":
    sys.exit(main())
