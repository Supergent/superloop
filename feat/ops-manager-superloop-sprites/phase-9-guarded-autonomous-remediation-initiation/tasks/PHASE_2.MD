# Phase 2 - Guarded Autonomous Hardening + Governance

## P2.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-9-guarded-autonomous-remediation-initiation/PLAN.MD` phase-2 scope aligns with merged phase-1 outcomes.
2. [x] Attach this phase file to scope authority issue (`https://github.com/Supergent/superloop/issues/80`).
3. [x] Link this phase packet from the issue and include prior PR context (`#85`, `#84`, `#83`, `#82`, `#81`).

## P2.1 Rollout Controls and Blast-Radius Containment
1. [x] Extend fleet policy contract with rollout controls for guarded autonomous mode (canary scope/percentage, pause flags, and deterministic cohort selection).
2. [x] Implement rollout gating in policy/handoff shaping so auto-dispatch applies only to in-scope cohorts while out-of-scope intents remain manual pending.
3. [x] Add fail-safe auto-pause triggers for ambiguity/failure spikes and ensure advisory/manual flows continue when auto execution is paused.

## P2.2 Governance and Policy-Change Authority
1. [x] Define and validate governance metadata for autonomous policy changes (actor identity, approval reference, rationale, and expiry/review window).
2. [x] Persist immutable governance audit events for autonomous mode toggles and policy mutations with trace linkage.
3. [x] Enforce fail-closed behavior when guarded autonomous mode is requested without required governance metadata/authority context.

## P2.3 Incident Drill Hardening
1. [x] Add executable kill-switch drill coverage proving immediate autonomous halt and deterministic fallback to explicit manual handoff.
2. [x] Add sprite-service outage drill coverage proving autonomous auto-pause and reason-coded operator fallback behavior.
3. [x] Add ambiguous-outcome drill coverage preventing retry storms and preserving deterministic escalation/reason semantics.

## P2.4 Operator Visibility and SLO Surfaces
1. [x] Extend fleet status projection with rollout/autopause state and governance posture surfaces (`who changed`, `when`, `why`, `until`).
2. [x] Add autonomous outcome rollups (`attempted`, `executed`, `ambiguous`, `failed`, `manual_backlog`) to fleet status and telemetry summaries.
3. [x] Ensure reason-code surfaces distinguish policy-gated, rollout-gated, governance-gated, and transport-gated autonomous suppression paths.

## P2.5 Test Coverage
1. [x] Extend `tests/ops-manager-fleet.bats` for rollout cohort gating, auto-pause behavior, governance validation, and incident drills.
2. [x] Add/extend parity regressions in `tests/ops-manager-service.bats` and `tests/ops-manager-visibility.bats` for rollout/autopause/governance semantics.
3. [x] Add regression tests for deterministic governance audit artifacts and reason-code stability under mixed success/ambiguity/failure runs.

## P2.6 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with rollout/governance contract fields and compatibility defaults.
2. [x] Update `docs/ops-manager-runbook.md` with autonomous rollout operations, pause/unpause procedures, and incident drill workflows.
3. [x] Document dogfood promotion gates (required metrics/evidence) for moving from guarded internal mode toward broader beta exposure.

## P2.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats tests/ops-manager-fleet.bats tests/usage-tracking.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs/runbook match implemented rollout/governance/drill semantics and operator workflow.
