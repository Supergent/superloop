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

Schema:

- `schema/horizons.schema.json`

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
