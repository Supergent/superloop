# Phase 1 - Promotion Apply Command Baseline

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-11-promotion-rollout-coupling-initiation/PLAN.MD` scope aligns with merged phase-10 outcomes.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/101`).
3. [x] Link this phase packet from the issue and include prior PR context (`#100`, `#98`).

## P1.1 Promotion Apply Command
1. [x] Add `scripts/ops-manager-promotion-apply.sh` with intent-based rollout mutation (`expand`, `resume`, `rollback`).
2. [x] Enforce decision gating rules (`expand`/`resume` require promotion decision `promote`; `rollback` remains safety-allowed).
3. [x] Enforce governance mutation metadata (`--by`, `--approval-ref`, `--rationale`, `--review-by`) and fail closed on missing values.
4. [x] Re-validate mutated registry via `scripts/ops-manager-fleet-registry.sh` before writing.
5. [x] Persist apply state and append telemetry artifacts with idempotency key, trace id, and before/after rollout posture.

## P1.2 Test Coverage
1. [x] Add `tests/ops-manager-promotion-apply.bats` covering successful expand/resume/rollback mutations.
2. [x] Add regressions for decision mismatch, governance metadata missing, and invalid expand-step values.
3. [x] Add idempotency regression proving replay with same key does not re-mutate registry or duplicate side effects.

## P1.3 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with promotion-apply command contract and artifact paths.
2. [x] Update `docs/ops-manager-runbook.md` with controlled rollout apply workflow and rollback procedure.
3. [x] Document operational semantics for idempotent replays and decision-gating failures.

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-apply.bats tests/ops-manager-promotion-gates.bats tests/ops-manager-fleet.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Updated docs/runbook match implemented apply semantics and artifact contract.
