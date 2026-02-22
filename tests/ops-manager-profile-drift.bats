#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

@test "profile drift activates after required mismatch streak" {
  local loop_id="demo-loop"

  run "$PROJECT_ROOT/scripts/ops-manager-profile-drift.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --applied-profile balanced \
    --recommended-profile relaxed \
    --recommendation-confidence high \
    --required-streak 2 \
    --summary-window 40
  [ "$status" -eq 0 ]
  local first_json="$output"

  run jq -r '.status' <<<"$first_json"
  [ "$status" -eq 0 ]
  [ "$output" = "mismatch_pending" ]

  run jq -r '.mismatchStreak' <<<"$first_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.driftActive' <<<"$first_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run "$PROJECT_ROOT/scripts/ops-manager-profile-drift.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --applied-profile balanced \
    --recommended-profile relaxed \
    --recommendation-confidence high \
    --required-streak 2 \
    --summary-window 40
  [ "$status" -eq 0 ]
  local second_json="$output"

  run jq -r '.status' <<<"$second_json"
  [ "$status" -eq 0 ]
  [ "$output" = "drift_active" ]

  run jq -r '.driftActive' <<<"$second_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.transitioned.toActive' <<<"$second_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  local drift_state_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/profile-drift.json"
  local drift_history_file="$TEMP_DIR/.superloop/ops-manager/$loop_id/telemetry/profile-drift.jsonl"
  [ -f "$drift_state_file" ]
  [ -f "$drift_history_file" ]

  run jq -r '.status' "$drift_state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "drift_active" ]

  run bash -lc "wc -l < '$drift_history_file' | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "profile drift resolves when profiles realign" {
  local loop_id="demo-loop"

  run "$PROJECT_ROOT/scripts/ops-manager-profile-drift.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --applied-profile balanced \
    --recommended-profile strict \
    --recommendation-confidence high \
    --required-streak 1
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/ops-manager-profile-drift.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --applied-profile balanced \
    --recommended-profile balanced \
    --recommendation-confidence high \
    --required-streak 1
  [ "$status" -eq 0 ]
  local resolved_json="$output"

  run jq -r '.status' <<<"$resolved_json"
  [ "$status" -eq 0 ]
  [ "$output" = "aligned" ]

  run jq -r '.driftActive' <<<"$resolved_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.mismatchStreak' <<<"$resolved_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.transitioned.toResolved' <<<"$resolved_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "profile drift mismatch is gated when confidence is below minimum" {
  local loop_id="demo-loop"

  run "$PROJECT_ROOT/scripts/ops-manager-profile-drift.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --applied-profile balanced \
    --recommended-profile strict \
    --recommendation-confidence low \
    --min-confidence high \
    --required-streak 1
  [ "$status" -eq 0 ]
  local drift_json="$output"

  run jq -r '.status' <<<"$drift_json"
  [ "$status" -eq 0 ]
  [ "$output" = "insufficient_confidence" ]

  run jq -r '.eligibleMismatch' <<<"$drift_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.mismatchStreak' <<<"$drift_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "profile drift fails closed on unknown threshold profile names" {
  local loop_id="demo-loop"

  run "$PROJECT_ROOT/scripts/ops-manager-profile-drift.sh" \
    --repo "$TEMP_DIR" \
    --loop "$loop_id" \
    --applied-profile unknown-profile \
    --recommended-profile balanced \
    --recommendation-confidence high
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown applied profile"* ]]
}
