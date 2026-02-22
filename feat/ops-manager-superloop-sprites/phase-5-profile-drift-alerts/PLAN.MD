# Feature: Ops Manager for Superloop + Sprites (Phase 5 Profile Drift Alerts)

## Goal
Introduce automated profile-drift detection so ops policy and observed runtime behavior stay aligned across sustained dogfood operation.

## Scope
- Detect mismatch between applied threshold profile and telemetry-recommended profile.
- Add confidence-gated streak logic before raising drift alerts to reduce noise.
- Persist profile-drift state/history in deterministic manager artifact paths.
- Emit reason-coded escalations when drift becomes active.
- Surface drift state and operator guidance in status output.

## Non-Goals (this iteration)
- Autonomous profile switching without operator control.
- External alerting integrations (Slack/PagerDuty/email).
- Multi-loop global policy optimization.

## Primary References
- `feat/ops-manager-superloop-sprites/phase-4-dogfood-hardening-observability/PLAN.MD`
- `scripts/ops-manager-reconcile.sh`
- `scripts/ops-manager-status.sh`
- `scripts/ops-manager-telemetry-summary.sh`
- `config/ops-manager-threshold-profiles.v1.json`
- `docs/ops-manager-v0.md`
- `docs/ops-manager-runbook.md`

## Architecture
Phase 5 adds a drift-evaluation layer on top of existing health/tuning artifacts:

1. Drift evaluator:
- Compares applied profile vs recommended profile per reconcile window.
- Applies confidence threshold + mismatch streak thresholds.
- Outputs deterministic drift state for operator and automation consumers.

2. Drift persistence:
- Writes current drift state JSON per loop.
- Appends drift events to telemetry history JSONL.

3. Alert/evidence path:
- Emits escalation records when drift transitions to active.
- Includes rationale and recommendation context for operator action.

## Decisions
- Drift alerts are advisory; profile changes remain explicit operator actions.
- Drift activation requires configurable consecutive mismatch streak.
- Confidence gating defaults to `medium` to avoid low-signal noise.
- All drift artifacts remain file-first under `.superloop/ops-manager/<loop>/`.

## Risks / Constraints
- Overly strict streak/confidence thresholds may suppress meaningful drift.
- Overly loose thresholds may create alert fatigue.
- Drift logic must remain transport-agnostic (`local` and `sprite_service`).

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Implement drift evaluator, persistence, escalations, status fields, tests, and docs.
