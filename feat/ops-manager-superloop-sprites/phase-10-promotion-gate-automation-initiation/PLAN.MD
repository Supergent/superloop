# Feature: Ops Manager for Superloop + Sprites (Phase 10 Guarded-Auto Promotion Gates Automation)

## Goal
Automate guarded-autonomous dogfood promotion decisions with deterministic gate evaluation, machine-readable evidence artifacts, and explicit hold reason codes.

## Scope
- Add a promotion-gates evaluator command that reads fleet status, handoff telemetry, and drill evidence artifacts.
- Evaluate all documented promotion gates (governance posture, outcome reliability, manual backlog, safety/suppression stability, drill recency) with deterministic pass/fail outputs.
- Persist promotion decision artifacts and append-only promotion telemetry for operator audit and rollout records.
- Document operator workflow for promotion checks, threshold overrides, and hold triage.
- Add regression coverage for gate math, fail-closed behavior, and artifact semantics.

## Non-Goals (this iteration)
- Automatically mutating fleet rollout policy when promotion passes.
- Building external dashboard integrations or multi-tenant promotion approval workflows.
- Replacing existing manual fallback operations when promotion checks fail.

## Primary References
- `docs/ops-manager-runbook.md` - guarded-autonomous promotion checklist and evidence expectations.
- `docs/ops-manager-v0.md` - fleet contract, reason-code surfaces, and persistence paths.
- `scripts/ops-manager-fleet-status.sh` - canonical governance/safety/outcome posture projection.
- `scripts/ops-manager-fleet-handoff.sh` - autonomous execution semantics and telemetry sources.
- `scripts/ops-manager-fleet-policy.sh` - policy contract defaults and governance surfaces.
- `tests/ops-manager-fleet.bats` - incident drill and fleet behavior regression baseline.

## Architecture
Phase 10 introduces a promotion decision layer on top of existing Phase 9 fleet surfaces:

1. Evidence ingestion plane:
- Read canonical fleet status projection, autonomous handoff telemetry, and drill recency artifact.

2. Gate evaluation plane:
- Evaluate promotion gates using configurable thresholds with deterministic pass/fail + reason codes.

3. Decision artifact plane:
- Write machine-readable promotion report state and append promotion decision telemetry for audit trails.

4. Operator workflow plane:
- Provide CLI-first promotion checks that can be run locally or in CI before rollout expansion.

## Decisions
- Promotion checks are fail-closed on missing/invalid required evidence.
- Default thresholds align with documented dogfood promotion gates and remain CLI-overridable.
- Hold decisions must include reason-coded failed gates to make remediation explicit.
- Promotion automation remains advisory/decision-oriented; policy mutation stays explicit/manual.

## Risks / Constraints
- Low-volume fleets can trigger prolonged hold state due to sample-size requirements.
- Stale or absent drill evidence can block promotion until operational drill workflow is maintained.
- Divergent telemetry windows between status and handoff artifacts can produce confusing operator signals without clear timestamps.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-promotion-gates.bats tests/ops-manager-fleet.bats tests/ops-manager-visibility.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Promotion gate evaluator command, decision artifacts, docs updates, and deterministic regression coverage.
- **Phase 2**: CI/workflow integration for recurring promotion evidence collection and rollout-control coupling.
