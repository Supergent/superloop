# Ops Manager Runbook (V0/V1 Transport)

## Scope
Operational procedures for manager core behavior across local and sprite-service transports:
- lifecycle projection
- divergence triage
- control-intent execution and retry
- cursor reset and replay
- service outage fallback

## Quick Paths
- manager state: `.superloop/ops-manager/<loop>/state.json`
- manager cursor: `.superloop/ops-manager/<loop>/cursor.json`
- manager health: `.superloop/ops-manager/<loop>/health.json`
- heartbeat state: `.superloop/ops-manager/<loop>/heartbeat.json`
- sequence state: `.superloop/ops-manager/<loop>/sequence-state.json`
- intent log: `.superloop/ops-manager/<loop>/intents.jsonl`
- profile drift state: `.superloop/ops-manager/<loop>/profile-drift.json`
- alert dispatch state: `.superloop/ops-manager/<loop>/alert-dispatch-state.json`
- reconcile telemetry: `.superloop/ops-manager/<loop>/telemetry/reconcile.jsonl`
- control telemetry: `.superloop/ops-manager/<loop>/telemetry/control.jsonl`
- control invocation audit: `.superloop/ops-manager/<loop>/telemetry/control-invocations.jsonl`
- heartbeat telemetry: `.superloop/ops-manager/<loop>/telemetry/heartbeat.jsonl`
- sequence telemetry: `.superloop/ops-manager/<loop>/telemetry/sequence.jsonl`
- profile drift telemetry: `.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl`
- alert dispatch telemetry: `.superloop/ops-manager/<loop>/telemetry/alerts.jsonl`
- transport health: `.superloop/ops-manager/<loop>/telemetry/transport-health.json`
- threshold profiles: `config/ops-manager-threshold-profiles.v1.json`
- alert sinks config: `config/ops-manager-alert-sinks.v1.json`
- runtime events: `.superloop/loops/<loop>/events.jsonl`

## Standard Reconcile
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --pretty
```

Expected outputs:
- updated projection state file
- updated cursor file
- updated health file
- appended reconcile telemetry

## Operator Status Snapshot
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --summary-window 200 --pretty
```

Use this as the default first read during incidents; it summarizes lifecycle, health, reason codes, latest control/reconcile outcomes, and tuning guidance (`recommendedProfile`, `confidence`).
Alert delivery fields are included under `alerts.dispatch` and `alerts.lastDelivery`.
Total visibility fields are surfaced under `visibility.heartbeat`, `visibility.sequence`, `visibility.invocationAudit`, and `visibility.trace`.

## Total Visibility Triage
Use this flow when the operator needs end-to-end visibility from runtime heartbeat to escalation delivery.

1. Pull status visibility summary:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

2. Verify heartbeat freshness surface:
- `visibility.heartbeat.freshnessStatus`: `fresh|degraded|critical`
- `visibility.heartbeat.reasonCode`: expected `runtime_heartbeat_stale` when degraded/critical
- `visibility.heartbeat.lastHeartbeatAt` and `heartbeatLagSeconds`

3. Verify sequence integrity surface:
- `visibility.sequence.status`: expected `ok` or `ordering_drift_detected`
- `visibility.sequence.violations`: inspect for `snapshot_sequence_regression`, `event_sequence_regression`, or missing sequence fields
- `visibility.sequence.traceId`: correlate with reconcile/escalation traces

4. Verify control invocation audit when control operations were issued:
```bash
tail -n 5 .superloop/ops-manager/<loop>/telemetry/control-invocations.jsonl
```
- compare `visibility.invocationAudit.traceId` against `visibility.trace.controlInvocationTraceId`
- confirm execution/confirmation/outcome status before retrying actions

5. Verify trace linkage across visibility and alert surfaces:
- `visibility.trace.reconcileTraceId`
- `visibility.trace.alertTraceId`
- `visibility.trace.sharedTraceId` (non-null means the latest trace surfaces are aligned)

## Profile Drift Triage
Use when policy profile and telemetry recommendation may be diverging.

1. Inspect current drift state:
```bash
jq '.' .superloop/ops-manager/<loop>/profile-drift.json
```

2. Check recent drift evaluations:
```bash
tail -n 20 .superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl
```

3. Read status action guidance:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --summary-window 200 --pretty
```

Operator actions for active drift (`status=drift_active`):
- review applied profile vs recommendation and rationale
- keep advisory mode (no automatic profile switching)
- apply explicit profile change only after operator confirmation

## Divergence Triage
1. Inspect current manager projection:
```bash
jq '.' .superloop/ops-manager/<loop>/state.json
```

2. Check divergence flags:
```bash
jq '.divergence' .superloop/ops-manager/<loop>/state.json
```

3. If divergence is true:
- freeze automated control actions for this loop
- replay from start to rebuild context:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --from-start --pretty
```
- if divergence persists, append escalation evidence to `.superloop/ops-manager/<loop>/escalations.jsonl`

4. Confirm health reason surface:
```bash
jq '.health.status, .health.reasonCodes' .superloop/ops-manager/<loop>/state.json
```

Expected reason code for this workflow:
- `divergence_detected`

## Safe Control-Intent Retry
1. Inspect latest intent entries:
```bash
tail -n 5 .superloop/ops-manager/<loop>/intents.jsonl
```

2. Retry only when prior status is `ambiguous` or `failed_command` and runtime state still requires intervention.

3. Execute intent with confirmation:
```bash
scripts/ops-manager-control.sh --repo /path/to/repo --loop <loop-id> --intent cancel
```

4. Reconcile immediately after intent:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id>
```

5. Validate control telemetry and ambiguous outcomes:
```bash
tail -n 5 .superloop/ops-manager/<loop>/telemetry/control.jsonl
```

If latest reason code is `control_ambiguous`, do not repeat actions blindly; inspect runtime artifacts first.

## Cursor Reset and Replay
Use when cursor drift or corrupted cursor JSON is detected.

1. Backup and remove cursor:
```bash
cp .superloop/ops-manager/<loop>/cursor.json .superloop/ops-manager/<loop>/cursor.backup.json
rm -f .superloop/ops-manager/<loop>/cursor.json
```

2. Replay from start:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --from-start --pretty
```

3. Verify cursor offset is monotonic and state no longer flags `cursorRegression`.

## Service Mode Operations
Reconcile using sprite service transport:
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --transport sprite_service \
  --service-base-url http://127.0.0.1:8787 \
  --service-token "$OPS_MANAGER_SERVICE_TOKEN"
```

Control using sprite service transport:
```bash
scripts/ops-manager-control.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --intent approve \
  --transport sprite_service \
  --service-base-url http://127.0.0.1:8787 \
  --service-token "$OPS_MANAGER_SERVICE_TOKEN" \
  --idempotency-key approve-<loop-id>-001
```

## Service Outage Fallback
If sprite service requests fail after retries:
1. Record the failed attempt in `intents.jsonl` and halt automated interventions.
2. Switch to local transport for critical operations:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --transport local
scripts/ops-manager-control.sh --repo /path/to/repo --loop <loop-id> --intent cancel --transport local
```
3. After service recovery, replay from start or stable cursor and re-enable service mode.

Operational reason codes expected in this flow:
- `transport_unreachable`
- `invalid_transport_payload`
- `ingest_stale` (if outage delays event freshness long enough)

## Partial Visibility Fallback
Use when status shows incomplete visibility (for example, missing `visibility.heartbeat` or `visibility.sequence`) due runtime/service gaps.

1. Confirm raw runtime artifacts exist:
```bash
ls -l .superloop/loops/<loop>/heartbeat.v1.json .superloop/loops/<loop>/events.jsonl
```

2. Force a full replay to repopulate sequence + heartbeat projections:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --from-start --pretty
```

3. If service mode is unstable, run fallback reconcile locally until transport recovers:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --transport local --from-start
```

4. Re-run status and ensure visibility surfaces are restored:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

## Alert Sink Config Baseline
Resolve config and route behavior before enabling external dispatch:

```bash
scripts/ops-manager-alert-sink-config.sh --pretty
scripts/ops-manager-alert-sink-config.sh --category health_critical --severity critical --pretty
```

Secret env checks:
- Enabled sinks require configured env-secret references to be set.
- Resolver is fail-closed by default when enabled sink secrets are missing.
- Use `--no-env-check` only for dry-run catalog inspection.

Config precedence:
1. `--config-file`
2. `OPS_MANAGER_ALERT_SINKS_FILE`
3. `config/ops-manager-alert-sinks.v1.json`

## Alert Delivery Triage
Use when escalations are being generated but expected external notifications are not observed.

1. Check current delivery summary in status:
```bash
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

2. Inspect dispatch state:
```bash
jq '.' .superloop/ops-manager/<loop>/alert-dispatch-state.json
```

3. Inspect recent delivery telemetry:
```bash
tail -n 20 .superloop/ops-manager/<loop>/telemetry/alerts.jsonl
```

4. Map reason codes to likely operator actions:
- `missing_secret`: set required sink env vars or disable the sink.
- `route_resolution_failed` / `invalid_route_resolution`: validate `config/ops-manager-alert-sinks.v1.json` against schema and route references.
- `http_error` / `request_failed`: verify endpoint reachability, credentials, and timeout settings.
- `no_dispatchable_sinks`: expected when matching routes only reference disabled sinks.
- `alert_dispatch_failed`: dispatch command failed during reconcile wrapper invocation; rerun dispatch manually after correcting root cause.

5. Manual replay after fix:
```bash
scripts/ops-manager-alert-dispatch.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --alert-config-file config/ops-manager-alert-sinks.v1.json \
  --pretty
```

## Alert Outage Fallback
When downstream sinks are degraded/outage-level:

1. Keep reconcile/control available by temporarily disabling dispatch in reconcile:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --alerts-enabled false
```

2. Continue collecting escalation evidence in:
- `.superloop/ops-manager/<loop>/escalations.jsonl`

3. After sink recovery, replay pending escalations through dispatch:
```bash
scripts/ops-manager-alert-dispatch.sh --repo /path/to/repo --loop <loop-id> --pretty
```

4. Re-enable dispatch and verify status summary reports fresh alert activity:
```bash
scripts/ops-manager-reconcile.sh --repo /path/to/repo --loop <loop-id> --alerts-enabled true
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

## Threshold Tuning
Default profile catalog (`config/ops-manager-threshold-profiles.v1.json`):
- `strict`: `120/300` ingest-lag seconds, `1/2` failure streak
- `balanced` (default): `300/900` ingest-lag seconds, `2/4` failure streak
- `relaxed`: `600/1800` ingest-lag seconds, `3/6` failure streak

Telemetry-first tuning workflow:
1. Summarize recent telemetry and inspect recommendation:
```bash
scripts/ops-manager-telemetry-summary.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --window 200 \
  --pretty
```
2. Apply profile on reconcile:
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --threshold-profile balanced \
  --drift-min-confidence medium \
  --drift-required-streak 3
```
3. If needed, override specific values explicitly (highest precedence):
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --threshold-profile strict \
  --critical-ingest-lag-seconds 480
```

Precedence rules:
1. explicit threshold flags
2. selected profile (`--threshold-profile` or `OPS_MANAGER_THRESHOLD_PROFILE`)
3. catalog default profile
