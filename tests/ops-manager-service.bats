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

  mkdir -p "$repo/.superloop/loops/$loop_id"

  cat > "$repo/.superloop/state.json" <<JSON
{"active":true,"loop_index":0,"iteration":2,"current_loop_id":"$loop_id","updated_at":"2026-02-22T11:00:00Z"}
JSON

  cat > "$repo/.superloop/loops/$loop_id/run-summary.json" <<JSON
{"version":1,"loop_id":"$loop_id","updated_at":"2026-02-22T11:00:00Z","entries":[{"run_id":"run-123","iteration":1,"gates":{"tests":"ok","validation":"ok","prerequisites":"ok","checklist":"ok","evidence":"skipped","approval":"none"},"stuck":{"streak":0,"threshold":3},"completion_ok":false,"ended_at":"2026-02-22T10:59:59Z"}]}
JSON

  cat > "$repo/.superloop/loops/$loop_id/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T11:00:00Z","event":"loop_start","loop_id":"$loop_id","run_id":"run-123","iteration":1,"data":{"max_iterations":5}}
{"timestamp":"2026-02-22T11:00:05Z","event":"iteration_start","loop_id":"$loop_id","run_id":"run-123","iteration":2,"data":{"started_at":"2026-02-22T11:00:05Z"}}
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
note=""
reject="0"

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
    --note)
      note="$2"
      shift 2
      ;;
    --by)
      shift 2
      ;;
    --reject)
      reject="1"
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
{"active":false,"loop_index":0,"iteration":2,"current_loop_id":"$loop","updated_at":"2026-02-22T11:10:00Z"}
JSON
    cat >> "$repo/.superloop/loops/$loop/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T11:10:00Z","event":"loop_stop","loop_id":"$loop","run_id":"run-123","iteration":2,"data":{"reason":"manual_cancel"}}
JSONL
    echo "Cancelled loop state."
    ;;
  approve)
    if [[ "$reject" == "1" ]]; then
      cat > "$repo/.superloop/loops/$loop/approval.json" <<JSON
{"status":"rejected","loop_id":"$loop","run_id":"run-123","iteration":2,"decision":{"note":"$note"}}
JSON
      cat >> "$repo/.superloop/loops/$loop/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T11:11:00Z","event":"approval_rejected","loop_id":"$loop","run_id":"run-123","iteration":2,"data":{"note":"$note"}}
JSONL
      echo "Rejected approval."
    else
      cat > "$repo/.superloop/loops/$loop/approval.json" <<JSON
{"status":"approved","loop_id":"$loop","run_id":"run-123","iteration":2,"decision":{"note":"$note"}}
JSON
      cat > "$repo/.superloop/loops/$loop/run-summary.json" <<JSON
{"version":1,"loop_id":"$loop","updated_at":"2026-02-22T11:11:00Z","entries":[{"run_id":"run-123","iteration":2,"gates":{"tests":"ok","validation":"ok","prerequisites":"ok","checklist":"ok","evidence":"ok","approval":"approved"},"stuck":{"streak":0,"threshold":3},"completion_ok":true,"ended_at":"2026-02-22T11:11:00Z"}]}
JSON
      cat >> "$repo/.superloop/loops/$loop/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T11:11:00Z","event":"loop_complete","loop_id":"$loop","run_id":"run-123","iteration":2,"data":{}}
JSONL
      echo "Approved completion."
    fi
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

@test "sprite service rejects unauthorized snapshot requests" {
  write_runtime_artifacts "$TEMP_DIR" "demo-loop"
  start_service "$TEMP_DIR" "$SERVICE_TOKEN"

  run bash -lc "curl -s -o '$TEMP_DIR/noauth.json' -w '%{http_code}' '$SERVICE_URL/ops/snapshot?loopId=demo-loop'"
  [ "$status" -eq 0 ]
  [ "$output" = "401" ]

  run jq -r '.error.code' "$TEMP_DIR/noauth.json"
  [ "$status" -eq 0 ]
  [ "$output" = "unauthorized" ]
}

@test "sprite service snapshot and events return expected shapes" {
  write_runtime_artifacts "$TEMP_DIR" "demo-loop"
  write_runtime_heartbeat "$TEMP_DIR" "demo-loop" "2026-02-22T11:00:04Z"
  start_service "$TEMP_DIR" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-service-client.sh" \
    --method GET \
    --base-url "$SERVICE_URL" \
    --path "/ops/snapshot?loopId=demo-loop" \
    --trace-id "trace-service-snapshot-1" \
    --token "$SERVICE_TOKEN"
  [ "$status" -eq 0 ]
  local snapshot_response="$output"

  run jq -r '.envelopeType' <<<"$snapshot_response"
  [ "$status" -eq 0 ]
  [ "$output" = "loop_run_snapshot" ]

  run jq -r '.runtime.heartbeat.timestamp' <<<"$snapshot_response"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-02-22T11:00:04Z" ]

  run jq -r '.sequence.source' <<<"$snapshot_response"
  [ "$status" -eq 0 ]
  [ "$output" = "cursor_event_line_offset" ]

  run jq -r '.sequence.value' <<<"$snapshot_response"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.traceId' <<<"$snapshot_response"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-service-snapshot-1" ]

  run jq -r '.artifacts.heartbeat.exists' <<<"$snapshot_response"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run "$PROJECT_ROOT/scripts/ops-manager-service-client.sh" \
    --method GET \
    --base-url "$SERVICE_URL" \
    --path "/ops/events?loopId=demo-loop&cursor=0&maxEvents=2" \
    --trace-id "trace-service-events-1" \
    --token "$SERVICE_TOKEN"
  [ "$status" -eq 0 ]
  local events_response="$output"

  run jq -r '.ok' <<<"$events_response"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.events | length' <<<"$events_response"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.events[0].sequence.source' <<<"$events_response"
  [ "$status" -eq 0 ]
  [ "$output" = "cursor_event_line_offset" ]

  run jq -r '.events[0].sequence.value' <<<"$events_response"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.traceId' <<<"$events_response"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-service-events-1" ]

  run jq -r '.events[0].traceId' <<<"$events_response"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-service-events-1" ]
}

@test "reconcile supports sprite_service transport and updates local cursor/state" {
  write_runtime_artifacts "$TEMP_DIR" "demo-loop"
  start_service "$TEMP_DIR" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN"
  [ "$status" -eq 0 ]

  local cursor_file="$TEMP_DIR/.superloop/ops-manager/demo-loop/cursor.json"
  local state_file="$TEMP_DIR/.superloop/ops-manager/demo-loop/state.json"
  [ -f "$cursor_file" ]
  [ -f "$state_file" ]

  run jq -r '.eventLineOffset' "$cursor_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.transition.currentState' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "running" ]
}

@test "control supports sprite_service transport with idempotency" {
  write_runtime_artifacts "$TEMP_DIR" "demo-loop"
  local stub="$TEMP_DIR/stub-superloop.sh"
  write_stub_superloop "$stub"
  start_service "$TEMP_DIR" "$SERVICE_TOKEN" "$stub"

  run "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --intent cancel \
    --trace-id "trace-service-control-1" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --idempotency-key "idem-1"
  [ "$status" -eq 0 ]

  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]

  run "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --intent cancel \
    --trace-id "trace-service-control-1" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --idempotency-key "idem-1"
  [ "$status" -eq 0 ]

  local intents_file="$TEMP_DIR/.superloop/ops-manager/demo-loop/intents.jsonl"
  [ -f "$intents_file" ]

  run bash -lc "tail -n 1 '$intents_file' | jq -r '.commandOutput' | jq -r '.replayed'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -lc "jq -r 'has(\"idem-1\")' '$TEMP_DIR/.superloop/ops-manager/demo-loop/service-idempotency.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  local invocation_telemetry="$TEMP_DIR/.superloop/ops-manager/demo-loop/telemetry/control-invocations.jsonl"
  [ -f "$invocation_telemetry" ]

  run bash -lc "wc -l < '$invocation_telemetry' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.transport'"
  [ "$status" -eq 0 ]
  [ "$output" = "sprite_service" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.idempotencyKey'"
  [ "$status" -eq 0 ]
  [ "$output" = "idem-1" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.execution.replayed'"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-service-control-1" ]
}

@test "control fails closed with wrong sprite_service token" {
  write_runtime_artifacts "$TEMP_DIR" "demo-loop"
  local stub="$TEMP_DIR/stub-superloop.sh"
  write_stub_superloop "$stub"
  start_service "$TEMP_DIR" "$SERVICE_TOKEN" "$stub"

  run "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --intent cancel \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "wrong-token" \
    --idempotency-key "idem-bad"
  [ "$status" -ne 0 ]
  [[ "$output" == *"service request failed"* || "$output" == *"failed_command"* ]]
}

@test "reconcile failure reason surfaces remain parity across local and sprite_service transports" {
  local loop_id="demo-loop"
  local local_repo="$TEMP_DIR/reconcile-failure-local"
  local service_repo="$TEMP_DIR/reconcile-failure-service"
  mkdir -p "$local_repo" "$service_repo"
  start_service "$service_repo" "$SERVICE_TOKEN"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$local_repo" \
    --loop "$loop_id" \
    --trace-id "trace-service-failure-parity-1"
  [ "$status" -ne 0 ]
  local local_failure_json="$output"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$service_repo" \
    --loop "$loop_id" \
    --transport sprite_service \
    --service-base-url "$SERVICE_URL" \
    --service-token "$SERVICE_TOKEN" \
    --trace-id "trace-service-failure-parity-1"
  [ "$status" -ne 0 ]
  local service_failure_json="$output"

  run jq -r '.status' <<<"$local_failure_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  run jq -r '.status' <<<"$service_failure_json"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded" ]

  local local_reason_codes
  local service_reason_codes
  local_reason_codes="$(jq -c '.reasonCodes | sort' <<<"$local_failure_json")"
  service_reason_codes="$(jq -c '.reasonCodes | sort' <<<"$service_failure_json")"
  [ "$local_reason_codes" = "$service_reason_codes" ]

  run jq -e '.reasonCodes | index("transport_unreachable") != null' <<<"$local_failure_json"
  [ "$status" -eq 0 ]

  run jq -e '.reasonCodes | index("transport_unreachable") != null' <<<"$service_failure_json"
  [ "$status" -eq 0 ]

  run jq -r '.transport.failureCode' <<<"$local_failure_json"
  [ "$status" -eq 0 ]
  [ "$output" = "snapshot_unavailable" ]

  run jq -r '.transport.failureCode' <<<"$service_failure_json"
  [ "$status" -eq 0 ]
  [ "$output" = "service_request_failed" ]
}

@test "fleet handoff autonomous execution semantics remain parity across local and sprite_service transports" {
  local loop_id="loop-target"
  local local_repo="$TEMP_DIR/fleet-handoff-local"
  local service_repo="$TEMP_DIR/fleet-handoff-service"

  mkdir -p "$local_repo/.superloop/ops-manager/fleet/telemetry"
  mkdir -p "$service_repo/.superloop/ops-manager/fleet/telemetry"

  write_runtime_artifacts "$local_repo" "$loop_id"
  write_runtime_artifacts "$service_repo" "$loop_id"

  local local_stub="$TEMP_DIR/stub-superloop-local-autonomous.sh"
  local service_stub="$TEMP_DIR/stub-superloop-service-autonomous.sh"
  write_stub_superloop "$local_stub"
  write_stub_superloop "$service_stub"
  start_service "$service_repo" "$SERVICE_TOKEN" "$service_stub"

  cat > "$local_repo/.superloop/ops-manager/fleet/registry.v1.json" <<'JSON'
{"schemaVersion":"v1","fleetId":"fleet-handoff-autonomous-parity","loops":[{"loopId":"loop-target","transport":"local"}]}
JSON

  cat > "$service_repo/.superloop/ops-manager/fleet/registry.v1.json" <<JSON
{"schemaVersion":"v1","fleetId":"fleet-handoff-autonomous-parity","loops":[{"loopId":"loop-target","transport":"sprite_service","service":{"baseUrl":"$SERVICE_URL","tokenEnv":"OPS_MANAGER_TEST_SERVICE_TOKEN"}}]}
JSON

  cat > "$local_repo/.superloop/ops-manager/fleet/policy-state.json" <<'JSON'
{"schemaVersion":"v1","updatedAt":"2026-02-23T14:00:00Z","fleetId":"fleet-handoff-autonomous-parity","traceId":"trace-fleet-handoff-autonomous-parity-policy","mode":"guarded_auto","candidateCount":2,"unsuppressedCount":2,"suppressedCount":0,"autoEligibleCount":1,"manualOnlyCount":1,"candidates":[{"candidateId":"loop-target:reconcile_failed","loopId":"loop-target","category":"reconcile_failed","signal":"status_failed","severity":"critical","confidence":"high","rationale":"Loop reconcile failed in fleet fan-out","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":true,"manualOnly":false,"reasons":[]}},{"candidateId":"loop-target:health_critical","loopId":"loop-target","category":"health_critical","signal":"health_critical","severity":"critical","confidence":"high","rationale":"Loop health is critical","recommendedIntent":"cancel","suppressed":false,"autonomous":{"eligible":false,"manualOnly":true,"reasons":["category_not_allowlisted"]}}],"reasonCodes":["fleet_action_required","fleet_auto_candidates_eligible"]}
JSON

  cp "$local_repo/.superloop/ops-manager/fleet/policy-state.json" "$service_repo/.superloop/ops-manager/fleet/policy-state.json"

  run env SUPERLOOP_BIN="$local_stub" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$local_repo" \
    --trace-id "trace-fleet-handoff-autonomous-parity-1" \
    --autonomous-execute \
    --no-runtime-confirm
  [ "$status" -eq 0 ]
  local local_handoff_json="$output"

  run env OPS_MANAGER_TEST_SERVICE_TOKEN="$SERVICE_TOKEN" \
    "$PROJECT_ROOT/scripts/ops-manager-fleet-handoff.sh" \
    --repo "$service_repo" \
    --trace-id "trace-fleet-handoff-autonomous-parity-1" \
    --autonomous-execute \
    --no-runtime-confirm
  [ "$status" -eq 0 ]
  local service_handoff_json="$output"

  local local_projection
  local service_projection
  local_projection="$(jq -c '{summary: (.summary | {executedCount, ambiguousCount, failedCount, pendingConfirmationCount, autoEligibleIntentCount, manualOnlyIntentCount}), execution: (.execution | {mode, requestedIntentCount, executedCount, ambiguousCount, failedCount}), intents: ((.intents // []) | map({intentId, loopId, status, autonomousEligible: (.autonomous.eligible // false), manualOnly: (.autonomous.manualOnly // false), executionReason: (.execution.reasonCode // null)}) | sort_by(.intentId))}' <<<"$local_handoff_json")"
  service_projection="$(jq -c '{summary: (.summary | {executedCount, ambiguousCount, failedCount, pendingConfirmationCount, autoEligibleIntentCount, manualOnlyIntentCount}), execution: (.execution | {mode, requestedIntentCount, executedCount, ambiguousCount, failedCount}), intents: ((.intents // []) | map({intentId, loopId, status, autonomousEligible: (.autonomous.eligible // false), manualOnly: (.autonomous.manualOnly // false), executionReason: (.execution.reasonCode // null)}) | sort_by(.intentId))}' <<<"$service_handoff_json")"
  [ "$local_projection" = "$service_projection" ]

  run jq -r '.execution.mode' <<<"$service_handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "autonomous" ]

  run jq -r '.execution.results[] | select(.loopId == "loop-target") | .traceId' <<<"$service_handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-fleet-handoff-autonomous-parity-1" ]

  run jq -r '.execution.results[] | select(.loopId == "loop-target") | .reasonCode' <<<"$service_handoff_json"
  [ "$status" -eq 0 ]
  [ "$output" = "control_confirmed" ]
}
