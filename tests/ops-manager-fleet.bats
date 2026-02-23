#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
  SERVICE_PID=""
  SERVICE_PORT=""
  SERVICE_URL=""
  SERVICE_TOKEN="fleet-test-token"
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
{"version":1,"loop_id":"$loop_id","updated_at":"$event_ts","entries":[{"run_id":"run-$loop_id","iteration":1,"gates":{"tests":"ok","validation":"ok","prerequisites":"ok","checklist":"ok","evidence":"skipped","approval":"none"},"stuck":{"streak":0,"threshold":3},"completion_ok":false,"ended_at":"$event_ts"}]}
JSON

  cat > "$repo/.superloop/loops/$loop_id/events.jsonl" <<JSONL
{"timestamp":"$event_ts","event":"loop_start","loop_id":"$loop_id","run_id":"run-$loop_id","iteration":1,"data":{"max_iterations":5}}
{"timestamp":"$event_ts","event":"iteration_start","loop_id":"$loop_id","run_id":"run-$loop_id","iteration":2,"data":{"started_at":"$event_ts"}}
JSONL
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

@test "fleet registry fails closed when sprite_service loop omits service base URL" {
  local repo="$TEMP_DIR/registry-invalid"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a","transport":"sprite_service"}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sprite_service loops require service.baseUrl or sprite.serviceBaseUrl"* ]]
}

@test "fleet registry fails closed on unknown suppression categories" {
  local repo="$TEMP_DIR/registry-policy-invalid"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"}],"policy":{"suppressions":{"*":["health_critical","unknown_category"]}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"contains unknown categories"* ]]
}

@test "fleet reconcile captures partial failure with deterministic ordering and trace linkage" {
  local repo="$TEMP_DIR/fleet-partial"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  write_runtime_artifacts "$repo" "loop-b" "$now_ts"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-partial","loops":[{"loopId":"loop-b","transport":"local"},{"loopId":"loop-a","transport":"local"}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-reconcile.sh" \
    --repo "$repo" \
    --deterministic-order \
    --max-parallel 2 \
    --trace-id "trace-fleet-partial-1"
  [ "$status" -eq 0 ]
  local fleet_json="$output"

  run jq -r '.status' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "partial_failure" ]

  run jq -r '.results | map(.loopId) | join(",")' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-a,loop-b" ]

  run jq -r '.failedCount' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.successCount' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.reasonCodes | index("fleet_partial_failure") != null' <<<"$fleet_json"
  [ "$status" -eq 0 ]

  run jq -r '.results[] | select(.loopId == "loop-a") | .status' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "failed" ]

  run jq -r '.results[] | select(.loopId == "loop-a") | .reasonCode' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [[ -n "$output" && "$output" != "null" ]]

  local telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/reconcile.jsonl"
  [ -f "$telemetry_file" ]

  run bash -lc "tail -n 1 '$telemetry_file' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-fleet-partial-1" ]
}

@test "fleet reconcile deterministic replay keeps stable loop ordering across runs" {
  local repo="$TEMP_DIR/fleet-deterministic"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  write_runtime_artifacts "$repo" "loop-c" "$now_ts"
  write_runtime_artifacts "$repo" "loop-a" "$now_ts"
  write_runtime_artifacts "$repo" "loop-b" "$now_ts"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-deterministic","loops":[{"loopId":"loop-c"},{"loopId":"loop-a"},{"loopId":"loop-b"}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-reconcile.sh" \
    --repo "$repo" \
    --deterministic-order \
    --max-parallel 3 \
    --trace-id "trace-fleet-order-1"
  [ "$status" -eq 0 ]
  local first_run="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-reconcile.sh" \
    --repo "$repo" \
    --deterministic-order \
    --max-parallel 3 \
    --trace-id "trace-fleet-order-2"
  [ "$status" -eq 0 ]
  local second_run="$output"

  run jq -r '.results | map(.loopId) | join(",")' <<<"$first_run"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-a,loop-b,loop-c" ]

  run jq -r '.results | map(.loopId) | join(",")' <<<"$second_run"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-a,loop-b,loop-c" ]
}

@test "fleet reconcile preserves parity across local and sprite_service transports" {
  local repo="$TEMP_DIR/fleet-parity"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  write_runtime_artifacts "$repo" "loop-local" "$now_ts"
  write_runtime_artifacts "$repo" "loop-service" "$now_ts"
  start_service "$repo" "$SERVICE_TOKEN"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<JSON
{"schemaVersion":"v1","fleetId":"fleet-parity","loops":[{"loopId":"loop-local","transport":"local"},{"loopId":"loop-service","transport":"sprite_service","service":{"baseUrl":"$SERVICE_URL","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}}]}
JSON

  run env OPS_MANAGER_TEST_SERVICE_TOKEN="$SERVICE_TOKEN" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-reconcile.sh" \
    --repo "$repo" \
    --deterministic-order \
    --max-parallel 2 \
    --trace-id "trace-fleet-parity-1"
  [ "$status" -eq 0 ]
  local fleet_json="$output"

  run jq -r '.status' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "success" ]

  run jq -r '.successCount' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.failedCount' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.results | map(.transport) | sort | join(",")' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "local,sprite_service" ]

  run jq -r '.results[] | select(.loopId == "loop-service") | .status' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "success" ]
}

@test "fleet policy and status project suppressions, exception buckets, and advisory actions" {
  local repo="$TEMP_DIR/fleet-policy"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy","loops":[{"loopId":"loop-red"},{"loopId":"loop-blue"}],"policy":{"mode":"advisory","suppressions":{"loop-red":["reconcile_failed"],"*":["health_degraded"]}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-22T18:00:00Z","startedAt":"2026-02-22T17:59:40Z","fleetId":"fleet-policy","traceId":"trace-fleet-policy-1","status":"partial_failure","reasonCodes":["fleet_partial_failure","fleet_health_critical"],"loopCount":2,"successCount":1,"failedCount":1,"skippedCount":0,"durationSeconds":20,"execution":{"maxParallel":2,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-22T18:00:00Z","startedAt":"2026-02-22T17:59:45Z","loopId":"loop-red","transport":"local","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}},{"timestamp":"2026-02-22T18:00:00Z","startedAt":"2026-02-22T17:59:50Z","loopId":"loop-blue","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"degraded","healthReasonCodes":["ingest_stale"],"durationSeconds":4,"traceId":"trace-fleet-policy-1-loop-blue","files":{"stateFile":"/tmp/loop-blue/state.json","healthFile":"/tmp/loop-blue/health.json","cursorFile":"/tmp/loop-blue/cursor.json","reconcileTelemetryFile":"/tmp/loop-blue/reconcile.jsonl"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/telemetry/reconcile.jsonl" <<'JSONL'
{"timestamp":"2026-02-22T18:00:00Z","category":"fleet_reconcile","fleetId":"fleet-policy","traceId":"trace-fleet-policy-1","status":"partial_failure","reasonCodes":["fleet_partial_failure","fleet_health_critical"]}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-policy-1"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.candidateCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -r '.unsuppressedCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.suppressedCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -e '.reasonCodes | index("fleet_action_required") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_actions_suppressed") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-status.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.policy.unsuppressedCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.exceptions.reconcileFailures | join(",")' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-red" ]

  run jq -r '.fleet.partialFailure' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.loops[] | select(.loopId == "loop-red") | .artifacts.stateFile' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/loop-red/state.json" ]
}

@test "fleet policy enforces suppression precedence and advisory cooldown dedupe" {
  local repo="$TEMP_DIR/fleet-policy-hardening"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-hardening","loops":[{"loopId":"loop-red"},{"loopId":"loop-blue"},{"loopId":"loop-green"}],"policy":{"mode":"advisory","suppressions":{"*":["health_critical"],"loop-red":["health_critical"]},"noiseControls":{"dedupeWindowSeconds":3600}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-22T18:00:00Z","startedAt":"2026-02-22T17:59:40Z","fleetId":"fleet-policy-hardening","traceId":"trace-fleet-policy-hardening-1","status":"partial_failure","reasonCodes":["fleet_partial_failure","fleet_health_critical"],"loopCount":3,"successCount":3,"failedCount":0,"skippedCount":0,"durationSeconds":20,"execution":{"maxParallel":2,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-22T18:00:00Z","startedAt":"2026-02-22T17:59:45Z","loopId":"loop-red","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-hardening-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}},{"timestamp":"2026-02-22T18:00:00Z","startedAt":"2026-02-22T17:59:50Z","loopId":"loop-blue","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["ingest_stale"],"durationSeconds":4,"traceId":"trace-fleet-policy-hardening-1-loop-blue","files":{"stateFile":"/tmp/loop-blue/state.json","healthFile":"/tmp/loop-blue/health.json","cursorFile":"/tmp/loop-blue/cursor.json","reconcileTelemetryFile":"/tmp/loop-blue/reconcile.jsonl"}},{"timestamp":"2026-02-22T18:00:00Z","startedAt":"2026-02-22T17:59:52Z","loopId":"loop-green","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"degraded","healthReasonCodes":["ingest_stale"],"durationSeconds":4,"traceId":"trace-fleet-policy-hardening-1-loop-green","files":{"stateFile":"/tmp/loop-green/state.json","healthFile":"/tmp/loop-green/health.json","cursorFile":"/tmp/loop-green/cursor.json","reconcileTelemetryFile":"/tmp/loop-green/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-policy-hardening-1"
  [ "$status" -eq 0 ]
  local first_policy_json="$output"

  run jq -r '.candidates[] | select(.loopId == "loop-red" and .category == "health_critical") | .suppressionScope' <<<"$first_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "loop" ]

  run jq -r '.candidates[] | select(.loopId == "loop-blue" and .category == "health_critical") | .suppressionScope' <<<"$first_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "global" ]

  run jq -r '.candidates[] | select(.loopId == "loop-green" and .category == "health_degraded") | .suppressed' <<<"$first_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-policy-hardening-2"
  [ "$status" -eq 0 ]
  local second_policy_json="$output"

  run jq -r '.candidates[] | select(.loopId == "loop-green" and .category == "health_degraded") | .suppressionReason' <<<"$second_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "advisory_cooldown_active" ]

  run jq -r '.candidates[] | select(.loopId == "loop-green" and .category == "health_degraded") | .suppressionScope' <<<"$second_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "cooldown" ]

  run jq -e '.reasonCodes | index("fleet_actions_deduped") != null' <<<"$second_policy_json"
  [ "$status" -eq 0 ]

  local history_file="$repo/.superloop/ops-manager/fleet/telemetry/policy-history.jsonl"
  [ -f "$history_file" ]
  run bash -lc "wc -l < '$history_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" -ge 6 ]
}
