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
- intent log: `.superloop/ops-manager/<loop>/intents.jsonl`
- reconcile telemetry: `.superloop/ops-manager/<loop>/telemetry/reconcile.jsonl`
- control telemetry: `.superloop/ops-manager/<loop>/telemetry/control.jsonl`
- transport health: `.superloop/ops-manager/<loop>/telemetry/transport-health.json`
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
scripts/ops-manager-status.sh --repo /path/to/repo --loop <loop-id> --pretty
```

Use this as the default first read during incidents; it summarizes lifecycle, health, reason codes, and latest control/reconcile outcomes.

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

## Threshold Tuning
Default reconcile thresholds:
- degraded ingest lag: `300s`
- critical ingest lag: `900s`
- degraded transport failure streak: `2`
- critical transport failure streak: `4`

Override example:
```bash
scripts/ops-manager-reconcile.sh \
  --repo /path/to/repo \
  --loop <loop-id> \
  --degraded-ingest-lag-seconds 120 \
  --critical-ingest-lag-seconds 300 \
  --degraded-transport-failure-streak 1 \
  --critical-transport-failure-streak 3
```
