# Feature: Ops Manager for Superloop + Sprites (Phase 9 Guarded Autonomous Remediation)

## Goal
Enable optional, guardrailed autonomous fleet remediation that can execute a constrained subset of control intents safely while preserving deterministic state, auditability, and operator override.

## Scope
- Extend fleet policy contract to support `guarded_auto` mode while keeping `advisory` as default.
- Introduce explicit auto-eligibility evaluation from policy candidates to execution intents.
- Add safety controls for autonomous execution (allowlists, confidence/severity thresholds, action caps, cooldowns, kill switch).
- Add autonomous execution telemetry/reason surfaces for fleet status and runbook triage.
- Preserve behavior parity for `local` and `sprite_service` loop transports.

## Non-Goals (this iteration)
- Full autonomous execution across all control intents and categories.
- Removal of existing explicit operator handoff workflows.
- Multi-tenant authorization, billing, or organization-scoped control policy.
- External orchestration services beyond existing file-first artifacts and scripts.

## Primary References
- `scripts/ops-manager-fleet-policy.sh` - fleet advisory candidate generation and suppression semantics.
- `scripts/ops-manager-fleet-handoff.sh` - fleet intent mapping and control dispatch orchestration.
- `scripts/ops-manager-control.sh` - loop-level control execution + confirmation behavior.
- `scripts/ops-manager-fleet-status.sh` - operator fleet posture projection and reason surfaces.
- `scripts/ops-manager-fleet-registry.sh` - fleet registry validation and policy contract normalization.
- `docs/ops-manager-v0.md` - manager/runtime artifacts and reason-code contract.
- `docs/ops-manager-runbook.md` - operator workflow and incident procedures.
- `feat/ops-manager-superloop-sprites/phase-8-fleet-orchestration-initiation/tasks/PHASE_2.MD` - prior phase baseline and constraints.

## Architecture
Phase 9 adds an autonomous remediation layer on top of fleet advisory/handoff primitives:

1. Eligibility plane:
- Derive auto-executable intents from unsuppressed policy candidates using explicit allowlists, thresholds, and mode gates.

2. Safety plane:
- Enforce guardrails (caps, cooldowns, category restrictions, kill switch, deterministic fail behavior) before any control dispatch.

3. Execution plane:
- Execute only eligible intents through existing `ops-manager-control.sh` semantics with trace/idempotency propagation.

4. Verification plane:
- Persist execution outcomes and reason-coded fleet status surfaces so operators can audit, override, or fall back to manual handoff.

## Decisions
- Keep fleet `policy.mode=advisory` as default; autonomous execution is explicit opt-in.
- Start with a constrained intent/category set (guarded subset) instead of broad automatic controls.
- Preserve file-first append-only telemetry and deterministic reason-code outputs as release gates.
- Keep operator override path first-class and available at all times.

## Risks / Constraints
- Misconfigured thresholds can over-trigger remediation and cause unnecessary loop cancellations.
- Repeated auto-actions can create action churn without cooldown and cap enforcement.
- Transport-specific error surfaces can diverge reason-code semantics if not validated for parity.
- Autonomous execution increases governance expectations for audit trail completeness and operator rollback clarity.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats tests/ops-manager-fleet.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Guarded auto-remediation contract, execution safety rails, autonomous dispatch, and operator surfaces.
- **Phase 2**: Hardening and governance (advanced safety policies, rollout controls, and incident drill validation).
