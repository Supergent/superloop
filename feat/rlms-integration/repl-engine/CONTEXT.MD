# RLMS REPL Engine - Deep Context

## 1. Why this phase exists

The hybrid MVP shipped RLMS trigger wiring, artifacts, and evidence integration, but the worker itself was still deterministic heuristics.

This phase upgrades RLMS into the paper-style execution model:

- Prompt/context stays outside model context in an external environment.
- A root model writes Python code each step.
- That code is executed in a constrained REPL sandbox.
- The code can make bounded sub-LLM CLI calls over context slices.
- Loop stops only when code sets a final value.

This gives Superloop a true long-context inference scaffold instead of a static analyzer.

## 2. What changed

### 2.1 `scripts/rlms_worker.py`

Replaced the heuristic recursive analyzer with a REPL RLMS engine:

1. Loads context files as external state (`CONTEXT` map, `list_files`, `read_file`).
2. Iteratively prompts a root CLI model to emit Python code.
3. Parses and validates code with strict AST rules.
4. Executes code in a restricted sandbox (safe builtins + helper API only).
5. Supports controlled `sub_rlm(prompt, depth=...)` sub-calls.
6. Ends when code calls `set_final(...)`.
7. Emits structured result JSON preserving existing artifact contract (`ok`, `highlights`, `citations`, stats, errors).

### 2.2 `scripts/rlms`

Extended CLI surface to carry root/subcall execution wiring:

- `--root-command-json`
- `--root-args-json`
- `--root-prompt-mode`
- `--subcall-command-json`
- `--subcall-args-json`
- `--subcall-prompt-mode`

Also supports env overrides:

- `SUPERLOOP_RLMS_ROOT_COMMAND_JSON`
- `SUPERLOOP_RLMS_ROOT_ARGS_JSON`
- `SUPERLOOP_RLMS_ROOT_PROMPT_MODE`
- `SUPERLOOP_RLMS_SUBCALL_COMMAND_JSON`
- `SUPERLOOP_RLMS_SUBCALL_ARGS_JSON`
- `SUPERLOOP_RLMS_SUBCALL_PROMPT_MODE`

### 2.3 `src/60-commands.sh`

When RLMS is triggered for a role, Superloop now:

1. Resolves the role runner config (`command/args/fast_args/prompt_mode`).
2. Applies role model + thinking mappings.
3. Converts resolved command vectors to JSON arrays.
4. Passes them to `scripts/rlms` as root/subcall commands.
5. Keeps current policy behavior (`warn_and_continue` vs `fail_role`).

Default behavior: subcall runner inherits root runner unless explicitly overridden by env.

## 3. Sandbox model

The sandbox deliberately limits what generated code can do.

Allowed:

- Safe Python expressions, loops, conditionals, simple function defs.
- Calls to approved helpers and safe builtins.

Blocked:

- `import` / `from ... import ...`
- Attribute access (`obj.attr`)
- Class definitions, `try/except`, with-statements, async constructs
- Dunder names
- Calls to non-allowlisted functions

This is intentionally strict for safety and predictability.

## 4. Helper API exposed to generated code

The root code can use:

- `list_files()`
- `read_file(path, start_line=1, end_line=None)`
- `grep(pattern, path=None, max_matches=80, flags='')`
- `slice_text(text, start=0, end=None)`
- `append_highlight(text)`
- `add_citation(path, start_line, end_line, signal='reference', snippet='')`
- `sub_rlm(prompt, depth=1)`
- `set_final(value)`

`set_final(...)` is the completion signal for the worker.

## 5. Control limits

RLMS is bounded by loop config limits:

- `max_steps`: max root iterations
- `max_depth`: max declared subcall depth
- `timeout_seconds`: hard wall-clock timeout

Worker also enforces derived max subcall count (`max_steps * 2`) and emits structured limit errors.

## 6. Output contract and observability

Worker still writes `result.json` and `summary.md` under RLMS role output dir.

Result includes:

- `ok`
- `loop_id`, `role`, `iteration`
- `highlights`
- `citations`
- `stats` (`step_count`, `subcall_count`, file/token metrics)
- `trace` (recent root/subcall activity)
- `error`, `error_code` on failure

Existing Superloop RLMS integrations (latest artifacts, evidence, events, prompt references) remain unchanged.

## 7. Failure classes

Common failure classes now:

- `missing_root_command`
- `invalid_config`
- `sandbox_violation`
- `model_invocation_failed`
- `limit_exceeded`
- `worker_failure`

Loop behavior after failure is still controlled by `rlms.policy.fail_mode`.

## 8. Test coverage added in this phase

`tests/rlms.bats` now verifies:

1. REPL success path with real worker and mocked root/subcall CLIs.
2. Sandbox rejection path (root emits forbidden import).
3. Subcall depth limit enforcement.

Legacy trigger/fallback/evidence tests remain in place and still pass.

## 9. Operational guidance

- Start with default role-derived root/subcall commands.
- Override root/subcall commands via env only when you need custom routing.
- Keep `max_steps`, `max_depth`, and timeout conservative until behavior is stable for a loop.
- Prefer `warn_and_continue` during rollout; use `fail_role` only where RLMS output is critical.

## 10. Non-goals (still out of scope)

- Async / parallel subcalls
- Deep recursive sub-RLMS trees
- Containerized sandbox isolation
- Model fine-tuning for native recursion

Those are future phases once this REPL engine is validated in production loops.
