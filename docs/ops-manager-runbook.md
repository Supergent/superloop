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
- profile drift state: `.superloop/ops-manager/<loop>/profile-drift.json`
- reconcile telemetry: `.superloop/ops-manager/<loop>/telemetry/reconcile.jsonl`
- control telemetry: `.superloop/ops-manager/<loop>/telemetry/control.jsonl`
- profile drift telemetry: `.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl`
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
