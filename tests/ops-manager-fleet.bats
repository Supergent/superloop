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

write_runtime_heartbeat() {
  local repo="$1"
  local loop_id="$2"
  local heartbeat_ts="$3"

  cat > "$repo/.superloop/loops/$loop_id/heartbeat.v1.json" <<JSON
{"schemaVersion":"v1","timestamp":"$heartbeat_ts","source":"runtime","status":"running","stage":"iteration"}
JSON
}

iso_timestamp_minus_seconds() {
  local seconds="$1"

  python3 - "$seconds" <<'PY'
import datetime
import sys

seconds = int(sys.argv[1])
value = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=seconds)
print(value.replace(microsecond=0).isoformat().replace("+00:00", "Z"))
PY
}

deterministic_rollout_bucket() {
  local seed="$1"

  python3 - "$seed" <<'PY'
import sys

seed = sys.argv[1].encode("utf-8")
value = 17
for item in seed:
    value = ((value * 31 + item) % 1000003)
print(value % 100)
PY
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

@test "fleet registry accepts guarded_auto policy contract and normalizes autonomous controls" {
  local repo="$TEMP_DIR/registry-guarded-auto"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["reconcile_failed","health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"warning","minConfidence":"medium"},"safety":{"maxActionsPerRun":3,"maxActionsPerLoop":2,"cooldownSeconds":120,"killSwitch":false}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local registry_json="$output"

  run jq -r '.policy.mode' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "guarded_auto" ]

  run jq -r '.policy.autonomous.enabled' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.policy.autonomous.allow.categories | join(",")' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "reconcile_failed,health_critical" ]

  run jq -r '.policy.autonomous.thresholds.minSeverity' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "warning" ]

  run jq -r '.policy.autonomous.safety.maxActionsPerRun' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -r '.policy.autonomous.governance.actor' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "ops-user" ]

  run jq -r '.policy.autonomous.governance.reviewWindowDays' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "311" ]
}

@test "fleet registry fails closed on unsupported autonomous categories" {
  local repo="$TEMP_DIR/registry-auto-category-invalid"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical","unknown_category"]}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"policy.autonomous.allow.categories contains unsupported categories"* ]]
}

@test "fleet registry fails closed on unsupported autonomous intents" {
  local repo="$TEMP_DIR/registry-auto-intent-invalid"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"intents":["cancel","approve"]}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"policy.autonomous.allow.intents contains unsupported intents"* ]]
}

@test "fleet registry fails closed on invalid autonomous threshold and safety values" {
  local repo="$TEMP_DIR/registry-auto-threshold-invalid"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"thresholds":{"minConfidence":"certain"},"safety":{"maxActionsPerRun":-1}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"policy.autonomous.thresholds.minConfidence must be one of high, medium, low"* ]]
  [[ "$output" == *"policy.autonomous.safety.maxActionsPerRun must be an integer >= 0 when present"* ]]
}

@test "fleet registry accepts rollout controls and normalizes deterministic cohort defaults" {
  local repo="$TEMP_DIR/registry-rollout-controls"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"},{"loopId":"loop-b"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"rollout":{"canaryPercent":40,"scope":{"loopIds":["loop-a"]}}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local registry_json="$output"

  run jq -r '.policy.autonomous.rollout.canaryPercent' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "40" ]

  run jq -r '.policy.autonomous.rollout.scope.loopIds | join(",")' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-a" ]

  run jq -r '.policy.autonomous.rollout.selector.salt' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "fleet-autonomous-rollout-v1" ]

  run jq -r '.policy.autonomous.rollout.autoPause.enabled' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.policy.autonomous.rollout.autoPause.lookbackExecutions' <<<"$registry_json"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "fleet registry fails closed on invalid rollout controls" {
  local repo="$TEMP_DIR/registry-rollout-invalid"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"},{"loopId":"loop-b"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"rollout":{"canaryPercent":101,"scope":{"loopIds":["loop-a","unknown-loop"]},"autoPause":{"failureRateThreshold":1.5}}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"policy.autonomous.rollout.canaryPercent must be an integer between 0 and 100 when present"* ]]
  [[ "$output" == *"policy.autonomous.rollout.scope.loopIds entries must reference declared loopIds"* ]]
  [[ "$output" == *"policy.autonomous.rollout.autoPause.failureRateThreshold must be a number between 0 and 1 when present"* ]]
}

@test "fleet registry fails closed when guarded_auto is requested without governance metadata" {
  local repo="$TEMP_DIR/registry-governance-missing"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"}],"policy":{"mode":"guarded_auto","autonomous":{"allow":{"categories":["reconcile_failed"],"intents":["cancel"]}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"policy.autonomous.governance.actor is required when policy.mode is guarded_auto"* ]]
  [[ "$output" == *"policy.autonomous.governance.approvalRef is required when policy.mode is guarded_auto"* ]]
  [[ "$output" == *"policy.autonomous.governance.changedAt must be an ISO-8601 timestamp when policy.mode is guarded_auto"* ]]
}

@test "fleet registry fails closed when guarded_auto governance review window is expired" {
  local repo="$TEMP_DIR/registry-governance-expired"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"demo","loops":[{"loopId":"loop-a"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-01-10T00:00:00Z","reviewBy":"2026-01-20T00:00:00Z"}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-registry.sh" --repo "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"policy.autonomous.governance.reviewBy must be in the future when policy.mode is guarded_auto"* ]]
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

@test "fleet reconcile mixed local and sprite_service loops preserve deterministic degraded critical and failure semantics" {
  local repo="$TEMP_DIR/fleet-mixed-parity"
  local now_ts
  local degraded_heartbeat_ts
  local critical_heartbeat_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  degraded_heartbeat_ts="$(iso_timestamp_minus_seconds 180)"
  critical_heartbeat_ts="$(iso_timestamp_minus_seconds 900)"
  mkdir -p "$repo/.superloop/ops-manager/fleet"

  write_runtime_artifacts "$repo" "loop-local-degraded" "$now_ts"
  write_runtime_artifacts "$repo" "loop-service-critical" "$now_ts"
  write_runtime_heartbeat "$repo" "loop-local-degraded" "$degraded_heartbeat_ts"
  write_runtime_heartbeat "$repo" "loop-service-critical" "$critical_heartbeat_ts"
  start_service "$repo" "$SERVICE_TOKEN"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<JSON
{"schemaVersion":"v1","fleetId":"fleet-mixed-parity","loops":[{"loopId":"loop-local-degraded","transport":"local"},{"loopId":"loop-service-critical","transport":"sprite_service","service":{"baseUrl":"$SERVICE_URL","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}},{"loopId":"loop-local-failure","transport":"local"},{"loopId":"loop-service-failure","transport":"sprite_service","service":{"baseUrl":"$SERVICE_URL","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}}]}
JSON

  run env OPS_MANAGER_TEST_SERVICE_TOKEN="$SERVICE_TOKEN" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-reconcile.sh" \
    --repo "$repo" \
    --deterministic-order \
    --max-parallel 4 \
    --trace-id "trace-fleet-mixed-parity-1"
  [ "$status" -eq 0 ]
  local fleet_json="$output"

  run jq -r '.status' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "partial_failure" ]

  run jq -r '.successCount' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.failedCount' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.results[] | select(.loopId == "loop-local-degraded") | .healthStatus' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -r '.results[] | select(.loopId == "loop-service-critical") | .healthStatus' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "critical" ]

  run jq -r '.results[] | select(.loopId == "loop-local-failure") | .reasonCode' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "transport_unreachable" ]

  run jq -r '.results[] | select(.loopId == "loop-service-failure") | .reasonCode' <<<"$fleet_json"
  [ "$status" -eq 0 ]
  [ "$output" = "transport_unreachable" ]

  run jq -e '.results[] | select(.loopId == "loop-local-failure") | .healthReasonCodes | index("transport_unreachable") != null' <<<"$fleet_json"
  [ "$status" -eq 0 ]

  run jq -e '.results[] | select(.loopId == "loop-service-failure") | .healthReasonCodes | index("transport_unreachable") != null' <<<"$fleet_json"
  [ "$status" -eq 0 ]
}

@test "fleet reconcile rollup and reason surfaces are parity across equivalent local and sprite_service states" {
  local local_repo="$TEMP_DIR/fleet-local-equivalent"
  local service_repo="$TEMP_DIR/fleet-service-equivalent"
  local now_ts
  local critical_heartbeat_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  critical_heartbeat_ts="$(iso_timestamp_minus_seconds 900)"

  mkdir -p "$local_repo/.superloop/ops-manager/fleet"
  mkdir -p "$service_repo/.superloop/ops-manager/fleet"

  write_runtime_artifacts "$local_repo" "loop-critical" "$now_ts"
  write_runtime_heartbeat "$local_repo" "loop-critical" "$critical_heartbeat_ts"

  write_runtime_artifacts "$service_repo" "loop-critical" "$now_ts"
  write_runtime_heartbeat "$service_repo" "loop-critical" "$critical_heartbeat_ts"

  start_service "$service_repo" "$SERVICE_TOKEN"

  cat > "$local_repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-equivalent","loops":[{"loopId":"loop-critical","transport":"local"},{"loopId":"loop-failure","transport":"local"}]}
JSON

  cat > "$service_repo/.superloop/ops-manager/fleet/registry.v1.json" <<JSON
{"schemaVersion":"v1","fleetId":"fleet-equivalent","loops":[{"loopId":"loop-critical","transport":"sprite_service","service":{"baseUrl":"$SERVICE_URL","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}},{"loopId":"loop-failure","transport":"sprite_service","service":{"baseUrl":"$SERVICE_URL","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-reconcile.sh" \
    --repo "$local_repo" \
    --deterministic-order \
    --max-parallel 2 \
    --trace-id "trace-fleet-equivalent-1"
  [ "$status" -eq 0 ]
  local local_fleet_json="$output"

  run env OPS_MANAGER_TEST_SERVICE_TOKEN="$SERVICE_TOKEN" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-reconcile.sh" \
    --repo "$service_repo" \
    --deterministic-order \
    --max-parallel 2 \
    --trace-id "trace-fleet-equivalent-1"
  [ "$status" -eq 0 ]
  local service_fleet_json="$output"

  local local_projection
  local service_projection
  local_projection="$(jq -c '{status, reasonCodes: ((.reasonCodes // []) | sort), loopCount, successCount, failedCount, skippedCount, results: ((.results // []) | map({loopId, status, reasonCode, reconcileStatus, healthStatus, healthReasonCodes: ((.healthReasonCodes // []) | sort)}) | sort_by(.loopId))}' <<<"$local_fleet_json")"
  service_projection="$(jq -c '{status, reasonCodes: ((.reasonCodes // []) | sort), loopCount, successCount, failedCount, skippedCount, results: ((.results // []) | map({loopId, status, reasonCode, reconcileStatus, healthStatus, healthReasonCodes: ((.healthReasonCodes // []) | sort)}) | sort_by(.loopId))}' <<<"$service_fleet_json")"
  [ "$local_projection" = "$service_projection" ]
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

@test "fleet status surfaces autonomous safety-gate decisions and handoff outcomes" {
  local repo="$TEMP_DIR/fleet-autonomous-status-surface"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-autonomous-status-surface","loops":[{"loopId":"loop-red","transport":"local"},{"loopId":"loop-blue","transport":"local"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"safety":{"killSwitch":false}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T13:00:00Z","startedAt":"2026-02-23T12:59:40Z","fleetId":"fleet-autonomous-status-surface","traceId":"trace-fleet-autonomous-status-surface-1","status":"partial_failure","reasonCodes":["fleet_partial_failure"],"loopCount":2,"successCount":1,"failedCount":1,"skippedCount":0,"durationSeconds":20,"execution":{"maxParallel":2,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T13:00:00Z","startedAt":"2026-02-23T12:59:45Z","loopId":"loop-red","transport":"local","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-autonomous-status-surface-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}},{"timestamp":"2026-02-23T13:00:00Z","startedAt":"2026-02-23T12:59:50Z","loopId":"loop-blue","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":4,"traceId":"trace-fleet-autonomous-status-surface-1-loop-blue","files":{"stateFile":"/tmp/loop-blue/state.json","healthFile":"/tmp/loop-blue/health.json","cursorFile":"/tmp/loop-blue/cursor.json","reconcileTelemetryFile":"/tmp/loop-blue/reconcile.jsonl"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T13:00:02Z","fleetId":"fleet-autonomous-status-surface","traceId":"trace-fleet-autonomous-policy-1","mode":"guarded_auto","candidateCount":2,"unsuppressedCount":2,"suppressedCount":0,"autoEligibleCount":1,"manualOnlyCount":1,"summary":{"byAutonomyReason":{"category_not_allowlisted":1,"autonomous_max_actions_per_run_exceeded":1}},"autonomous":{"controls":{"safety":{"killSwitch":false}}},"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-blue:health_critical","loopId":"loop-blue","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted","autonomous_max_actions_per_run_exceeded"]}}],"reasonCodes":["fleet_action_required","fleet_auto_candidates_safety_blocked"]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/handoff-state.json" <<'JSON'
{"schemaVersion":"v1","generatedAt":"2026-02-23T13:00:03Z","updatedAt":"2026-02-23T13:00:06Z","fleetId":"fleet-autonomous-status-surface","traceId":"trace-fleet-autonomous-handoff-1","policyTraceId":"trace-fleet-autonomous-policy-1","mode":"guarded_auto","summary":{"intentCount":2,"autoEligibleIntentCount":1,"manualOnlyIntentCount":1,"pendingConfirmationCount":1,"executedCount":1,"ambiguousCount":0,"failedCount":0},"reasonCodes":["fleet_handoff_action_required","fleet_handoff_confirmation_pending","fleet_handoff_executed","fleet_handoff_auto_eligible_intents"],"intents":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","intent":"cancel","status":"executed","autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"intentId":"loop-blue:health_critical:cancel","loopId":"loop-blue","intent":"cancel","status":"pending_operator_confirmation","autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted"]}}],"execution":{"mode":"autonomous","requestedBy":"ops-bot","requestedAt":"2026-02-23T13:00:04Z","completedAt":"2026-02-23T13:00:06Z","requestedIntentCount":1,"executedIntentCount":1,"executedCount":1,"ambiguousCount":0,"failedCount":0,"results":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","status":"executed","reasonCode":"control_confirmed"}]}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/telemetry/reconcile.jsonl" <<'JSONL'
{"timestamp":"2026-02-23T13:00:00Z","category":"fleet_reconcile","fleetId":"fleet-autonomous-status-surface","traceId":"trace-fleet-autonomous-status-surface-1","status":"partial_failure","reasonCodes":["fleet_partial_failure","fleet_health_critical"]}
JSONL

  cat > "$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl" <<'JSONL'
{"timestamp":"2026-02-23T13:00:06Z","category":"fleet_handoff_execute","fleetId":"fleet-autonomous-status-surface","traceId":"trace-fleet-autonomous-handoff-1","execution":{"mode":"autonomous","requestedIntentCount":1,"executedCount":1,"ambiguousCount":0,"failedCount":0},"summary":{"reasonCodes":["fleet_handoff_action_required","fleet_handoff_executed"]}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-status.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.autonomous.enabled' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.autonomous.eligibleCandidateCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.manualOnlyCandidateCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.safetyGateDecisions.byReason.autonomous_max_actions_per_run_exceeded' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.handoff.execution.mode' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous" ]

  run jq -r '.handoff.pendingManualOnlyCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.handoff.pendingManualOnlyCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.handoff.outcomeReasonCodes.control_confirmed' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.latestHandoffTelemetry.execution.mode' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous" ]

  run jq -e '.latestHandoffTelemetry.reasonCodes | index("fleet_handoff_executed") != null' <<<"$status_json"
  [ "$status" -eq 0 ]
}

@test "fleet status surfaces governance posture outcome rollups and suppression-path buckets" {
  local repo="$TEMP_DIR/fleet-status-operator-visibility"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-status-operator-visibility","loops":[{"loopId":"loop-red","transport":"local"},{"loopId":"loop-blue","transport":"sprite_service","service":{"baseUrl":"http://sprite-service.local"}},{"loopId":"loop-green","transport":"sprite_service","service":{"baseUrl":"http://sprite-service.local"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T13:30:00Z","startedAt":"2026-02-23T13:29:40Z","fleetId":"fleet-status-operator-visibility","traceId":"trace-fleet-status-operator-visibility-1","status":"partial_failure","reasonCodes":["fleet_partial_failure"],"loopCount":3,"successCount":2,"failedCount":1,"skippedCount":0,"durationSeconds":20,"execution":{"maxParallel":3,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T13:30:00Z","startedAt":"2026-02-23T13:29:45Z","loopId":"loop-red","transport":"local","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-status-operator-visibility-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}},{"timestamp":"2026-02-23T13:30:00Z","startedAt":"2026-02-23T13:29:48Z","loopId":"loop-blue","transport":"sprite_service","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"degraded","healthReasonCodes":["ingest_stale"],"durationSeconds":4,"traceId":"trace-fleet-status-operator-visibility-1-loop-blue","files":{"stateFile":"/tmp/loop-blue/state.json","healthFile":"/tmp/loop-blue/health.json","cursorFile":"/tmp/loop-blue/cursor.json","reconcileTelemetryFile":"/tmp/loop-blue/reconcile.jsonl"}},{"timestamp":"2026-02-23T13:30:00Z","startedAt":"2026-02-23T13:29:50Z","loopId":"loop-green","transport":"sprite_service","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":4,"traceId":"trace-fleet-status-operator-visibility-1-loop-green","files":{"stateFile":"/tmp/loop-green/state.json","healthFile":"/tmp/loop-green/health.json","cursorFile":"/tmp/loop-green/cursor.json","reconcileTelemetryFile":"/tmp/loop-green/reconcile.jsonl"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T13:30:02Z","fleetId":"fleet-status-operator-visibility","traceId":"trace-fleet-status-operator-visibility-policy-1","mode":"guarded_auto","candidateCount":3,"unsuppressedCount":3,"suppressedCount":0,"autoEligibleCount":1,"manualOnlyCount":2,"summary":{"byAutonomyReason":{"category_not_allowlisted":1,"autonomous_max_actions_per_run_exceeded":1,"autonomous_rollout_canary_excluded":1,"autonomous_rollout_paused_auto":1,"autonomous_autopause_failure_spike":1}},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-501","rationale":"guarded rollout expansion","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z","reviewWindowDays":311,"authorityContextPresent":false},"controls":{"safety":{"killSwitch":false}},"rollout":{"canaryPercent":50,"scopeLoopIds":["loop-red","loop-blue","loop-green"],"selectorSalt":"fleet-autonomous-rollout-v1","candidateBuckets":{"inScopeCount":3,"inCohortCount":1,"outOfCohortCount":2},"pause":{"active":true,"reasons":["autonomous_rollout_paused_auto"],"manual":false,"auto":{"enabled":true,"active":true,"reasons":["autonomous_autopause_failure_spike"],"lookbackExecutions":3,"minSampleSize":2,"ambiguityRateThreshold":0.4,"failureRateThreshold":0.5,"metrics":{"windowExecutionCount":3,"attemptedCount":2,"executedCount":1,"ambiguousCount":0,"failedCount":1,"ambiguityRate":0,"failureRate":0.5}}}}},"reasonCodes":["fleet_action_required","fleet_auto_candidates_rollout_gated","fleet_auto_candidates_safety_blocked"],"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-blue:health_critical","loopId":"loop-blue","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":false,"manualOnly":true,"reasons":["autonomous_rollout_canary_excluded"]}},{"candidateId":"loop-green:health_critical","loopId":"loop-green","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted","autonomous_max_actions_per_run_exceeded"]}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/handoff-state.json" <<'JSON'
{"schemaVersion":"v1","generatedAt":"2026-02-23T13:30:03Z","updatedAt":"2026-02-23T13:30:06Z","fleetId":"fleet-status-operator-visibility","traceId":"trace-fleet-status-operator-visibility-handoff-1","policyTraceId":"trace-fleet-status-operator-visibility-policy-1","mode":"guarded_auto","summary":{"intentCount":3,"autoEligibleIntentCount":2,"manualOnlyIntentCount":1,"pendingConfirmationCount":1,"executedCount":1,"ambiguousCount":0,"failedCount":1},"reasonCodes":["fleet_handoff_action_required","fleet_handoff_confirmation_pending","fleet_handoff_execution_failed","fleet_handoff_auto_eligible_intents"],"intents":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","intent":"cancel","status":"executed","transport":"local","autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"intentId":"loop-blue:health_critical:cancel","loopId":"loop-blue","intent":"cancel","status":"pending_operator_confirmation","transport":"sprite_service","autonomous":{"eligible":false,"manualOnly":true,"reasons":["autonomous_rollout_canary_excluded"]}},{"intentId":"loop-green:health_critical:cancel","loopId":"loop-green","intent":"cancel","status":"execution_failed","transport":"sprite_service","autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}}],"execution":{"mode":"autonomous","requestedBy":"ops-bot","requestedAt":"2026-02-23T13:30:04Z","completedAt":"2026-02-23T13:30:06Z","requestedIntentCount":2,"executedIntentCount":2,"executedCount":1,"ambiguousCount":0,"failedCount":1,"results":[{"intentId":"loop-red:reconcile_failed:cancel","loopId":"loop-red","status":"executed","reasonCode":"control_confirmed"},{"intentId":"loop-green:health_critical:cancel","loopId":"loop-green","status":"failed","reasonCode":"control_failed_command"}]}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl" <<'JSONL'
{"timestamp":"2026-02-23T13:30:06Z","category":"fleet_handoff_execute","fleetId":"fleet-status-operator-visibility","traceId":"trace-fleet-status-operator-visibility-handoff-1","execution":{"mode":"autonomous","requestedIntentCount":2,"executedCount":1,"ambiguousCount":0,"failedCount":1},"summary":{"summary":{"intentCount":3,"autoEligibleIntentCount":2,"manualOnlyIntentCount":1,"pendingConfirmationCount":1,"pendingManualOnlyCount":1,"executedCount":1,"ambiguousCount":0,"failedCount":1},"reasonCodes":["fleet_handoff_action_required","fleet_handoff_execution_failed"]}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-status.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.autonomous.governance.changedBy' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "ops-user" ]

  run jq -r '.autonomous.governance.changedAt' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-02-23T00:00:00Z" ]

  run jq -r '.autonomous.governance.why' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "guarded rollout expansion" ]

  run jq -r '.autonomous.governance.until' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-12-31T00:00:00Z" ]

  run jq -r '.autonomous.governance.posture' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "authority_missing" ]

  run jq -e '.autonomous.governance.reasonCodes | index("autonomous_governance_authority_missing") != null' <<<"$status_json"
  [ "$status" -eq 0 ]

  run jq -r '.autonomous.rollout.state.autoPauseActive' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.autonomous.rollout.autopause.active' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.autonomous.outcomeRollup.attempted' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.autonomous.outcomeRollup.executed' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.outcomeRollup.failed' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.outcomeRollup.manual_backlog' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.handoff.summary.autonomousOutcomeRollup.manual_backlog' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.latestHandoffTelemetry.autonomousOutcomeRollup.failed' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.safetyGateDecisions.byPath.policyGated.blockedCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.autonomous.safetyGateDecisions.byPath.rolloutGated.blockedCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -r '.autonomous.safetyGateDecisions.byPath.governanceGated.blockedCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -r '.autonomous.safetyGateDecisions.byPath.transportGated.blockedCount' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.autonomous.safetyGateDecisions.byPath.transportGated.byReason.control_failed_command' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.autonomous.safetyGateDecisions.suppressionReasonCodes | index("autonomous_suppression_policy_gated") != null' <<<"$status_json"
  [ "$status" -eq 0 ]

  run jq -e '.autonomous.safetyGateDecisions.suppressionReasonCodes | index("autonomous_suppression_rollout_gated") != null' <<<"$status_json"
  [ "$status" -eq 0 ]

  run jq -e '.autonomous.safetyGateDecisions.suppressionReasonCodes | index("autonomous_suppression_governance_gated") != null' <<<"$status_json"
  [ "$status" -eq 0 ]

  run jq -e '.autonomous.safetyGateDecisions.suppressionReasonCodes | index("autonomous_suppression_transport_gated") != null' <<<"$status_json"
  [ "$status" -eq 0 ]
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

@test "fleet policy supports guarded_auto mode while preserving advisory candidate semantics" {
  local repo="$TEMP_DIR/fleet-policy-guarded-auto"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-guarded-auto","loops":[{"loopId":"loop-red"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["reconcile_failed"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":1,"maxActionsPerLoop":1,"cooldownSeconds":300,"killSwitch":false}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T00:00:00Z","startedAt":"2026-02-22T23:59:50Z","fleetId":"fleet-policy-guarded-auto","traceId":"trace-fleet-policy-guarded-auto-1","status":"partial_failure","reasonCodes":["fleet_partial_failure"],"loopCount":1,"successCount":0,"failedCount":1,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T00:00:00Z","startedAt":"2026-02-22T23:59:55Z","loopId":"loop-red","transport":"local","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-guarded-auto-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.mode' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "guarded_auto" ]

  run jq -r '.candidateCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.autoEligibleCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.manualOnlyCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.candidates[] | select(.category == "reconcile_failed") | .autonomous.eligible' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.candidates[] | select(.category == "health_critical") | .autonomous.manualOnly' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -e '.candidates[] | select(.category == "health_critical") | .autonomous.reasons | index("category_not_allowlisted") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_eligible") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  local history_file="$repo/.superloop/ops-manager/fleet/telemetry/policy-history.jsonl"
  [ -f "$history_file" ]
  run bash -lc "tail -n 1 '$history_file' | jq -r '.autonomousEligible'"
  [ "$status" -eq 0 ]
  [[ "$output" == "true" || "$output" == "false" ]]
}

@test "fleet policy guarded_auto kill switch blocks autonomous eligibility without suppressing manual handoff" {
  local repo="$TEMP_DIR/fleet-policy-kill-switch"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-kill-switch","loops":[{"loopId":"loop-red"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["reconcile_failed","health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":5,"maxActionsPerLoop":5,"cooldownSeconds":300,"killSwitch":true}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T01:00:00Z","startedAt":"2026-02-23T00:59:50Z","fleetId":"fleet-policy-kill-switch","traceId":"trace-fleet-policy-kill-switch-1","status":"partial_failure","reasonCodes":["fleet_partial_failure"],"loopCount":1,"successCount":0,"failedCount":1,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T01:00:00Z","startedAt":"2026-02-23T00:59:55Z","loopId":"loop-red","transport":"local","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-kill-switch-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.autoEligibleCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.manualOnlyCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -e '.candidates[] | .autonomous.reasons | index("autonomous_kill_switch_enabled") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_kill_switch_enabled") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]
}

@test "incident drill kill switch halts autonomous execution and falls back to explicit manual handoff" {
  local repo="$TEMP_DIR/fleet-drill-kill-switch-fallback"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-drill-kill-switch-fallback","loops":[{"loopId":"loop-red","transport":"local"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-900","rationale":"kill switch drill","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":2,"maxActionsPerLoop":2,"cooldownSeconds":0,"killSwitch":true}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T01:10:00Z","startedAt":"2026-02-23T01:09:50Z","fleetId":"fleet-drill-kill-switch-fallback","traceId":"trace-fleet-drill-kill-switch-fallback-policy-1","status":"success","reasonCodes":[],"loopCount":1,"successCount":1,"failedCount":0,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T01:10:00Z","startedAt":"2026-02-23T01:09:55Z","loopId":"loop-red","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-drill-kill-switch-fallback-policy-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-drill-kill-switch-fallback-policy-1"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.autoEligibleCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.manualOnlyCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.candidates[] | .autonomous.reasons | index("autonomous_kill_switch_enabled") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  local control_log="$TEMP_DIR/fleet-drill-kill-switch-fallback-control-log.jsonl"
  local control_stub="$TEMP_DIR/fleet-drill-kill-switch-fallback-control-stub.sh"
  cat > "$control_stub" <<BASH
#!/usr/bin/env bash
set -euo pipefail

loop_id=""
trace_id=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --loop)
      loop_id="\${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="\${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

jq -cn --arg loop_id "\$loop_id" --arg trace_id "\$trace_id" '{loopId: \$loop_id, traceId: \$trace_id}' >> "$control_log"
jq -cn --arg status "confirmed" --argjson confirmed true '{status: \$status, confirmed: \$confirmed}'
BASH
  chmod +x "$control_stub"

  run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-drill-kill-switch-fallback-handoff-auto-1" \
    --autonomous-execute \
    --by "ops-bot"
  [ "$status" -eq 0 ]
  local autonomous_handoff="$output"

  run jq -r '.execution.mode' <<<"$autonomous_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous" ]

  run jq -r '.execution.requestedIntentCount' <<<"$autonomous_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$autonomous_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.reasonCodes | index("fleet_handoff_confirmation_pending") != null' <<<"$autonomous_handoff"
  [ "$status" -eq 0 ]

  if [[ -f "$control_log" ]]; then
    run bash -lc "wc -l < '$control_log' | tr -d ' '"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
  fi

  local intent_id
  intent_id="$(jq -r '.intents[0].intentId' <<<"$autonomous_handoff")"
  [[ -n "$intent_id" && "$intent_id" != "null" ]]

  run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-drill-kill-switch-fallback-handoff-manual-1" \
    --execute \
    --confirm \
    --intent-id "$intent_id" \
    --by "oncall-operator"
  [ "$status" -eq 0 ]
  local manual_handoff="$output"

  run jq -r '.execution.mode' <<<"$manual_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "manual" ]

  run jq -r '.execution.requestedIntentCount' <<<"$manual_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.executedCount' <<<"$manual_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$manual_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.intents[] | select(.intentId == "'"$intent_id"'") | .status' <<<"$manual_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "executed" ]

  run jq -e '.reasonCodes | index("fleet_handoff_executed") != null' <<<"$manual_handoff"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$control_log' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "fleet policy guarded_auto enforces per-run and per-loop autonomous action caps" {
  local repo="$TEMP_DIR/fleet-policy-caps"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-caps","loops":[{"loopId":"loop-a"},{"loopId":"loop-b"},{"loopId":"loop-c"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["reconcile_failed","health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":2,"maxActionsPerLoop":1,"cooldownSeconds":300,"killSwitch":false}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T01:30:00Z","startedAt":"2026-02-23T01:29:45Z","fleetId":"fleet-policy-caps","traceId":"trace-fleet-policy-caps-1","status":"partial_failure","reasonCodes":["fleet_partial_failure"],"loopCount":3,"successCount":2,"failedCount":1,"skippedCount":0,"durationSeconds":15,"execution":{"maxParallel":2,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T01:30:00Z","startedAt":"2026-02-23T01:29:50Z","loopId":"loop-a","transport":"local","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":4,"traceId":"trace-fleet-policy-caps-1-loop-a","files":{"stateFile":"/tmp/loop-a/state.json","healthFile":"/tmp/loop-a/health.json","cursorFile":"/tmp/loop-a/cursor.json","reconcileTelemetryFile":"/tmp/loop-a/reconcile.jsonl"}},{"timestamp":"2026-02-23T01:30:00Z","startedAt":"2026-02-23T01:29:52Z","loopId":"loop-b","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":3,"traceId":"trace-fleet-policy-caps-1-loop-b","files":{"stateFile":"/tmp/loop-b/state.json","healthFile":"/tmp/loop-b/health.json","cursorFile":"/tmp/loop-b/cursor.json","reconcileTelemetryFile":"/tmp/loop-b/reconcile.jsonl"}},{"timestamp":"2026-02-23T01:30:00Z","startedAt":"2026-02-23T01:29:54Z","loopId":"loop-c","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":3,"traceId":"trace-fleet-policy-caps-1-loop-c","files":{"stateFile":"/tmp/loop-c/state.json","healthFile":"/tmp/loop-c/health.json","cursorFile":"/tmp/loop-c/cursor.json","reconcileTelemetryFile":"/tmp/loop-c/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.autoEligibleCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -e '.candidates[] | select(.loopId == "loop-a" and .category == "reconcile_failed") | .autonomous.reasons | index("autonomous_max_actions_per_loop_exceeded") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.candidates[] | select(.loopId == "loop-c" and .category == "health_critical") | .autonomous.reasons | index("autonomous_max_actions_per_run_exceeded") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_safety_blocked") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]
}

@test "fleet policy guarded_auto cooldown blocks repeated autonomous candidate within window" {
  local repo="$TEMP_DIR/fleet-policy-auto-cooldown"
  local recent_ts
  recent_ts="$(iso_timestamp_minus_seconds 60)"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-auto-cooldown","loops":[{"loopId":"loop-a"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":3,"maxActionsPerLoop":3,"cooldownSeconds":600,"killSwitch":false}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T02:00:00Z","startedAt":"2026-02-23T01:59:50Z","fleetId":"fleet-policy-auto-cooldown","traceId":"trace-fleet-policy-auto-cooldown-1","status":"partial_failure","reasonCodes":["fleet_partial_failure"],"loopCount":1,"successCount":1,"failedCount":0,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T02:00:00Z","startedAt":"2026-02-23T01:59:55Z","loopId":"loop-a","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-auto-cooldown-1-loop-a","files":{"stateFile":"/tmp/loop-a/state.json","healthFile":"/tmp/loop-a/health.json","cursorFile":"/tmp/loop-a/cursor.json","reconcileTelemetryFile":"/tmp/loop-a/reconcile.jsonl"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/telemetry/policy-history.jsonl" <<JSONL
{"timestamp":"$recent_ts","category":"fleet_policy_candidate","fleetId":"fleet-policy-auto-cooldown","traceId":"trace-prev","mode":"guarded_auto","candidateId":"loop-a:health_critical","loopId":"loop-a","candidateCategory":"health_critical","autonomousEligible":true}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.autoEligibleCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -e '.candidates[] | select(.category == "health_critical") | .autonomous.reasons | index("autonomous_cooldown_active") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_safety_blocked") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]
}

@test "fleet policy guarded_auto applies deterministic rollout cohort gating" {
  local repo="$TEMP_DIR/fleet-policy-rollout-cohort"
  local rollout_salt="cohort-seed-v1"
  local canary_percent=50
  local in_loop=""
  local out_loop=""
  local candidate=""
  local bucket=""
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  for i in $(seq 1 400); do
    candidate="loop-$i"
    bucket="$(deterministic_rollout_bucket "${candidate}|${rollout_salt}")"
    if [[ -z "$in_loop" && "$bucket" -lt "$canary_percent" ]]; then
      in_loop="$candidate"
    fi
    if [[ -z "$out_loop" && "$bucket" -ge "$canary_percent" ]]; then
      out_loop="$candidate"
    fi
    if [[ -n "$in_loop" && -n "$out_loop" ]]; then
      break
    fi
  done

  [ -n "$in_loop" ]
  [ -n "$out_loop" ]

  local scope_miss_loop="loop-scope-miss"
  local in_bucket
  local out_bucket
  in_bucket="$(deterministic_rollout_bucket "${in_loop}|${rollout_salt}")"
  out_bucket="$(deterministic_rollout_bucket "${out_loop}|${rollout_salt}")"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<JSON
{"schemaVersion":"v1","fleetId":"fleet-policy-rollout-cohort","loops":[{"loopId":"$in_loop"},{"loopId":"$out_loop"},{"loopId":"$scope_miss_loop"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":10,"maxActionsPerLoop":10,"cooldownSeconds":0,"killSwitch":false},"rollout":{"canaryPercent":$canary_percent,"scope":{"loopIds":["$in_loop","$out_loop"]},"selector":{"salt":"$rollout_salt"}}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<JSON
{"schemaVersion":"v1","updatedAt":"2026-02-23T03:00:00Z","startedAt":"2026-02-23T02:59:50Z","fleetId":"fleet-policy-rollout-cohort","traceId":"trace-fleet-policy-rollout-cohort-1","status":"success","reasonCodes":[],"loopCount":3,"successCount":3,"failedCount":0,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":3,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T03:00:00Z","startedAt":"2026-02-23T02:59:52Z","loopId":"$in_loop","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":2,"traceId":"trace-fleet-policy-rollout-cohort-1-$in_loop","files":{"stateFile":"/tmp/$in_loop/state.json","healthFile":"/tmp/$in_loop/health.json","cursorFile":"/tmp/$in_loop/cursor.json","reconcileTelemetryFile":"/tmp/$in_loop/reconcile.jsonl"}},{"timestamp":"2026-02-23T03:00:00Z","startedAt":"2026-02-23T02:59:53Z","loopId":"$out_loop","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":2,"traceId":"trace-fleet-policy-rollout-cohort-1-$out_loop","files":{"stateFile":"/tmp/$out_loop/state.json","healthFile":"/tmp/$out_loop/health.json","cursorFile":"/tmp/$out_loop/cursor.json","reconcileTelemetryFile":"/tmp/$out_loop/reconcile.jsonl"}},{"timestamp":"2026-02-23T03:00:00Z","startedAt":"2026-02-23T02:59:54Z","loopId":"$scope_miss_loop","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":2,"traceId":"trace-fleet-policy-rollout-cohort-1-$scope_miss_loop","files":{"stateFile":"/tmp/$scope_miss_loop/state.json","healthFile":"/tmp/$scope_miss_loop/health.json","cursorFile":"/tmp/$scope_miss_loop/cursor.json","reconcileTelemetryFile":"/tmp/$scope_miss_loop/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-rollout-cohort-1"
  [ "$status" -eq 0 ]
  local first_policy_json="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-rollout-cohort-2"
  [ "$status" -eq 0 ]
  local second_policy_json="$output"

  run jq -r ".candidates[] | select(.loopId == \"$in_loop\") | .autonomous.eligible" <<<"$first_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r ".candidates[] | select(.loopId == \"$in_loop\") | .autonomous.rollout.selector.bucket" <<<"$first_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$in_bucket" ]

  run jq -r ".candidates[] | select(.loopId == \"$out_loop\") | .autonomous.manualOnly" <<<"$first_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -e ".candidates[] | select(.loopId == \"$out_loop\") | .autonomous.reasons | index(\"autonomous_rollout_canary_excluded\") != null" <<<"$first_policy_json"
  [ "$status" -eq 0 ]

  run jq -r ".candidates[] | select(.loopId == \"$out_loop\") | .autonomous.rollout.selector.bucket" <<<"$first_policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$out_bucket" ]

  run jq -e ".candidates[] | select(.loopId == \"$scope_miss_loop\") | .autonomous.reasons | index(\"autonomous_rollout_scope_excluded\") != null" <<<"$first_policy_json"
  [ "$status" -eq 0 ]

  run jq -cn \
    --argjson first "$first_policy_json" \
    --argjson second "$second_policy_json" \
    '(
      $first.candidates
      | map({candidateId, bucket: .autonomous.rollout.selector.bucket, inCohort: .autonomous.rollout.selector.inCohort})
      | sort_by(.candidateId)
    ) == (
      $second.candidates
      | map({candidateId, bucket: .autonomous.rollout.selector.bucket, inCohort: .autonomous.rollout.selector.inCohort})
      | sort_by(.candidateId)
    )'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_rollout_gated") != null' <<<"$first_policy_json"
  [ "$status" -eq 0 ]
}

@test "fleet policy rollout manual pause blocks autonomous dispatch while keeping manual handoff pending" {
  local repo="$TEMP_DIR/fleet-policy-rollout-manual-pause"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-rollout-manual-pause","loops":[{"loopId":"loop-red","transport":"local"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":3,"maxActionsPerLoop":3,"cooldownSeconds":0,"killSwitch":false},"rollout":{"canaryPercent":100,"pause":{"manual":true}}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T03:20:00Z","startedAt":"2026-02-23T03:19:50Z","fleetId":"fleet-policy-rollout-manual-pause","traceId":"trace-fleet-policy-rollout-manual-pause-1","status":"success","reasonCodes":[],"loopCount":1,"successCount":1,"failedCount":0,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T03:20:00Z","startedAt":"2026-02-23T03:19:55Z","loopId":"loop-red","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-rollout-manual-pause-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-rollout-manual-pause-1"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.autoEligibleCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.manualOnlyCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.candidates[] | .autonomous.reasons | index("autonomous_rollout_paused_manual") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_paused") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" --repo "$repo" --trace-id "trace-fleet-handoff-rollout-manual-pause-1"
  [ "$status" -eq 0 ]
  local handoff_plan="$output"

  run jq -r '.summary.intentCount' <<<"$handoff_plan"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.autoEligibleIntentCount' <<<"$handoff_plan"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$handoff_plan"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-rollout-manual-pause-2" \
    --autonomous-execute \
    --by "ops-bot"
  [ "$status" -eq 0 ]
  local handoff_exec="$output"

  run jq -r '.execution.requestedIntentCount' <<<"$handoff_exec"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$handoff_exec"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "fleet policy rollout auto-pause triggers on autonomous ambiguity spike and preserves manual fallback" {
  local repo="$TEMP_DIR/fleet-policy-rollout-auto-pause"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-rollout-auto-pause","loops":[{"loopId":"loop-red","transport":"local"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-123","rationale":"dogfood guarded auto","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":3,"maxActionsPerLoop":3,"cooldownSeconds":0,"killSwitch":false},"rollout":{"canaryPercent":100,"pause":{"manual":false},"autoPause":{"enabled":true,"lookbackExecutions":3,"minSampleSize":2,"ambiguityRateThreshold":0.4,"failureRateThreshold":0.8}}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T03:40:00Z","startedAt":"2026-02-23T03:39:50Z","fleetId":"fleet-policy-rollout-auto-pause","traceId":"trace-fleet-policy-rollout-auto-pause-1","status":"success","reasonCodes":[],"loopCount":1,"successCount":1,"failedCount":0,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T03:40:00Z","startedAt":"2026-02-23T03:39:55Z","loopId":"loop-red","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-rollout-auto-pause-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl" <<'JSONL'
{"timestamp":"2026-02-23T03:35:00Z","category":"fleet_handoff_execute","fleetId":"fleet-policy-rollout-auto-pause","traceId":"trace-auto-1","execution":{"mode":"autonomous","requestedIntentCount":2,"executedCount":1,"ambiguousCount":1,"failedCount":0}}
{"timestamp":"2026-02-23T03:36:00Z","category":"fleet_handoff_execute","fleetId":"fleet-policy-rollout-auto-pause","traceId":"trace-auto-2","execution":{"mode":"autonomous","requestedIntentCount":2,"executedCount":1,"ambiguousCount":1,"failedCount":0}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-rollout-auto-pause-1"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.autoEligibleCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.autonomous.rollout.pause.auto.active' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.autonomous.rollout.pause.auto.metrics.attemptedCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]

  run jq -r '.autonomous.rollout.pause.auto.metrics.ambiguityRate' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0.5" ]

  run jq -e '.candidates[] | .autonomous.reasons | index("autonomous_rollout_paused_auto") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.candidates[] | .autonomous.reasons | index("autonomous_autopause_ambiguous_spike") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_paused") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_autopause_triggered") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" --repo "$repo" --trace-id "trace-fleet-handoff-rollout-auto-pause-1"
  [ "$status" -eq 0 ]
  local handoff_json="$output"

  run jq -r '.summary.intentCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.autoEligibleIntentCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "incident drill sprite_service outage triggers autonomous auto-pause and reason-coded manual fallback" {
  local repo="$TEMP_DIR/fleet-drill-sprite-outage-autopause"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-drill-sprite-outage-autopause","loops":[{"loopId":"loop-sprite","transport":"sprite_service","service":{"baseUrl":"http://sprite-outage.local"}}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-901","rationale":"sprite outage drill","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["reconcile_failed"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":3,"maxActionsPerLoop":3,"cooldownSeconds":0,"killSwitch":false},"rollout":{"canaryPercent":100,"pause":{"manual":false},"autoPause":{"enabled":true,"lookbackExecutions":3,"minSampleSize":2,"ambiguityRateThreshold":0.9,"failureRateThreshold":0.5}}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T05:10:00Z","startedAt":"2026-02-23T05:09:50Z","fleetId":"fleet-drill-sprite-outage-autopause","traceId":"trace-fleet-drill-sprite-outage-policy-1","status":"partial_failure","reasonCodes":["fleet_partial_failure","fleet_reconcile_failed"],"loopCount":1,"successCount":0,"failedCount":1,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T05:10:00Z","startedAt":"2026-02-23T05:09:55Z","loopId":"loop-sprite","transport":"sprite_service","enabled":true,"status":"failed","reasonCode":"reconcile_failed","reconcileStatus":"failed","healthStatus":"degraded","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-drill-sprite-outage-policy-1-loop-sprite","files":{"stateFile":"/tmp/loop-sprite/state.json","healthFile":"/tmp/loop-sprite/health.json","cursorFile":"/tmp/loop-sprite/cursor.json","reconcileTelemetryFile":"/tmp/loop-sprite/reconcile.jsonl"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl" <<'JSONL'
{"timestamp":"2026-02-23T05:00:00Z","category":"fleet_handoff_execute","fleetId":"fleet-drill-sprite-outage-autopause","traceId":"trace-fleet-drill-sprite-outage-auto-1","execution":{"mode":"autonomous","requestedIntentCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1}}
{"timestamp":"2026-02-23T05:01:00Z","category":"fleet_handoff_execute","fleetId":"fleet-drill-sprite-outage-autopause","traceId":"trace-fleet-drill-sprite-outage-auto-2","execution":{"mode":"autonomous","requestedIntentCount":1,"executedCount":0,"ambiguousCount":0,"failedCount":1}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-drill-sprite-outage-policy-1"
  [ "$status" -eq 0 ]
  local policy_json="$output"

  run jq -r '.autonomous.rollout.pause.auto.active' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.autonomous.rollout.pause.auto.metrics.attemptedCount' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.autonomous.rollout.pause.auto.metrics.failureRate' <<<"$policy_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.candidates[] | .autonomous.reasons | index("autonomous_rollout_paused_auto") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.candidates[] | .autonomous.reasons | index("autonomous_autopause_failure_spike") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_paused") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_auto_candidates_autopause_triggered") != null' <<<"$policy_json"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" --repo "$repo" --trace-id "trace-fleet-drill-sprite-outage-handoff-plan-1"
  [ "$status" -eq 0 ]
  local handoff_plan="$output"

  run jq -r '.summary.autoEligibleIntentCount' <<<"$handoff_plan"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$handoff_plan"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -e '.intents[] | .autonomous.reasons | index("autonomous_autopause_failure_spike") != null' <<<"$handoff_plan"
  [ "$status" -eq 0 ]

  local control_log="$TEMP_DIR/fleet-drill-sprite-outage-control-log.jsonl"
  local control_stub="$TEMP_DIR/fleet-drill-sprite-outage-control-stub.sh"
  cat > "$control_stub" <<BASH
#!/usr/bin/env bash
set -euo pipefail
jq -cn '{called: true}' >> "$control_log"
jq -cn --arg status "confirmed" --argjson confirmed true '{status: \$status, confirmed: \$confirmed}'
BASH
  chmod +x "$control_stub"

  run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-drill-sprite-outage-handoff-auto-1" \
    --autonomous-execute \
    --by "ops-bot"
  [ "$status" -eq 0 ]
  local handoff_auto="$output"

  run jq -r '.execution.requestedIntentCount' <<<"$handoff_auto"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$handoff_auto"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -e '.reasonCodes | index("fleet_handoff_confirmation_pending") != null' <<<"$handoff_auto"
  [ "$status" -eq 0 ]

  if [[ -f "$control_log" ]]; then
    run bash -lc "wc -l < '$control_log' | tr -d ' '"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
  fi
}

@test "fleet policy emits immutable governance audit events for autonomous initialization mutation and mode toggles" {
  local repo="$TEMP_DIR/fleet-policy-governance-audit"
  local audit_file="$repo/.superloop/ops-manager/fleet/telemetry/policy-governance.jsonl"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-governance-audit","loops":[{"loopId":"loop-red"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-111","rationale":"initial approval","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":1,"maxActionsPerLoop":1,"cooldownSeconds":0,"killSwitch":false}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T04:00:00Z","startedAt":"2026-02-23T03:59:50Z","fleetId":"fleet-policy-governance-audit","traceId":"trace-fleet-policy-governance-audit-1","status":"success","reasonCodes":[],"loopCount":1,"successCount":1,"failedCount":0,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-23T04:00:00Z","startedAt":"2026-02-23T03:59:55Z","loopId":"loop-red","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-governance-audit-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-governance-audit-1"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-governance-audit-2"
  [ "$status" -eq 0 ]

  [ -f "$audit_file" ]
  run bash -lc "wc -l < '$audit_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.eventType'"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous_policy_initialized" ]

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-governance-audit","loops":[{"loopId":"loop-red"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-222","rationale":"expanded safety envelope","changedAt":"2026-02-24T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":1,"maxActionsPerLoop":1,"cooldownSeconds":0,"killSwitch":false}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-governance-audit-3"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$audit_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.eventType'"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous_policy_mutated" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-fleet-policy-governance-audit-3" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.governance.approvalRef'"
  [ "$status" -eq 0 ]
  [ "$output" = "CAB-222" ]

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-governance-audit","loops":[{"loopId":"loop-red"}],"policy":{"mode":"advisory","noiseControls":{"dedupeWindowSeconds":0}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-governance-audit-4"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$audit_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.eventType'"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous_mode_toggled" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.previousMode'"
  [ "$status" -eq 0 ]
  [ "$output" = "guarded_auto" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.mode'"
  [ "$status" -eq 0 ]
  [ "$output" = "advisory" ]
}

@test "fleet policy governance audit snapshots remain deterministic across mutation reruns" {
  local repo="$TEMP_DIR/fleet-policy-governance-deterministic"
  local audit_file="$repo/.superloop/ops-manager/fleet/telemetry/policy-governance.jsonl"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-governance-deterministic","loops":[{"loopId":"loop-red"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-301","rationale":"baseline approval","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":1,"maxActionsPerLoop":1,"cooldownSeconds":0,"killSwitch":false}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-24T01:00:00Z","startedAt":"2026-02-24T00:59:50Z","fleetId":"fleet-policy-governance-deterministic","traceId":"trace-fleet-policy-governance-deterministic-1","status":"success","reasonCodes":[],"loopCount":1,"successCount":1,"failedCount":0,"skippedCount":0,"durationSeconds":10,"execution":{"maxParallel":1,"deterministicOrder":true,"fromStart":false,"maxEvents":0},"results":[{"timestamp":"2026-02-24T01:00:00Z","startedAt":"2026-02-24T00:59:55Z","loopId":"loop-red","transport":"local","enabled":true,"status":"success","reconcileStatus":"success","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":5,"traceId":"trace-fleet-policy-governance-deterministic-1-loop-red","files":{"stateFile":"/tmp/loop-red/state.json","healthFile":"/tmp/loop-red/health.json","cursorFile":"/tmp/loop-red/cursor.json","reconcileTelemetryFile":"/tmp/loop-red/reconcile.jsonl"}}]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-governance-deterministic-1"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$audit_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.eventType'"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous_policy_initialized" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.controls.safety.maxActionsPerRun'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-policy-governance-deterministic","loops":[{"loopId":"loop-red"}],"policy":{"mode":"guarded_auto","noiseControls":{"dedupeWindowSeconds":0},"autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-302","rationale":"expanded run cap","changedAt":"2026-02-24T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"},"allow":{"categories":["health_critical"],"intents":["cancel"]},"thresholds":{"minSeverity":"critical","minConfidence":"high"},"safety":{"maxActionsPerRun":2,"maxActionsPerLoop":1,"cooldownSeconds":0,"killSwitch":false}}}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-governance-deterministic-2"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$audit_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.eventType'"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous_policy_mutated" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.previousGovernance.approvalRef'"
  [ "$status" -eq 0 ]
  [ "$output" = "CAB-301" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.governance.approvalRef'"
  [ "$status" -eq 0 ]
  [ "$output" = "CAB-302" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.previousControls.safety.maxActionsPerRun'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "tail -n 1 '$audit_file' | jq -r '.controls.safety.maxActionsPerRun'"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-policy.sh" --repo "$repo" --trace-id "trace-fleet-policy-governance-deterministic-3"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$audit_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "fleet handoff mixed autonomous outcomes keep reason-code projection stable" {
  local repo_a="$TEMP_DIR/fleet-handoff-mixed-a"
  local repo_b="$TEMP_DIR/fleet-handoff-mixed-b"
  local first_handoff=""
  local second_handoff=""

  for repo in "$repo_a" "$repo_b"; do
    mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

    cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-mixed-stability","loops":[{"loopId":"loop-ok","transport":"local"},{"loopId":"loop-amb","transport":"local"},{"loopId":"loop-fail","transport":"local"}]}
JSON

    cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-24T02:00:00Z","fleetId":"fleet-handoff-mixed-stability","traceId":"trace-fleet-handoff-mixed-stability-policy","mode":"guarded_auto","candidateCount":3,"unsuppressedCount":3,"suppressedCount":0,"autoEligibleCount":3,"manualOnlyCount":0,"candidates":[{"candidateId":"loop-ok:reconcile_failed","loopId":"loop-ok","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-amb:reconcile_failed","loopId":"loop-amb","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-fail:health_critical","loopId":"loop-fail","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}}],"reasonCodes":["fleet_action_required","fleet_auto_candidates_eligible"]}
JSON

    local control_stub="$TEMP_DIR/$(basename "$repo")-mixed-control-stub.sh"
    cat > "$control_stub" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

loop_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop)
      loop_id="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$loop_id" in
  loop-ok)
    jq -cn --arg status "confirmed" --argjson confirmed true '{status: $status, confirmed: $confirmed}'
    exit 0
    ;;
  loop-amb)
    jq -cn --arg status "ambiguous" --argjson confirmed false '{status: $status, confirmed: $confirmed}'
    exit 2
    ;;
  *)
    jq -cn --arg status "failed_command" --argjson confirmed false '{status: $status, confirmed: $confirmed}'
    exit 1
    ;;
esac
BASH
    chmod +x "$control_stub"

    run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
      "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
      --repo "$repo" \
      --trace-id "trace-fleet-handoff-mixed-stability-1" \
      --autonomous-execute \
      --by "ops-bot"
    [ "$status" -eq 0 ]

    if [[ "$repo" == "$repo_a" ]]; then
      first_handoff="$output"
    else
      second_handoff="$output"
    fi
  done

  local first_projection
  local second_projection
  first_projection="$(jq -c '{summary: (.summary | {executedCount, ambiguousCount, failedCount, pendingConfirmationCount}), reasonCodes: ((.reasonCodes // []) | sort), executionReasonCodes: ((.execution.results // []) | map(.reasonCode) | sort), intentStatuses: ((.intents // []) | map({intentId, status}) | sort_by(.intentId))}' <<<"$first_handoff")"
  second_projection="$(jq -c '{summary: (.summary | {executedCount, ambiguousCount, failedCount, pendingConfirmationCount}), reasonCodes: ((.reasonCodes // []) | sort), executionReasonCodes: ((.execution.results // []) | map(.reasonCode) | sort), intentStatuses: ((.intents // []) | map({intentId, status}) | sort_by(.intentId))}' <<<"$second_handoff")"
  [ "$first_projection" = "$second_projection" ]

  run jq -r '.summary.executedCount' <<<"$first_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.ambiguousCount' <<<"$first_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.failedCount' <<<"$first_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.reasonCodes | index("fleet_handoff_executed") != null' <<<"$first_handoff"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_handoff_execution_ambiguous") != null' <<<"$first_handoff"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_handoff_execution_failed") != null' <<<"$first_handoff"
  [ "$status" -eq 0 ]
}

@test "fleet handoff maps unsuppressed candidates into explicit pending control intents" {
  local repo="$TEMP_DIR/fleet-handoff-plan"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-plan","loops":[{"loopId":"loop-red","transport":"local"},{"loopId":"loop-blue","transport":"local"}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T10:00:00Z","fleetId":"fleet-handoff-plan","traceId":"trace-fleet-handoff-plan-policy","mode":"advisory","candidateCount":3,"unsuppressedCount":2,"suppressedCount":1,"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","suppressed":false},{"candidateId":"loop-blue:health_critical","loopId":"loop-blue","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","suppressed":false},{"candidateId":"loop-blue:health_degraded","loopId":"loop-blue","category":"health_degraded","signal":"health_degraded","severity":"warning","confidence":"medium","rationale":"Loop health is degraded","suppressed":true,"suppressionScope":"global","suppressionReason":"registry_policy_suppression"}],"reasonCodes":["fleet_action_required"]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-plan-1"
  [ "$status" -eq 0 ]
  local handoff_json="$output"

  run jq -r '.summary.intentCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '[.intents[] | .intent] | unique | join(",")' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "cancel" ]

  run jq -r '[.intents[] | .status] | unique | join(",")' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "pending_operator_confirmation" ]

  run jq -e '.reasonCodes | index("fleet_handoff_confirmation_pending") != null' <<<"$handoff_json"
  [ "$status" -eq 0 ]

  run jq -r '.intents[0].idempotencyKey' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [[ "$output" == fleet-handoff-trace-fleet-handoff-plan-1-* ]]

  local telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl"
  [ -f "$telemetry_file" ]
  run bash -lc "tail -n 1 '$telemetry_file' | jq -r '.category'"
  [ "$status" -eq 0 ]
  [ "$output" = "fleet_handoff_plan" ]
}

@test "fleet handoff preserves autonomous eligibility classification from policy candidates" {
  local repo="$TEMP_DIR/fleet-handoff-autonomy"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-autonomy","loops":[{"loopId":"loop-red","transport":"local"},{"loopId":"loop-blue","transport":"local"}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T10:30:00Z","fleetId":"fleet-handoff-autonomy","traceId":"trace-fleet-handoff-autonomy-policy","mode":"guarded_auto","candidateCount":2,"unsuppressedCount":2,"suppressedCount":0,"autoEligibleCount":1,"manualOnlyCount":1,"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-blue:health_critical","loopId":"loop-blue","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted"]}}],"reasonCodes":["fleet_action_required","fleet_auto_candidates_eligible"]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-autonomy-1"
  [ "$status" -eq 0 ]
  local handoff_json="$output"

  run jq -r '.summary.autoEligibleIntentCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.manualOnlyIntentCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.intents[] | select(.loopId == "loop-red") | .autonomous.eligible' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.intents[] | select(.loopId == "loop-blue") | .autonomous.manualOnly' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -e '.intents[] | select(.loopId == "loop-blue") | .autonomous.reasons | index("category_not_allowlisted") != null' <<<"$handoff_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_handoff_auto_eligible_intents") != null' <<<"$handoff_json"
  [ "$status" -eq 0 ]
}

@test "fleet handoff execute requires explicit confirmation and propagates trace/idempotency" {
  local repo="$TEMP_DIR/fleet-handoff-exec"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-exec","loops":[{"loopId":"loop-red","transport":"local"}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T11:00:00Z","fleetId":"fleet-handoff-exec","traceId":"trace-fleet-handoff-exec-policy","mode":"advisory","candidateCount":1,"unsuppressedCount":1,"suppressedCount":0,"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","suppressed":false}],"reasonCodes":["fleet_action_required"]}
JSON

  local superloop_stub="$TEMP_DIR/superloop-stub.sh"
  cat > "$superloop_stub" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
echo "ok"
BASH
  chmod +x "$superloop_stub"

  local confirm_stub="$TEMP_DIR/confirm-stub.sh"
  cat > "$confirm_stub" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
intent=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --intent)
      intent="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
jq -cn \
  --arg intent "$intent" \
  --arg observed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{
    intent: $intent,
    confirmed: true,
    reason: "stubbed_confirmation",
    attempts: 1,
    timeoutSeconds: 0,
    observedStatus: "running",
    observedLastEvent: "stubbed",
    observedApprovalStatus: null,
    observedActive: false,
    observedAt: $observed_at
  }'
BASH
  chmod +x "$confirm_stub"

  run env \
    SUPERLOOP_BIN="$superloop_stub" \
    OPS_MANAGER_CONFIRM_SCRIPT="$confirm_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-exec-1" \
    --execute \
    --by "operator-a"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--execute requires --confirm"* ]]

  run env \
    SUPERLOOP_BIN="$superloop_stub" \
    OPS_MANAGER_CONFIRM_SCRIPT="$confirm_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-exec-1" \
    --execute \
    --confirm \
    --by "operator-a" \
    --note "manual_action"
  [ "$status" -eq 0 ]
  local handoff_json="$output"

  run jq -r '.summary.executedCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.intents[0].status' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "executed" ]

  run jq -r '.execution.results[0].traceId' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-fleet-handoff-exec-1" ]

  run jq -r '.execution.results[0].idempotencyKey' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  local expected_idempotency="$output"

  local control_telemetry_file="$repo/.superloop/ops-manager/loop-red/telemetry/control.jsonl"
  [ -f "$control_telemetry_file" ]

  run bash -lc "tail -n 1 '$control_telemetry_file' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-fleet-handoff-exec-1" ]

  run bash -lc "tail -n 1 '$control_telemetry_file' | jq -r '.idempotencyKey'"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected_idempotency" ]
}

@test "fleet handoff autonomous execute requires guarded_auto policy mode" {
  local repo="$TEMP_DIR/fleet-handoff-autonomous-mode-gate"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-autonomous-mode-gate","loops":[{"loopId":"loop-red","transport":"local"}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T12:00:00Z","fleetId":"fleet-handoff-autonomous-mode-gate","traceId":"trace-fleet-handoff-autonomous-mode-gate-policy","mode":"advisory","candidateCount":1,"unsuppressedCount":1,"suppressedCount":0,"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}}],"reasonCodes":["fleet_action_required"]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-autonomous-mode-gate-1" \
    --autonomous-execute
  [ "$status" -ne 0 ]
  [[ "$output" == *"--autonomous-execute requires policy mode guarded_auto"* ]]
}

@test "fleet handoff autonomous execute dispatches only autonomous-eligible intents" {
  local repo="$TEMP_DIR/fleet-handoff-autonomous-eligible"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-autonomous-eligible","loops":[{"loopId":"loop-red","transport":"local"},{"loopId":"loop-blue","transport":"local"}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T12:10:00Z","fleetId":"fleet-handoff-autonomous-eligible","traceId":"trace-fleet-handoff-autonomous-eligible-policy","mode":"guarded_auto","candidateCount":2,"unsuppressedCount":2,"suppressedCount":0,"autoEligibleCount":1,"manualOnlyCount":1,"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-blue:health_critical","loopId":"loop-blue","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted"]}}],"reasonCodes":["fleet_action_required","fleet_auto_candidates_eligible"]}
JSON

  local control_log="$TEMP_DIR/fleet-autonomous-control-log.jsonl"
  local control_stub="$TEMP_DIR/fleet-autonomous-control-stub.sh"
  cat > "$control_stub" <<BASH
#!/usr/bin/env bash
set -euo pipefail

loop_id=""
transport=""
trace_id=""
idempotency_key=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --loop)
      loop_id="\${2:-}"
      shift 2
      ;;
    --transport)
      transport="\${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="\${2:-}"
      shift 2
      ;;
    --idempotency-key)
      idempotency_key="\${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

jq -cn \
  --arg loop_id "\$loop_id" \
  --arg transport "\$transport" \
  --arg trace_id "\$trace_id" \
  --arg idempotency_key "\$idempotency_key" \
  '{loopId: \$loop_id, transport: \$transport, traceId: \$trace_id, idempotencyKey: \$idempotency_key, status: "confirmed", confirmed: true}' \
  >> "$control_log"

jq -cn --arg status "confirmed" --argjson confirmed true '{status: \$status, confirmed: \$confirmed}'
BASH
  chmod +x "$control_stub"

  run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-autonomous-eligible-1" \
    --autonomous-execute \
    --by "operator-auto"
  [ "$status" -eq 0 ]
  local handoff_json="$output"

  run jq -r '.execution.mode' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous" ]

  run jq -r '.execution.requestedIntentCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.executedCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.intents[] | select(.loopId == "loop-red") | .status' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "executed" ]

  run jq -r '.intents[] | select(.loopId == "loop-blue") | .status' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "pending_operator_confirmation" ]

  run jq -r '.execution.results[0].reasonCode' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "control_confirmed" ]

  run bash -lc "wc -l < '$control_log' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.loopId' "$control_log"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-red" ]
}

@test "incident drill ambiguous autonomous outcomes are retry-guarded to prevent execution storms" {
  local repo="$TEMP_DIR/fleet-drill-ambiguous-retry-guard"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-drill-ambiguous-retry-guard","loops":[{"loopId":"loop-red","transport":"local"}],"policy":{"mode":"guarded_auto","autonomous":{"governance":{"actor":"ops-user","approvalRef":"CAB-902","rationale":"ambiguous retry guard drill","changedAt":"2026-02-23T00:00:00Z","reviewBy":"2026-12-31T00:00:00Z"}}}}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T12:30:00Z","fleetId":"fleet-drill-ambiguous-retry-guard","traceId":"trace-fleet-drill-ambiguous-retry-guard-policy-1","mode":"guarded_auto","candidateCount":1,"unsuppressedCount":1,"suppressedCount":0,"autoEligibleCount":1,"manualOnlyCount":0,"candidates":[{"candidateId":"loop-red:reconcile_failed","loopId":"loop-red","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}}],"reasonCodes":["fleet_action_required","fleet_auto_candidates_eligible"]}
JSON

  local control_log="$TEMP_DIR/fleet-drill-ambiguous-retry-guard-control-log.jsonl"
  local control_stub="$TEMP_DIR/fleet-drill-ambiguous-retry-guard-control-stub.sh"
  cat > "$control_stub" <<BASH
#!/usr/bin/env bash
set -euo pipefail

loop_id=""
trace_id=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --loop)
      loop_id="\${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="\${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

jq -cn --arg loop_id "\$loop_id" --arg trace_id "\$trace_id" '{loopId: \$loop_id, traceId: \$trace_id}' >> "$control_log"
jq -cn --arg status "ambiguous" --argjson confirmed false '{status: \$status, confirmed: \$confirmed}'
exit 2
BASH
  chmod +x "$control_stub"

  run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-drill-ambiguous-retry-guard-handoff-1" \
    --autonomous-execute \
    --by "ops-bot"
  [ "$status" -eq 0 ]
  local first_handoff="$output"

  run jq -r '.execution.requestedIntentCount' <<<"$first_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.ambiguousCount' <<<"$first_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -e '.reasonCodes | index("fleet_handoff_execution_ambiguous") != null' <<<"$first_handoff"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$control_log' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-drill-ambiguous-retry-guard-handoff-2" \
    --autonomous-execute \
    --by "ops-bot"
  [ "$status" -eq 0 ]
  local second_handoff="$output"

  run jq -r '.execution.requestedIntentCount' <<<"$second_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.ambiguousCount' <<<"$second_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.summary.pendingConfirmationCount' <<<"$second_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.intents[0].status' <<<"$second_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "pending_operator_confirmation" ]

  run jq -r '.intents[0].autonomous.manualOnly' <<<"$second_handoff"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -e '.intents[0].autonomous.reasons | index("autonomous_retry_guard_ambiguous") != null' <<<"$second_handoff"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_handoff_retry_guarded") != null' <<<"$second_handoff"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("fleet_handoff_confirmation_pending") != null' <<<"$second_handoff"
  [ "$status" -eq 0 ]

  run bash -lc "wc -l < '$control_log' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "fleet handoff autonomous execute preserves deterministic status mapping across transports" {
  local repo="$TEMP_DIR/fleet-handoff-autonomous-status"
  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-autonomous-status","loops":[{"loopId":"loop-ok","transport":"local"},{"loopId":"loop-amb","transport":"sprite_service","service":{"baseUrl":"http://sprite-service.local"}},{"loopId":"loop-fail","transport":"sprite_service","service":{"baseUrl":"http://sprite-service.local"}}]}
JSON

  cat > "$repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T12:20:00Z","fleetId":"fleet-handoff-autonomous-status","traceId":"trace-fleet-handoff-autonomous-status-policy","mode":"guarded_auto","candidateCount":3,"unsuppressedCount":3,"suppressedCount":0,"autoEligibleCount":3,"manualOnlyCount":0,"candidates":[{"candidateId":"loop-ok:reconcile_failed","loopId":"loop-ok","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-amb:reconcile_failed","loopId":"loop-amb","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-fail:health_critical","loopId":"loop-fail","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}}],"reasonCodes":["fleet_action_required","fleet_auto_candidates_eligible"]}
JSON

  local control_log="$TEMP_DIR/fleet-autonomous-status-control-log.jsonl"
  local control_stub="$TEMP_DIR/fleet-autonomous-status-control-stub.sh"
  cat > "$control_stub" <<BASH
#!/usr/bin/env bash
set -euo pipefail

loop_id=""
transport=""
trace_id=""
idempotency_key=""
service_base_url=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --loop)
      loop_id="\${2:-}"
      shift 2
      ;;
    --transport)
      transport="\${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="\${2:-}"
      shift 2
      ;;
    --idempotency-key)
      idempotency_key="\${2:-}"
      shift 2
      ;;
    --service-base-url)
      service_base_url="\${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

jq -cn \
  --arg loop_id "\$loop_id" \
  --arg transport "\$transport" \
  --arg trace_id "\$trace_id" \
  --arg idempotency_key "\$idempotency_key" \
  --arg service_base_url "\$service_base_url" \
  '{loopId: \$loop_id, transport: \$transport, traceId: \$trace_id, idempotencyKey: \$idempotency_key, serviceBaseUrl: (if (\$service_base_url | length) > 0 then \$service_base_url else null end)} | with_entries(select(.value != null))' \
  >> "$control_log"

if [[ "\$transport" == "sprite_service" && -z "\$service_base_url" ]]; then
  jq -cn --arg status "failed_command" --argjson confirmed false '{status: \$status, confirmed: \$confirmed}'
  exit 1
fi

case "\$loop_id" in
  loop-ok)
    jq -cn --arg status "confirmed" --argjson confirmed true '{status: \$status, confirmed: \$confirmed}'
    exit 0
    ;;
  loop-amb)
    jq -cn --arg status "ambiguous" --argjson confirmed false '{status: \$status, confirmed: \$confirmed}'
    exit 2
    ;;
  *)
    jq -cn --arg status "failed_command" --argjson confirmed false '{status: \$status, confirmed: \$confirmed}'
    exit 1
    ;;
esac
BASH
  chmod +x "$control_stub"

  run env OPS_MANAGER_CONTROL_SCRIPT="$control_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$repo" \
    --trace-id "trace-fleet-handoff-autonomous-status-1" \
    --autonomous-execute \
    --by "operator-auto"
  [ "$status" -eq 0 ]
  local handoff_json="$output"

  run jq -r '.summary.executedCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.ambiguousCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.failedCount' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.intents[] | select(.loopId == "loop-ok") | .status' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "executed" ]

  run jq -r '.intents[] | select(.loopId == "loop-amb") | .status' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "execution_ambiguous" ]

  run jq -r '.intents[] | select(.loopId == "loop-fail") | .status' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "execution_failed" ]

  run jq -r '.execution.results[] | select(.loopId == "loop-ok") | .reasonCode' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "control_confirmed" ]

  run jq -r '.execution.results[] | select(.loopId == "loop-amb") | .reasonCode' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "control_ambiguous" ]

  run jq -r '.execution.results[] | select(.loopId == "loop-fail") | .reasonCode' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "control_failed_command" ]

  run jq -r '.execution.results[] | select(.loopId == "loop-amb") | .traceId' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-fleet-handoff-autonomous-status-1" ]

  run jq -r '.execution.results[] | select(.loopId == "loop-fail") | .idempotencyKey' <<<"$handoff_json"
  [ "$status" -eq 0 ]
  [[ -n "$output" && "$output" != "null" ]]

  run bash -lc "wc -l < '$control_log' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -r '. | select(.loopId == "loop-amb") | .transport' "$control_log"
  [ "$status" -eq 0 ]
  [ "$output" = "sprite_service" ]

  run jq -r '. | select(.loopId == "loop-amb") | .serviceBaseUrl' "$control_log"
  [ "$status" -eq 0 ]
  [ "$output" = "http://sprite-service.local" ]
}
