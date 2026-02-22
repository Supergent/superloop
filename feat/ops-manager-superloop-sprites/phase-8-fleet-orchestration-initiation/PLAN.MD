# Feature: Ops Manager for Superloop + Sprites (Phase 8 Fleet Orchestration)

## Goal
Enable the ops manager to coordinate and observe multiple loop runs across sprites as a fleet with deterministic, policy-aware orchestration.

## Scope
- Add a fleet registry artifact that tracks loop run membership, sprite assignment, transport mode, and latest per-loop health/status pointers.
- Add fleet reconcile fan-out that executes per-loop reconcile safely with bounded concurrency and records fleet-level outcomes.
- Add advisory fleet policy evaluation that summarizes candidate actions without auto-execution.
- Add fleet operator status surfaces for fleet health rollups, per-loop exceptions, and trace-linked drill-down.
- Preserve local and `sprite_service` transport parity for fleet-level orchestration semantics.

## Non-Goals (this iteration)
- Autonomous remediation that executes control actions without explicit operator approval.
- Multi-tenant authorization, billing, or organization-scoped control planes.
- Cross-repo orchestration; this phase is single-repo fleet coordination.
- External tracing/APM vendor coupling beyond existing file-first telemetry artifacts.

## Primary References
- `scripts/ops-manager-reconcile.sh` - per-loop reconciliation primitive used by fleet fan-out.
- `scripts/ops-manager-control.sh` - per-loop control primitive used by advisory policy handoff.
- `scripts/ops-manager-status.sh` - per-loop visibility projection used for fleet rollups.
- `scripts/ops-manager-sprite-service.py` - service transport parity contract for sprite execution.
- `docs/ops-manager-v0.md` - manager/runtime contract and persistence paths.
- `docs/ops-manager-runbook.md` - operational triage and fallback workflow baseline.
- `feat/ops-manager-superloop-sprites/phase-7-total-visibility/PLAN.MD` - prior-phase visibility assumptions carried forward.

## Architecture
Phase 8 introduces a fleet orchestration layer above existing loop-scoped manager artifacts:

1. Fleet registry plane:
- File-first registry under `.superloop/ops-manager/fleet/` declaring managed loops, sprite assignments, transport preferences, and policy metadata.

2. Fleet execution plane:
- Fleet reconcile entrypoint orchestrates loop-level reconcile passes with bounded parallelism, deterministic ordering options, and per-loop result capture.

3. Fleet policy plane:
- Advisory evaluator consumes loop health/visibility outputs to produce ranked, trace-linked action recommendations.

4. Fleet operator plane:
- Fleet status/reporting surface summarizes overall fleet posture and identifies loops needing manual intervention.

## Decisions
- Keep `Loop Run` as the primary managed unit; fleet is an orchestration wrapper across loop units.
- Keep phase output file-first and append-only where possible for replay/debug value.
- Start with advisory policy mode only; no automatic control dispatch in Phase 8 initiation.
- Maintain transport parity as a release gate, not a best-effort follow-up.

## Risks / Constraints
- Fleet fan-out can increase I/O and process contention if concurrency is not bounded.
- Partial failures across loops can produce inconsistent fleet snapshots without strict aggregation semantics.
- Policy recommendations may drift/noise without clear confidence and suppression controls.
- Trace correlation across many loops may become ambiguous without explicit fleet/session IDs.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-contract.bats tests/ops-manager-core.bats tests/ops-manager-service.bats tests/ops-manager-observability.bats tests/ops-manager-threshold-tuning.bats tests/ops-manager-profile-drift.bats tests/ops-manager-alert-sinks.bats tests/ops-manager-visibility.bats tests/ops-manager-fleet.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Fleet registry contract + fan-out reconcile baseline + advisory policy/status surfaces.
- **Phase 2**: Fleet policy hardening, operator controls, runbook workflows, and parity hardening.
