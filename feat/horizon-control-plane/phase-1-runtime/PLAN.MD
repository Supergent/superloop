# Feature: Horizon Control Plane (Phase 1 Runtime Packet Lifecycle)

## Goal
Ship a concrete Horizon packet runtime that lets humans/agents create, transition, inspect, and audit packet state above Superloop loop execution.

## Scope
- Add `scripts/horizon-packet.sh` with `create`, `transition`, `show`, and `list` commands.
- Persist packet state artifacts at `.superloop/horizons/packets/*.json`.
- Persist append-only packet telemetry at `.superloop/horizons/telemetry/packets.jsonl`.
- Enforce deterministic packet status transitions with fail-closed validation.
- Add BATS coverage for create/transition/list/show success + failure paths.
- Update Horizon docs/readme with executable usage and artifact contract.

## Non-Goals (this iteration)
- Embedding packet execution semantics into `superloop.sh run` role loops.
- Transport adapters for live delivery (webhook/slack/email) and retries.
- Cross-repo directory/discovery service for external contacts.

## Primary References
- `docs/horizon-planning.md` - horizon operating model and artifact contract.
- `schema/horizons.schema.json` - horizon control-plane schema.
- `scripts/validate-horizons.sh` - existing horizon schema/invariant validation path.
- `README.md` - top-level operator guidance.

## Architecture
The runtime introduces an explicit packet state machine persisted in repo artifacts:

1. command plane (`scripts/horizon-packet.sh`) validates input and transitions.
2. state artifact per packet (`.superloop/horizons/packets/<id>.json`).
3. append-only telemetry stream (`.superloop/horizons/telemetry/packets.jsonl`).

This is additive and decoupled from ops-manager controllers and loop execution internals.

## Decisions
- Status model is fixed for Phase 1: `queued`, `dispatched`, `acknowledged`, `in_progress`, `completed`, `failed`, `escalated`, `cancelled`.
- Transition matrix is explicit and fail-closed; illegal transitions return non-zero.
- Packet artifacts always include `traceId`, `horizonRef`, `evidenceRefs`, and optional `loopId`.
- CLI remains standalone script-level surface for this phase to avoid broad command-router churn.

## Risks / Constraints
- No automatic reconciliation loop yet; operators/agents must invoke commands explicitly.
- Schema evolution requires backward compatibility for stored packet artifacts.
- Concurrent writers to the same packet file are not lock-managed in this phase.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `/usr/bin/bats tests/horizon-packet.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: packet runtime script, deterministic transitions, telemetry artifacts, docs, tests.
- **Phase 2**: optional integration into higher-level Horizon orchestrator commands and dispatch adapters.
