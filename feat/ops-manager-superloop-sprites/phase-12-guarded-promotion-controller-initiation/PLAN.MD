# Feature: Ops Manager for Superloop + Sprites (Phase 12 Guarded Promotion Controller)

## Goal
Add a guarded promotion controller loop that can continuously evaluate fleet evidence and manage rollout posture with deterministic safety gates, while keeping Horizon integration strictly additive.

## Scope
- Add `scripts/ops-manager-promotion-controller.sh` implementing `observe -> evaluate -> decide -> apply/propose -> verify -> rollback/hold`.
- Add decision freshness gates (TTL/recency checks) for promotion evidence before mutation decisions.
- Add rollout budgets/rate limits for mutation control (step/window limits, cooldowns, freeze windows).
- Add controller policy mode with default `propose_only` and gated `guarded_auto_apply` execution.
- Add deterministic post-apply verification and rollback triggers.
- Persist controller state and append-only telemetry artifacts with shared seam fields: `traceId`, `loopId`, `horizonRef`, `evidenceRefs`.
- Update runbook and contract docs to codify hard boundary to Horizon runtime internals.

## Non-Goals (this iteration)
- Embedding Horizon runtime/controller behavior inside Phase 12 controller internals.
- Replacing the existing promotion CI/apply contracts with a new subsystem.
- Multi-tenant authorization or external approval workflow orchestration.

## Primary References
- `.github/workflows/ops-manager-promotion-gates.yml` - scheduled promotion evidence evaluation baseline.
- `.github/workflows/ops-manager-promotion-rollout.yml` - operator-triggered rollout orchestration baseline.
- `scripts/ops-manager-promotion-ci.sh` - promotion decision wrapper used by controller evaluate stage.
- `scripts/ops-manager-promotion-orchestrate.sh` - apply/propose/rollback orchestration surface used by controller execute stage.
- `scripts/ops-manager-promotion-apply.sh` - rollout mutation semantics and governance enforcement.
- `feat/ops-manager-superloop-sprites/phase-11-promotion-rollout-coupling-initiation/PLAN.MD` - explicit Phase 11 non-goal boundary on full automatic mutation.
- `docs/horizon-planning.md` - Horizon control-plane model and decoupling guidance.
- `schema/config.schema.json` - optional `horizon_ref` linkage surface.

## Architecture
Phase 12 adds a controller plane above promotion evaluate/apply primitives:

1. Observe plane:
- Read fleet status/policy/handoff plus latest promotion artifacts and controller state.

2. Evaluate plane:
- Execute promotion decision evaluation and freshness/budget gate checks.

3. Decide plane:
- Choose deterministic action (`propose`, `apply`, `hold`, `rollback`) from policy mode + gate results.

4. Execute plane:
- Call orchestration wrapper in `dry_run`/`apply`/`rollback` mode with strict governance + idempotency semantics.

5. Verify plane:
- Re-evaluate post-apply evidence and trigger deterministic rollback/hold when verification fails.

6. Audit plane:
- Persist state and append telemetry with seam fields (`traceId`, `loopId`, `horizonRef`, `evidenceRefs`).

## Decisions
- Maintain hard boundary: Horizon remains a separate control-plane track; Phase 12 only accepts optional seam fields.
- Keep default execution mode `propose_only`; `guarded_auto_apply` requires all governance/freshness/budget/verification gates to pass.
- Preserve fail-closed behavior for missing/invalid evidence and stale promotion decisions.
- Keep rollback safety path explicitly allowed and deterministic.
- Keep integration additive: seam fields are optional and nullable, never mandatory for controller operation.

## Risks / Constraints
- Controller oscillation risk if verification and budget thresholds are too aggressive.
- Stale artifact windows can produce false confidence without strict freshness checks.
- Manual out-of-band registry edits can conflict with controller decisions unless drift is detected and held.
- Overly sensitive rollback triggers can cause availability churn if not tuned with cooldown hysteresis.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-controller.bats tests/ops-manager-promotion-orchestrate.bats tests/ops-manager-promotion-ci.bats tests/ops-manager-promotion-apply.bats tests/ops-manager-fleet.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Controller contract and propose-only execution baseline with freshness/budget gates, seam fields, artifacts, docs, and tests.
- **Phase 2**: Guarded auto-apply execution path with deterministic post-apply verification/rollback workflow integration and hardening.
