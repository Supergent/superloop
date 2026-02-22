# Feature: Ops Manager for Superloop + Sprites (Phase 7 Total Visibility)

## Goal
Deliver total visibility across manager and sprite runtime boundaries so operators can trace intent, execution, and escalation end-to-end with deterministic telemetry.

## Scope
- Add runtime heartbeat telemetry and manager ingestion for liveness/process context.
- Add explicit command invocation audit logs for manager-issued control actions.
- Add envelope sequence IDs and monotonic ordering diagnostics for snapshot/event streams.
- Propagate correlation/trace IDs from manager intent through runtime effects and alert dispatch.
- Surface visibility signals in status and runbook flows with transport parity (`local`, `sprite_service`).

## Non-Goals (this iteration)
- Full distributed tracing vendor integration (OTel collectors, SaaS APM coupling).
- Multi-tenant authz, billing, or org-scoped telemetry controls.
- Autonomous remediation policies; this phase is observability-first.
- Replacing existing v1 envelope contracts with breaking schema changes.

## Primary References
- `docs/ops-manager-sprite-integration.md`
- `docs/ops-manager-v0.md`
- `docs/ops-manager-runbook.md`
- `scripts/ops-manager-reconcile.sh`
- `scripts/ops-manager-status.sh`
- `scripts/ops-manager-sprite-service.py`
- `tests/ops-manager-service.bats`
- `tests/ops-manager-observability.bats`

## Architecture
Phase 7 adds a visibility plane across runtime, transport, and manager artifacts:

1. Runtime heartbeat channel:
- Emit periodic heartbeat envelopes with process/runtime metadata.
- Persist heartbeat artifacts under loop-scoped telemetry paths.
- Project heartbeat freshness into manager health/status context.

2. Invocation audit channel:
- Capture structured records for manager-issued control command execution.
- Include command intent, idempotency key, transport mode, and observed outcome.
- Ensure append-only audit logs with stable envelope fields.

3. Ordering and traceability:
- Add per-envelope sequence identifiers for ordering diagnostics.
- Enforce monotonic checks and reason-coded ordering regressions.
- Introduce trace IDs spanning manager intent -> runtime effect -> escalation/dispatch telemetry.

4. Operator surfaces:
- Extend status output with heartbeat freshness, ordering diagnostics, and recent trace links.
- Update runbook procedures for diagnosing partial visibility and transport gaps.
- Keep local and sprite service visibility semantics equivalent.

## Decisions
- Keep all new visibility artifacts file-first and schema-versioned (`v1` additive fields only).
- Treat visibility failures as reason-coded degradations, not silent best-effort drops.
- Maintain fail-open reconcile semantics for non-critical telemetry writes.
- Use deterministic IDs/offsets where possible to preserve replay/debug value.

## Risks / Constraints
- Heartbeat frequency too high can cause noisy telemetry and I/O overhead.
- Sequence enforcement must not falsely flag benign replay/restart scenarios.
- Trace propagation drift across adapters can break cross-artifact correlation.
- Service and local transport implementations must stay behaviorally aligned.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Heartbeat + invocation audit + sequence/trace propagation + operator surfaces + parity tests.
