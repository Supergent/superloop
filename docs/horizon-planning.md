# Horizon Planning for Superloop

## Why this exists

Superloop is an execution harness. It is excellent at bounded role cycles (planner -> implementer -> tester -> reviewer), but long-lived organizations need a control plane above individual runs.

Horizon Planning provides that control plane.

Important: horizons are optional. Superloop runs do not require horizon files.

## Layering model

Use this hierarchy:

1. Organization charter (purpose, constraints, authority)
2. Horizon (adaptive planning envelope)
3. Superloop loop/run/iteration (bounded execution)
4. PLAN/PHASE tasks (atomic implementation)

Do not collapse horizons into checkbox tasks. Tasks are execution artifacts inside a run. Horizons govern which runs should exist and why.

## Horizon levels

Use exactly three levels for control simplicity:

1. `H3` exploration: high uncertainty, discovery-oriented.
2. `H2` convergence: medium uncertainty, decision closure.
3. `H1` execution: low uncertainty, implementation-ready.

If you need nuance, use status and confidence fields, not extra levels.

## Time-domain model

Horizons can span different operating cadences:

1. `realtime` (ms-s)
2. `tactical` (minutes-days)
3. `program` (weeks-months)
4. `strategic` (years-decades)

Superloop primarily executes tactical/program slices. Strategy should inform slices, not be encoded as one giant run.

## Waterfall tension and learning

Do not treat horizons as fixed waterfall plans.

Treat each horizon as a falsifiable hypothesis with:

1. Thesis
2. Success signals
3. Kill signals
4. Constraints
5. Review cadence
6. Expiry

After each run, update confidence and choose one action:

1. Continue
2. Pivot
3. Split
4. Merge
5. Retire

## Artifact contract

Optional control-plane file:

- `.superloop/horizons.json`
- `.superloop/horizon-directory.json` (optional)

Schema:

- `schema/horizons.schema.json`
- `schema/horizon-directory.schema.json`

Loop linkage:

- In `.superloop/config.json`, set `loops[].horizon_ref` to a horizon ID when a loop is executing a specific horizon slice.

Validation:

```bash
scripts/validate-horizons.sh --repo .
```

Validate an example or alternate file:

```bash
scripts/validate-horizons.sh --repo . --file docs/examples/horizons.example.json
```

Optional strict schema validation (requires python `jsonschema` module):

```bash
scripts/validate-horizons.sh --repo . --strict
```

Validate the optional directory file:

```bash
test ! -f .superloop/horizon-directory.json || scripts/validate-horizon-directory.sh --repo .
```

Strict directory validation:

```bash
test ! -f .superloop/horizon-directory.json || scripts/validate-horizon-directory.sh --repo . --strict
```

## Packet runtime (Phase 1)

Use horizon packets for atomic dispatch/work tracking above loop execution.

Command:

```bash
scripts/horizon-packet.sh <create|transition|show|list> --repo .
```

Create a packet:

```bash
scripts/horizon-packet.sh create \
  --repo . \
  --packet-id pkt-001 \
  --horizon-ref HZ-program-authn-v1 \
  --sender planner \
  --recipient-type local_agent \
  --recipient-id implementer \
  --intent "implement auth slice" \
  --loop-id auth-loop \
  --evidence-ref artifact://run-summary
```

Transition a packet:

```bash
scripts/horizon-packet.sh transition \
  --repo . \
  --packet-id pkt-001 \
  --to-status dispatched \
  --by dispatcher \
  --reason "recipient selected"
```

List packets:

```bash
scripts/horizon-packet.sh list --repo . --horizon-ref HZ-program-authn-v1
```

## Orchestrator runtime (Phase 2)

Use the orchestrator when you need deterministic packet selection + adapter-backed dispatch from the queued horizon backlog.

Command:

```bash
scripts/horizon-orchestrate.sh <plan|dispatch> --repo .
```

Plan queued dispatches without mutation:

```bash
scripts/horizon-orchestrate.sh plan \
  --repo . \
  --horizon-ref HZ-program-authn-v1 \
  --adapter filesystem_outbox \
  --limit 20
```

Execute dispatch:

```bash
scripts/horizon-orchestrate.sh dispatch \
  --repo . \
  --horizon-ref HZ-program-authn-v1 \
  --adapter filesystem_outbox \
  --actor dispatcher \
  --reason "queued packet dispatch"
```

Preview dispatch behavior without mutation:

```bash
scripts/horizon-orchestrate.sh dispatch \
  --repo . \
  --horizon-ref HZ-program-authn-v1 \
  --dry-run
```

Adapters:

1. `filesystem_outbox` (default): writes one JSON envelope per dispatch to `.superloop/horizons/outbox/<recipient-type>/<recipient-id>.jsonl`.
2. `stdout`: includes dispatch envelopes directly in command JSON output (`execution.results[].envelope`).

Freshness and fail-closed behavior:

1. Packets with invalid `createdAt` are blocked with `packet_created_at_invalid`.
2. Packets with expired TTL are blocked with `packet_ttl_expired`.
3. Packets missing recipient fields are blocked with `packet_recipient_type_missing` / `packet_recipient_id_missing`.
4. Adapter write failures force packet transition to `failed` with reason `adapter_write_failed`.
5. In `--directory-mode required`, unknown recipients are blocked with `directory_contact_not_found`.

Directory routing:

1. In `optional` mode (default), orchestrator uses directory overrides when available and falls back to packet recipient routing when no contact exists.
2. In `required` mode, dispatch fails closed for recipients not declared in `.superloop/horizon-directory.json`.

## Delivery confirm + retry runtime (Phase 3)

Use Phase 3 when you need deterministic delivery confirmation and bounded retry policy without coupling Horizon runtime to Ops Manager internals.

Directory sample:

```bash
cat docs/examples/horizon-directory.example.json
```

Ingest delivery receipts:

```bash
scripts/horizon-ack.sh ingest \
  --repo . \
  --file /path/to/receipts.jsonl
```

Receipt contract fields:

1. required: `schemaVersion`, `packetId`, `traceId`, `status`
2. optional: `receiptId`, `by`, `reason`, `note`, `evidenceRefs`
3. supported statuses: `acknowledged`, `failed`, `escalated`, `cancelled`

Ack behavior:

1. dedupe is keyed by `receiptId` (or deterministic hash fallback).
2. successful `acknowledged` receipts transition `dispatched -> acknowledged`.
3. acknowledged packets are removed from retry-state tracking.

Run retry reconcile loop:

```bash
scripts/horizon-retry.sh reconcile \
  --repo . \
  --directory-mode optional \
  --ack-timeout-seconds 600 \
  --max-retries 3 \
  --retry-backoff-seconds 120
```

Retry behavior:

1. scans packets in `dispatched` status.
2. if timeout elapsed and retries remain, emits `horizon_dispatch_retry` envelope and increments retry counter.
3. if retry budget exhausted, transitions packet to `escalated` and appends dead-letter record.
4. dry-run mode evaluates actions without mutating packet/state artifacts.

Status model:

1. `queued`
2. `dispatched`
3. `acknowledged`
4. `in_progress`
5. `completed`
6. `failed`
7. `escalated`
8. `cancelled`

Primary allowed flow:

1. `queued -> dispatched -> acknowledged -> in_progress -> completed`

Safety flow:

1. `queued|dispatched|acknowledged|in_progress -> failed|escalated|cancelled`

Artifacts:

- `.superloop/horizons/packets/<packet-id>.json`
- `.superloop/horizons/telemetry/packets.jsonl`
- `.superloop/horizons/telemetry/orchestrator.jsonl`
- `.superloop/horizons/outbox/<recipient-type>/<recipient-id>.jsonl` (filesystem adapter)
- `.superloop/horizons/ack-state.json`
- `.superloop/horizons/telemetry/ack.jsonl`
- `.superloop/horizons/retry-state.json`
- `.superloop/horizons/telemetry/retry.jsonl`
- `.superloop/horizons/telemetry/dead-letter.jsonl`

Each packet artifact records:

1. `traceId`
2. `loopId` (optional)
3. `horizonRef`
4. `evidenceRefs`
5. transition history with actor/reason/note

## Operational rules

1. A loop may execute without any horizon binding.
2. A horizon may have zero or many loop slices over time.
3. Promotion from `H3 -> H2 -> H1` must include evidence references.
4. Demotion is allowed and expected when new evidence invalidates assumptions.
5. Only `H1` slices should be handed to implementation-heavy runs.

## Minimal rollout

1. Add `horizons.json` for program-level visibility.
2. Link selected loops with `horizon_ref`.
3. Use existing Superloop events/usage artifacts as evidence refs.
4. Evolve policy and promotion criteria after observing real runs.
