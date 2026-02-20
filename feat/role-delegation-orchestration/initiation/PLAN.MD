# Feature: Role-Local Delegation Orchestration

## Goal
Add optional, bounded child-agent delegation inside a role turn while preserving Superloop's deterministic top-level loop and gate model.

## Scope
- Introduce a role-local delegation plane that can decompose and execute bounded subtasks in waves.
- Keep the existing control plane intact: role order, completion gates, and loop lifecycle remain sequential and authoritative.
- Add explicit delegation configuration, including precise wake semantics (`on_child_complete`, `on_wave_complete`) with compatibility for legacy labels.
- Add delegation artifacts and events for full observability and run-summary auditability.
- Deliver an initial pilot path focused on Implementer-role delegation after contract/scaffolding hardening.

## Non-Goals (this iteration)
- Replacing top-level `planner -> implementer -> tester -> reviewer` loop with a parallel swarm.
- Delegating final Reviewer judgment or completion promise authority.
- Changing completion gates (promise/tests/checklists/evidence/approval).
- Forcing delegation on by default.

## Primary References
- `src/60-commands.sh` - role loop execution path and role dispatch boundary.
- `src/20-prompts.sh` - role prompt context injection.
- `src/50-events.sh` - event logging and run-summary artifact metadata.
- `src/30-runner.sh` - runner invocation and lifecycle behavior.
- `schema/config.schema.json` - loop configuration contract.
- `ARCHITECTURE.md` - core architecture constraints and invariants.
- `README.md` - user-facing config documentation and operational guidance.

## Architecture
Superloop will use a two-plane model:

1. Control plane (existing, unchanged invariants):
- Iteration lifecycle, role sequencing, gate evaluation, state persistence, and completion remain deterministic and sequential.

2. Delegation plane (new, role-local):
- Within a role turn, the parent role agent may decompose bounded subtasks and dispatch child executions in one or more waves.
- Wake behavior is explicit:
  - `on_child_complete`: parent can adapt planning after each child completion.
  - `on_wave_complete`: parent resumes after full batch completion.
- Parent remains sole owner of canonical role artifacts (`plan.md`, `implementer.md`, `test-report.md`, `review.md`); child outputs are intermediate inputs.
- Delegation state is persisted under loop-local artifacts and emitted through structured events for auditability.

## Decisions
- Preserve top-level sequencing as the system safety contract; delegation is nested orchestration, not a new top-level scheduler.
- Use explicit naming:
  - `wake_policy=on_child_complete|on_wave_complete`
  - Keep `immediate|after_all` as backward-compatible aliases with deprecation path.
- Default `delegation.enabled=false` to guarantee no behavior change until explicitly enabled.
- Enforce bounded execution via limits (`max_children`, `max_waves`, per-child timeouts, retry policy).
- Require parent-only canonical writes to prevent uncontrolled artifact churn.
- Pilot rollout order:
  - Implementer first,
  - then Tester,
  - then Planner reconnaissance delegation.

## Risks / Constraints
- Merge/conflict risk across child outputs if write boundaries are unclear.
- Cost and runtime expansion if child fan-out is unbounded.
- Non-deterministic churn if parent re-planning is too aggressive.
- Rate-limit interaction with multiple concurrent runner invocations.
- Backward compatibility complexity for legacy wake labels and config defaults.

## Phases
- **Phase 1**: Contract + scaffolding (schema, naming, no-op runtime path, events/artifacts contract, docs/tests baseline).
- **Phase 2**: Implementer pilot (`on_wave_complete`) with bounded child execution and parent aggregation.
- **Phase 3**: Tester pilot (`on_child_complete`) for adaptive failure-focused wave execution.
- **Phase 4**: Planner reconnaissance delegation with read-heavy bounded subtasks.
- **Phase 5**: Hardening, metrics-driven tuning, and default-policy decision.
