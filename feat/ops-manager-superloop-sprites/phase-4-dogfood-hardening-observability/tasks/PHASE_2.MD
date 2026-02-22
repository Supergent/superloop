# Phase 2 - Dogfood Threshold Tuning + Operator UX Hardening

## P2.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-4-dogfood-hardening-observability/PLAN.MD` phase-2 scope aligns with current repo state.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/49`).
3. [x] Link this phase packet from the issue and include prior PR context (`#40`, `#42`, `#44`, `#46`, `#48`).

## P2.1 Threshold Profiles
1. [x] Add versioned threshold profile catalog for dogfood operations (`strict|balanced|relaxed`).
2. [x] Add profile resolver script and fail-closed behavior for unknown profiles.
3. [x] Wire reconcile to accept `--threshold-profile` and `--thresholds-file` with deterministic precedence over defaults.

## P2.2 Telemetry-Driven Tuning Surface
1. [x] Add telemetry summary script that reads reconcile/control telemetry and emits machine-readable aggregates.
2. [x] Compute suggested threshold profile from observed health/failure rates and include rationale.
3. [x] Ensure summary script works without external services (file-first dogfood mode).

## P2.3 Operator UX Hardening
1. [x] Extend status output with applied threshold profile and tuning context.
2. [x] Add clear guidance fields for operators (`recommendedProfile`, `summaryWindow`, `confidence`).
3. [x] Keep status output backward-compatible for existing consumers.

## P2.4 Test Coverage
1. [x] Add tests for threshold profile resolution and reconcile profile wiring.
2. [x] Add tests for telemetry summary recommendation behavior.
3. [x] Add tests for status output profile/tuning fields.

## P2.5 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with threshold profile contract and script usage.
2. [x] Update `docs/ops-manager-runbook.md` with telemetry-guided threshold tuning workflow.
3. [x] Document precedence rules for explicit flags vs profile defaults.

## P2.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs match implemented profile names, fields, and commands.
