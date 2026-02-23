# Feature: Horizon Control Plane (Phase 2 Orchestrator + Dispatch Adapters)

## Goal
Add a deterministic Horizon orchestrator runtime that plans and dispatches queued packets through explicit adapters, with stale-packet gating and auditable artifacts.

## Scope
- Add `scripts/horizon-orchestrate.sh` with `plan` and `dispatch` commands.
- Support deterministic queued packet selection with optional filters (`horizon_ref`, recipient type, limit).
- Add packet TTL freshness gating (expired packets are blocked from dispatch and surfaced with reason codes).
- Add built-in dispatch adapters:
  - `filesystem_outbox` (default)
  - `stdout`
- Persist orchestrator telemetry at `.superloop/horizons/telemetry/orchestrator.jsonl`.
- Ensure dispatch transitions reuse `scripts/horizon-packet.sh` state machine (`queued -> dispatched`, fail path to `failed` on adapter write errors).
- Add BATS coverage for plan/dispatch/dry-run/filter/limit/stale behavior.
- Update docs (`README.md`, `docs/horizon-planning.md`).

## Non-Goals (this iteration)
- Embedding orchestrator behavior into `superloop.sh run`.
- External SaaS transports (Slack/email/webhooks) and retry daemons.
- Global contact directory service across repositories.

## Primary References
- `feat/horizon-control-plane/phase-1-runtime/PLAN.MD` - Phase 1 baseline and explicit Phase 2 target.
- `scripts/horizon-packet.sh` - packet state machine and telemetry contract.
- `tests/horizon-packet.bats` - packet contract regression baseline.
- `docs/horizon-planning.md` - Horizon model and operating guidance.
- `README.md` - operator quickstart guidance.

## Architecture
Phase 2 adds an explicit orchestrator plane over packet artifacts:

1. Observe:
- Read queued packet artifacts from `.superloop/horizons/packets/*.json`.

2. Plan:
- Build deterministic selection (`createdAt`, `packetId`) with optional filters and dispatch route resolution.
- Evaluate freshness gates from `ttlSeconds` + `createdAt` and mark blocked packets with reason codes.

3. Dispatch:
- For dispatchable packets, transition packet state via `horizon-packet.sh`.
- Deliver a dispatch envelope through the selected adapter.
- On adapter write failure, transition packet to `failed` with deterministic reason code.

4. Audit:
- Append orchestrator run records to `.superloop/horizons/telemetry/orchestrator.jsonl`.

## Decisions
- Keep orchestrator standalone (`scripts/horizon-orchestrate.sh`) to preserve Phase 1 isolation and avoid command-router churn.
- Default adapter is `filesystem_outbox` for zero-dependency local/agent/human handoff.
- Use fail-closed freshness gate semantics (`packet_ttl_expired`, `packet_created_at_invalid`).
- Keep optional seam context additive; no hard coupling to Ops Manager internals.

## Risks / Constraints
- Concurrent orchestrator writers are not lock-managed in this phase.
- Filesystem outbox paths are local-repo artifacts, not guaranteed delivery channels.
- `stdout` adapter requires an external consumer process for actual delivery.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `/usr/bin/bats tests/horizon-packet.bats tests/horizon-orchestrate.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: packet lifecycle runtime baseline (complete).
- **Phase 2**: orchestrator `plan/dispatch` runtime, dispatch adapters, freshness gates, docs, tests.
