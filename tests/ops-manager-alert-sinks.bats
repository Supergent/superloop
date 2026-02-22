#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
  RECEIVER_PID=""
  RECEIVER_PORT=""
  RECEIVER_URL=""
  RECEIVER_LOG="$TEMP_DIR/alert-receiver.jsonl"
  SERVICE_PID=""
  SERVICE_PORT=""
  SERVICE_URL=""
  SERVICE_TOKEN="test-token"
}

teardown() {
  if [[ -n "$RECEIVER_PID" ]] && kill -0 "$RECEIVER_PID" 2>/dev/null; then
    kill "$RECEIVER_PID" 2>/dev/null || true
    wait "$RECEIVER_PID" 2>/dev/null || true
  fi
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

start_alert_receiver() {
  RECEIVER_PORT="$(get_free_port)"
  RECEIVER_URL="http://127.0.0.1:$RECEIVER_PORT"
  : > "$RECEIVER_LOG"

  python3 - "$RECEIVER_PORT" "$RECEIVER_LOG" <<'PY' >"$TEMP_DIR/alert-receiver.log" 2>&1 &
import http.server
import json
import sys

port = int(sys.argv[1])
log_path = sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        entry = {
            "path": self.path,
            "headers": dict(self.headers),
            "body": body
        }
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, *_):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY

  RECEIVER_PID=$!

  local ready=0
  for _ in $(seq 1 60); do
    if ! kill -0 "$RECEIVER_PID" 2>/dev/null; then
      break
    fi
    if python3 - "$RECEIVER_PORT" <<'PY' >/dev/null 2>&1
import socket
import sys
port = int(sys.argv[1])
s = socket.socket()
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
    then
      ready=1
      break
    fi
    sleep 0.1
  done

  [ "$ready" -eq 1 ]
}

wait_for_log_lines() {
  local expected="$1"
  local attempts="${2:-60}"

  for _ in $(seq 1 "$attempts"); do
    local count
    count=$(wc -l < "$RECEIVER_LOG" | tr -d ' ')
    if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -ge "$expected" ]; then
      return 0
    fi
    sleep 0.1
  done

  return 1
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

write_enabled_webhook_config() {
  local path="$1"
  cat > "$path" <<'JSON'
{
  "schemaVersion": "v1",
  "defaultMinSeverity": "warning",
  "sinks": {
    "webhook-a": {
      "enabled": true,
      "type": "webhook",
      "urlEnv": "OPS_MANAGER_TEST_WEBHOOK_URL",
      "timeoutSeconds": 5
    }
  },
  "routing": {
    "defaultSinks": [
      "webhook-a"
    ],
    "categorySeverity": {
      "health_degraded": "warning"
    },
    "routes": [
      {
        "category": "health_degraded",
        "sinks": [
          "webhook-a"
        ],
        "minSeverity": "warning",
        "enabled": true
      }
    ]
  }
}
JSON
}

@test "alert sink resolver lists default sink catalog entries" {
  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" --list-sinks
  [ "$status" -eq 0 ]
  [[ "$output" == *"webhook-default"* ]]
  [[ "$output" == *"slack-default"* ]]
  [[ "$output" == *"pagerduty-default"* ]]
}

@test "alert sink resolver returns default config summary" {
  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh"
  [ "$status" -eq 0 ]
  local resolver_json="$output"

  run jq -r '.defaultMinSeverity' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "warning" ]

  run jq -r '.enabledSinkCount' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "alert sink resolver rejects severity without category" {
  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" --severity warning
  [ "$status" -ne 0 ]
  [[ "$output" == *"--severity requires --category"* ]]
}

@test "alert sink resolver fails closed when enabled sink secret env var is missing" {
  local config_file="$TEMP_DIR/enabled-webhook.json"
  write_enabled_webhook_config "$config_file"

  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" --config-file "$config_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"enabled sink secret env var(s) are unset"* ]]
}

@test "alert sink resolver resolves route and dispatchable sinks when env var is set" {
  local config_file="$TEMP_DIR/enabled-webhook.json"
  write_enabled_webhook_config "$config_file"

  run env OPS_MANAGER_TEST_WEBHOOK_URL="https://example.test/webhook" \
    "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" \
    --config-file "$config_file" \
    --category health_degraded \
    --severity warning
  [ "$status" -eq 0 ]
  local route_json="$output"

  run jq -r '.shouldDispatch' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.dispatchableSinks | length' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.dispatchableSinks[0].id' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "webhook-a" ]
}

@test "alert sink resolver enforces min severity gate during category resolution" {
  local config_file="$TEMP_DIR/enabled-webhook.json"
  write_enabled_webhook_config "$config_file"

  run env OPS_MANAGER_TEST_WEBHOOK_URL="https://example.test/webhook" \
    "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" \
    --config-file "$config_file" \
    --category health_degraded \
    --severity info
  [ "$status" -eq 0 ]
  local route_json="$output"

  run jq -r '.shouldDispatch' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.dispatchableSinks | length' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "alert sink resolver uses OPS_MANAGER_ALERT_SINKS_FILE when --config-file is omitted" {
  local config_file="$TEMP_DIR/custom-config.json"
  cat > "$config_file" <<'JSON'
{
  "schemaVersion": "v1",
  "defaultMinSeverity": "critical",
  "sinks": {
    "webhook-a": {
      "enabled": false,
      "type": "webhook",
      "urlEnv": "OPS_MANAGER_TEST_WEBHOOK_URL"
    }
  },
  "routing": {
    "defaultSinks": [
      "webhook-a"
    ],
    "categorySeverity": {},
    "routes": []
  }
}
JSON

  run env OPS_MANAGER_ALERT_SINKS_FILE="$config_file" \
    "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh"
  [ "$status" -eq 0 ]
  local resolver_json="$output"

  run jq -r '.sourceFile' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$config_file" ]

  run jq -r '.defaultMinSeverity' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "critical" ]
}

@test "alert dispatch processes new escalation rows once and is idempotent on repeat runs" {
  local loop_id="demo-loop"
  local repo="$TEMP_DIR/repo"
  local ops_dir="$repo/.superloop/ops-manager/$loop_id"
  mkdir -p "$ops_dir"

  local config_file="$PROJECT_ROOT/config/ops-manager-alert-sinks.v1.json"

  cat > "$ops_dir/escalations.jsonl" <<'JSONL'
{"timestamp":"2026-02-22T11:00:00Z","loopId":"demo-loop","category":"health_degraded","reasonCodes":["ingest_stale"]}
{"timestamp":"2026-02-22T11:01:00Z","loopId":"demo-loop","category":"divergence_detected","reasonCodes":["divergence_detected"]}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-alert-dispatch.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --trace-id "trace-alert-dispatch-1" \
    --alert-config-file "$config_file"
  [ "$status" -eq 0 ]
  local first_json="$output"

  run jq -r '.processedCount' <<<"$first_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.dispatchedCount' <<<"$first_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.skippedCount' <<<"$first_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run "$PROJECT_ROOT/scripts/ops-manager-alert-dispatch.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --alert-config-file "$config_file"
  [ "$status" -eq 0 ]
  local second_json="$output"

  run jq -r '.status' <<<"$second_json"
  [ "$status" -eq 0 ]
  [ "$output" = "no_new_escalations" ]

  run jq -r '.processedCount' <<<"$second_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  local telemetry_file="$ops_dir/telemetry/alerts.jsonl"
  [ -f "$telemetry_file" ]

  run bash -lc "wc -l < '$telemetry_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run bash -lc "head -n 1 '$telemetry_file' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-alert-dispatch-1" ]

  local dispatch_state_file="$ops_dir/alert-dispatch-state.json"
  [ -f "$dispatch_state_file" ]
  run jq -r '.escalationsLineOffset' "$dispatch_state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "reconcile invokes alert dispatch without changing reconcile success semantics" {
  local loop_id="demo-loop"
  local repo="$TEMP_DIR/repo-reconcile"
  local stale_ts="2020-01-01T00:00:00Z"
  write_runtime_artifacts "$repo" "$loop_id" "$stale_ts"

  local config_file="$PROJECT_ROOT/config/ops-manager-alert-sinks.v1.json"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --trace-id "trace-alert-status-1" \
    --alerts-enabled true \
    --alert-config-file "$config_file" \
    --degraded-ingest-lag-seconds 1 \
    --critical-ingest-lag-seconds 999999999
  [ "$status" -eq 0 ]
  local state_json="$output"

  run jq -r '.health.status' <<<"$state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  local dispatch_state_file="$repo/.superloop/ops-manager/$loop_id/alert-dispatch-state.json"
  local dispatch_telemetry_file="$repo/.superloop/ops-manager/$loop_id/telemetry/alerts.jsonl"
  [ -f "$dispatch_state_file" ]
  [ -f "$dispatch_telemetry_file" ]

  run jq -r '.processedCount' "$dispatch_state_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run jq -r '.skippedCount' "$dispatch_state_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --trace-id "trace-alert-status-1" \
    --alerts-enabled true \
    --alert-config-file "$config_file" \
    --degraded-ingest-lag-seconds 1 \
    --critical-ingest-lag-seconds 999999999
  [ "$status" -eq 0 ]

  run jq -r '.status' "$dispatch_state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "no_new_escalations" ]

  run jq -r '.processedCount' "$dispatch_state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "status includes alert dispatch and last delivery summaries" {
  local loop_id="demo-loop"
  local repo="$TEMP_DIR/repo-status"
  local stale_ts="2020-01-01T00:00:00Z"
  write_runtime_artifacts "$repo" "$loop_id" "$stale_ts"

  local config_file="$PROJECT_ROOT/config/ops-manager-alert-sinks.v1.json"
  local dispatch_state_file="$repo/.superloop/ops-manager/$loop_id/alert-dispatch-state.json"
  local dispatch_telemetry_file="$repo/.superloop/ops-manager/$loop_id/telemetry/alerts.jsonl"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$repo" \
    --loop "$loop_id" \
    --trace-id "trace-alert-status-1" \
    --alerts-enabled true \
    --alert-config-file "$config_file" \
    --degraded-ingest-lag-seconds 1 \
    --critical-ingest-lag-seconds 999999999
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.alerts.dispatch.status' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "success" ]

  run jq -r '.alerts.dispatch.lastTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-alert-status-1" ]

  run jq -e '.alerts.dispatch.processedCount >= 1' <<<"$status_json"
  [ "$status" -eq 0 ]

  run jq -r '.alerts.lastDelivery.status' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "skipped" ]

  run jq -r '.alerts.lastDelivery.reasonCode' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "no_dispatchable_sinks" ]

  run jq -r '.alerts.lastDelivery.traceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-alert-status-1" ]

  run jq -r '.traceLinkage.reconcileTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-alert-status-1" ]

  run jq -r '.traceLinkage.alertTraceId' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-alert-status-1" ]

  run jq -r '.files.alertDispatchStateFile' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$dispatch_state_file" ]

  run jq -r '.files.alertDispatchTelemetryFile' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$dispatch_telemetry_file" ]
}

@test "alert dispatch is transport-parity across local and sprite_service reconciles" {
  local loop_id="demo-loop"
  local stale_ts="2020-01-01T00:00:00Z"
  local local_repo="$TEMP_DIR/local-alerts"
  local service_repo="$TEMP_DIR/service-alerts"
  mkdir -p "$local_repo" "$service_repo"

  write_runtime_artifacts "$local_repo" "$loop_id" "$stale_ts"
  write_runtime_artifacts "$service_repo" "$loop_id" "$stale_ts"

  local config_file="$PROJECT_ROOT/config/ops-manager-alert-sinks.v1.json"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --alerts-enabled true \
    --alert-config-file "$config_file" \
    --degraded-ingest-lag-seconds 1 \
    --critical-ingest-lag-seconds 999999999
  [ "$status" -eq 0 ]

  start_service "$service_repo" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --alerts-enabled true \
    --alert-config-file "$config_file" \
    --degraded-ingest-lag-seconds 1 \
    --critical-ingest-lag-seconds 999999999
  [ "$status" -eq 0 ]

  local local_dispatch_state="$local_repo/.superloop/ops-manager/$loop_id/alert-dispatch-state.json"
  local service_dispatch_state="$service_repo/.superloop/ops-manager/$loop_id/alert-dispatch-state.json"
  [ -f "$local_dispatch_state" ]
  [ -f "$service_dispatch_state" ]

  local local_state_summary
  local service_state_summary
  local_state_summary="$(jq -c '{status, processedCount, dispatchedCount, skippedCount, failedCount, failureReasonCodes}' "$local_dispatch_state")"
  service_state_summary="$(jq -c '{status, processedCount, dispatchedCount, skippedCount, failedCount, failureReasonCodes}' "$service_dispatch_state")"
  [ "$local_state_summary" = "$service_state_summary" ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$local_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local local_status_json="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" --repo "$service_repo" --loop "$loop_id"
  [ "$status" -eq 0 ]
  local service_status_json="$output"

  local local_alert_summary
  local service_alert_summary
  local_alert_summary="$(jq -c '{dispatch: (.alerts.dispatch | {status, processedCount, dispatchedCount, skippedCount, failedCount}), lastDelivery: (.alerts.lastDelivery | {status, reasonCode, escalationCategory, eventSeverity, sinkCount, dispatchedSinkCount, failedSinkCount})}' <<<"$local_status_json")"
  service_alert_summary="$(jq -c '{dispatch: (.alerts.dispatch | {status, processedCount, dispatchedCount, skippedCount, failedCount}), lastDelivery: (.alerts.lastDelivery | {status, reasonCode, escalationCategory, eventSeverity, sinkCount, dispatchedSinkCount, failedSinkCount})}' <<<"$service_status_json")"
  [ "$local_alert_summary" = "$service_alert_summary" ]
}
