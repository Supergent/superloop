# Phase 2 - Promotion Rollout Orchestration Workflow

## P2.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-11-promotion-rollout-coupling-initiation/PLAN.MD` phase-2 scope aligns with merged phase-1 outcomes.
2. [x] Attach this phase file to scope authority issue (`https://github.com/Supergent/superloop/issues/103`).
3. [x] Link this phase packet from the issue and include prior PR context (`#102`).

## P2.1 Orchestration Wrapper Command
1. [x] Add `scripts/ops-manager-promotion-orchestrate.sh` supporting `--mode dry_run|apply|rollback`.
2. [x] Run promotion decision evaluation via `scripts/ops-manager-promotion-ci.sh` and persist orchestration result artifacts.
3. [x] For apply/rollback modes, invoke `scripts/ops-manager-promotion-apply.sh` with deterministic argument forwarding and governance checks.
4. [x] Support idempotency/trace forwarding and fail-closed behavior on invalid mode/intent combinations.

## P2.2 Workflow Integration
1. [x] Add `.github/workflows/ops-manager-promotion-rollout.yml` with `workflow_dispatch` inputs for dry-run/apply/rollback orchestration.
2. [x] Wire workflow inputs to orchestration wrapper flags (mode, intent, thresholds, governance metadata).
3. [x] Emit operator-visible result artifacts (`promotion-orchestrate-result.json`, markdown summary) in workflow logs/summary.

## P2.3 Test Coverage
1. [x] Add `tests/ops-manager-promotion-orchestrate.bats` covering dry-run preview, apply success, rollback success, and governance-failure paths.
2. [x] Add regression coverage for decision gating propagation (`apply` blocked when decision is not `promote`).
3. [x] Keep promotion CI/apply suites green (`tests/ops-manager-promotion-ci.bats`, `tests/ops-manager-promotion-apply.bats`).

## P2.4 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with orchestration command + workflow contract.
2. [x] Update `docs/ops-manager-runbook.md` with operator runbook for dry-run/apply/rollback orchestration.
3. [x] Document artifact paths and triage semantics for orchestration-level failures.

## P2.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-orchestrate.bats tests/ops-manager-promotion-ci.bats tests/ops-manager-promotion-apply.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Workflow YAML and docs reflect implemented orchestration behavior.
