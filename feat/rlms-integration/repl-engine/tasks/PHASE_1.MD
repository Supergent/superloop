# Phase 1 - RLMS REPL Engine Implementation

## P1.1 Worker Engine Rewrite
1. [x] Replace `scripts/rlms_worker.py` heuristic segmentation with REPL loop root-code execution.
2. [x] Implement sandbox guardrails in `scripts/rlms_worker.py` (AST allowlist + blocked imports/attributes/dunder access).
3. [x] Add bounded helper APIs in `scripts/rlms_worker.py` (`list_files`, `read_file`, `grep`, `sub_rlm`, `set_final`, citation/highlight helpers).
4. [x] Preserve RLMS output contract fields (`ok`, highlights/citations, stats/errors) for existing pipeline compatibility.

## P1.2 Command Plumbing
1. [x] Extend `scripts/rlms` to accept root/subcall command vectors and prompt modes.
2. [x] Support environment overrides for root/subcall command vectors in `scripts/rlms`.
3. [x] Update `src/60-commands.sh` to resolve role-derived runner commands and pass them into `scripts/rlms`.
4. [x] Keep RLMS failure policy semantics unchanged (`warn_and_continue` vs `fail_role`).

## P1.3 Regression and New Behavior Tests
1. [x] Keep existing trigger/fallback/evidence RLMS tests green in `tests/rlms.bats`.
2. [x] Add REPL success-path test with mocked root/subcall CLI scripts in `tests/rlms.bats`.
3. [x] Add sandbox violation test (forbidden import) in `tests/rlms.bats`.
4. [x] Add subcall depth-limit enforcement test in `tests/rlms.bats`.

## P1.4 Documentation and Engineer Context
1. [x] Add deep implementation context for this phase in `feat/rlms-integration/repl-engine/CONTEXT.MD`.
2. [x] Update README RLMS section with REPL CLI-command wiring behavior and override knobs.

## P1.V Validation
1. [x] Run `python3 -m py_compile scripts/rlms_worker.py`.
2. [x] Run `bats tests/rlms.bats`.
3. [x] Run `bats tests/superloop.bats`.
4. [x] Run `./scripts/build.sh` and ensure generated `superloop.sh` is updated.
5. [x] Run `./superloop.sh validate --repo .`.
