# Horizon Envelope Contract v1 (Frozen)

This document defines the frozen contract consumed by the Ops Manager Horizon bridge adapter.

Contract ID: `horizon-envelope-contract-v1`

Producer context:
- Horizon outbox dispatch envelopes (filesystem outbox adapter).

Consumer context:
- `scripts/ops-manager-horizon-bridge.sh` on the Ops Manager side.

## Required fields (fail closed when missing)

Required envelope fields:
- `schemaVersion`
- `traceId`
- `packet.packetId`
- `packet.recipient.type`
- `packet.recipient.id`
- `packet.intent`
- `evidenceRefs`

Required value constraints:
- `schemaVersion` must equal `"v1"`.
- `traceId` must be a non-empty string.
- `packet.packetId` must be a non-empty string.
- `packet.recipient.type` must be a non-empty string.
- `packet.recipient.id` must be a non-empty string.
- `packet.intent` must be a non-empty string.
- `evidenceRefs` must be a JSON array (can be empty).

If any required field is missing/invalid:
- the claimed outbox file is rejected,
- no intents from that file are queued,
- bridge run status becomes `failed_contract_validation`,
- telemetry records contract-failure reason codes.

## Unknown/additive fields (fail open)

Any fields not listed above are treated as additive extras:
- extras are ignored by the bridge,
- extras do not block ingestion,
- extras are preserved only if copied explicitly into future adapter revisions.

## Replay-safe dedupe key

Dedupe key (frozen): `packet.packetId + "::" + traceId`

Behavior:
- if a dedupe key has already been processed, the envelope is skipped as duplicate,
- duplicate envelopes do not create new queue intents.

## Queue projection semantics

Bridge queue intents are projected as:
- `status = "pending_operator_confirmation"`
- `requiresOperatorConfirmation = true`
- `autonomous.eligible = false`
- `autonomous.manualOnly = true`

The bridge never performs implicit autonomous execution.

## Atomic claim expectation

Bridge ingestion claims outbox files via atomic rename (`mv`) into a bridge claim workspace before parsing.

This minimizes multi-consumer races and enables deterministic processing outcomes:
- claimed -> processed
- claimed -> rejected

## Versioning policy

This contract is frozen at v1.

Allowed evolution:
- additive-only fields
- explicit consumer rollout before any required-field changes

Breaking changes:
- introducing new required fields without bridge update is not allowed.
