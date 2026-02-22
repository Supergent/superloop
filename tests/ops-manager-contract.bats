#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
  LOOP_ID="demo-loop"

  mkdir -p "$TEMP_DIR/.superloop/loops/$LOOP_ID"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

write_base_runtime_artifacts() {
  local loop_dir="$TEMP_DIR/.superloop/loops/$LOOP_ID"

  mkdir -p "$TEMP_DIR/.superloop"

  cat > "$TEMP_DIR/.superloop/state.json" << 'JSON'
{"active":true,"loop_index":0,"iteration":2,"current_loop_id":"demo-loop","updated_at":"2026-02-22T04:00:00Z"}
JSON

  cat > "$TEMP_DIR/.superloop/active-run.json" << 'JSON'
{"repo":"/tmp/demo","pid":1200,"pgid":1200,"loop_id":"demo-loop","iteration":2,"stage":"loop_start","updated_at":"2026-02-22T04:00:00Z"}
JSON

  cat > "$loop_dir/run-summary.json" << 'JSON'
{
  "version": 1,
  "loop_id": "demo-loop",
  "updated_at": "2026-02-22T04:00:01Z",
  "entries": [
    {
      "run_id": "run-123",
      "iteration": 1,
      "gates": {
        "tests": "ok",
        "validation": "ok",
        "prerequisites": "ok",
        "checklist": "ok",
        "evidence": "skipped",
        "approval": "none"
      },
      "stuck": {
        "streak": 0,
        "threshold": 3
      },
      "completion_ok": false,
      "ended_at": "2026-02-22T04:00:01Z"
    }
  ]
}
JSON

  cat > "$loop_dir/events.jsonl" << 'JSONL'
{"timestamp":"2026-02-22T04:00:00Z","event":"loop_start","loop_id":"demo-loop","run_id":"run-123","iteration":1,"data":{"max_iterations":5}}
{"timestamp":"2026-02-22T04:00:05Z","event":"iteration_start","loop_id":"demo-loop","run_id":"run-123","iteration":2,"data":{"started_at":"2026-02-22T04:00:05Z"}}
{"timestamp":"2026-02-22T04:00:20Z","event":"role_end","loop_id":"demo-loop","run_id":"run-123","iteration":2,"role":"planner","status":"ok","data":{"duration_ms":1200}}
JSONL
}

@test "ops manager snapshot emits loop_run_snapshot envelope" {
  write_base_runtime_artifacts

  run "$PROJECT_ROOT/scripts/ops-manager-loop-run-snapshot.sh" --repo "$TEMP_DIR" --loop "$LOOP_ID"
  [ "$status" -eq 0 ]

  output_file="$TEMP_DIR/snapshot.json"
  printf '%s\n' "$output" > "$output_file"

  run jq -r '.schemaVersion' "$output_file"
  [ "$status" -eq 0 ]
  [ "$output" = "v1" ]

  run jq -r '.envelopeType' "$output_file"
  [ "$status" -eq 0 ]
  [ "$output" = "loop_run_snapshot" ]

  run jq -r '.source.loopId' "$output_file"
  [ "$status" -eq 0 ]
  [ "$output" = "$LOOP_ID" ]

  run jq -r '.run.runId' "$output_file"
  [ "$status" -eq 0 ]
  [ "$output" = "run-123" ]

  run jq -r '.cursor.eventLineOffset' "$output_file"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "ops manager snapshot fails closed when events artifact is missing" {
  mkdir -p "$TEMP_DIR/.superloop/loops/$LOOP_ID"
  cat > "$TEMP_DIR/.superloop/loops/$LOOP_ID/run-summary.json" << 'JSON'
{"version":1,"loop_id":"demo-loop","entries":[]}
JSON

  run "$PROJECT_ROOT/scripts/ops-manager-loop-run-snapshot.sh" --repo "$TEMP_DIR" --loop "$LOOP_ID"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "required artifact missing" ]]
}

@test "ops manager event poll emits cursor-safe loop_run_event envelopes" {
  write_base_runtime_artifacts

  cursor_file="$TEMP_DIR/cursor.json"

  run "$PROJECT_ROOT/scripts/ops-manager-poll-events.sh" --repo "$TEMP_DIR" --loop "$LOOP_ID" --cursor-file "$cursor_file"
  [ "$status" -eq 0 ]

  line_count=$(printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$line_count" = "3" ]

  printf '%s\n' "$output" > "$TEMP_DIR/events.ndjson"
  run jq -r 'select(.envelopeType == "loop_run_event") | .envelopeType' "$TEMP_DIR/events.ndjson"
  [ "$status" -eq 0 ]

  run jq -r '.eventLineOffset' "$cursor_file"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run "$PROJECT_ROOT/scripts/ops-manager-poll-events.sh" --repo "$TEMP_DIR" --loop "$LOOP_ID" --cursor-file "$cursor_file"
  [ "$status" -eq 0 ]
  line_count_second=$(printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$line_count_second" = "0" ]

  cat >> "$TEMP_DIR/.superloop/loops/$LOOP_ID/events.jsonl" << 'JSONL'
{"timestamp":"2026-02-22T04:00:30Z","event":"iteration_end","loop_id":"demo-loop","run_id":"run-123","iteration":2,"data":{"completed":true}}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-poll-events.sh" --repo "$TEMP_DIR" --loop "$LOOP_ID" --cursor-file "$cursor_file" --max-events 1
  [ "$status" -eq 0 ]
  line_count_third=$(printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$line_count_third" = "1" ]

  run jq -r '.eventLineOffset' "$cursor_file"
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "ops manager contract fixtures include required envelope fields" {
  run jq -e '
    .schemaVersion == "v1"
    and .envelopeType == "loop_run_snapshot"
    and (.source.repoPath | length) > 0
    and (.source.loopId | length) > 0
    and (.cursor.eventLineOffset >= 0)
    and (.health.eventCount >= 0)
  ' "$PROJECT_ROOT/tests/fixtures/ops-manager/snapshot.v1.json"
  [ "$status" -eq 0 ]

  run jq -e '
    .schemaVersion == "v1"
    and .envelopeType == "loop_run_event"
    and (.source.repoPath | length) > 0
    and (.source.loopId | length) > 0
    and (.event.name | length) > 0
    and (.run.iteration >= 0)
  ' "$PROJECT_ROOT/tests/fixtures/ops-manager/event.v1.json"
  [ "$status" -eq 0 ]
}
