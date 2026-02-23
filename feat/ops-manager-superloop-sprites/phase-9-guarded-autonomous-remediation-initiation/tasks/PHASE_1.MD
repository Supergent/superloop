# Phase 1 - Guarded Autonomous Remediation Baseline

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-9-guarded-autonomous-remediation-initiation/PLAN.MD` aligns with current repo state and phase-8 outcomes.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/80`).
3. [x] Link this phase packet from the issue and include prior PR/issue context (`#79`, `#74`).

## P1.1 Policy Mode and Contract Extension
1. [x] Extend fleet registry policy contract to support explicit autonomous remediation controls (`mode`, thresholds, caps, cooldowns, allowlists).
2. [x] Enforce fail-closed validation for unsupported auto categories/intents and invalid threshold/cap values.
3. [x] Update `docs/ops-manager-v0.md` contract notes for new policy fields and compatibility defaults.

## P1.2 Auto-Eligibility Evaluation
1. [x] Extend fleet policy/handoff shaping to classify unsuppressed candidates as auto-eligible vs manual-only with explicit rejection reasons.
2. [x] Gate auto eligibility by category/intent allowlists plus severity/confidence thresholds.
3. [x] Persist auto-eligibility artifacts/telemetry so operators can audit why candidates were or were not auto-executed.

## P1.3 Safety Rails and Circuit Breakers
1. [x] Enforce per-run and per-loop autonomous action caps before dispatch.
2. [x] Enforce cooldown windows to prevent repeated autonomous controls for the same loop/category.
3. [x] Add a global autonomous remediation kill switch that hard-disables auto dispatch without breaking advisory/manual flows.

## P1.4 Autonomous Dispatch Workflow
1. [ ] Add an autonomous execution path that dispatches only eligible intents via existing `ops-manager-control.sh` behavior.
2. [ ] Preserve trace/idempotency propagation and deterministic execution status (`executed`, `ambiguous`, `failed`) across transports.
3. [ ] Ensure autonomous dispatch failures are reason-coded and do not execute out-of-policy intents.

## P1.5 Operator Visibility and Runbook
1. [ ] Extend fleet status/reason surfaces for autonomous remediation outcomes and safety-gate decisions.
2. [ ] Update `docs/ops-manager-runbook.md` with autonomous mode operating workflow, kill-switch usage, and fallback to explicit manual handoff.
3. [ ] Document operator governance expectations for when autonomous mode should be enabled/disabled.

## P1.6 Test Coverage
1. [x] Extend `tests/ops-manager-fleet.bats` for autonomous mode contract, eligibility gating, cap/cooldown rails, and kill-switch behavior.
2. [ ] Add/extend transport parity regressions in `tests/ops-manager-service.bats` and `tests/ops-manager-visibility.bats` for autonomous execution semantics.
3. [ ] Add regressions for deterministic reason-code behavior under partial autonomous execution failures.

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats tests/ops-manager-fleet.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [ ] Updated docs/runbook match implemented autonomous policy fields, execution semantics, and operator workflow.
