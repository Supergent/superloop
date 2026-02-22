# Ops Manager Lifecycle State Machine (Loop Run)

## Scope
This is the outer operations lifecycle machine. It manages run-level state from normalized runtime envelopes and does not replace Superloop's internal role orchestration.

## States

1. `unknown`
- No trustworthy runtime signal yet.

2. `running`
- Runtime indicates active execution for target loop.

3. `awaiting_approval`
- Approval gate is pending and run cannot complete without external decision.

4. `complete`
- Completion conditions satisfied and recorded in runtime summary.

5. `stopped`
- Runtime emitted an intentional stop condition (e.g., max iterations, manual stop path).

6. `failed`
- Runtime emitted error/timeout/blocked/rate-limited terminal conditions.

7. `idle`
- Loop has artifacts but no active execution and no terminal completion for current inference window.

## Input Events
- `SNAPSHOT_INGESTED`: `loop_run_snapshot` envelope accepted.
- `EVENT_INGESTED`: `loop_run_event` envelope accepted.
- `CONTROL_INTENT_SENT`: manager issued pause/cancel/approval action.
- `CONTROL_INTENT_CONFIRMED`: runtime artifacts confirm intended effect.
- `DIVERGENCE_DETECTED`: manager observed contradictory signals across sources.

## Transition Mapping (Runtime -> Manager)

### Direct mappings
- pending approval (`approval.status == pending`) -> `awaiting_approval`
- summary completion (`run.summary.completion_ok == true`) -> `complete`
- active state (`state.active == true` and `state.current_loop_id == loop`) -> `running`
- stop event (`loop_stop`, `rate_limit_stop`, `no_progress_stop`) -> `stopped`
- error-like event status (`error`, `timeout`, `blocked`, `rate_limited`) -> `failed`

### Fallback mapping
- none of the above with known artifacts -> `idle`
- no reliable artifacts -> `unknown`

## Guards
- Cursor monotonicity: reject event progression if cursor regresses.
- Loop scope integrity: reject envelopes whose `source.loopId` mismatches manager target.
- Contract version gate: reject unsupported `schemaVersion`.

## Actions
- `projectLifecycle`: compute current state from snapshot/event sequence.
- `recordObservation`: persist envelope + computed state transition.
- `raiseIntervention`: emit operator alert for pending approval, stuck drift, or failure conditions.
- `issueControlIntent`: dispatch cancel/pause/approve actions through approved interface.
- `reconcileAfterControl`: require post-control snapshot/event confirmation.

## Intervention Semantics
- Manager never assumes intent success without runtime confirmation.
- Control intents are modeled as transitions with evidence, not side effects.
- If confirmation does not arrive in time, transition to a manager-local divergence flag and require operator review.

## Divergence Handling
Divergence is raised when state and event signals conflict, for example:
- state says active=false while new iteration events are still arriving
- approval pending but completion marked true

On divergence:
1. Freeze automated control actions for that loop run.
2. Request fresh snapshot + event replay from last stable cursor.
3. Escalate to operator if conflict persists.
