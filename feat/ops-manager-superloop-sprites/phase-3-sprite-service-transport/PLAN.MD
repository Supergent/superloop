# Feature: Ops Manager for Superloop + Sprites (Phase 3 Sprite Service Transport)

## Goal
Add a production-shaped service transport between Ops Manager and Sprite runtimes while preserving the existing `v1` snapshot/event contract and control-intent semantics.

## Scope
- Add Sprite-facing service endpoints for snapshot, incremental events, and allowlisted control intents.
- Add manager transport mode support (`local` vs `sprite_service`) with no contract schema drift.
- Add service auth and request signing baseline suitable for internal dogfood operations.
- Add retry/backoff and idempotency handling for control-intent requests.
- Add e2e tests validating service transport parity with local-script transport.

## Non-Goals (this iteration)
- Multi-tenant RBAC and billing controls.
- Replacing manager core lifecycle projection logic from Phase 2.
- Cross-sprite scheduling/packing policy changes.

## Primary References
- `feat/ops-manager-superloop-sprites/initiation/PLAN.MD` - initial architecture and product framing.
- `feat/ops-manager-superloop-sprites/phase-2-manager-core/PLAN.MD` - manager core implementation baseline.
- `schema/ops-manager.contract.schema.json` - transport-invariant envelope contract.
- `scripts/ops-manager-reconcile.sh` - current local reconcile entrypoint.
- `scripts/ops-manager-control.sh` - current control-intent execution path.
- `docs/ops-manager-v0.md` - v0 contract and persisted artifacts.
- `docs/ops-manager-sprite-integration.md` - integration boundary assumptions.

## Architecture
Phase 3 introduces a transport abstraction while preserving manager logic and envelopes:

1. Sprite service adapter:
- Exposes `loop_run_snapshot` and `loop_run_event` envelopes over HTTP.
- Exposes control-intent execution endpoint (`cancel`, `approve`, `reject`) using the same confirmation model.

2. Manager transport layer:
- Selects `local` (existing scripts) or `sprite_service` (HTTP) per loop/runtime target.
- Normalizes responses into existing projection/reconcile/control pipelines.

3. Reliability/security layer:
- Auth token validation and request provenance fields.
- Retry/backoff with bounded attempts and idempotency keys for control requests.
- Structured error envelopes for transport failures.

## Decisions
- Contract parity is mandatory: no `schemaVersion` bump unless payload shape changes.
- Service transport must remain optional; local-script mode remains fallback.
- Control endpoints stay allowlisted and auditable; no arbitrary command execution.
- Dogfood rollout remains one-loop-per-sprite default.

## Risks / Constraints
- Service latency/availability can increase reconcile staleness.
- Control idempotency bugs can create duplicate interventions.
- Auth misconfiguration can cause blocked or unsafe control paths.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + service e2e)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Implement sprite service endpoints, manager transport adapter, auth/retry/idempotency, and tests.
- **Phase 2**: Dogfood hardening and transport observability metrics.
