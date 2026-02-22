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

@test "threshold profile resolver lists expected profiles" {
  run "$PROJECT_ROOT/scripts/ops-manager-threshold-profile.sh" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"strict"* ]]
  [[ "$output" == *"balanced"* ]]
  [[ "$output" == *"relaxed"* ]]
}

@test "threshold profile resolver uses balanced catalog default" {
  run "$PROJECT_ROOT/scripts/ops-manager-threshold-profile.sh"
  [ "$status" -eq 0 ]
  local resolver_json="$output"

  run jq -r '.profile' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "balanced" ]

  run jq -r '.values.criticalTransportFailureStreak' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "threshold profile resolver fails on unknown profile" {
  run "$PROJECT_ROOT/scripts/ops-manager-threshold-profile.sh" --profile unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown threshold profile"* ]]
}

@test "reconcile applies strict threshold profile into health output" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --threshold-profile strict
  [ "$status" -eq 0 ]
  local state_json="$output"

  run jq -r '.health.thresholds.profile' <<<"$state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "strict" ]

  run jq -r '.health.thresholds.degradedIngestLagSeconds' <<<"$state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "120" ]
}

@test "reconcile explicit threshold flags override profile defaults" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --threshold-profile strict \
    --critical-ingest-lag-seconds 777
  [ "$status" -eq 0 ]
  local state_json="$output"

  run jq -r '.health.thresholds.profile' <<<"$state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "strict" ]

  run jq -r '.health.thresholds.criticalIngestLagSeconds' <<<"$state_json"
  [ "$status" -eq 0 ]
  [ "$output" = "777" ]
}

@test "telemetry summary recommends relaxed for high critical and failed rates" {
  local loop_id="demo-loop"
  local telemetry_dir="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry"
  mkdir -p "$telemetry_dir"

  cat > "$telemetry_dir/reconcile.jsonl" <<'JSONL'
{"timestamp":"2026-02-22T10:00:00Z","status":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":3}
{"timestamp":"2026-02-22T10:01:00Z","status":"failed","healthStatus":"critical","healthReasonCodes":["transport_unreachable"],"durationSeconds":4}
{"timestamp":"2026-02-22T10:02:00Z","status":"success","healthStatus":"degraded","healthReasonCodes":["ingest_stale"],"durationSeconds":2}
{"timestamp":"2026-02-22T10:03:00Z","status":"success","healthStatus":"healthy","healthReasonCodes":[],"durationSeconds":1}
JSONL

  run "$PROJECT_ROOT/scripts/ops-manager-telemetry-summary.sh" --repo "$TEMP_DIR" --loop "$loop_id" --window 50
  [ "$status" -eq 0 ]
  local summary_json="$output"

  run jq -r '.recommendedProfile' <<<"$summary_json"
  [ "$status" -eq 0 ]
  [ "$output" = "relaxed" ]
}

@test "telemetry summary recommends strict for stable healthy window" {
  local loop_id="demo-loop"
  local telemetry_dir="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry"
  mkdir -p "$telemetry_dir"

  for i in $(seq 1 40); do
    printf '{"timestamp":"2026-02-22T10:%02d:00Z","status":"success","healthStatus":"healthy","healthReasonCodes":[],"durationSeconds":1}\n' "$i" >> "$telemetry_dir/reconcile.jsonl"
  done

  run "$PROJECT_ROOT/scripts/ops-manager-telemetry-summary.sh" --repo "$TEMP_DIR" --loop "$loop_id" --window 40
  [ "$status" -eq 0 ]
  local summary_json="$output"

  run jq -r '.recommendedProfile' <<<"$summary_json"
  [ "$status" -eq 0 ]
  [ "$output" = "strict" ]

  run jq -r '.confidence' <<<"$summary_json"
  [ "$status" -eq 0 ]
  [ "$output" = "medium" ]
}

@test "status includes tuning guidance fields" {
  local loop_id="demo-loop"
  local now_ts
  now_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_runtime_artifacts "$TEMP_DIR" "$loop_id" "$now_ts"

  run "$PROJECT_ROOT/scripts/ops-manager-reconcile.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --threshold-profile balanced
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-status.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --summary-window 25
  [ "$status" -eq 0 ]
  local status_json="$output"

  run jq -r '.tuning.appliedProfile' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "balanced" ]

  run jq -r '.tuning.summaryWindow' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ "$output" = "25" ]

  run jq -r '.tuning.recommendedProfile' <<<"$status_json"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
