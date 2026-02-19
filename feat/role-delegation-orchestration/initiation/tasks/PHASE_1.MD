# Phase 1 - Delegation Contract and Scaffolding

## P1.1 Delegation Config Contract (`schema/config.schema.json`, `README.md`)
1. [x] Add `loops[].delegation` schema with bounded controls (`enabled`, `roles`, `dispatch_mode`, `wake_policy`, `max_children`, `max_waves`, `child_timeout_seconds`, `retry_limit`).
2. [x] Add explicit enum values for `wake_policy`: `on_child_complete` and `on_wave_complete`.
3. [x] Add compatibility handling in schema/docs for legacy labels (`immediate`, `after_all`) with deprecation note.
4. [x] Document default behavior: delegation disabled, existing sequential loop behavior unchanged unless enabled.

## P1.2 Runtime Scaffolding (`src/60-commands.sh`, `src/30-runner.sh`, `superloop.sh`)
1. [x] Add a delegation decision boundary at role-turn start before `run_role` dispatch in `src/60-commands.sh`.
2. [x] Implement no-op fallback path so role execution remains identical when `delegation.enabled=false`.
3. [x] Define role eligibility guardrails (initially permit Implementer pilot only; others remain sequential).
4. [x] Ensure compatibility path normalizes legacy wake labels to new internal values before execution.

## P1.3 Artifact and Event Contract (`src/50-events.sh`, `src/20-prompts.sh`, `README.md`)
1. [x] Define loop-local delegation artifact paths under `.superloop/loops/<loop-id>/delegation/iter-<n>/`.
2. [x] Add structured events for delegation lifecycle (`delegation_wave_start`, `delegation_child_start`, `delegation_child_end`, `delegation_wave_end`).
3. [x] Extend run-summary artifact metadata to include delegation status/index artifacts when present.
4. [x] Wire delegation summaries into parent role prompt context without changing canonical artifact ownership.

## P1.4 Test Baseline and Safety Proof (`tests/*.bats`, `tests/e2e/*.bats`)
1. [x] Add tests verifying default-off delegation produces unchanged sequential behavior and gate outcomes.
2. [x] Add tests validating config normalization for legacy wake labels and new explicit wake policy labels.
3. [x] Add tests verifying delegation event/artifact emission in dry-run or mock-mode scaffolding path.
4. [x] Add regression tests ensuring Reviewer remains non-delegated in Phase 1.

## P1.V Validation
1. [x] Run static validation for schema and script health (including `superloop.sh validate --repo <repo>`).
2. [x] Run targeted unit/bats coverage for new config normalization and event/artifact contract.
3. [x] Run at least one full-loop e2e with delegation disabled and confirm output parity with baseline gates.
4. [x] Confirm docs consistency (`README.md`, `ARCHITECTURE.md`, feature `PLAN.MD`/`PHASE_1.MD`) and no contradictory mode naming remains.

## Completion Notes
1. Validation used `bash -n`, `jq empty`, `superloop.sh validate`, and mock-runner e2e smoke runs.
2. `bats` CLI is not installed in this environment; tests were added/updated and equivalent smoke behavior was executed manually.
