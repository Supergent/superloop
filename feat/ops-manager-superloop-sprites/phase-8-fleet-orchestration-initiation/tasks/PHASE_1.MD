# Phase 1 - Fleet Orchestration Baseline

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-8-fleet-orchestration-initiation/PLAN.MD` aligns with current repo state and prior phase outcomes.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/70`).
3. [x] Link this phase packet from the issue and include prior PR context (`#68`, `#69`).

## P1.1 Fleet Registry Contract
1. [ ] Define fleet registry artifact path/schema under `.superloop/ops-manager/fleet/`.
2. [ ] Add validation/fail-closed behavior for malformed or incomplete fleet entries.
3. [ ] Include transport mode and sprite assignment metadata per loop run.

## P1.2 Fleet Reconcile Fan-Out
1. [ ] Add fleet reconcile command that executes per-loop reconcile with bounded concurrency.
2. [ ] Capture per-loop results (success/failure, reason code, trace linkage, duration) in fleet telemetry.
3. [ ] Support deterministic replay mode for fleet reconcile ordering.

## P1.3 Advisory Fleet Policy Evaluation
1. [ ] Add fleet policy evaluator that consumes per-loop health/visibility outputs.
2. [ ] Emit advisory action candidates with confidence and rationale (no automatic execution).
3. [ ] Persist policy telemetry and suppression metadata for operator triage.

## P1.4 Operator Fleet Surface
1. [ ] Add fleet status projection summarizing fleet health posture and loop exception buckets.
2. [ ] Surface trace-linked drill-down pointers to loop-level status/telemetry artifacts.
3. [ ] Add reason-coded fleet degradation signals for partial-failure scenarios.

## P1.5 Test Coverage
1. [ ] Add `tests/ops-manager-fleet.bats` for registry validation, fan-out reconcile behavior, and policy/status outputs.
2. [ ] Add/extend tests proving fleet parity across `local` and `sprite_service` transports.
3. [ ] Add regression tests for fleet partial-failure and replay determinism behavior.

## P1.V Validation
1. [ ] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats tests/ops-manager-fleet.bats` passes.
2. [ ] All new/changed scripts pass `bash -n` syntax checks.
3. [ ] Updated docs/runbook match implemented fleet artifacts, fields, and operator workflow.
