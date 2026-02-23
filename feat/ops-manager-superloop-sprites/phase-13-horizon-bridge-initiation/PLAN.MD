# Feature: Ops Manager for Superloop + Sprites (Phase 13 Horizon Outbox Bridge)

## Goal
Add a narrow, contract-locked bridge adapter on the Ops Manager side that consumes Horizon outbox envelopes and projects them into pending operator-confirmation queue artifacts without autonomous execution.

## Scope
- Add `scripts/ops-manager-horizon-bridge.sh` to ingest Horizon outbox envelope files.
- Enforce frozen envelope contract v1 required fields and fail-closed behavior when required fields are missing.
- Keep additive/extensible behavior by failing open on unknown extra fields.
- Add atomic file-claim mechanics for outbox ingestion.
- Add replay-safe dedupe keyed by `packetId + traceId`.
- Persist queue and bridge state artifacts with `pending_operator_confirmation` intents only.
- Persist append-only bridge telemetry for ingestion/audit outcomes.
- Document frozen contract in `docs/horizon-envelope-contract-v1.md`.
- Update ops-manager docs/runbook with bridge command + triage semantics.

## Non-Goals
- Any Horizon runtime/orchestrator/packet script changes.
- Ack/retry/dead-letter orchestration logic from Horizon Phase 3.
- Implicit autonomous execution from bridge outputs.

## Primary References
- `scripts/horizon-orchestrate.sh` - outbox envelope writer shape.
- `tests/horizon-orchestrate.bats` - outbox envelope behavior.
- `scripts/ops-manager-fleet-handoff.sh` - pending operator confirmation intent semantics.
- `docs/horizon-planning.md` - Horizon operating model.

## Architecture
1. Input plane:
- Read outbox envelope files from `.superloop/horizons/outbox/*/*.jsonl`.

2. Claim plane:
- Atomically move each candidate file into bridge claim workspace before parsing.

3. Validation plane:
- Validate required contract fields from each envelope line.
- Missing required fields fail closed for that claimed file.
- Unknown/additive fields are ignored.

4. Replay-safety plane:
- Skip duplicate envelopes based on deterministic key: `packetId + traceId`.

5. Queue projection plane:
- Emit bridge queue intents with status `pending_operator_confirmation`.
- Mark intents as manual-only; no autonomous eligibility.

6. Audit plane:
- Persist bridge state + append-only telemetry artifacts.

## Decisions
- Keep bridge isolated from Horizon runtime internals and evolution.
- Lock required v1 fields and behavior in a frozen contract document.
- Use atomic file-claim to minimize concurrent consumer races.
- Use dedupe index for replay-safe ingestion across reruns.

## Risks / Constraints
- Large dedupe state growth if retention is unbounded.
- Contract failures can block files until operator remediation.
- Parallel Horizon changes require explicit contract handshake before required-field updates.

## Gate Baseline
- Tests mode: `N/A (repository feature work; validate via BATS + script checks)`
- Tests commands: `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-horizon-bridge.bats tests/ops-manager-fleet.bats`
- Validation require on completion: `N/A`
- Validation checklist mapping file: `N/A`

## Phases
- **Phase 1**: Bridge adapter baseline, contract enforcement, atomic claim + dedupe, queue/telemetry artifacts, docs, and tests.
