# Phase 1 - Observability + Dogfood Hardening Baseline

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-4-dogfood-hardening-observability/PLAN.MD` aligns with prior phases and current repo state.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/47`).
3. [x] Link this phase packet from the issue and include prior PR context (`#40`, `#42`, `#44`, `#46`).

## P1.1 Telemetry Artifact Model
1. [x] Define and emit per-loop telemetry artifacts for reconcile/control cycles.
2. [x] Record transport attempts, retry counts, latency, and result status with stable field names.
3. [x] Persist telemetry artifacts under `.superloop/ops-manager/<loop>/` with deterministic paths.

## P1.2 Health Projection and Reason Codes
1. [x] Add health-state projection (`healthy|degraded|critical`) derived from telemetry + lifecycle state.
2. [x] Add reason-coded degradation/escalation output (e.g. `transport_unreachable`, `ingest_stale`, `control_ambiguous`).
3. [x] Ensure reasons are machine-readable and documented.

## P1.3 Guardrails and Escalation Policy
1. [x] Add configurable thresholds for ingest lag and transport failure streaks.
2. [x] Escalate when thresholds breach, without executing autonomous write-side remediation.
3. [x] Preserve explicit operator intent as the only control trigger path.

## P1.4 Operator Surface + Runbook
1. [x] Add an operator-facing status surface (script/JSON) summarizing health + reasons per loop run.
2. [x] Update `docs/ops-manager-v0.md` with observability artifact contracts.
3. [x] Update `docs/ops-manager-runbook.md` with incident triage/recovery flows using new reason codes.

## P1.5 Test Coverage
1. [x] Add `tests/ops-manager-observability.bats` covering healthy/degraded/critical projections.
2. [x] Add fixtures for transport outage, ingest staleness, and ambiguous confirmation scenarios.
3. [x] Assert local and sprite-service transports produce equivalent observability outcomes.

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs match implemented artifact paths and reason codes.
