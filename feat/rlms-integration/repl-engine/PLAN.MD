# Feature: RLMS REPL Engine (Paper-Style)

## Goal
Upgrade RLMS from deterministic chunk analyzer to a true REPL scaffold where a root model writes code, executes in a constrained sandbox, and makes bounded recursive sub-LLM CLI calls.

## Scope
- Replace `scripts/rlms_worker.py` with REPL loop + sandboxed Python code execution.
- Add root/subcall CLI command plumbing through `scripts/rlms` and `src/60-commands.sh`.
- Ensure role-derived runner commands can be reused for RLMS root and subcalls.
- Preserve RLMS artifact/event/evidence contracts introduced in MVP.
- Add tests for REPL success path, sandbox violation, and subcall invocation.

## Non-Goals (this iteration)
- No async subcall fan-out.
- No model fine-tuning.
- No deep recursion beyond configured depth/call limits.
- No external container runtime; sandbox remains in-process with strict AST + builtins limits.

## Primary References
- `feat/rlms-integration/initiation/CONTEXT.MD`
- `feat/rlms-integration/hybrid-mvp/PLAN.MD`
- `scripts/rlms`
- `scripts/rlms_worker.py`
- `src/60-commands.sh`
- `tests/rlms.bats`

## Architecture
1. `src/60-commands.sh` resolves RLMS root/subcall command vectors.
2. `scripts/rlms` forwards command metadata and limits into worker.
3. Worker root loop asks root LLM for Python code each step.
4. Worker executes code in sandbox with helper API (`list_files`, `read_file`, `grep`, `sub_rlm`, `set_final`).
5. `sub_rlm` invokes sub-LLM CLI calls with depth/call/time caps and structured JSON output.
6. Worker returns `Final` + trace/citations; existing Superloop RLMS artifact plumbing remains.

## Decisions
- Keep `scripts/rlms` as stable orchestrator surface.
- Represent root/subcall commands as JSON arrays to avoid shell injection ambiguity.
- Enforce AST allowlist and block imports, dunder access, and unsafe builtins.
- Keep RLMS failure policy behavior unchanged (`warn_and_continue` vs `fail_role`).

## Risks / Constraints
- CLI model outputs may be non-deterministic and format-noisy.
- Overly strict sandbox may prevent useful generated code; overly loose sandbox is unsafe.
- Role runner argument compatibility with REPL prompting must remain robust.

## Phases
- **Phase 1**: REPL engine implementation + command plumbing + tests.
