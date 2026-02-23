# Phase 2 - Promotion CI Workflow + Evidence Automation

## P2.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-10-promotion-gate-automation-initiation/PLAN.MD` phase-2 scope aligns with merged phase-1 outcomes.
2. [x] Attach this phase file to scope authority issue (`https://github.com/Supergent/superloop/issues/99`).
3. [x] Link this phase packet from the issue and include prior PR context (`#98`).

## P2.1 CI Wrapper Command
1. [x] Add `scripts/ops-manager-promotion-ci.sh` to run promotion-gate evaluation and emit CI-friendly JSON + markdown summaries.
2. [x] Support explicit CI control flags (`--fail-on-hold`, `--skip-on-missing-evidence`) and deterministic evidence path configuration.
3. [x] Publish summary output to `GITHUB_STEP_SUMMARY` when available while preserving local CLI usability.

## P2.2 GitHub Actions Workflow
1. [x] Add `.github/workflows/ops-manager-promotion-gates.yml` with `workflow_dispatch` and scheduled execution for recurring promotion checks.
2. [x] Wire workflow inputs to threshold and behavior controls used by the CI wrapper command.
3. [x] Ensure workflow can run non-destructively when evidence is absent (`skip` mode) while still supporting strict enforcement mode.

## P2.3 Test Coverage
1. [x] Add `tests/ops-manager-promotion-ci.bats` for promote/hold/skip pathways and markdown summary emission.
2. [x] Add regressions for wrapper exit semantics (`0` promote/skip, `2` hold when enforced).
3. [x] Keep existing promotion gate evaluator suite green (`tests/ops-manager-promotion-gates.bats`).

## P2.4 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with CI wrapper and workflow command contracts.
2. [x] Update `docs/ops-manager-runbook.md` with recurring automation workflow (manual dispatch + schedule) and triage semantics for `hold` vs `skipped`.
3. [x] Document artifact locations for CI summaries and promotion decision outputs.

## P2.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-gates.bats tests/ops-manager-promotion-ci.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Workflow YAML and docs reflect implemented CI behavior.
