# Phase 1 - Total Visibility Plane

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-7-total-visibility/PLAN.MD` aligns with prior phases and current repo state.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/59`).
3. [x] Link this phase packet from the issue and include prior PR context (`#40`, `#42`, `#44`, `#46`, `#48`, `#50`, `#53`, `#55`, `#56`, `#57`, `#58`).

## P1.1 Runtime Heartbeat Telemetry
1. [x] Add heartbeat envelope artifact path and schema shape for loop runtime/service adapters.
2. [x] Ingest heartbeat signals in manager reconcile and persist loop-scoped heartbeat telemetry.
3. [x] Project heartbeat freshness into health/status with reason-coded degradation behavior.

## P1.2 Control Invocation Audit Log
1. [x] Add structured invocation log entries for manager-issued control actions.
2. [x] Capture transport, idempotency key, intent, execution result, and confirmation outcome.
3. [x] Ensure append-only audit trails under `.superloop/ops-manager/<loop>/telemetry/`.

## P1.3 Envelope Sequence Diagnostics
1. [ ] Add sequence identifiers for snapshot/event envelopes (local + sprite_service).
2. [ ] Add monotonic sequence validation and reason-coded ordering drift signals.
3. [ ] Persist ordering diagnostics for operator triage.

## P1.4 Trace ID Propagation
1. [ ] Generate/propagate trace IDs across reconcile, control, runtime effects, and escalation/alert telemetry.
2. [ ] Surface trace linkage fields in status output for latest control/reconcile/alert actions.
3. [ ] Preserve backward compatibility with null-safe trace fields for existing artifacts.

## P1.5 Operator Surface + Runbook
1. [ ] Extend `scripts/ops-manager-status.sh` with heartbeat, sequence, and trace visibility summary fields.
2. [ ] Update `docs/ops-manager-v0.md` with visibility artifact contract and field definitions.
3. [ ] Update `docs/ops-manager-runbook.md` with total-visibility triage workflows and fallback behavior.

## P1.6 Test Coverage
1. [ ] Add `tests/ops-manager-visibility.bats` for heartbeat, invocation audit, sequence checks, and trace propagation.
2. [ ] Add/extend tests proving status output includes new visibility fields.
3. [ ] Verify local vs sprite_service parity for visibility artifacts and reason codes.

## P1.V Validation
1. [ ] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [ ] Updated docs match implemented visibility artifacts, fields, and operator flow.
