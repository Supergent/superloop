# Phase 1 - RLMS Hybrid MVP Implementation

## P1.1 Config Contract + Validation
1. [x] Add `rlms` schema definition and loop-level property to `schema/config.schema.json`.
2. [x] Add static validation checks for RLMS ranges/enums in `src/56-validate-static.sh`.
3. [x] Add/adjust config validation tests in `tests/superloop.bats`.

## P1.2 RLMS Executor
1. [x] Create `scripts/rlms` CLI entrypoint with deterministic args and output behavior.
2. [x] Create `scripts/rlms_worker.py` implementing:
   1. [x] Persistent REPL with prompt in environment variable/state.
   2. [x] Recursive sub-call interface with bounded `max_depth`.
   3. [x] Global step/time limits with structured error output.
3. [x] Add a focused test fixture or smoke invocation path for executor behavior.

## P1.3 Runtime Invocation + Prompt Wiring
1. [x] Parse RLMS loop config in `src/60-commands.sh`.
2. [x] Implement hybrid trigger evaluation helper logic in `src/60-commands.sh`.
3. [x] Invoke RLMS pre-role when triggered and store outputs in `.superloop/loops/<id>/rlms/`.
4. [x] Inject RLMS artifact paths into prompts from `src/20-prompts.sh`.

## P1.4 Events + Evidence Integration
1. [x] Add RLMS lifecycle events via `src/50-events.sh` event logging calls from run flow.
2. [x] Include RLMS artifacts in evidence output in `src/10-evidence.sh`.
3. [x] Ensure run summary captures RLMS artifact metadata where relevant.

## P1.5 Regression Coverage
1. [x] Add BATS tests for hybrid trigger behavior in `tests/rlms.bats`.
2. [x] Add BATS tests for RLMS non-fatal fallback behavior in `tests/rlms.bats`.
3. [x] Add BATS tests ensuring RLMS artifacts are present in evidence output.

## P1.V Validation
1. [x] Run targeted BATS suites for touched modules and confirm pass.
2. [x] Run `./scripts/build.sh` and verify generated `superloop.sh` is in sync.
3. [x] Run `./superloop.sh validate --repo .` against updated config/schema.
