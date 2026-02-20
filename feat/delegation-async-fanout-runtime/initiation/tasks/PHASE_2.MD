# Phase 2 - Concurrent Wave Scheduler

## P2.1 Bounded Dispatcher (`src/60-commands.sh`)
1. [ ] Implement a bounded worker scheduler for `dispatch_mode=parallel` that never exceeds configured concurrency cap.
2. [ ] Dispatch additional children as slots free up instead of launching all-at-once without cap.
3. [ ] Keep serial dispatch code path behavior stable and isolated.

## P2.2 Async Completion Intake (`src/60-commands.sh`)
1. [ ] Replace strict serial join assumptions with completion-driven intake.
2. [ ] Record completion metadata per child (started_at, completed_at, attempt_count, terminal_state).
3. [ ] Ensure parent-loop bookkeeping is safe for out-of-order completion events.

## P2.3 Child Isolation and Safety (`src/60-commands.sh`, `src/30-runner.sh`)
1. [ ] Guarantee per-child temp/log/status paths are unique and race-safe under concurrency.
2. [ ] Prevent shared-file clobbering for usage/status writes during concurrent child execution.
3. [ ] Emit explicit scheduler errors when child process tracking metadata is missing/corrupt.

## P2.4 Event and Status Wiring (`src/50-events.sh`, `src/60-commands.sh`)
1. [ ] Emit scheduler-capacity telemetry (active_workers, queued_children, cap) in wave lifecycle events.
2. [ ] Persist wave-level counters for dispatched/completed/failed/cancelled children.
3. [ ] Keep event payloads machine-parseable and stable for run-summary rollups.

## P2.V Validation / Acceptance Tests
1. [ ] New test proves measured overlap between sibling children in parallel mode.
2. [ ] New test proves cap enforcement (`max_children/max_parallel=1` behaves as serial, >1 allows overlap but bounded).
3. [ ] Existing test `run executes delegated children in parallel wave mode` remains green with updated scheduler internals.
4. [ ] `bats tests/superloop.bats` passes delegation-related suite without regressions.
