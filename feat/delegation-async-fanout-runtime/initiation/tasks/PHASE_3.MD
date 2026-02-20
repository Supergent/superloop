# Phase 3 - Parallel Wake and Deterministic Aggregation

## P3.1 True Parallel `on_child_complete` (`src/60-commands.sh`, `README.md`)
1. [ ] Remove coercion of `wake_policy=on_child_complete` in parallel mode.
2. [ ] Invoke adaptation hook on each child completion while other children may still run.
3. [ ] Bound adaptation frequency to prevent unbounded parent replanning churn.

## P3.2 Parent Decision Semantics (`src/60-commands.sh`)
1. [ ] Define decision contract for continue/stop-wave/stop-delegation in async context.
2. [ ] Ensure stop decisions can cancel queued or in-flight children according to policy.
3. [ ] Persist adaptation decisions with child-completion correlation metadata.

## P3.3 Deterministic Aggregation (`src/60-commands.sh`, `src/20-prompts.sh`)
1. [ ] Define canonical aggregation ordering independent of completion race (e.g., wave index + child id).
2. [ ] Persist both completion order and canonical aggregation order for auditability.
3. [ ] Ensure parent prompt references deterministic summary content across repeated runs.

## P3.4 Artifacts and Events (`src/50-events.sh`, `src/60-commands.sh`)
1. [ ] Emit adaptation start/end events with clear decision payloads in parallel mode.
2. [ ] Add status fields for stopped/cancelled-by-adaptation children.
3. [ ] Keep summary format stable for existing downstream parsing.

## P3.V Validation / Acceptance Tests
1. [ ] New test proves parallel `on_child_complete` no longer coerces to `on_wave_complete`.
2. [ ] New test proves adaptation can stop remaining work deterministically in async waves.
3. [ ] New test proves deterministic summary ordering across repeated runs with intentionally out-of-order child completion.
4. [ ] Existing adaptation tests for serial mode remain green.
