# Feature: Ops Manager for Superloop + Sprites (Phase 6 External Alert Sinks)

## Goal
Add operator-configurable external alert sinks so profile drift and health escalations can be pushed out of file artifacts into actionable notification channels.

## Scope
- Introduce sink-agnostic alert dispatch from manager escalation artifacts.
- Add configurable sink routing policy for severity/category mapping.
- Support first sink targets through deterministic adapters (`webhook`, `slack`, `pagerduty_events`).
- Preserve existing file-first artifacts while adding non-blocking delivery telemetry.
- Surface delivery status in operator status output and runbook workflows.

## Non-Goals (this iteration)
- Autonomous remediation actions (dispatch remains notify-only).
- Rich incident management workflows (ack, assign, resolve lifecycles).
- Multi-tenant org-level alert policy management.
- Vendor lock-in SDK dependencies beyond lightweight HTTP adapters.

## Primary References
- `feat/ops-manager-superloop-sprites/phase-5-profile-drift-alerts/PLAN.MD`
- `scripts/ops-manager-reconcile.sh`
- `scripts/ops-manager-status.sh`
- `scripts/ops-manager-control.sh`
- `docs/ops-manager-v0.md`
- `docs/ops-manager-runbook.md`

## Architecture
Phase 6 layers a delivery plane on top of existing escalation generation:

1. Alert dispatch adapter:
- Read newly emitted escalation records and map each to sink payload envelopes.
- Enforce per-sink validation and normalized category/severity fields.
- Record delivery attempts and outcomes as append-only telemetry.

2. Routing and policy:
- Add a versioned alert sink config with enabled sinks, categories, and delivery thresholds.
- Support environment-driven secrets/tokens with fail-closed config validation.
- Keep dispatch idempotent to avoid duplicate notifications on repeated reconcile passes.

3. Operator surfaces:
- Extend status with last alert delivery state and failure reason summary.
- Update runbook with alert outage triage and safe fallback behavior.
- Keep local and sprite_service dispatch semantics aligned.

## Decisions
- Keep alert dispatch advisory-only and side-effect isolated from control intent flows.
- Default delivery behavior is fail-open for reconcile execution, fail-closed for invalid sink configuration.
- Start with HTTP-based adapters to keep portability high and operational overhead low.
- Persist all delivery telemetry under `.superloop/ops-manager/<loop>/telemetry/`.

## Risks / Constraints
- Misconfigured sink credentials/endpoints can create silent notification gaps.
- Alert fanout without deduplication can cause noisy repeats during churn.
- External API rate limits and transient failures can delay notifications.
- Payload schema drift across sink providers can break adapter compatibility.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Implement alert sink config/dispatch, status exposure, docs, and tests.
