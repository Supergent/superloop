# Feature: Ops Manager for Superloop + Sprites (Phase 4 Dogfood Hardening + Observability)

## Goal
Harden dogfood operations with explicit observability, staleness/health signaling, and operator-facing evidence so loop-run supervision is trustworthy under real internal load.

## Scope
- Add manager observability outputs for runtime health, transport health, ingest lag, and control-intent outcomes.
- Add dogfood guardrails for stale snapshots/events, repeated transport failures, and ambiguous control confirmations.
- Add explicit escalation levels and reason codes suitable for operator triage.
- Add runbook-level operational playbooks for sprite outage, degraded transport, and recovery verification.
- Add tests validating observability parity across `local` and `sprite_service` transports.

## Non-Goals (this iteration)
- Full external telemetry vendor integration (Datadog/Grafana/OpenTelemetry backend lock-in).
- Multi-tenant RBAC, billing, and org-level policy controls.
- Scheduler/packing policy changes beyond one-loop-per-sprite default.
- Autonomous remediation workflows that execute write-side actions without operator intent.

## Primary References
- `feat/ops-manager-superloop-sprites/initiation/PLAN.MD` - initial architecture and rollout assumptions.
- `feat/ops-manager-superloop-sprites/phase-2-manager-core/PLAN.MD` - lifecycle projection + control semantics.
- `feat/ops-manager-superloop-sprites/phase-3-sprite-service-transport/PLAN.MD` - service transport baseline.
- `scripts/ops-manager-reconcile.sh` - ingest/projection entrypoint.
- `scripts/ops-manager-control.sh` - control-intent path and confirmation semantics.
- `docs/ops-manager-v0.md` - contract baseline and artifact model.
- `docs/ops-manager-runbook.md` - operational procedures.

## Architecture
Phase 4 introduces a dedicated observability layer on top of the existing manager runtime:

1. Telemetry capture:
- Emit structured operation records for reconcile/control cycles.
- Track transport attempts, retries, result codes, and latency buckets.
- Track ingest cursor lag and last-seen runtime progress timestamps.

2. Health and SLO projection:
- Compute manager health states (`healthy`, `degraded`, `critical`) from telemetry + lifecycle context.
- Generate machine-readable escalation records with deterministic reason codes.
- Distinguish transport failures from runtime divergence for clearer operator action.

3. Operator surfaces:
- Add script/JSON outputs for concise per-loop operational health snapshots.
- Preserve backward compatibility for existing state and intent artifacts.
- Keep local and sprite-service observability semantics aligned.

## Decisions
- Keep observability artifacts file-first under `.superloop/ops-manager/<loop>/` for deterministic dogfood debugging.
- Introduce health metadata as additive fields to avoid schema-breaking churn.
- Treat ambiguous control confirmations as first-class operational events.
- Prefer explicit reason codes over free-text summaries in machine-consumed outputs.

## Risks / Constraints
- Overly aggressive thresholds can create noisy escalations and operator fatigue.
- Under-sensitive thresholds can hide genuine regressions in runtime/transport behavior.
- Additional telemetry writes can increase I/O overhead in tight reconcile loops.
- Cross-transport parity can drift without fixture-backed tests.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Implement observability artifacts, health projection, reason-coded escalations, docs, and tests.
- **Phase 2**: Dogfood threshold tuning and operator UX hardening from internal feedback.
