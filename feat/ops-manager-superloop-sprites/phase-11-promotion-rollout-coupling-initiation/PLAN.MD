# Feature: Ops Manager for Superloop + Sprites (Phase 11 Promotion-to-Rollout Coupling)

## Goal
Turn promotion decisions into explicit, governed rollout policy mutations with deterministic safety behavior, idempotent apply semantics, and auditable artifacts.

## Scope
- Add a promotion apply command that consumes promotion decision artifacts and mutates fleet rollout policy in controlled steps.
- Enforce governance metadata requirements (`actor`, `approvalRef`, `rationale`, `reviewBy`) for every mutation.
- Support safe intents for rollout progression and rollback posture (`expand`, `resume`, `rollback`).
- Persist promotion-apply state and append-only mutation telemetry with before/after rollout posture.
- Add regression coverage for decision gating, idempotency, governance requirements, and rollback behavior.

## Non-Goals (this iteration)
- Fully automatic policy mutation directly inside scheduled CI workflow without explicit operator intent.
- Multi-tenant authorization or external approval systems.
- Arbitrary policy mutation beyond rollout + governance coupling for guarded autonomous mode.

## Primary References
- `scripts/ops-manager-promotion-gates.sh` - promotion decision source (`promote|hold`).
- `scripts/ops-manager-fleet-registry.sh` - canonical policy contract normalization/validation.
- `docs/ops-manager-v0.md` - fleet policy contract and artifact paths.
- `docs/ops-manager-runbook.md` - guarded autonomous operational workflow and promotion runbook.
- `tests/ops-manager-promotion-gates.bats` - promotion decision baseline behavior.

## Architecture
Phase 11 adds an apply layer after promotion evaluation:

1. Decision intake plane:
- Read current promotion decision artifact and validate intent compatibility (`expand` and `resume` require `promote`).

2. Mutation plane:
- Mutate only rollout/governance policy fields in registry with explicit intent semantics and deterministic limits.

3. Verification plane:
- Re-validate mutated registry via `ops-manager-fleet-registry.sh` before persistence.

4. Audit plane:
- Persist apply state and append telemetry with idempotency key, trace linkage, and before/after posture.

## Decisions
- Apply command is fail-closed for missing/invalid decision or governance metadata.
- Rollout progression is step-based (`expand` by integer percent) for controlled blast-radius changes.
- `rollback` is always allowed to force safe pause posture, even when latest promotion decision is not `promote`.
- Idempotency key replay returns existing apply record without mutating registry again.

## Risks / Constraints
- Applying rollout changes against stale decision artifacts can cause operator confusion if evidence windows drift.
- Governance metadata freshness depends on operator discipline and review cadence.
- Invalid manual registry edits can still break apply unless registry validation remains strict.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-apply.bats tests/ops-manager-promotion-gates.bats tests/ops-manager-fleet.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Promotion apply command, audit artifacts, docs updates, and deterministic tests.
- **Phase 2**: CI/manual orchestration workflow for guarded rollout transitions with dry-run/apply/rollback actions.
