# Phase 1 - Horizon Outbox Bridge Adapter Baseline

## P1.0 Feature Baseline and Scope Discipline
1. [x] Confirm `feat/ops-manager-superloop-sprites/phase-13-horizon-bridge-initiation/PLAN.MD` scope is bridge-only and excludes Horizon orchestration/runtime edits.
2. [x] Attach this phase file to scope authority issue (`https://github.com/Supergent/superloop/issues/114`).
3. [x] Link this phase packet from the issue and include prior PR context (`#112`, `#110`).

## P1.1 Bridge Adapter Contract and Artifacts
1. [x] Add `scripts/ops-manager-horizon-bridge.sh` for Horizon outbox ingestion.
2. [x] Persist bridge state artifact and queue artifact with `pending_operator_confirmation` intents only.
3. [x] Persist append-only bridge telemetry at `.superloop/ops-manager/fleet/telemetry/horizon-bridge.jsonl`.
4. [x] Keep no implicit autonomous execution semantics in bridge outputs.

## P1.2 Frozen Envelope Contract + Parsing Rules
1. [x] Enforce required envelope fields: `schemaVersion`, `traceId`, `packet.packetId`, `packet.recipient.type`, `packet.recipient.id`, `packet.intent`, `evidenceRefs`.
2. [x] Fail closed for missing required fields.
3. [x] Fail open for unknown/additive extra fields.
4. [x] Add frozen contract doc: `docs/horizon-envelope-contract-v1.md`.

## P1.3 Atomic Claim and Replay Safety
1. [x] Add atomic file-claim behavior for outbox files before parse/ingest.
2. [x] Add replay-safe dedupe keyed by `packetId + traceId`.
3. [x] Ensure duplicate envelopes are skipped without re-queueing intents.
4. [x] Ensure claim processing writes deterministic reason-coded telemetry outcomes.

## P1.4 Tests and Regressions
1. [x] Add `tests/ops-manager-horizon-bridge.bats` for valid ingest, contract-failure handling, and dedupe behavior.
2. [x] Add regression coverage for unknown-field fail-open behavior.
3. [x] Add regression coverage for atomic claim file movement behavior.
4. [x] Keep existing fleet suite green (`tests/ops-manager-fleet.bats`).

## P1.5 Docs and Runbook
1. [x] Update `docs/ops-manager-v0.md` with bridge command contract, artifacts, and reason codes.
2. [x] Update `docs/ops-manager-runbook.md` with bridge operation and failure-triage semantics.
3. [x] Document strict parallel boundary with Horizon runtime track.

## P1.V Validation
1. [x] `~/.local/bats-runtime/node_modules/.bin/bats tests/ops-manager-horizon-bridge.bats tests/ops-manager-fleet.bats` passes.
2. [x] All new/changed scripts pass `bash -n` syntax checks.
3. [x] Docs reflect frozen envelope contract and bridge-only boundary.
