# Phase 1 - External Alert Sink Dispatch

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-6-alert-sinks/PLAN.MD` aligns with prior phases and current repo state.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/54`).
3. [x] Link this phase packet from the issue and include prior PR context (`#40`, `#42`, `#44`, `#46`, `#48`, `#50`, `#53`).

## P1.1 Alert Sink Config Contract
1. [ ] Add versioned alert sink config file and schema (enabled sinks, routing policy, severity/category mapping).
2. [ ] Add config resolver script with fail-closed validation and env-secret references.
3. [ ] Document defaults and override precedence.

## P1.2 Dispatch Pipeline Integration
1. [ ] Add alert dispatch script that consumes newly emitted escalation entries.
2. [ ] Integrate dispatch invocation into reconcile flow without breaking existing reconcile exit semantics.
3. [ ] Ensure dispatch is idempotent across repeated reconciles.

## P1.3 Sink Adapters and Telemetry
1. [ ] Implement adapter support for `webhook`, `slack`, and `pagerduty_events`.
2. [ ] Persist delivery attempt/outcome telemetry under `.superloop/ops-manager/<loop>/telemetry/`.
3. [ ] Record reason-coded delivery failures for operator triage.

## P1.4 Operator Surface + Runbook
1. [ ] Extend `scripts/ops-manager-status.sh` with last alert delivery summary fields.
2. [ ] Update `docs/ops-manager-v0.md` with alert sink contract and telemetry artifacts.
3. [ ] Update `docs/ops-manager-runbook.md` with alert failure/outage triage and fallback guidance.

## P1.5 Test Coverage
1. [ ] Add `tests/ops-manager-alert-sinks.bats` for config validation, dispatch success/failure, and idempotency.
2. [ ] Add/extend tests proving status includes alert delivery summaries.
3. [ ] Verify transport parity for alert dispatch (`local` vs `sprite_service`) where applicable.

## P1.V Validation
1. [ ] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats` passes.
2. [ ] All new/changed scripts pass `bash -n` syntax checks.
3. [ ] Updated docs match implemented alert sink artifacts, fields, and operator flow.
