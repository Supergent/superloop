# Phase 1 - RLMS Hybrid MVP

## P1.0 Deep Context Onboarding
1. [x] Create `feat/rlms-integration/initiation/CONTEXT.MD` with full problem statement, rationale, architecture, constraints, and rollout plan for zero-context engineers.
2. [x] Link `CONTEXT.MD` from `feat/rlms-integration/initiation/PLAN.MD` primary references.

## P1.1 Config + Validation Surface
1. [ ] Add `rlms` configuration block to `schema/config.schema.json` with mode, thresholds, per-role toggles, limits, and output settings.
2. [ ] Extend static validation in `src/56-validate-static.sh` for RLMS field shape/ranges and sensible defaults.
3. [ ] Parse RLMS loop config in `src/60-commands.sh` into runtime variables.

## P1.2 RLMS Executor
1. [ ] Create `scripts/rlms` CLI entrypoint for deterministic invocation from Superloop roles.
2. [ ] Add Python worker module in `scripts/rlms_worker.py` implementing:
   1. [ ] Persistent REPL state with prompt/context variables.
   2. [ ] Bounded recursive sub-call interface with `max_depth`, `max_steps`, and timeout controls.
   3. [ ] Structured JSON output + execution metadata contract.
3. [ ] Ensure executor exits non-zero on hard contract violations and writes diagnostic output for loop logs.

## P1.3 Role Integration
1. [ ] Add RLMS trigger evaluation helper(s) in `src/60-commands.sh` for hybrid mode:
   1. [ ] Auto-threshold checks (line/token/file-count heuristics).
   2. [ ] Role-requested override checks.
2. [ ] Invoke RLMS before role execution when triggered and store artifacts under `.superloop/loops/<loop-id>/rlms/`.
3. [ ] Append RLMS context file paths into role prompts via `src/20-prompts.sh`.
4. [ ] Log RLMS lifecycle events into `events.jsonl` via `src/50-events.sh` helpers.

## P1.4 Evidence + Reporting Integration
1. [ ] Include RLMS artifacts in evidence manifest generation in `src/10-evidence.sh`.
2. [ ] Add RLMS artifact metadata to run summary/timeline paths in `src/50-events.sh` as needed.
3. [ ] Keep completion gating behavior unchanged unless RLMS is explicitly configured as required evidence.

## P1.5 Tests
1. [ ] Add BATS tests for RLMS config validation and defaulting behavior in `tests/superloop.bats` and/or `tests/runner.bats`.
2. [ ] Add BATS tests for hybrid trigger logic (auto on threshold, manual request, force off).
3. [ ] Add BATS tests verifying RLMS artifact emission and non-fatal fallback when RLMS fails.

## P1.V Validation
1. [ ] Run targeted BATS tests for changed areas and confirm they pass.
2. [ ] Run `./scripts/build.sh` and verify generated `superloop.sh` matches sources.
3. [ ] Run `./superloop.sh validate --repo .` against updated schema/config samples.
