# Phase 2 - Guarded Promotion Controller Hardening + Automation

## P2.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-12-guarded-promotion-controller-initiation/PLAN.MD` phase-2 scope aligns with merged phase-1 outcomes.
2. [x] Attach this phase file to scope authority issue (`https://github.com/Supergent/superloop/issues/111`).
3. [x] Link this phase packet from the issue and include prior PR context (`#110`, `#108`, `#106`).

## P2.1 Controller Runtime Hardening
1. [x] Persist deterministic failed-run state/telemetry when evaluate/apply/rollback command stages fail.
2. [x] Add stage-attributed failure reason codes and command exit metadata to controller artifacts.
3. [x] Keep fail-closed behavior while preserving append-only telemetry integrity.
4. [x] Remove placeholder governance projection and emit deterministic governance fields directly.

## P2.2 Controller Workflow Automation
1. [x] Add `.github/workflows/ops-manager-promotion-controller.yml` with `workflow_dispatch` and scheduled execution.
2. [x] Wire workflow inputs to controller flags (mode, freshness/budget limits, freeze windows, seam fields, governance metadata).
3. [x] Emit operator-visible controller artifacts and summaries in workflow logs/step summary.

## P2.3 Tests and Regressions
1. [x] Expand `tests/ops-manager-promotion-controller.bats` for command-failure persistence paths.
2. [x] Add regression coverage for freeze-window blocking and deterministic stage reason codes.
3. [x] Keep existing promotion suites green (`tests/ops-manager-promotion-orchestrate.bats`, `tests/ops-manager-promotion-ci.bats`, `tests/ops-manager-promotion-apply.bats`, `tests/ops-manager-fleet.bats`).

## P2.4 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with controller hardening semantics and workflow contract.
2. [x] Update `docs/ops-manager-runbook.md` with scheduled/dispatch controller operations and failure-triage flow.
3. [x] Preserve hard Horizon boundary language (additive seam-only linkage).

## P2.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-controller.bats tests/ops-manager-promotion-orchestrate.bats tests/ops-manager-promotion-ci.bats tests/ops-manager-promotion-apply.bats tests/ops-manager-fleet.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Workflow YAML and docs reflect implemented phase-2 controller behavior.
