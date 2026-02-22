# Ops Manager V0 Contract (Superloop + Sprites)

## Purpose
This document defines the V0 manager/runtime contract for operating Superloop runs from outside a Sprite sandbox VM.

Primary managed unit:
- `Loop Run`

Default isolation policy:
- one loop run per sprite VM

## Contract Surfaces
V0 exports two envelope types described by `schema/ops-manager.contract.schema.json`:

1. `loop_run_snapshot`
- point-in-time lifecycle projection for one loop id
- includes run identity, manager health signals, and artifact metadata

2. `loop_run_event`
- incremental event envelope from `.superloop/loops/<loop>/events.jsonl`
- cursor-aware, supports polling without event duplication

## Required Runtime Artifacts
Required for V0 snapshot/event ingestion:

- `.superloop/loops/<loop>/events.jsonl`

Optional but consumed when present:

- `.superloop/loops/<loop>/run-summary.json`
- `.superloop/state.json`
- `.superloop/active-run.json`
- `.superloop/loops/<loop>/approval.json`

Adapter scripts fail closed when required artifacts are missing.

## Adapter Commands

### Snapshot
```bash
scripts/ops-manager-loop-run-snapshot.sh \
  --repo /path/to/repo \
  --loop my-loop
```

Options:
- `--run-id <id>`: override inferred run id
- `--pretty`: formatted JSON output

### Incremental Events
```bash
scripts/ops-manager-poll-events.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --cursor-file /tmp/my-loop.cursor.json
```

Options:
- `--from-start`: ignore existing cursor and replay from first event
- `--max-events <n>`: cap events emitted in one poll

## Manager Core Commands

### Project State
```bash
scripts/ops-manager-project-state.sh \
  --repo /path/to/repo \
  --loop my-loop
```

Purpose:
- Computes canonical manager lifecycle projection from snapshot/event envelopes.
- Writes state to `.superloop/ops-manager/<loop>/state.json`.

### Reconcile
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop my-loop
```

Purpose:
- Executes snapshot + incremental poll + projection in one pass.
- Maintains cursor and state under `.superloop/ops-manager/<loop>/`.
- Emits reconcile telemetry and health projection artifacts under `.superloop/ops-manager/<loop>/telemetry/`.
- Computes reason-coded manager health (`healthy|degraded|critical`) and writes `.superloop/ops-manager/<loop>/health.json`.

Observability thresholds:
- `--threshold-profile <strict|balanced|relaxed>`
- `--thresholds-file <path>`
- `--drift-min-confidence <low|medium|high>`
- `--drift-required-streak <n>`
- `--drift-summary-window <n>`
- `--drift-state-file <path>`
- `--drift-history-file <path>`
- `--degraded-ingest-lag-seconds <n>`
- `--critical-ingest-lag-seconds <n>`
- `--degraded-transport-failure-streak <n>`
- `--critical-transport-failure-streak <n>`

Threshold precedence:
1. Explicit threshold flags (`--degraded-*`, `--critical-*`)
2. Selected threshold profile (`--threshold-profile` or `OPS_MANAGER_THRESHOLD_PROFILE`)
3. Profile catalog default (`defaultProfile` in thresholds file)

Profile catalog default path:
- `config/ops-manager-threshold-profiles.v1.json`

### Control Intent
```bash
scripts/ops-manager-control.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --intent cancel
```

Supported intents:
- `cancel`
- `approve`
- `reject`

Service transport example:
```bash
scripts/ops-manager-control.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --intent approve \
  --transport sprite_service \
  --service-base-url http://127.0.0.1:8787 \
  --service-token "$OPS_MANAGER_SERVICE_TOKEN" \
  --idempotency-key approve-my-loop-001
```

Confirmation:
- `scripts/ops-manager-confirm-intent.sh` is used by default.
- `--no-confirm` skips confirmation and records `executed_unconfirmed`.
- Control telemetry is appended to `.superloop/ops-manager/<loop>/telemetry/control.jsonl`.

### Operator Status
```bash
scripts/ops-manager-status.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --pretty
```

Purpose:
- Provides operator-facing lifecycle + health summary for one loop run.
- Normalizes state, health, cursor, latest control, and latest reconcile telemetry.
- Includes tuning guidance fields from telemetry summaries (`recommendedProfile`, `confidence`, `rationale`).
- Includes profile-drift state/action fields when drift artifacts are present.
- Includes alert delivery summary fields from dispatch artifacts (`alerts.dispatch`, `alerts.lastDelivery`).
- Includes visibility summaries for heartbeat, sequence diagnostics, invocation audit, and trace linkage (`visibility.*`).

Visibility summary fields:
- `visibility.heartbeat`: `freshnessStatus`, `reasonCode`, `lastHeartbeatAt`, `heartbeatLagSeconds`, `updatedAt`, `transport`, `traceId`.
- `visibility.sequence`: `status`, `reasonCode`, `driftActive`, `violations`, `snapshotCurrent`, `eventsLast`, `updatedAt`, `transport`, `traceId`.
- `visibility.invocationAudit`: latest control invocation audit record summary (`intent`, `transport`, `idempotencyKey`, execution/confirmation/outcome status, `traceId`).
- `visibility.trace`: latest trace surface across control/reconcile/heartbeat/sequence/alert artifacts and `sharedTraceId` when all present traces agree.

### Threshold Profile Resolver
```bash
scripts/ops-manager-threshold-profile.sh --profile strict --pretty
```

Purpose:
- Resolves profile values from a versioned profile catalog.
- Enforces fail-closed behavior for unknown/invalid profiles.
- Lists available profiles via `--list`.

### Alert Sink Config Resolver
```bash
scripts/ops-manager-alert-sink-config.sh --pretty
scripts/ops-manager-alert-sink-config.sh --category health_critical --severity critical --pretty
```

Purpose:
- Resolves a versioned alert sink catalog with routing policy and category severity mapping.
- Validates sink definitions and route references with fail-closed behavior.
- Validates env-secret references for enabled sinks (can be bypassed with `--no-env-check`).

Config file precedence:
1. Explicit `--config-file`
2. `OPS_MANAGER_ALERT_SINKS_FILE`
3. `config/ops-manager-alert-sinks.v1.json`

### Alert Dispatch
```bash
scripts/ops-manager-alert-dispatch.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --alert-config-file config/ops-manager-alert-sinks.v1.json \
  --pretty
```

Purpose:
- Consumes new rows from `.superloop/ops-manager/<loop>/escalations.jsonl` using cursor-style offsets.
- Resolves dispatch policy via alert sink config and routes to `webhook`, `slack`, and `pagerduty_events`.
- Persists dispatch state and per-attempt delivery telemetry for operator triage.
- Runs automatically in `scripts/ops-manager-reconcile.sh` when `--alerts-enabled true` (default).

### Telemetry Summary
```bash
scripts/ops-manager-telemetry-summary.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --window 200 \
  --pretty
```

Purpose:
- Summarizes reconcile/control telemetry over a bounded recent window.
- Emits profile recommendation + confidence for dogfood threshold tuning.

### Profile Drift Evaluator
```bash
scripts/ops-manager-profile-drift.sh \
  --repo /path/to/repo \
  --loop my-loop \
  --applied-profile balanced \
  --recommended-profile strict \
  --recommendation-confidence medium \
  --required-streak 3 \
  --summary-window 200 \
  --pretty
```

Purpose:
- Evaluates profile mismatch drift with confidence/streak gating.
- Persists current drift state and appends drift history telemetry.
- Emits `profile_drift_detected` escalations when drift transitions active.

## Sprite Service Transport
Service implementation entrypoint:
- `scripts/ops-manager-sprite-service.py`

Service client helper:
- `scripts/ops-manager-service-client.sh`

Auth:
- shared token via `Authorization: Bearer <token>` or `X-Ops-Token`

Transport retry:
- `--retry-attempts <n>`
- `--retry-backoff-seconds <n>`

Transport mode switch:
- reconcile: `scripts/ops-manager-reconcile.sh --transport <local|sprite_service> ...`
- control: `scripts/ops-manager-control.sh --transport <local|sprite_service> ...`

## Manager Persistence Paths
- `.superloop/ops-manager/<loop>/state.json` - projected lifecycle state.
- `.superloop/ops-manager/<loop>/cursor.json` - incremental event cursor.
- `.superloop/ops-manager/<loop>/health.json` - latest health status + reason codes.
- `.superloop/ops-manager/<loop>/heartbeat.json` - latest runtime heartbeat freshness projection.
- `.superloop/ops-manager/<loop>/sequence-state.json` - latest envelope sequence diagnostics state.
- `.superloop/ops-manager/<loop>/intents.jsonl` - control intent execution log.
- `.superloop/ops-manager/<loop>/escalations.jsonl` - divergence/escalation records.
- `.superloop/ops-manager/<loop>/profile-drift.json` - current profile drift state.
- `.superloop/ops-manager/<loop>/alert-dispatch-state.json` - latest alert dispatch summary and cursor offsets.
- `.superloop/ops-manager/<loop>/telemetry/reconcile.jsonl` - reconcile attempt telemetry.
- `.superloop/ops-manager/<loop>/telemetry/control.jsonl` - control attempt telemetry.
- `.superloop/ops-manager/<loop>/telemetry/control-invocations.jsonl` - detailed control invocation audit trail.
- `.superloop/ops-manager/<loop>/telemetry/heartbeat.jsonl` - heartbeat ingestion/freshness telemetry history.
- `.superloop/ops-manager/<loop>/telemetry/sequence.jsonl` - sequence diagnostic telemetry history.
- `.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl` - profile drift history.
- `.superloop/ops-manager/<loop>/telemetry/alerts.jsonl` - alert delivery attempts/outcomes and reason codes.
- `.superloop/ops-manager/<loop>/telemetry/transport-health.json` - rolling transport failure streak state.
- `config/ops-manager-threshold-profiles.v1.json` - threshold profile catalog (repo-level, versioned).
- `config/ops-manager-alert-sinks.v1.json` - alert sink routing/catalog config (repo-level, versioned).
- `schema/ops-manager-alert-sinks.config.schema.json` - JSON schema reference for alert sink config.

## Health Reason Codes
Current reason-code surface used in health and escalation artifacts:
- `transport_unreachable`
- `ingest_stale`
- `control_ambiguous`
- `control_failed_command`
- `divergence_detected`
- `invalid_transport_payload`
- `projection_failed`
- `reconcile_failed`
- `profile_drift_detected`

## Alert Dispatch Reason Codes
Current alert dispatch telemetry/state may include:
- `invalid_escalation_json`
- `missing_escalation_category`
- `route_resolution_failed`
- `invalid_route_resolution`
- `severity_below_min`
- `no_dispatchable_sinks`
- `missing_secret`
- `http_error`
- `request_failed`
- `unsupported_sink_type`
- `invalid_sink_result`
- `sink_dispatch_failed`
- `partial_dispatch_failure`
- `dispatch_failed`
- `alert_dispatch_failed`

## Compatibility and Versioning Rules
- `schemaVersion` is required and currently fixed to `v1`.
- New fields may be added only as backward-compatible additions.
- Breaking changes require a new schema version and dual-read support during migration.
- Manager logic must key off explicit lifecycle fields and not parse free-form text output.

## Failure Behavior
The adapters are intentionally fail-closed for contract safety:

- missing required artifact root or required event file: non-zero exit
- invalid JSON in source artifacts: non-zero exit
- cursor offset ahead of available events: non-zero exit (explicit reset required)

## Operator Notes
- Use snapshot for current lifecycle state.
- Use event polling for real-time progression.
- Use both together to detect divergence between runtime activity and summary state.
