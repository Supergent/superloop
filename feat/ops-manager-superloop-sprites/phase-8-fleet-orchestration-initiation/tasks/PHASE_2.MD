# Phase 2 - Fleet Policy Hardening + Operator Controls

## P2.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-8-fleet-orchestration-initiation/PLAN.MD` phase-2 scope aligns with current repo state and phase-1 outcomes.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/74`).
3. [x] Link this phase packet from the issue and include prior PR/issue context (`#73`, `#70`).

## P2.1 Fleet Policy Hardening
1. [x] Harden advisory candidate taxonomy and severity/confidence normalization for fleet policy output.
2. [x] Enforce suppression precedence and validation semantics (`loopId`-specific over global `*`, unknown categories fail closed).
3. [x] Add advisory-noise controls (dedupe/cooldown windows) without introducing automatic control execution.

## P2.2 Fleet Operator Control Handoff
1. [x] Add a fleet handoff artifact that maps unsuppressed policy candidates into explicit per-loop control intents.
2. [x] Add explicit operator confirmation workflow for fleet handoff actions (no autonomous remediation).
3. [x] Propagate fleet trace/idempotency fields through handoff and loop-level control telemetry for auditability.

## P2.3 Runbook Workflow Hardening
1. [x] Extend `docs/ops-manager-runbook.md` with end-to-end fleet operator workflow (`reconcile -> policy -> status -> explicit control -> verify`).
2. [x] Add partial-failure and transport-outage fleet drills with reason-code-driven triage steps.
3. [x] Document suppression governance workflow (add/remove suppression + audit trail expectations).

## P2.4 Local vs Sprite Service Parity Hardening
1. [x] Extend fleet parity coverage for mixed `local` and `sprite_service` loop sets under degraded/critical/failure conditions.
2. [x] Verify fleet rollup and reason-code parity across transports for equivalent runtime states.
3. [x] Harden failure classification behavior to keep fleet status semantics deterministic across transports.

## P2.5 Test Coverage
1. [x] Extend `tests/ops-manager-fleet.bats` for policy hardening and operator handoff flows.
2. [x] Add/extend transport parity regressions across `tests/ops-manager-service.bats` and `tests/ops-manager-visibility.bats` where relevant.
3. [x] Add regression tests for suppression precedence and advisory-noise controls.

## P2.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats tests/ops-manager-fleet.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs/runbook match implemented fleet policy/handoff/parity artifacts and operator workflow.
