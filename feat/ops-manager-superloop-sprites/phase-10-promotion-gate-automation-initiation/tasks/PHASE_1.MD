# Phase 1 - Guarded-Auto Promotion Gate Evaluator Baseline

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-10-promotion-gate-automation-initiation/PLAN.MD` scope aligns with merged phase-9 outcomes and promotion-gate docs.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/97`).
3. [x] Link this phase packet from the issue and include prior PR context (`#96`, `#95`, `#94`, `#93`, `#92`).

## P1.1 Promotion Gate Evaluator Command
1. [x] Add `scripts/ops-manager-promotion-gates.sh` with fail-closed input validation and configurable thresholds.
2. [x] Evaluate governance, reliability, manual backlog, safety/suppression, and drill-recency gates with deterministic pass/fail semantics.
3. [x] Emit machine-readable promotion decision output (`promote` vs `hold`) with reason-coded failed-gate summaries.
4. [x] Persist latest promotion report state + append-only promotion decision telemetry artifacts.

## P1.2 Test Coverage
1. [x] Add `tests/ops-manager-promotion-gates.bats` covering promotion-pass baseline and each gate hold path.
2. [x] Add regressions for fail-closed behavior on missing/invalid/stale drill evidence.
3. [x] Add projection stability assertions for suppression-path completeness and hold reason-code determinism.

## P1.3 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with promotion evaluator command contract and persisted artifact paths.
2. [x] Update `docs/ops-manager-runbook.md` with automated promotion workflow and hold-triage guidance.
3. [x] Document threshold override knobs and default values that map to dogfood promotion criteria.

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-gates.bats tests/ops-manager-fleet.bats tests/ops-manager-visibility.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs/runbook match implemented promotion gate semantics and artifact contract.
