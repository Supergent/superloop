#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

iso_hours_ago() {
  local hours="$1"

  python3 - "$hours" <<'PY'
import datetime
import sys

hours = int(sys.argv[1])
value = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
print(value.replace(microsecond=0).isoformat().replace("+00:00", "Z"))
PY
}

write_status_fixture() {
  local file="$1"
  local posture="$2"
  local blocks_autonomous="$3"
  local manual_backlog="$4"
  local autopause_active="$5"

  cat > "$file" <<JSON
{
  "schemaVersion": "v1",
  "autonomous": {
    "enabled": true,
    "governance": {
      "posture": "$posture",
      "blocksAutonomous": $blocks_autonomous,
      "reasonCodes": []
    },
    "outcomeRollup": {
      "manual_backlog": $manual_backlog
    },
    "rollout": {
      "autopause": {
        "active": $autopause_active
      }
    },
    "safetyGateDecisions": {
      "byPath": {
        "policyGated": {"blockedCount": 0, "byReason": {}},
        "rolloutGated": {"blockedCount": 0, "byReason": {}},
        "governanceGated": {"blockedCount": 0, "reasonCodes": []},
        "transportGated": {"blockedCount": 0, "byReason": {}}
      }
    }
  }
}
JSON
}

write_handoff_telemetry() {
  local file="$1"
  local runs="$2"
  local attempted="$3"
  local executed="$4"
  local ambiguous="$5"
  local failed="$6"

  : > "$file"
  for _ in $(seq 1 "$runs"); do
    printf '{"timestamp":"%s","category":"fleet_handoff_execute","execution":{"mode":"autonomous","requestedIntentCount":%s,"executedCount":%s,"ambiguousCount":%s,"failedCount":%s}}\n' \
      "$(now_iso)" "$attempted" "$executed" "$ambiguous" "$failed" >> "$file"
  done
}

write_drill_state() {
  local file="$1"
  local completed_at="$2"

  cat > "$file" <<JSON
{
  "schemaVersion": "v1",
  "updatedAt": "$(now_iso)",
  "drills": [
    {"id": "kill_switch", "status": "pass", "completedAt": "$completed_at"},
    {"id": "sprite_service_outage", "status": "pass", "completedAt": "$completed_at"},
    {"id": "ambiguous_retry_guard", "status": "pass", "completedAt": "$completed_at"}
  ]
}
JSON
}

@test "promotion CI skips with success when evidence is missing and skip mode is enabled" {
  local repo="$TEMP_DIR/repo-skip"
  local result_file="$TEMP_DIR/result-skip.json"
  local summary_file="$TEMP_DIR/summary-skip.md"

  mkdir -p "$repo"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-ci.sh" \
    --repo "$repo" \
    --skip-on-missing-evidence \
    --result-file "$result_file" \
    --summary-file "$summary_file"

  [ "$status" -eq 0 ]

  run jq -r '.summary.decision' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "skipped" ]

  run jq -e '.summary.reasonCodes | index("promotion_ci_missing_evidence") != null' "$result_file"
  [ "$status" -eq 0 ]

  run grep -q 'Decision: `skipped`' "$summary_file"
  [ "$status" -eq 0 ]
}

@test "promotion CI emits promote decision and markdown summary" {
  local repo="$TEMP_DIR/repo-promote"
  local status_file="$TEMP_DIR/status-promote.json"
  local handoff_file="$TEMP_DIR/handoff-promote.jsonl"
  local drill_file="$TEMP_DIR/drills-promote.json"
  local result_file="$TEMP_DIR/result-promote.json"
  local summary_file="$TEMP_DIR/summary-promote.md"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry" "$repo/.superloop/ops-manager/fleet/drills"

  write_status_fixture "$status_file" "active" "false" "1" "false"
  write_handoff_telemetry "$handoff_file" 20 1 1 0 0
  write_drill_state "$drill_file" "$(iso_hours_ago 1)"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-ci.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file" \
    --result-file "$result_file" \
    --summary-file "$summary_file"

  [ "$status" -eq 0 ]

  run jq -r '.summary.decision' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "promote" ]

  run grep -q 'Decision: `promote`' "$summary_file"
  [ "$status" -eq 0 ]
}

@test "promotion CI propagates hold exit code when fail-on-hold is enabled" {
  local repo="$TEMP_DIR/repo-hold"
  local status_file="$TEMP_DIR/status-hold.json"
  local handoff_file="$TEMP_DIR/handoff-hold.jsonl"
  local drill_file="$TEMP_DIR/drills-hold.json"
  local result_file="$TEMP_DIR/result-hold.json"
  local summary_file="$TEMP_DIR/summary-hold.md"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry" "$repo/.superloop/ops-manager/fleet/drills"

  write_status_fixture "$status_file" "active" "false" "99" "false"
  write_handoff_telemetry "$handoff_file" 20 1 1 0 0
  write_drill_state "$drill_file" "$(iso_hours_ago 1)"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-ci.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file" \
    --result-file "$result_file" \
    --summary-file "$summary_file" \
    --fail-on-hold

  [ "$status" -eq 2 ]

  run jq -r '.summary.decision' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "hold" ]

  run jq -e '.summary.reasonCodes | index("promotion_manual_backlog_exceeded") != null' "$result_file"
  [ "$status" -eq 0 ]

  run grep -q 'Decision: `hold`' "$summary_file"
  [ "$status" -eq 0 ]
}
