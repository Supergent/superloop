# Feature: Delegation Async Fan-Out Runtime

## Goal
Deliver true async child fan-out for delegation waves with bounded concurrency, deterministic parent outcomes, and auditable artifacts/events.

## Scope
- Implement a wave scheduler that executes sibling children concurrently with explicit concurrency caps.
- Support asynchronous completion handling (out-of-order child finishes) without serial join assumptions.
- Remove parallel-mode coercion of `wake_policy=on_child_complete` and implement explicit adaptation semantics in parallel waves.
- Define deterministic aggregation semantics for child outputs despite nondeterministic completion order.
- Enforce timeout/retry/cancel/failure-policy behavior (`warn_and_continue`, `fail_role`, stop-wave semantics) in async mode.
- Extend artifacts/events to expose scheduler lifecycle and per-child state transitions for debugging and operations.
- Expand bats coverage with timing/race-oriented assertions that fail if real concurrency is absent.

## Non-Goals (this iteration)
- Cross-wave speculative execution (wave N+1 cannot start before wave N completion/termination policy).
- Replacing top-level role order (`planner -> implementer -> tester -> reviewer`) or completion gates.
- Introducing a new role type or replacing parent ownership of canonical role artifacts.
- Broad config redesign unrelated to async runtime controls.

## Primary References
- `src/60-commands.sh` - delegation lifecycle, wave execution, adaptation, and policy handling.
- `src/50-events.sh` - event emission and run-summary/timeline rollups.
- `src/20-prompts.sh` - parent prompt injection of delegation status and summaries.
- `schema/config.schema.json` - delegation config contract and bounds.
- `README.md` - user-facing delegation semantics and operational guidance.
- `tests/superloop.bats` - delegation regression + async behavior tests.
- `feat/role-delegation-orchestration/initiation/PLAN.MD` - delivered baseline architecture and constraints.

## Architecture
Delegation remains role-local and bounded, but execution inside each wave shifts to a scheduler-driven async model:
1. Parent loads request and creates wave child tasks.
2. Scheduler dispatches children up to concurrency cap and tracks task state transitions (`pending`, `running`, terminal states).
3. Completion queue feeds parent adaptation hooks when `wake_policy=on_child_complete`, including explicit continue/stop decisions.
4. Wave finalization computes deterministic aggregate output and policy outcomes independent of completion race order.
5. Artifacts/events capture both scheduling details and parent decisions for replay/audit.

Top-level loop invariants and gate authority remain unchanged.

## Decisions
- Keep delegation nested under existing control plane; async fan-out is a runtime enhancement, not a control-plane rewrite.
- Preserve existing config fields where possible and add only minimal async controls (e.g., explicit concurrency cap semantics).
- Treat deterministic aggregation as a hard requirement even when execution order is nondeterministic.
- Require policy outcomes to be machine-auditable in status artifacts and events before rollout.
- Build in phases with test-first acceptance criteria to prevent regressions in existing serial/parallel paths.

## Risks / Constraints
- Race conditions across child status writes and event ordering can break determinism if not isolated.
- Host scheduler variance can make timing tests flaky unless assertions use robust overlap/cap checks.
- Async retries/timeouts/cancellations can create state-machine complexity and hidden edge cases.
- Existing users may depend on current coercion behavior; docs/migration notes must be explicit.

## Phases
- **Phase 1**: Contract and scheduler-state scaffolding (schema/docs/artifact/event model + test harness).
- **Phase 2**: Bounded concurrent wave scheduler with asynchronous completion intake.
- **Phase 3**: Parallel `on_child_complete` adaptation and deterministic output aggregation.
- **Phase 4**: Timeout/retry/cancel/failure-policy state machine hardening.
- **Phase 5**: Stress validation, observability rollups, and rollout docs.
