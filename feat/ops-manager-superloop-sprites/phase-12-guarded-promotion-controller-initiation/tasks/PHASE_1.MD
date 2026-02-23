# Phase 1 - Guarded Promotion Controller Baseline

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-12-guarded-promotion-controller-initiation/PLAN.MD` scope aligns with merged phase-11 promotion rollout outcomes.
2. [x] Open/attach follow-on issue with this phase file as scope authority (`https://github.com/Supergent/superloop/issues/105`).
3. [x] Link this phase packet from the issue and include prior PR context (`#104`, `#102`, `#100`).

## P1.1 Controller Command and State Artifacts
1. [ ] Add `scripts/ops-manager-promotion-controller.sh` implementing `observe -> evaluate -> decide -> apply/propose -> verify -> rollback/hold`.
2. [ ] Support controller policy mode selection (`propose_only`, `guarded_auto_apply`) with `propose_only` as default.
3. [ ] Persist controller state artifact at `.superloop/ops-manager/fleet/promotion-controller-state.json`.
4. [ ] Persist append-only controller telemetry at `.superloop/ops-manager/fleet/telemetry/promotion-controller.jsonl`.

## P1.2 Freshness and Budget Gating
1. [ ] Add promotion decision freshness checks (TTL/recency) and fail closed when stale.
2. [ ] Add rollout budget/rate limits (max step/window, cooldown, freeze-window gates).
3. [ ] Keep rollback path deterministic and explicitly safety-allowed when verification gates fail.
4. [ ] Keep controller behavior independent from Horizon runtime internals.

## P1.3 Shared Seam Fields (Additive Boundary)
1. [ ] Add optional seam fields to controller artifacts: `traceId`, `loopId`, `horizonRef` (nullable), `evidenceRefs` (array).
2. [ ] Ensure seam fields are forwarded through controller decisions/orchestration metadata when present.
3. [ ] Ensure absent/null `horizonRef` does not block controller operation.

## P1.4 Tests and Regressions
1. [ ] Add `tests/ops-manager-promotion-controller.bats` covering propose-only baseline, gated auto-apply denial, and deterministic rollback trigger paths.
2. [ ] Add regression coverage for freshness-gate failures, budget saturation behavior, and seam-field passthrough/nullability.
3. [ ] Keep existing promotion suites green (`tests/ops-manager-promotion-orchestrate.bats`, `tests/ops-manager-promotion-ci.bats`, `tests/ops-manager-promotion-apply.bats`).

## P1.5 Docs and Runbook
1. [ ] Update `docs/ops-manager-v0.md` with controller command contract, artifacts, mode semantics, and shared seam fields.
2. [ ] Update `docs/ops-manager-runbook.md` with operator workflows for `propose_only` and `guarded_auto_apply`.
3. [ ] Document hard boundary to Horizon track and additive future integration path.

## P1.V Validation
1. [ ] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-controller.bats tests/ops-manager-promotion-orchestrate.bats tests/ops-manager-promotion-ci.bats tests/ops-manager-promotion-apply.bats tests/ops-manager-fleet.bats` passes.
2. [ ] All new/changed scripts pass `bash -n` syntax checks.
3. [ ] Workflow/docs reflect implemented controller semantics and boundary constraints.
