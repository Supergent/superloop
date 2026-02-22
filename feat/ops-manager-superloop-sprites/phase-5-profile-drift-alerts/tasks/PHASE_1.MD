# Phase 1 - Profile Drift Detection + Alerts

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-5-profile-drift-alerts/PLAN.MD` aligns with prior phases and current repo state.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/52`).
3. [x] Link this phase packet from the issue and include prior PR context (`#40`, `#42`, `#44`, `#46`, `#48`, `#50`).

## P1.1 Drift Evaluator
1. [x] Add profile-drift evaluator script with confidence-gated mismatch logic.
2. [x] Add configurable activation controls (required mismatch streak, minimum confidence).
3. [x] Fail closed on invalid inputs (unknown confidence/profile values).

## P1.2 Persistence and Escalation
1. [x] Persist current drift state JSON under `.superloop/ops-manager/<loop>/`.
2. [x] Append drift history records under `.superloop/ops-manager/<loop>/telemetry/`.
3. [x] Emit escalation entries when drift transitions to active.

## P1.3 Pipeline Integration
1. [x] Integrate drift evaluation into reconcile pipeline after telemetry summary recommendation.
2. [x] Include drift context in reconcile/state outputs.
3. [x] Ensure status output includes drift fields and actionable guidance.

## P1.4 Test Coverage
1. [x] Add `tests/ops-manager-profile-drift.bats` for drift activation/reset logic.
2. [x] Add/extend tests proving reconcile and status include drift artifacts.
3. [x] Verify transport parity for drift logic (`local` vs `sprite_service`) where applicable.

## P1.5 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with drift artifact schema and commands.
2. [x] Update `docs/ops-manager-runbook.md` with drift triage workflow.
3. [x] Document operator actions for active drift (advisory only, no auto-switch).

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs match implemented drift fields/artifacts and operator flow.
