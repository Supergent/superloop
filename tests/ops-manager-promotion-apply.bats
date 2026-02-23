#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

write_registry_guarded_auto() {
  local repo="$1"
  local canary_percent="$2"
  local manual_pause="$3"

  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/registry.v1.json" <<JSON
{
  "schemaVersion": "v1",
  "fleetId": "fleet-phase11",
  "loops": [
    {"loopId": "loop-a", "transport": "local"},
    {"loopId": "loop-b", "transport": "local"}
  ],
  "policy": {
    "mode": "guarded_auto",
    "autonomous": {
      "governance": {
        "actor": "ops-initial",
        "approvalRef": "CAB-0",
        "rationale": "initial",
        "changedAt": "2026-02-23T00:00:00Z",
        "reviewBy": "2099-01-01T00:00:00Z"
      },
      "rollout": {
        "canaryPercent": $canary_percent,
        "pause": {
          "manual": $manual_pause
        }
      }
    }
  }
}
JSON
}

write_promotion_state() {
  local repo="$1"
  local decision="$2"

  mkdir -p "$repo/.superloop/ops-manager/fleet"

  cat > "$repo/.superloop/ops-manager/fleet/promotion-state.json" <<JSON
{
  "schemaVersion": "v1",
  "summary": {
    "decision": "$decision",
    "reasonCodes": []
  }
}
JSON
}

@test "promotion apply expand mutates canary and clears manual pause on promote decision" {
  local repo="$TEMP_DIR/repo-expand"
  write_registry_guarded_auto "$repo" 25 true
  write_promotion_state "$repo" promote

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-apply.sh" \
    --repo "$repo" \
    --intent expand \
    --expand-step 25 \
    --by ops-user \
    --approval-ref CAB-111 \
    --rationale "phase11-expand" \
    --review-by "2099-01-01T00:00:00Z"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.rollout.after.canaryPercent' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "50" ]

  run jq -r '.rollout.after.manualPause' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.traceId | type' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "string" ]

  run jq -r '.loopId == null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.horizonRef == null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r --arg ref "$repo/.superloop/ops-manager/fleet/promotion-state.json" '.evidenceRefs | index($ref) != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.policy.autonomous.rollout.canaryPercent' "$repo/.superloop/ops-manager/fleet/registry.v1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "50" ]

  run jq -r '.policy.autonomous.rollout.pause.manual' "$repo/.superloop/ops-manager/fleet/registry.v1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.policy.autonomous.governance.actor' "$repo/.superloop/ops-manager/fleet/registry.v1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "ops-user" ]

  [ -f "$repo/.superloop/ops-manager/fleet/promotion-apply-state.json" ]
  [ -f "$repo/.superloop/ops-manager/fleet/telemetry/promotion-apply.jsonl" ]

  run bash -lc "wc -l < '$repo/.superloop/ops-manager/fleet/telemetry/promotion-apply.jsonl'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "promotion apply accepts optional seam fields and records them" {
  local repo="$TEMP_DIR/repo-seam-fields"
  write_registry_guarded_auto "$repo" 15 false
  write_promotion_state "$repo" promote

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-apply.sh" \
    --repo "$repo" \
    --intent resume \
    --loop-id loop-a \
    --horizon-ref HZ-fleet-promo-v1 \
    --evidence-ref "artifact://promotion-window" \
    --evidence-ref "artifact://fleet-health" \
    --by ops-user \
    --approval-ref CAB-111A \
    --rationale "phase12-seam-fields" \
    --review-by "2099-01-01T00:00:00Z"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.loopId' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-a" ]

  run jq -r '.horizonRef' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "HZ-fleet-promo-v1" ]

  run jq -r '.evidenceRefs | index("artifact://promotion-window") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.evidenceRefs | index("artifact://fleet-health") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r --arg ref "$repo/.superloop/ops-manager/fleet/promotion-state.json" '.evidenceRefs | index($ref) != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "promotion apply expand fails when promotion decision is hold" {
  local repo="$TEMP_DIR/repo-expand-hold"
  write_registry_guarded_auto "$repo" 25 false
  write_promotion_state "$repo" hold

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-apply.sh" \
    --repo "$repo" \
    --intent expand \
    --expand-step 10 \
    --by ops-user \
    --approval-ref CAB-112 \
    --rationale "phase11-expand-hold" \
    --review-by "2099-01-01T00:00:00Z"

  [ "$status" -ne 0 ]
  [[ "$output" == *"intent expand requires promotion decision promote"* ]]
}

@test "promotion apply rollback is safety-allowed on hold decision and sets manual pause true" {
  local repo="$TEMP_DIR/repo-rollback"
  write_registry_guarded_auto "$repo" 70 false
  write_promotion_state "$repo" hold

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-apply.sh" \
    --repo "$repo" \
    --intent rollback \
    --by ops-user \
    --approval-ref CAB-113 \
    --rationale "phase11-rollback" \
    --review-by "2099-01-01T00:00:00Z"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.rollout.after.manualPause' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.rollout.after.canaryPercent' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "70" ]

  run jq -r '.policy.autonomous.rollout.pause.manual' "$repo/.superloop/ops-manager/fleet/registry.v1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "promotion apply requires governance mutation metadata" {
  local repo="$TEMP_DIR/repo-governance-required"
  write_registry_guarded_auto "$repo" 25 false
  write_promotion_state "$repo" promote

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-apply.sh" \
    --repo "$repo" \
    --intent resume \
    --approval-ref CAB-114 \
    --rationale "phase11-resume" \
    --review-by "2099-01-01T00:00:00Z"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--by is required"* ]]
}

@test "promotion apply idempotency replay does not re-mutate or append telemetry" {
  local repo="$TEMP_DIR/repo-idempotency"
  write_registry_guarded_auto "$repo" 40 true
  write_promotion_state "$repo" promote

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-apply.sh" \
    --repo "$repo" \
    --intent expand \
    --expand-step 20 \
    --idempotency-key replay-key-1 \
    --by ops-user \
    --approval-ref CAB-115 \
    --rationale "phase11-idempotent-expand" \
    --review-by "2099-01-01T00:00:00Z"

  [ "$status" -eq 0 ]

  run jq -r '.policy.autonomous.rollout.canaryPercent' "$repo/.superloop/ops-manager/fleet/registry.v1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "60" ]

  run "$PROJECT_ROOT/scripts/ops-manager-promotion-apply.sh" \
    --repo "$repo" \
    --intent expand \
    --expand-step 30 \
    --idempotency-key replay-key-1 \
    --by ops-user \
    --approval-ref CAB-116 \
    --rationale "phase11-idempotent-expand-retry" \
    --review-by "2099-01-01T00:00:00Z"

  [ "$status" -eq 0 ]

  run jq -r '.replayed' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.policy.autonomous.rollout.canaryPercent' "$repo/.superloop/ops-manager/fleet/registry.v1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "60" ]

  run bash -lc "wc -l < '$repo/.superloop/ops-manager/fleet/telemetry/promotion-apply.jsonl'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
