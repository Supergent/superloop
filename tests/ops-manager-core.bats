#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

write_runtime_artifacts() {
  local repo="$1"
  local loop_id="$2"

  mkdir -p "$repo/.superloop/loops/$loop_id"

  cat > "$repo/.superloop/state.json" <<JSON
{"active":true,"loop_index":0,"iteration":2,"current_loop_id":"$loop_id","updated_at":"2026-02-22T10:00:00Z"}
JSON

  cat > "$repo/.superloop/loops/$loop_id/run-summary.json" <<JSON
{"version":1,"loop_id":"$loop_id","updated_at":"2026-02-22T10:00:00Z","entries":[{"run_id":"run-123","iteration":1,"gates":{"tests":"ok","validation":"ok","prerequisites":"ok","checklist":"ok","evidence":"skipped","approval":"none"},"stuck":{"streak":0,"threshold":3},"completion_ok":false,"ended_at":"2026-02-22T09:59:59Z"}]}
JSON

  cat > "$repo/.superloop/loops/$loop_id/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T10:00:00Z","event":"loop_start","loop_id":"$loop_id","run_id":"run-123","iteration":1,"data":{"max_iterations":5}}
{"timestamp":"2026-02-22T10:00:05Z","event":"iteration_start","loop_id":"$loop_id","run_id":"run-123","iteration":2,"data":{"started_at":"2026-02-22T10:00:05Z"}}
JSONL
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
{"active":false,"loop_index":0,"iteration":2,"current_loop_id":"$loop","updated_at":"2026-02-22T10:10:00Z"}
JSON
    cat >> "$repo/.superloop/loops/$loop/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T10:10:00Z","event":"loop_stop","loop_id":"$loop","run_id":"run-123","iteration":2,"data":{"reason":"manual_cancel"}}
JSONL
    echo "Cancelled loop state."
    ;;
  approve)
    if [[ "$reject" == "1" ]]; then
      cat > "$repo/.superloop/loops/$loop/approval.json" <<JSON
{"status":"rejected","loop_id":"$loop","run_id":"run-123","iteration":2,"decision":{"note":"$note"}}
JSON
      cat >> "$repo/.superloop/loops/$loop/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T10:11:00Z","event":"approval_rejected","loop_id":"$loop","run_id":"run-123","iteration":2,"data":{"note":"$note"}}
JSONL
      echo "Rejected approval."
    else
      cat > "$repo/.superloop/loops/$loop/approval.json" <<JSON
{"status":"approved","loop_id":"$loop","run_id":"run-123","iteration":2,"decision":{"note":"$note"}}
JSON
      cat > "$repo/.superloop/loops/$loop/run-summary.json" <<JSON
{"version":1,"loop_id":"$loop","updated_at":"2026-02-22T10:11:00Z","entries":[{"run_id":"run-123","iteration":2,"gates":{"tests":"ok","validation":"ok","prerequisites":"ok","checklist":"ok","evidence":"ok","approval":"approved"},"stuck":{"streak":0,"threshold":3},"completion_ok":true,"ended_at":"2026-02-22T10:11:00Z"}]}
JSON
      cat >> "$repo/.superloop/loops/$loop/events.jsonl" <<JSONL
{"timestamp":"2026-02-22T10:11:00Z","event":"loop_complete","loop_id":"$loop","run_id":"run-123","iteration":2,"data":{}}
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

@test "ops manager project-state computes running lifecycle with event trigger" {
  local state_file="$TEMP_DIR/state.json"

  run "$PROJECT_ROOT/scripts/ops-manager-project-state.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --snapshot-file "$PROJECT_ROOT/tests/fixtures/ops-manager/core/snapshot-running.v1.json" \
    --events-file "$PROJECT_ROOT/tests/fixtures/ops-manager/core/events-running.ndjson" \
    --state-file "$state_file"
  [ "$status" -eq 0 ]

  run jq -r '.transition.currentState' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "running" ]

  run jq -r '.transition.triggeringSignal' "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" == event:* ]]

  run jq -r '.divergence.any' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "ops manager project-state flags approval-completion divergence" {
  local state_file="$TEMP_DIR/state-divergent.json"

  run "$PROJECT_ROOT/scripts/ops-manager-project-state.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --snapshot-file "$PROJECT_ROOT/tests/fixtures/ops-manager/core/snapshot-approval-completion-conflict.v1.json" \
    --state-file "$state_file"
  [ "$status" -eq 0 ]

  run jq -r '.divergence.flags.approvalCompletionConflict' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.divergence.any' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.transition.confidence' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "low" ]
}

@test "ops manager project-state flags cursor regression against prior state" {
  local state_file="$TEMP_DIR/cursor-regression-state.json"
  cat > "$state_file" <<'JSON'
{"cursor":{"eventLineOffset":99},"transition":{"currentState":"running"}}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-project-state.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --snapshot-file "$PROJECT_ROOT/tests/fixtures/ops-manager/core/snapshot-running.v1.json" \
    --state-file "$state_file"
  [ "$status" -eq 0 ]

  run jq -r '.divergence.flags.cursorRegression' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "ops manager reconcile updates cursor and state across polls" {
  local loop_id="demo-loop"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" --repo "$TEMP_DIR" --loop "$loop_id" --trace-id "trace-reconcile-1"
  [ "$status" -eq 0 ]

  run jq -r '.health.traceId' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-reconcile-1" ]

  local cursor_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/cursor.json"
  local state_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/state.json"
  [ -f "$cursor_file" ]
  [ -f "$state_file" ]

  run jq -r '.eventLineOffset' "$cursor_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  cat >> "$TEMP_DIR/.superloop/loops/$loop_id/events.jsonl" <<'JSONL'
{"timestamp":"2026-02-22T10:00:25Z","event":"role_end","loop_id":"demo-loop","run_id":"run-123","iteration":2,"role":"planner","status":"ok","data":{"duration_ms":1200}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" --repo "$TEMP_DIR" --loop "$loop_id" --max-events 1 --trace-id "trace-reconcile-2"
  [ "$status" -eq 0 ]

  run jq -r '.eventLineOffset' "$cursor_file"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  local reconcile_telemetry="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry/reconcile.jsonl"
  [ -f "$reconcile_telemetry" ]

  run bash -lc "tail -n 1 '$reconcile_telemetry' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-reconcile-2" ]
}

@test "ops manager reconcile emits escalation artifact on divergence" {
  local loop_id="demo-loop"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id"

  cat > "$TEMP_DIR/.superloop/state.json" <<JSON
{"active":false,"loop_index":0,"iteration":2,"current_loop_id":"$loop_id","updated_at":"2026-02-22T10:00:00Z"}
JSON

  cat >> "$TEMP_DIR/.superloop/loops/$loop_id/events.jsonl" <<'JSONL'
{"timestamp":"2026-02-22T10:00:15Z","event":"role_end","loop_id":"demo-loop","run_id":"run-123","iteration":2,"role":"planner","status":"ok","data":{"duration_ms":800}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" --repo "$TEMP_DIR" --loop "$loop_id"
  [ "$status" -eq 0 ]

  local escalations_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/escalations.jsonl"
  [ -f "$escalations_file" ]

  run bash -lc "jq -r 'select(.category == \"divergence_detected\") | .category' '$escalations_file' | wc -l | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "ops manager project-state fails closed on invalid event envelope" {
  local bad_events="$TEMP_DIR/bad-events.ndjson"
  local state_file="$TEMP_DIR/invalid-event-state.json"
  cat > "$bad_events" <<'EOF'
{"not":"a-valid-envelope"}
EOF

  run "$PROJECT_ROOT/scripts/ops-manager-project-state.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --snapshot-file "$PROJECT_ROOT/tests/fixtures/ops-manager/core/snapshot-running.v1.json" \
    --events-file "$bad_events" \
    --state-file "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"event envelope is invalid"* ]]
}

@test "ops manager control fails closed on unknown intent" {
  run "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$TEMP_DIR" \
    --loop demo-loop \
    --intent unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"intent must be one of"* ]]
}

@test "ops manager control cancel executes and confirms" {
  local loop_id="demo-loop"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id"
  local stub="$TEMP_DIR/stub-superloop.sh"
  write_stub_superloop "$stub"

  run env SUPERLOOP_BIN="$stub" "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --intent cancel \
    --trace-id "trace-control-local-1"
  [ "$status" -eq 0 ]

  local intents_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/intents.jsonl"
  [ -f "$intents_file" ]

  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]

  run bash -lc "tail -n 1 '$intents_file' | jq -r '.intent'"
  [ "$status" -eq 0 ]
  [ "$output" = "cancel" ]

  run bash -lc "tail -n 1 '$intents_file' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-control-local-1" ]

  local control_telemetry="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry/control.jsonl"
  local invocation_telemetry="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry/control-invocations.jsonl"
  [ -f "$control_telemetry" ]
  [ -f "$invocation_telemetry" ]

  run bash -lc "tail -n 1 '$control_telemetry' | jq -r '.status'"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]

  run bash -lc "tail -n 1 '$control_telemetry' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-control-local-1" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.execution.status'"
  [ "$status" -eq 0 ]
  [ "$output" = "succeeded" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.traceId'"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-control-local-1" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.confirmation.status'"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.outcome.status'"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]
}

@test "ops manager control approve executes and confirms completion" {
  local loop_id="demo-loop"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id"

  cat > "$TEMP_DIR/.superloop/loops/$loop_id/approval.json" <<'JSON'
{"status":"pending","loop_id":"demo-loop","run_id":"run-123","iteration":2}
JSON

  local stub="$TEMP_DIR/stub-superloop.sh"
  write_stub_superloop "$stub"

  run env SUPERLOOP_BIN="$stub" "$PROJECT_ROOT/scripts/ops-manager-control.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --intent approve \
    --by "ops-user" \
    --note "Looks good"
  [ "$status" -eq 0 ]

  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]

  run jq -r '.status' "$TEMP_DIR/.superloop/loops/$loop_id/approval.json"
  [ "$status" -eq 0 ]
  [ "$output" = "approved" ]

  local invocation_telemetry="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry/control-invocations.jsonl"
  [ -f "$invocation_telemetry" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.intent'"
  [ "$status" -eq 0 ]
  [ "$output" = "approve" ]

  run bash -lc "tail -n 1 '$invocation_telemetry' | jq -r '.confirmation.status'"
  [ "$status" -eq 0 ]
  [ "$output" = "confirmed" ]
}
