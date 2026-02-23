#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"

  PROMOTION_CI_STUB="$TEMP_DIR/promotion-ci-stub.sh"
  PROMOTION_APPLY_STUB="$TEMP_DIR/promotion-apply-stub.sh"
  APPLY_LOG="$TEMP_DIR/apply-log.jsonl"

  cat > "$PROMOTION_CI_STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

repo=""
result_file=""
summary_file=""
fail_on_hold="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --result-file)
      result_file="${2:-}"
      shift 2
      ;;
    --summary-file)
      summary_file="${2:-}"
      shift 2
      ;;
    --fail-on-hold)
      fail_on_hold="1"
      shift
      ;;
    --skip-on-missing-evidence)
      shift
      ;;
    --fleet-status-file|--handoff-telemetry-file|--drill-state-file|--window-executions|--min-sample-size|--max-ambiguity-rate|--max-failure-rate|--max-manual-backlog|--max-drill-age-hours|--trace-id)
      shift 2
      ;;
    --pretty)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$repo" ]]
[[ -n "$result_file" ]]
[[ -n "$summary_file" ]]

mkdir -p "$(dirname "$result_file")"
mkdir -p "$(dirname "$summary_file")"

decision="${PROMOTION_STUB_DECISION:-promote}"

cat > "$result_file" <<JSON
{"schemaVersion":"v1","summary":{"decision":"$decision","failedGates":[],"reasonCodes":[]}}
JSON

echo "stub summary decision=$decision" > "$summary_file"

echo "{\"summary\":{\"decision\":\"$decision\"}}"

if [[ "$fail_on_hold" == "1" && "$decision" == "hold" ]]; then
  exit 2
fi

exit 0
STUB
  chmod +x "$PROMOTION_CI_STUB"

  cat > "$PROMOTION_APPLY_STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

intent=""
promotion_state_file=""
expand_step=""
idempotency_key=""
trace_id=""
actor=""
approval_ref=""
rationale=""
review_by=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --intent)
      intent="${2:-}"
      shift 2
      ;;
    --promotion-state-file)
      promotion_state_file="${2:-}"
      shift 2
      ;;
    --expand-step)
      expand_step="${2:-}"
      shift 2
      ;;
    --idempotency-key)
      idempotency_key="${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="${2:-}"
      shift 2
      ;;
    --by)
      actor="${2:-}"
      shift 2
      ;;
    --approval-ref)
      approval_ref="${2:-}"
      shift 2
      ;;
    --rationale)
      rationale="${2:-}"
      shift 2
      ;;
    --review-by)
      review_by="${2:-}"
      shift 2
      ;;
    --repo)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$intent" ]]
[[ -n "$promotion_state_file" ]]

decision="$(jq -r '.summary.decision // "unknown"' "$promotion_state_file")"
if [[ "$intent" != "rollback" && "$decision" != "promote" ]]; then
  echo "intent $intent requires promotion decision promote (found: $decision)" >&2
  exit 7
fi

if [[ -n "${APPLY_STUB_LOG:-}" ]]; then
  jq -cn --arg intent "$intent" --arg decision "$decision" --arg expand_step "$expand_step" --arg idempotency_key "$idempotency_key" --arg trace_id "$trace_id" --arg promotion_state_file "$promotion_state_file" --arg actor "$actor" --arg approval_ref "$approval_ref" --arg rationale "$rationale" --arg review_by "$review_by" '{intent:$intent,decision:$decision,expandStep:$expand_step,idempotencyKey:$idempotency_key,traceId:$trace_id,promotionStateFile:$promotion_state_file,actor:$actor,approvalRef:$approval_ref,rationale:$rationale,reviewBy:$review_by}' >> "$APPLY_STUB_LOG"
fi

jq -cn --arg intent "$intent" --arg decision "$decision" '{schemaVersion:"v1",status:"applied",intent:$intent,promotionDecision:$decision}'
STUB
  chmod +x "$PROMOTION_APPLY_STUB"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

@test "orchestrate dry_run returns preview without executing apply" {
  local repo="$TEMP_DIR/repo-dry"
  local result_file="$TEMP_DIR/orchestrate-dry.json"
  local summary_file="$TEMP_DIR/orchestrate-dry.md"
  local ci_result_file="$TEMP_DIR/ci-dry.json"
  local ci_summary_file="$TEMP_DIR/ci-dry.md"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" OPS_MANAGER_PROMOTION_APPLY_SCRIPT="$PROMOTION_APPLY_STUB" APPLY_STUB_LOG="$APPLY_LOG" PROMOTION_STUB_DECISION="hold" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-orchestrate.sh" \
    --repo "$repo" \
    --mode dry_run \
    --promotion-ci-result-file "$ci_result_file" \
    --promotion-ci-summary-file "$ci_summary_file" \
    --result-file "$result_file" \
    --summary-file "$summary_file"

  [ "$status" -eq 0 ]

  run jq -r '.mode' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "dry_run" ]

  run jq -r '.status' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "preview" ]

  run jq -r '.decision' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "hold" ]

  run jq -r '.apply.executed' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  [ ! -f "$APPLY_LOG" ]
}

@test "orchestrate apply executes apply intent and forwards idempotency and trace" {
  local repo="$TEMP_DIR/repo-apply"
  local result_file="$TEMP_DIR/orchestrate-apply.json"
  local summary_file="$TEMP_DIR/orchestrate-apply.md"
  local ci_result_file="$TEMP_DIR/ci-apply.json"
  local ci_summary_file="$TEMP_DIR/ci-apply.md"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" OPS_MANAGER_PROMOTION_APPLY_SCRIPT="$PROMOTION_APPLY_STUB" APPLY_STUB_LOG="$APPLY_LOG" PROMOTION_STUB_DECISION="promote" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-orchestrate.sh" \
    --repo "$repo" \
    --mode apply \
    --apply-intent expand \
    --expand-step 30 \
    --idempotency-key idmp-01 \
    --trace-id trace-01 \
    --by ops-user \
    --approval-ref CAB-201 \
    --rationale "phase11p2-apply" \
    --review-by "2099-01-01T00:00:00Z" \
    --promotion-ci-result-file "$ci_result_file" \
    --promotion-ci-summary-file "$ci_summary_file" \
    --result-file "$result_file" \
    --summary-file "$summary_file"

  [ "$status" -eq 0 ]

  run jq -r '.status' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "applied" ]

  run jq -r '.apply.executed' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.apply.intent' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "expand" ]

  run bash -lc "wc -l < '$APPLY_LOG'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.expandStep' "$APPLY_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "30" ]

  run jq -r '.idempotencyKey' "$APPLY_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "idmp-01" ]

  run jq -r '.traceId' "$APPLY_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-01" ]
}

@test "orchestrate apply propagates decision gating failure when decision is hold" {
  local repo="$TEMP_DIR/repo-apply-hold"
  local result_file="$TEMP_DIR/orchestrate-apply-hold.json"
  local summary_file="$TEMP_DIR/orchestrate-apply-hold.md"
  local ci_result_file="$TEMP_DIR/ci-apply-hold.json"
  local ci_summary_file="$TEMP_DIR/ci-apply-hold.md"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" OPS_MANAGER_PROMOTION_APPLY_SCRIPT="$PROMOTION_APPLY_STUB" APPLY_STUB_LOG="$APPLY_LOG" PROMOTION_STUB_DECISION="hold" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-orchestrate.sh" \
    --repo "$repo" \
    --mode apply \
    --apply-intent resume \
    --by ops-user \
    --approval-ref CAB-202 \
    --rationale "phase11p2-apply-hold" \
    --review-by "2099-01-01T00:00:00Z" \
    --promotion-ci-result-file "$ci_result_file" \
    --promotion-ci-summary-file "$ci_summary_file" \
    --result-file "$result_file" \
    --summary-file "$summary_file"

  [ "$status" -ne 0 ]
  [[ "$output" == *"requires promotion decision promote"* ]]
}

@test "orchestrate rollback executes rollback intent on hold decision" {
  local repo="$TEMP_DIR/repo-rollback"
  local result_file="$TEMP_DIR/orchestrate-rollback.json"
  local summary_file="$TEMP_DIR/orchestrate-rollback.md"
  local ci_result_file="$TEMP_DIR/ci-rollback.json"
  local ci_summary_file="$TEMP_DIR/ci-rollback.md"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" OPS_MANAGER_PROMOTION_APPLY_SCRIPT="$PROMOTION_APPLY_STUB" APPLY_STUB_LOG="$APPLY_LOG" PROMOTION_STUB_DECISION="hold" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-orchestrate.sh" \
    --repo "$repo" \
    --mode rollback \
    --by ops-user \
    --approval-ref CAB-203 \
    --rationale "phase11p2-rollback" \
    --review-by "2099-01-01T00:00:00Z" \
    --promotion-ci-result-file "$ci_result_file" \
    --promotion-ci-summary-file "$ci_summary_file" \
    --result-file "$result_file" \
    --summary-file "$summary_file"

  [ "$status" -eq 0 ]

  run jq -r '.status' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "rolled_back" ]

  run jq -r '.apply.intent' "$result_file"
  [ "$status" -eq 0 ]
  [ "$output" = "rollback" ]

  run jq -r '.intent' "$APPLY_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "rollback" ]
}

@test "orchestrate requires governance metadata for apply and rollback modes" {
  local repo="$TEMP_DIR/repo-governance"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" OPS_MANAGER_PROMOTION_APPLY_SCRIPT="$PROMOTION_APPLY_STUB" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-orchestrate.sh" \
    --repo "$repo" \
    --mode apply

  [ "$status" -ne 0 ]
  [[ "$output" == *"--by is required for mode apply"* ]]
}
