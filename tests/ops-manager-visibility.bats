#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
  SERVICE_PID=""
  SERVICE_PORT=""
  SERVICE_URL=""
  SERVICE_TOKEN="test-token"
}

teardown() {
  if [[ -n "$SERVICE_PID" ]] && kill -0 "$SERVICE_PID" 2>/dev/null; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_DIR"
}

get_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

write_runtime_artifacts() {
  local repo="$1"
  local loop_id="$2"
  local event_ts="$3"

  mkdir -p "$repo/.superloop/loops/$loop_id"

  cat > "$repo/.superloop/state.json" <<JSON
{"active":true,"loop_index":0,"iteration":2,"current_loop_id":"$loop_id","updated_at":"$event_ts"}
JSON

  cat > "$repo/.superloop/loops/$loop_id/run-summary.json" <<JSON
{"version":1,"loop_id":"$loop_id","updated_at":"$event_ts","entries":[{"run_id":"run-123","iteration":1,"gates":{"tests":"ok","validation":"ok","prerequisites":"ok","checklist":"ok","evidence":"skipped","approval":"none"},"stuck":{"streak":0,"threshold":3},"completion_ok":false,"ended_at":"$event_ts"}]}
JSON

  cat > "$repo/.superloop/loops/$loop_id/events.jsonl" <<JSONL
{"timestamp":"$event_ts","event":"loop_start","loop_id":"$loop_id","run_id":"run-123","iteration":1,"data":{"max_iterations":5}}
{"timestamp":"$event_ts","event":"iteration_start","loop_id":"$loop_id","run_id":"run-123","iteration":2,"data":{"started_at":"$event_ts"}}
JSONL
}

write_runtime_heartbeat() {
  local repo="$1"
  local loop_id="$2"
  local heartbeat_ts="$3"

  cat > "$repo/.superloop/loops/$loop_id/heartbeat.v1.json" <<JSON
{"schemaVersion":"v1","timestamp":"$heartbeat_ts","source":"runtime","status":"running","stage":"iteration"}
JSON
}

write_stub_superloop() {
  local path="$1"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

repo=""
loop=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --loop)
      loop="$2"
      shift 2
      ;;
    --by)
      shift 2
      ;;
    --note)
      shift 2
      ;;
    --reject)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$repo" ]]; then
  echo "missing repo" >&2
  exit 1
fi
if [[ -z "$loop" ]]; then
  loop="demo-loop"
fi

mkdir -p "$repo/.superloop/loops/$loop"

case "$cmd" in
  cancel)
    cat > "$repo/.superloop/state.json" <<JSON
{"active":false,"loop_index":0,"iteration":2,"current_loop_id":"$loop","updated_at":"2026-02-22T12:10:00Z"}
JSON
    cat >> "$repo/.superloop/loops/$loop/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T12:10:00Z","event":"loop_stop","loop_id":"$loop","run_id":"run-123","iteration":2,"data":{"reason":"manual_cancel"}}
JSONL
    echo "Cancelled loop state."
    ;;
  *)
    echo "unsupported command: $cmd" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$path"
}

start_service() {
  local repo="$1"
  local token="$2"
  local superloop_bin_override="${3:-}"

  SERVICE_PORT="$(get_free_port)"
  SERVICE_URL="http://127.0.0.1:$SERVICE_PORT"

  if [[ -n "$superloop_bin_override" ]]; then
    OPS_MANAGER_SERVICE_TOKEN="$token" SUPERLOOP_BIN="$superloop_bin_override" \
      "$PROJECT_ROOT/scripts/ops-manager-sprite-service.py" \
      --repo "$repo" --host 127.0.0.1 --port "$SERVICE_PORT" --token "$token" \
      >"$TEMP_DIR/service.log" 2>&1 &
  else
    OPS_MANAGER_SERVICE_TOKEN="$token" \
      "$PROJECT_ROOT/scripts/ops-manager-sprite-service.py" \
      --repo "$repo" --host 127.0.0.1 --port "$SERVICE_PORT" --token "$token" \
      >"$TEMP_DIR/service.log" 2>&1 &
  fi

  SERVICE_PID=$!

  local ready=0
  for _ in $(seq 1 60); do
    if curl -sS -H "X-Ops-Token: $token" "$SERVICE_URL/healthz" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.1
  done

  [ "$ready" -eq 1 ]
}

trim_events_to_single_line() {
  local repo="$1"
  local loop_id="$2"
  local events_file="$repo/.superloop/loops/$loop_id/events.jsonl"

  run bash -lc "head -n 1 '$events_file' > '$events_file.tmp' && mv '$events_file.tmp' '$events_file'"
  [ "$status" -eq 0 ]
}

@test "status visibility surfaces stale heartbeat and ordering drift with trace linkage" {
  local loop_id="demo-loop"
  local repo="$TEMP_DIR/repo"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$repo" "$loop_id" "$now_ts"
  write_runtime_heartbeat "$repo" "$loop_id" "2020-01-01T00:00:00Z"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --from-start \
    --trace-id "trace-vis-baseline-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  trim_events_to_single_line "$repo" "$loop_id"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --from-start \
    --trace-id "trace-vis-drift-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-heartbeat-lag-seconds 1 \
    --critical-heartbeat-lag-seconds 999999999
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.visibility.heartbeat.freshnessStatus' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -r '.visibility.heartbeat.reasonCode' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "runtime_heartbeat_stale" ]

  run jq -r '.visibility.sequence.status' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "ordering_drift_detected" ]

  run jq -r '.visibility.sequence.driftActive' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -e '.visibility.sequence.violations | index("snapshot_sequence_regression") != null' <<<"$status_json"
  [ "$status" -eq 0 ]

  run jq -e '.visibility.sequence.violations | index("event_sequence_regression") != null' <<<"$status_json"
  [ "$status" -eq 0 ]

  run jq -r '.visibility.trace.reconcileTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-drift-1" ]

  run jq -r '.visibility.trace.heartbeatTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-drift-1" ]

  run jq -r '.visibility.trace.sequenceTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-drift-1" ]

  run jq -r '.visibility.trace.sharedTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-drift-1" ]
}

@test "status visibility includes control invocation audit fields" {
  local loop_id="demo-loop"
  local repo="$TEMP_DIR/repo-control"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$repo" "$loop_id" "$now_ts"
  local stub="$TEMP_DIR/stub-superloop-control.sh"
  write_stub_superloop "$stub"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --trace-id "trace-vis-control-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  run env SUPERLOOP_BIN="$stub" \
    "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --intent cancel \
    --trace-id "trace-vis-control-1"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.visibility.invocationAudit.intent' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "cancel" ]

  run jq -r '.visibility.invocationAudit.transport' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "local" ]

  run jq -r '.visibility.invocationAudit.executionStatus' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "succeeded" ]

  run jq -r '.visibility.invocationAudit.confirmationStatus' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]

  run jq -r '.visibility.invocationAudit.outcomeStatus' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]

  run jq -r '.visibility.invocationAudit.traceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-control-1" ]

  run jq -r '.visibility.trace.controlInvocationTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-control-1" ]
}

@test "local and sprite_service transports preserve visibility parity for reason surfaces" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local local_repo="$TEMP_DIR/local-repo"
  local service_repo="$TEMP_DIR/service-repo"
  mkdir -p "$local_repo" "$service_repo"

  write_runtime_artifacts "$local_repo" "$loop_id" "$now_ts"
  write_runtime_artifacts "$service_repo" "$loop_id" "$now_ts"
  write_runtime_heartbeat "$local_repo" "$loop_id" "2020-01-01T00:00:00Z"
  write_runtime_heartbeat "$service_repo" "$loop_id" "2020-01-01T00:00:00Z"

  local local_stub="$TEMP_DIR/stub-superloop-local.sh"
  local service_stub="$TEMP_DIR/stub-superloop-service.sh"
  write_stub_superloop "$local_stub"
  write_stub_superloop "$service_stub"
  start_service "$service_repo" "$SERVICE_TOKEN" "$service_stub"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --from-start \
    --trace-id "trace-vis-parity-baseline-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --from-start \
    --trace-id "trace-vis-parity-baseline-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  trim_events_to_single_line "$local_repo" "$loop_id"
  trim_events_to_single_line "$service_repo" "$loop_id"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --from-start \
    --trace-id "trace-vis-parity-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-heartbeat-lag-seconds 1 \
    --critical-heartbeat-lag-seconds 999999999
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --from-start \
    --trace-id "trace-vis-parity-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-heartbeat-lag-seconds 1 \
    --critical-heartbeat-lag-seconds 999999999
  [ "$status" -eq 0 ]

  run env SUPERLOOP_BIN="$local_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --intent cancel \
    --trace-id "trace-vis-parity-1"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --intent cancel \
    --trace-id "trace-vis-parity-1" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --idempotency-key "vis-parity-cancel-1"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$local_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local local_status_json="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$service_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local service_status_json="$output"

  local local_reason_codes
  local service_reason_codes
  local_reason_codes="$(jq -c '.health.reasonCodes | sort' <<<"$local_status_json")"
  service_reason_codes="$(jq -c '.health.reasonCodes | sort' <<<"$service_status_json")"
  [ "$local_reason_codes" = "$service_reason_codes" ]

  local local_visibility_summary
  local service_visibility_summary
  local_visibility_summary="$(jq -c '{heartbeat: (.visibility.heartbeat | {freshnessStatus, reasonCode}), sequence: (.visibility.sequence | {status, reasonCode, driftActive, violations: ((.violations // []) | sort)}), invocationAudit: (.visibility.invocationAudit | {intent, executionStatus, confirmationStatus, outcomeStatus}), trace: (.visibility.trace | {controlTraceId, controlInvocationTraceId, reconcileTraceId, heartbeatTraceId, sequenceTraceId, sharedTraceId})}' <<<"$local_status_json")"
  service_visibility_summary="$(jq -c '{heartbeat: (.visibility.heartbeat | {freshnessStatus, reasonCode}), sequence: (.visibility.sequence | {status, reasonCode, driftActive, violations: ((.violations // []) | sort)}), invocationAudit: (.visibility.invocationAudit | {intent, executionStatus, confirmationStatus, outcomeStatus}), trace: (.visibility.trace | {controlTraceId, controlInvocationTraceId, reconcileTraceId, heartbeatTraceId, sequenceTraceId, sharedTraceId})}' <<<"$service_status_json")"
  [ "$local_visibility_summary" = "$service_visibility_summary" ]

  run jq -r '.visibility.trace.sharedTraceId' <<<"$local_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-parity-1" ]

  run jq -r '.visibility.trace.sharedTraceId' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-parity-1" ]
}

@test "visibility invocation audit preserves autonomous no-confirm parity across local and sprite_service transports" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local local_repo="$TEMP_DIR/visibility-autonomous-local"
  local service_repo="$TEMP_DIR/visibility-autonomous-service"
  mkdir -p "$local_repo" "$service_repo"

  write_runtime_artifacts "$local_repo" "$loop_id" "$now_ts"
  write_runtime_artifacts "$service_repo" "$loop_id" "$now_ts"

  local local_stub="$TEMP_DIR/stub-superloop-autonomous-local.sh"
  local service_stub="$TEMP_DIR/stub-superloop-autonomous-service.sh"
  write_stub_superloop "$local_stub"
  write_stub_superloop "$service_stub"
  start_service "$service_repo" "$SERVICE_TOKEN" "$service_stub"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --trace-id "trace-vis-autonomous-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --trace-id "trace-vis-autonomous-1" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  run env SUPERLOOP_BIN="$local_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --intent cancel \
    --trace-id "trace-vis-autonomous-1" \
    --no-confirm
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --intent cancel \
    --trace-id "trace-vis-autonomous-1" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --idempotency-key "vis-autonomous-cancel-1" \
    --no-confirm
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$local_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local local_status_json="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$service_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local service_status_json="$output"

  local local_projection
  local service_projection
  local_projection="$(jq -c '{invocationAudit: (.visibility.invocationAudit | {intent, executionStatus, confirmationStatus, outcomeStatus}), trace: (.visibility.trace | {controlInvocationTraceId, sharedTraceId})}' <<<"$local_status_json")"
  service_projection="$(jq -c '{invocationAudit: (.visibility.invocationAudit | {intent, executionStatus, confirmationStatus, outcomeStatus}), trace: (.visibility.trace | {controlInvocationTraceId, sharedTraceId})}' <<<"$service_status_json")"
  [ "$local_projection" = "$service_projection" ]

  run jq -r '.visibility.invocationAudit.confirmationStatus' <<<"$local_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "skipped" ]

  run jq -r '.visibility.invocationAudit.outcomeStatus' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "executed_unconfirmed" ]

  run jq -r '.visibility.trace.controlInvocationTraceId' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-autonomous-1" ]
}

@test "status preserves reason-surface parity after failed local and sprite_service reconciles" {
  local loop_id="demo-loop"
  local local_repo="$TEMP_DIR/visibility-failure-local"
  local service_repo="$TEMP_DIR/visibility-failure-service"
  mkdir -p "$local_repo" "$service_repo"
  start_service "$service_repo" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --trace-id "trace-vis-failure-parity-1"
  [ "$status" -ne 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --trace-id "trace-vis-failure-parity-1"
  [ "$status" -ne 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$local_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local local_status_json="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$service_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local service_status_json="$output"

  run jq -r '.health.status' <<<"$local_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -r '.health.status' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  local local_reason_codes
  local service_reason_codes
  local_reason_codes="$(jq -c '.health.reasonCodes | sort' <<<"$local_status_json")"
  service_reason_codes="$(jq -c '.health.reasonCodes | sort' <<<"$service_status_json")"
  [ "$local_reason_codes" = "$service_reason_codes" ]

  run jq -e '.health.reasonCodes | index("transport_unreachable") != null' <<<"$local_status_json"
  [ "$status" -eq 0 ]

  run jq -e '.health.reasonCodes | index("transport_unreachable") != null' <<<"$service_status_json"
  [ "$status" -eq 0 ]

  run jq -r '.reconcile.lastStatus' <<<"$local_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "failed" ]

  run jq -r '.reconcile.lastStatus' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "failed" ]

  run jq -r '.visibility.trace.reconcileTraceId' <<<"$local_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-failure-parity-1" ]

  run jq -r '.visibility.trace.reconcileTraceId' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-vis-failure-parity-1" ]
}

@test "fleet status keeps rollout autopause and governance projections stable across transports" {
  local local_repo="$TEMP_DIR/visibility-fleet-local"
  local service_repo="$TEMP_DIR/visibility-fleet-service"

  mkdir -p "$local_repo/.superloop/ops-manager/fleet/telemetry"
  mkdir -p "$service_repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$local_repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-visibility-parity","loops":[{"loopId":"loop-red","transport":"local"},{"loopId":"loop-blue","transport":"local"}]}
JSON

  cat > "$service_repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-visibility-parity","loops":[{"loopId":"loop-red","transport":"sprite_service","service":{"baseUrl":"http://sprite-service.local","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}},{"loopId":"loop-blue","transport":"sprite_service","service":{"baseUrl":"http://sprite-service.local","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}}]}
JSON

  cat > "$local_repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-24T10:00:00Z","startedAt":"2026-02-24T09:59:40Z","fleetId":"fleet-visibility-parity","traceId":"trace-fleet-visibility-parity-1","status":"partial_failure","reasonCodes":["fleet_partial_failure"],"loopCount":2,"successCount":1,"failedCount":1,"skippedCount":0,"durationSeconds":20,"execution":{"maxParallel":2,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-24T10:00:00Z","startedAt":"2026-02-24T09:59:45Z","loopId":"loop-red","transport":"local","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-visibility-parity-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}},{"timestamp":"2026-02-24T10:00:00Z","startedAt":"2026-02-24T09:59:50Z","loopId":"loop-blue","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":4,"traceId":"trace-fleet-visibility-parity-1-loop-blue","files":{"stateFile":"/tmp/loop-blue/state.json","healthFile":"/tmp/loop-blue/health.json","cursorFile":"/tmp/loop-blue/cursor.json","reconcileTelemetryFile":"/tmp/loop-blue/reconcile.jsonl"}}]}
JSON

  cp "$local_repo/.superloop/ops-manager/fleet/state.json" "$service_repo/.superloop/ops-manager/fleet/state.json"

  cat > "$local_repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-24T10:00:02Z","fleetId":"fleet-visibility-parity","traceId":"trace-fleet-visibility-parity-policy-1","mode":"guarded_auto","candidateCount":2,"unsuppressedCount":2,"suppressedCount":0,"autoEligibleCount":1,"manualOnlyCount":1,"summary":{"byAutonomyReason":{"category_not_allowlisted":1,"autonomous_rollout_paused_auto":1,"autonomous_autopause_failure_spike":1}},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-702","rationale":"visibility parity drill","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z","reviewWindowDays":311,"authorityContextPresent":true},"controls":{"safety":{"killSwitch":false}},"rollout":{"canaryPercent":100,"scopeLoopIds":["loop-red","loop-blue"],"selectorSalt":"fleet-autonomous-rollout-v1","candidateBuckets":{"inScopeCount":2,"inCohortCount":2,"outOfCohortCount":0},"pause":{"active":true,"reasons":["autonomous_rollout_paused_auto"],"manual":false,"auto":{"enabled":true,"active":true,"reasons":["autonomous_autopause_failure_spike"],"lookbackExecutions":3,"minSampleSize":2,"ambiguityRateThreshold":0.4,"failureRateThreshold":0.5,"metrics":{"windowExecutionCount":3,"attemptedCount":2,"executedCount":1,"ambiguousCount":0,"failedCount":1,"ambiguityRate":0,"failureRate":0.5}}}}},"reasonCodes":["fleet_action_required","fleet_auto_candidates_rollout_gated"],"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-blue:health_critical","loopId":"loop-blue","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted"]}}]}
JSON

  cp "$local_repo/.superloop/ops-manager/fleet/policy-state.json" "$service_repo/.superloop/ops-manager/fleet/policy-state.json"

  cat > "$local_repo/.superloop/ops-manager/fleet/handoff-state.json" <<'JSON'
{"schemaVersion":"v1","generatedAt":"2026-02-24T10:00:03Z","updatedAt":"2026-02-24T10:00:06Z","fleetId":"fleet-visibility-parity","traceId":"trace-fleet-visibility-parity-handoff-1","policyTraceId":"trace-fleet-visibility-parity-policy-1","mode":"guarded_auto","summary":{"intentCount":2,"autoEligibleIntentCount":1,"manualOnlyIntentCount":1,"pendingConfirmationCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1},"reasonCodes":["fleet_handoff_action_required","fleet_handoff_confirmation_pending","fleet_handoff_execution_failed"],"intents":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","intent":"cancel","status":"execution_failed","transport":"local","autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"intentId":"loop-blue:health_critical:cancel","loopId":"loop-blue","intent":"cancel","status":"pending_operator_confirmation","transport":"local","autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted"]}}],"execution":{"mode":"autonomous","requestedBy":"ops-bot","requestedAt":"2026-02-24T10:00:04Z","completedAt":"2026-02-24T10:00:06Z","requestedIntentCount":1,"executedIntentCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1,"results":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","status":"failed","reasonCode":"control_failed_command"}]}}
JSON

  cat > "$service_repo/.superloop/ops-manager/fleet/handoff-state.json" <<'JSON'
{"schemaVersion":"v1","generatedAt":"2026-02-24T10:00:03Z","updatedAt":"2026-02-24T10:00:06Z","fleetId":"fleet-visibility-parity","traceId":"trace-fleet-visibility-parity-handoff-1","policyTraceId":"trace-fleet-visibility-parity-policy-1","mode":"guarded_auto","summary":{"intentCount":2,"autoEligibleIntentCount":1,"manualOnlyIntentCount":1,"pendingConfirmationCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1},"reasonCodes":["fleet_handoff_action_required","fleet_handoff_confirmation_pending","fleet_handoff_execution_failed"],"intents":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","intent":"cancel","status":"execution_failed","transport":"sprite_service","autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"intentId":"loop-blue:health_critical:cancel","loopId":"loop-blue","intent":"cancel","status":"pending_operator_confirmation","transport":"sprite_service","autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted"]}}],"execution":{"mode":"autonomous","requestedBy":"ops-bot","requestedAt":"2026-02-24T10:00:04Z","completedAt":"2026-02-24T10:00:06Z","requestedIntentCount":1,"executedIntentCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1,"results":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","status":"failed","reasonCode":"control_failed_command"}]}}
JSON

  cat > "$local_repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl" <<'JSONL'
{"timestamp":"2026-02-24T10:00:06Z","category":"fleet_handoff_execute","fleetId":"fleet-visibility-parity","traceId":"trace-fleet-visibility-parity-handoff-1","execution":{"mode":"autonomous","requestedIntentCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1},"summary":{"summary":{"intentCount":2,"autoEligibleIntentCount":1,"manualOnlyIntentCount":1,"pendingConfirmationCount":1,"pendingManualOnlyCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1},"reasonCodes":["fleet_handoff_action_required","fleet_handoff_execution_failed"]}}
JSONL

  cp "$local_repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl" "$service_repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl"

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-status.sh" --repo "$local_repo"
  [ "$status" -eq 0 ]
  local local_status_json="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-status.sh" --repo "$service_repo"
  [ "$status" -eq 0 ]
  local service_status_json="$output"

  local local_projection
  local service_projection
  local_projection="$(jq -c '{governance: (.autonomous.governance | {changedBy, changedAt, why, until, posture, blocksAutonomous}), rollout: (.autonomous.rollout | {state, autopause}), outcomeRollup: .autonomous.outcomeRollup, byPath: (.autonomous.safetyGateDecisions.byPath | {policyGated, rolloutGated, governanceGated}), suppressionReasonCodes: ((.autonomous.safetyGateDecisions.suppressionReasonCodes // []) | map(select(. != "autonomous_suppression_transport_gated")) | sort), telemetryRollup: .latestHandoffTelemetry.autonomousOutcomeRollup}' <<<"$local_status_json")"
  service_projection="$(jq -c '{governance: (.autonomous.governance | {changedBy, changedAt, why, until, posture, blocksAutonomous}), rollout: (.autonomous.rollout | {state, autopause}), outcomeRollup: .autonomous.outcomeRollup, byPath: (.autonomous.safetyGateDecisions.byPath | {policyGated, rolloutGated, governanceGated}), suppressionReasonCodes: ((.autonomous.safetyGateDecisions.suppressionReasonCodes // []) | map(select(. != "autonomous_suppression_transport_gated")) | sort), telemetryRollup: .latestHandoffTelemetry.autonomousOutcomeRollup}' <<<"$service_status_json")"
  [ "$local_projection" = "$service_projection" ]

  run jq -r '.autonomous.governance.posture' <<<"$local_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "active" ]

  run jq -r '.autonomous.rollout.autopause.active' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.autonomous.safetyGateDecisions.byPath.transportGated.blockedCount' <<<"$local_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.autonomous.safetyGateDecisions.byPath.transportGated.blockedCount' <<<"$service_status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.autonomous.safetyGateDecisions.suppressionReasonCodes | index("autonomous_suppression_transport_gated") != null' <<<"$service_status_json"
  [ "$status" -eq 0 ]
}
