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
  local include_transport_path="$6"
  local governance_reason_codes="$7"

  cat > "$file" <<JSON
{
  "schemaVersion": "v1",
  "autonomous": {
    "enabled": true,
    "governance": {
      "posture": "$posture",
      "blocksAutonomous": $blocks_autonomous,
      "reasonCodes": $governance_reason_codes
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
        "governanceGated": {"blockedCount": 0, "reasonCodes": []}
      }
    }
  }
}
JSON

  if [[ "$include_transport_path" == "1" ]]; then
    tmp_file="$file.tmp"
    jq '.autonomous.safetyGateDecisions.byPath.transportGated = {"blockedCount": 0, "byReason": {}}' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
  fi
}

write_handoff_telemetry() {
  local file="$1"
  local runs="$2"
  local attempted="$3"
  local executed="$4"
  local ambiguous="$5"
  local failed="$6"

  : > "$file"
  for i in $(seq 1 "$runs"); do
    printf '{"timestamp":"%s","category":"fleet_handoff_execute","execution":{"mode":"autonomous","requestedIntentCount":%s,"executedCount":%s,"ambiguousCount":%s,"failedCount":%s}}\n' \
      "$(now_iso)" "$attempted" "$executed" "$ambiguous" "$failed" >> "$file"
  done
}

write_drill_state() {
  local file="$1"
  local completed_at="$2"
  local status_value="${3:-pass}"

  cat > "$file" <<JSON
{
  "schemaVersion": "v1",
  "updatedAt": "$(now_iso)",
  "drills": [
    {"id": "kill_switch", "status": "$status_value", "completedAt": "$completed_at"},
    {"id": "sprite_service_outage", "status": "$status_value", "completedAt": "$completed_at"},
    {"id": "ambiguous_retry_guard", "status": "$status_value", "completedAt": "$completed_at"}
  ]
}
JSON
}

@test "promotion gates promotes when all gates pass" {
  local repo="$TEMP_DIR/repo-pass"
  local status_file="$TEMP_DIR/status-pass.json"
  local handoff_file="$TEMP_DIR/handoff-pass.jsonl"
  local drill_file="$TEMP_DIR/drills-pass.json"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry" "$repo/.superloop/ops-manager/fleet/drills"

  write_status_fixture "$status_file" "active" "false" "2" "false" "1" '[]'
  write_handoff_telemetry "$handoff_file" 20 1 1 0 0
  write_drill_state "$drill_file" "$(iso_hours_ago 1)"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-gates.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.summary.decision' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "promote" ]

  local state_file="$repo/.superloop/ops-manager/fleet/promotion-state.json"
  local telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/promotion.jsonl"

  [ -f "$state_file" ]
  [ -f "$telemetry_file" ]

  run jq -r '.summary.gateFailCount' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run bash -lc "wc -l < '$telemetry_file'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "promotion gates holds when governance authority is missing" {
  local repo="$TEMP_DIR/repo-governance-hold"
  local status_file="$TEMP_DIR/status-governance-hold.json"
  local handoff_file="$TEMP_DIR/handoff-governance-hold.jsonl"
  local drill_file="$TEMP_DIR/drills-governance-hold.json"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry" "$repo/.superloop/ops-manager/fleet/drills"

  write_status_fixture "$status_file" "authority_missing" "true" "0" "false" "1" '["autonomous_governance_authority_missing"]'
  write_handoff_telemetry "$handoff_file" 20 1 1 0 0
  write_drill_state "$drill_file" "$(iso_hours_ago 1)"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-gates.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.summary.decision' <<<"$result_json"
  [ "$output" = "hold" ]

  run jq -e '.summary.failedGates | index("governance") != null' <<<"$result_json"
  [ "$status" -eq 0 ]

  run jq -e '.summary.reasonCodes | index("promotion_governance_authority_missing") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
}

@test "promotion gates holds when autonomous sample is below minimum" {
  local repo="$TEMP_DIR/repo-reliability-sample-hold"
  local status_file="$TEMP_DIR/status-reliability-sample-hold.json"
  local handoff_file="$TEMP_DIR/handoff-reliability-sample-hold.jsonl"
  local drill_file="$TEMP_DIR/drills-reliability-sample-hold.json"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry" "$repo/.superloop/ops-manager/fleet/drills"

  write_status_fixture "$status_file" "active" "false" "0" "false" "1" '[]'
  write_handoff_telemetry "$handoff_file" 3 1 1 0 0
  write_drill_state "$drill_file" "$(iso_hours_ago 1)"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-gates.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.summary.decision' <<<"$result_json"
  [ "$output" = "hold" ]

  run jq -e '.summary.failedGates | index("outcome_reliability") != null' <<<"$result_json"
  [ "$status" -eq 0 ]

  run jq -e '.summary.reasonCodes | index("promotion_autonomous_sample_insufficient") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
}

@test "promotion gates holds when autopause is active and suppression paths are incomplete" {
  local repo="$TEMP_DIR/repo-safety-hold"
  local status_file="$TEMP_DIR/status-safety-hold.json"
  local handoff_file="$TEMP_DIR/handoff-safety-hold.jsonl"
  local drill_file="$TEMP_DIR/drills-safety-hold.json"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry" "$repo/.superloop/ops-manager/fleet/drills"

  write_status_fixture "$status_file" "active" "false" "0" "true" "0" '[]'
  write_handoff_telemetry "$handoff_file" 20 1 1 0 0
  write_drill_state "$drill_file" "$(iso_hours_ago 1)"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-gates.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.summary.decision' <<<"$result_json"
  [ "$output" = "hold" ]

  run jq -e '.summary.failedGates | index("safety_suppression") != null' <<<"$result_json"
  [ "$status" -eq 0 ]

  run jq -e '.summary.reasonCodes | index("promotion_autopause_active") != null' <<<"$result_json"
  [ "$status" -eq 0 ]

  run jq -e '.summary.reasonCodes | index("promotion_suppression_paths_missing") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
}

@test "promotion gates fails closed to hold when drill state evidence is missing" {
  local repo="$TEMP_DIR/repo-drill-missing-hold"
  local status_file="$TEMP_DIR/status-drill-missing-hold.json"
  local handoff_file="$TEMP_DIR/handoff-drill-missing-hold.jsonl"
  local drill_file="$TEMP_DIR/drills-missing.json"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry"

  write_status_fixture "$status_file" "active" "false" "0" "false" "1" '[]'
  write_handoff_telemetry "$handoff_file" 20 1 1 0 0

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-gates.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.summary.decision' <<<"$result_json"
  [ "$output" = "hold" ]

  run jq -e '.summary.failedGates | index("drill_recency") != null' <<<"$result_json"
  [ "$status" -eq 0 ]

  run jq -e '.summary.reasonCodes | index("promotion_drill_state_missing") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
}

@test "promotion gates --fail-on-hold exits non-zero when decision is hold" {
  local repo="$TEMP_DIR/repo-fail-on-hold"
  local status_file="$TEMP_DIR/status-fail-on-hold.json"
  local handoff_file="$TEMP_DIR/handoff-fail-on-hold.jsonl"
  local drill_file="$TEMP_DIR/drills-fail-on-hold.json"

  mkdir -p "$repo/.superloop/ops-manager/fleet/telemetry" "$repo/.superloop/ops-manager/fleet/drills"

  write_status_fixture "$status_file" "active" "false" "10" "false" "1" '[]'
  write_handoff_telemetry "$handoff_file" 20 1 1 0 0
  write_drill_state "$drill_file" "$(iso_hours_ago 1)"

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-gates.sh" \
    --repo "$repo" \
    --fleet-status-file "$status_file" \
    --handoff-telemetry-file "$handoff_file" \
    --drill-state-file "$drill_file" \
    --fail-on-hold

  [ "$status" -eq 2 ]
  local result_json="$output"

  run jq -r '.summary.decision' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "hold" ]
}
