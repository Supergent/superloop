# Phase 3 - Parallel Waves and Adaptive Wake

## P3.1 Parallel Wave Scheduler (`src/60-commands.sh`, `superloop.sh`)
1. [x] Honor `delegation.dispatch_mode=parallel` without coercing to serial.
2. [x] Execute child tasks concurrently within a wave (bounded by `max_children`).
3. [x] Preserve deterministic parent aggregation: wait for all child jobs, then finalize child status/events/artifacts.
4. [x] Keep serial behavior unchanged when `dispatch_mode=serial`.

## P3.2 Adaptive Wake (`on_child_complete`) (`src/60-commands.sh`, `README.md`)
1. [x] Implement true `on_child_complete` parent adaptation between child completions.
2. [x] Add bounded adaptation pass limits (max replans per wave / per iteration).
3. [x] Persist adaptation decisions as artifacts and events.

## P3.3 Reliability + Policy (`src/60-commands.sh`, `tests/superloop.bats`)
1. [x] Add explicit failure policy mode for child failures (`warn_and_continue` vs `fail_role`).
2. [x] Add retry/backoff policy options for child jobs in parallel mode.
3. [x] Harden concurrent usage/rate-limit interactions for shared runner telemetry files.

## P3.4 Tests and Verification (`tests/superloop.bats`, smoke runs)
1. [x] Add deterministic test proving parallel dispatch behavior in wave execution.
2. [x] Add tests for `on_child_complete` adaptation once implemented.
3. [x] Add regression tests ensuring artifact/event contract remains stable across dispatch modes.

## P3.V Validation
1. [x] Rebuild `superloop.sh`.
2. [x] Run syntax + schema validation.
3. [x] Run smoke proving real parallel child dispatch via near-simultaneous child completion timestamps and `dispatch_mode_effective=parallel`.
4. [x] Update docs + phase notes with rollout caveats.
5. [x] Run smoke proving `on_child_complete` adaptation can stop remaining delegated work and emits adaptation events/artifacts.
6. [x] Run `bats tests/superloop.bats` and confirm delegation + baseline suite pass end-to-end.
