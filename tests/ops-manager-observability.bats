#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  OBS_FIXTURES="$PROJECT_ROOT/tests/fixtures/ops-manager/observability"
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

start_service() {
  local repo="$1"
  local token="$2"

  SERVICE_PORT="$(get_free_port)"
  SERVICE_URL="http://127.0.0.1:$SERVICE_PORT"

  OPS_MANAGER_SERVICE_TOKEN="$token" \
    "$PROJECT_ROOT/scripts/ops-manager-sprite-service.py" \
    --repo "$repo" --host 127.0.0.1 --port "$SERVICE_PORT" --token "$token" \
    >"$TEMP_DIR/service.log" 2>&1 &

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

@test "reconcile emits healthy health projection and operator status surface" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  run jq -r '.health.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "healthy" ]

  local health_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/health.json"
  [ -f "$health_file" ]

  run jq -r '.status' "$health_file"
  [ "$status" -eq 0 ]
  [ "$output" = "healthy" ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$TEMP_DIR" --loop "$loop_id"
  [ "$status" -eq 0 ]

  run jq -r '.health.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "healthy" ]
}

@test "reconcile marks ingest_stale as degraded and escalates with reason codes" {
  local loop_id="demo-loop"
  local stale_event_at
  stale_event_at="$(tr -d '\r\n' < "$OBS_FIXTURES/stale-event-at.txt")"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id" "$stale_event_at"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --degraded-ingest-lag-seconds 1 \
    --critical-ingest-lag-seconds 999999999
  [ "$status" -eq 0 ]
  local stale_state_json="$output"

  run jq -r '.health.status' <<<"$stale_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -c '.health.reasonCodes | sort' <<<"$stale_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = '["ingest_stale"]' ]

  local escalations_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/escalations.jsonl"
  [ -f "$escalations_file" ]

  run bash -lc "tail -n 1 '$escalations_file' | jq -r '.category'"
  [ "$status" -eq 0 ]
  [ "$output" = "health_degraded" ]
}

@test "reconcile surfaces control_ambiguous as degraded health reason" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id" "$now_ts"

  local intents_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/intents.jsonl"
  mkdir -p "$(dirname "$intents_file")"
  cp "$OBS_FIXTURES/intents-ambiguous.jsonl" "$intents_file"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local ambiguous_state_json="$output"

  run jq -r '.health.status' <<<"$ambiguous_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -c '.health.reasonCodes | sort' <<<"$ambiguous_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = '["control_ambiguous"]' ]
}

@test "local and sprite_service transports produce equivalent observability health" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local local_repo="$TEMP_DIR/local"
  local service_repo="$TEMP_DIR/service"
  mkdir -p "$local_repo" "$service_repo"

  write_runtime_artifacts "$local_repo" "$loop_id" "$now_ts"
  write_runtime_artifacts "$service_repo" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local local_health_status
  local_health_status="$(jq -r '.health.status' <<<"$output")"
  local local_reason_codes
  local_reason_codes="$(jq -c '.health.reasonCodes | sort' <<<"$output")"

  start_service "$service_repo" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local service_state_json="$output"

  run jq -r '.health.status' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_health_status" ]

  run jq -c '.health.reasonCodes | sort' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_reason_codes" ]
}

@test "local and sprite_service transports produce equivalent profile drift outputs" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local local_repo="$TEMP_DIR/local-drift"
  local service_repo="$TEMP_DIR/service-drift"
  mkdir -p "$local_repo" "$service_repo"

  write_runtime_artifacts "$local_repo" "$loop_id" "$now_ts"
  write_runtime_artifacts "$service_repo" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --threshold-profile balanced \
    --drift-min-confidence low \
    --drift-required-streak 1 \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local local_state_json="$output"
  local local_drift_status
  local_drift_status="$(jq -r '.drift.status' <<<"$local_state_json")"
  local local_drift_profile
  local_drift_profile="$(jq -r '.drift.recommendedProfile' <<<"$local_state_json")"
  local local_drift_active
  local_drift_active="$(jq -r '.drift.driftActive' <<<"$local_state_json")"

  start_service "$service_repo" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --threshold-profile balanced \
    --drift-min-confidence low \
    --drift-required-streak 1 \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local service_state_json="$output"

  run jq -r '.drift.status' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_drift_status" ]

  run jq -r '.drift.recommendedProfile' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_drift_profile" ]

  run jq -r '.drift.driftActive' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_drift_active" ]
}

@test "reconcile detects ordering drift and degrades health with sequence diagnostics" {
  local loop_id="demo-loop"
  local repo="$TEMP_DIR/sequence-local"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$repo" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --trace-id "trace-seq-baseline-1" \
    --from-start \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  cat > "$repo/.superloop/loops/$loop_id/events.jsonl" <<JSONL
{"timestamp":"$now_ts","event":"loop_start","loop_id":"$loop_id","run_id":"run-123","iteration":1,"data":{"max_iterations":5}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --trace-id "trace-seq-drift-1" \
    --from-start \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local drift_state_json="$output"

  run jq -r '.health.status' <<<"$drift_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -r '.health.traceId' <<<"$drift_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-seq-drift-1" ]

  run jq -e '.health.reasonCodes | index("ordering_drift_detected") != null' <<<"$drift_state_json"
  [ "$status" -eq 0 ]

  local sequence_state_file="$repo/.superloop/ops-manager/$loop_id/sequence-state.json"
  local sequence_telemetry_file="$repo/.superloop/ops-manager/$loop_id/telemetry/sequence.jsonl"
  [ -f "$sequence_state_file" ]
  [ -f "$sequence_telemetry_file" ]

  run jq -r '.driftActive' "$sequence_state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.traceId' "$sequence_state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-seq-drift-1" ]

  run jq -e '.violations | index("snapshot_sequence_regression") != null' "$sequence_state_file"
  [ "$status" -eq 0 ]

  run jq -e '.violations | index("event_sequence_regression") != null' "$sequence_state_file"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.visibility.sequence.status' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "ordering_drift_detected" ]

  run jq -r '.visibility.sequence.driftActive' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.visibility.sequence.traceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-seq-drift-1" ]

  run jq -r '.visibility.trace.sequenceTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-seq-drift-1" ]

  local escalations_file="$repo/.superloop/ops-manager/$loop_id/escalations.jsonl"
  [ -f "$escalations_file" ]

  run bash -lc "tail -n 1 '$escalations_file' | jq -r '.category'"
  [ "$status" -eq 0 ]
  [ "$output" = "health_degraded" ]

  run bash -lc "tail -n 1 '$escalations_file' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-seq-drift-1" ]
}

@test "local and sprite_service transports produce equivalent ordering drift diagnostics" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local local_repo="$TEMP_DIR/local-sequence"
  local service_repo="$TEMP_DIR/service-sequence"
  mkdir -p "$local_repo" "$service_repo"

  write_runtime_artifacts "$local_repo" "$loop_id" "$now_ts"
  write_runtime_artifacts "$service_repo" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --from-start \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  start_service "$service_repo" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --from-start \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]

  cat > "$local_repo/.superloop/loops/$loop_id/events.jsonl" <<JSONL
{"timestamp":"$now_ts","event":"loop_start","loop_id":"$loop_id","run_id":"run-123","iteration":1,"data":{"max_iterations":5}}
JSONL
  cat > "$service_repo/.superloop/loops/$loop_id/events.jsonl" <<JSONL
{"timestamp":"$now_ts","event":"loop_start","loop_id":"$loop_id","run_id":"run-123","iteration":1,"data":{"max_iterations":5}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --from-start \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local local_state_json="$output"
  local local_health_status
  local local_reason_codes
  local_health_status="$(jq -r '.health.status' <<<"$local_state_json")"
  local_reason_codes="$(jq -c '.health.reasonCodes | sort' <<<"$local_state_json")"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --from-start \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999
  [ "$status" -eq 0 ]
  local service_state_json="$output"

  run jq -r '.health.status' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_health_status" ]

  run jq -c '.health.reasonCodes | sort' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_reason_codes" ]

  local local_sequence_state="$local_repo/.superloop/ops-manager/$loop_id/sequence-state.json"
  local service_sequence_state="$service_repo/.superloop/ops-manager/$loop_id/sequence-state.json"
  [ -f "$local_sequence_state" ]
  [ -f "$service_sequence_state" ]

  local local_sequence_summary
  local service_sequence_summary
  local_sequence_summary="$(jq -c '{status, driftActive, violations: (.violations | sort)}' "$local_sequence_state")"
  service_sequence_summary="$(jq -c '{status, driftActive, violations: (.violations | sort)}' "$service_sequence_state")"
  [ "$local_sequence_summary" = "$service_sequence_summary" ]
}

@test "health script projects critical transport_unreachable from failure streak fixture" {
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local state_file="$TEMP_DIR/state.json"

  cat > "$state_file" <<JSON
{
  "projection": {
    "status": "running",
    "lastEventAt": "$now_ts"
  },
  "transition": {
    "currentState": "running"
  },
  "divergence": {
    "any": false
  }
}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-health.sh" \
    --state-file "$state_file" \
    --transport-health-file "$OBS_FIXTURES/transport-health-critical.json" \
    --transport sprite_service \
    --degraded-transport-failure-streak 1 \
    --critical-transport-failure-streak 2 \
    --now "$now_ts"
  [ "$status" -eq 0 ]
  local health_json="$output"

  run jq -r '.status' <<<"$health_json"
  [ "$status" -eq 0 ]
  [ "$output" = "critical" ]

  run jq -c '.reasonCodes | sort' <<<"$health_json"
  [ "$status" -eq 0 ]
  [ "$output" = '["transport_unreachable"]' ]
}

@test "transport failure streak escalates to critical health" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "http://127.0.0.1:9" \
    --service-token "$SERVICE_TOKEN" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-transport-failure-streak 1 \
    --critical-transport-failure-streak 2
  [ "$status" -ne 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "http://127.0.0.1:9" \
    --service-token "$SERVICE_TOKEN" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-transport-failure-streak 1 \
    --critical-transport-failure-streak 2
  [ "$status" -ne 0 ]

  local health_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/health.json"
  [ -f "$health_file" ]

  run jq -r '.status' "$health_file"
  [ "$status" -eq 0 ]
  [ "$output" = "critical" ]

  run jq -c '.reasonCodes | sort' "$health_file"
  [ "$status" -eq 0 ]
  [ "$output" = '["transport_unreachable"]' ]

  local reconcile_telemetry="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry/reconcile.jsonl"
  [ -f "$reconcile_telemetry" ]

  run bash -lc "tail -n 1 '$reconcile_telemetry' | jq -r '.status'"
  [ "$status" -eq 0 ]
  [ "$output" = "failed" ]

  local escalations_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/escalations.jsonl"
  [ -f "$escalations_file" ]

  run bash -lc "tail -n 1 '$escalations_file' | jq -r '.category'"
  [ "$status" -eq 0 ]
  [ "$output" = "health_critical" ]
}

@test "reconcile persists heartbeat telemetry and marks runtime_heartbeat_stale" {
  local loop_id="demo-loop"
  local repo="$TEMP_DIR/heartbeat-local"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$repo" "$loop_id" "$now_ts"
  write_runtime_heartbeat "$repo" "$loop_id" "2020-01-01T00:00:00Z"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-heartbeat-lag-seconds 1 \
    --critical-heartbeat-lag-seconds 999999999
  [ "$status" -eq 0 ]
  local state_json="$output"

  run jq -r '.health.status' <<<"$state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -c '.health.reasonCodes | sort' <<<"$state_json"
  [ "$status" -eq 0 ]
  [ "$output" = '["runtime_heartbeat_stale"]' ]

  local heartbeat_state_file="$repo/.superloop/ops-manager/$loop_id/heartbeat.json"
  local heartbeat_telemetry_file="$repo/.superloop/ops-manager/$loop_id/telemetry/heartbeat.jsonl"
  [ -f "$heartbeat_state_file" ]
  [ -f "$heartbeat_telemetry_file" ]

  run jq -r '.freshnessStatus' "$heartbeat_state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run bash -lc "tail -n 1 '$heartbeat_telemetry_file' | jq -r '.status'"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.visibility.heartbeat.freshnessStatus' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -r '.visibility.heartbeat.reasonCode' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "runtime_heartbeat_stale" ]

  run jq -r '.visibility.heartbeat.lastHeartbeatAt' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2020-01-01T00:00:00Z" ]
}

@test "local and sprite_service transports produce equivalent heartbeat stale health" {
  local loop_id="demo-loop"
  local heartbeat_ts="2020-01-01T00:00:00Z"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local local_repo="$TEMP_DIR/local-heartbeat"
  local service_repo="$TEMP_DIR/service-heartbeat"
  mkdir -p "$local_repo" "$service_repo"

  write_runtime_artifacts "$local_repo" "$loop_id" "$now_ts"
  write_runtime_artifacts "$service_repo" "$loop_id" "$now_ts"
  write_runtime_heartbeat "$local_repo" "$loop_id" "$heartbeat_ts"
  write_runtime_heartbeat "$service_repo" "$loop_id" "$heartbeat_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-heartbeat-lag-seconds 1 \
    --critical-heartbeat-lag-seconds 999999999
  [ "$status" -eq 0 ]
  local local_state_json="$output"
  local local_health_status
  local local_reason_codes
  local_health_status="$(jq -r '.health.status' <<<"$local_state_json")"
  local_reason_codes="$(jq -c '.health.reasonCodes | sort' <<<"$local_state_json")"

  start_service "$service_repo" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --degraded-ingest-lag-seconds 999999 \
    --critical-ingest-lag-seconds 9999999 \
    --degraded-heartbeat-lag-seconds 1 \
    --critical-heartbeat-lag-seconds 999999999
  [ "$status" -eq 0 ]
  local service_state_json="$output"

  run jq -r '.health.status' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_health_status" ]

  run jq -c '.health.reasonCodes | sort' <<<"$service_state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_reason_codes" ]

  local local_heartbeat_state="$local_repo/.superloop/ops-manager/$loop_id/heartbeat.json"
  local service_heartbeat_state="$service_repo/.superloop/ops-manager/$loop_id/heartbeat.json"
  [ -f "$local_heartbeat_state" ]
  [ -f "$service_heartbeat_state" ]

  local local_summary
  local service_summary
  local_summary="$(jq -c '{freshnessStatus, reasonCode}' "$local_heartbeat_state")"
  service_summary="$(jq -c '{freshnessStatus, reasonCode}' "$service_heartbeat_state")"
  [ "$local_summary" = "$service_summary" ]
}
