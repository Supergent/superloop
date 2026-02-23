#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"

  ORCHESTRATE_STUB="$TEMP_DIR/orchestrate-stub.sh"
  PROMOTION_CI_STUB="$TEMP_DIR/promotion-ci-stub.sh"
  ORCH_LOG="$TEMP_DIR/orchestrate-log.jsonl"

  cat > "$ORCHESTRATE_STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

mode=""
result_file=""
summary_file=""
promotion_ci_result_file=""
promotion_ci_summary_file=""
trace_id=""
loop_id=""
horizon_ref=""
apply_intent=""
expand_step=""
evidence_refs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      mode="${2:-}"
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
    --promotion-ci-result-file)
      promotion_ci_result_file="${2:-}"
      shift 2
      ;;
    --promotion-ci-summary-file)
      promotion_ci_summary_file="${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="${2:-}"
      shift 2
      ;;
    --loop-id)
      loop_id="${2:-}"
      shift 2
      ;;
    --horizon-ref)
      horizon_ref="${2:-}"
      shift 2
      ;;
    --evidence-ref)
      evidence_refs+=("${2:-}")
      shift 2
      ;;
    --apply-intent)
      apply_intent="${2:-}"
      shift 2
      ;;
    --expand-step)
      expand_step="${2:-}"
      shift 2
      ;;
    --repo|--fleet-status-file|--handoff-telemetry-file|--drill-state-file|--window-executions|--min-sample-size|--max-ambiguity-rate|--max-failure-rate|--max-manual-backlog|--max-drill-age-hours|--idempotency-key|--by|--approval-ref|--rationale|--review-by)
      shift 2
      ;;
    --skip-on-missing-evidence|--fail-on-hold|--pretty)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$mode" ]]
[[ -n "$result_file" ]]
[[ -n "$summary_file" ]]

mkdir -p "$(dirname "$result_file")"
mkdir -p "$(dirname "$summary_file")"

if [[ -n "$promotion_ci_result_file" ]]; then
  mkdir -p "$(dirname "$promotion_ci_result_file")"
fi
if [[ -n "$promotion_ci_summary_file" ]]; then
  mkdir -p "$(dirname "$promotion_ci_summary_file")"
fi

evidence_refs_json='[]'
if (( ${#evidence_refs[@]} > 0 )); then
  evidence_refs_json="$(printf '%s\n' "${evidence_refs[@]}" | jq -R . | jq -s .)"
fi

if [[ -n "${ORCHESTRATE_STUB_LOG:-}" ]]; then
  jq -cn \
    --arg mode "$mode" \
    --arg trace_id "$trace_id" \
    --arg loop_id "$loop_id" \
    --arg horizon_ref "$horizon_ref" \
    --arg apply_intent "$apply_intent" \
    --arg expand_step "$expand_step" \
    --argjson evidence_refs "$evidence_refs_json" \
    '{mode:$mode,traceId:$trace_id,loopId:$loop_id,horizonRef:$horizon_ref,applyIntent:$apply_intent,expandStep:$expand_step,evidenceRefs:$evidence_refs}' >> "$ORCHESTRATE_STUB_LOG"
fi

preview_decision="${PREVIEW_DECISION:-promote}"
preview_generated_at="${PREVIEW_GENERATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

if [[ "$mode" == "dry_run" ]]; then
  if [[ -n "$promotion_ci_result_file" ]]; then
    cat > "$promotion_ci_result_file" <<JSON
{"schemaVersion":"v1","generatedAt":"$preview_generated_at","summary":{"decision":"$preview_decision","failedGates":[],"reasonCodes":[]}}
JSON
  fi
  if [[ -n "$promotion_ci_summary_file" ]]; then
    echo "stub preview summary" > "$promotion_ci_summary_file"
  fi

  cat > "$result_file" <<JSON
{"schemaVersion":"v1","mode":"dry_run","status":"preview","decision":"$preview_decision","summary":{"failedGates":[],"reasonCodes":[]},"apply":{"executed":false},"context":{"traceId":$(jq -cn --arg v "$trace_id" '$v|if length>0 then . else null end'),"loopId":$(jq -cn --arg v "$loop_id" '$v|if length>0 then . else null end'),"horizonRef":$(jq -cn --arg v "$horizon_ref" '$v|if length>0 then . else null end'),"evidenceRefs":$evidence_refs_json}}
JSON
  echo "stub preview" > "$summary_file"
  jq -cn --arg decision "$preview_decision" '{decision:$decision,mode:"dry_run"}'
  exit 0
fi

if [[ "$mode" == "apply" ]]; then
  cat > "$result_file" <<JSON
{"schemaVersion":"v1","mode":"apply","status":"applied","decision":"$preview_decision","summary":{"failedGates":[],"reasonCodes":[]},"apply":{"executed":true,"intent":"${apply_intent:-expand}","record":{"status":"applied"}}}
JSON
  echo "stub apply" > "$summary_file"
  jq -cn '{mode:"apply",status:"applied"}'
  exit 0
fi

if [[ "$mode" == "rollback" ]]; then
  cat > "$result_file" <<JSON
{"schemaVersion":"v1","mode":"rollback","status":"rolled_back","decision":"$preview_decision","summary":{"failedGates":[],"reasonCodes":[]},"apply":{"executed":true,"intent":"rollback","record":{"status":"applied"}}}
JSON
  echo "stub rollback" > "$summary_file"
  jq -cn '{mode:"rollback",status:"rolled_back"}'
  exit 0
fi

echo "unsupported mode: $mode" >&2
exit 9
STUB
  chmod +x "$ORCHESTRATE_STUB"

  cat > "$PROMOTION_CI_STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

result_file=""
summary_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --result-file)
      result_file="${2:-}"
      shift 2
      ;;
    --summary-file)
      summary_file="${2:-}"
      shift 2
      ;;
    --repo|--fleet-status-file|--handoff-telemetry-file|--drill-state-file|--window-executions|--min-sample-size|--max-ambiguity-rate|--max-failure-rate|--max-manual-backlog|--max-drill-age-hours|--trace-id)
      shift 2
      ;;
    --skip-on-missing-evidence|--pretty)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$result_file" ]]
[[ -n "$summary_file" ]]
mkdir -p "$(dirname "$result_file")"
mkdir -p "$(dirname "$summary_file")"

verify_decision="${VERIFY_DECISION:-promote}"
verify_generated_at="${VERIFY_GENERATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

cat > "$result_file" <<JSON
{"schemaVersion":"v1","generatedAt":"$verify_generated_at","summary":{"decision":"$verify_decision","failedGates":[],"reasonCodes":[]}}
JSON

echo "verify decision=$verify_decision" > "$summary_file"

jq -cn --arg decision "$verify_decision" '{summary:{decision:$decision}}'
STUB
  chmod +x "$PROMOTION_CI_STUB"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

iso_minutes_ago() {
  local minutes="$1"

  python3 - "$minutes" <<'PY'
import datetime
import sys

minutes = int(sys.argv[1])
value = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=minutes)
print(value.replace(microsecond=0).isoformat().replace('+00:00', 'Z'))
PY
}

@test "controller propose_only emits proposed state and seam context fields" {
  local repo="$TEMP_DIR/repo-propose"
  local state_file="$TEMP_DIR/state-propose.json"
  local telemetry_file="$TEMP_DIR/telemetry-propose.jsonl"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_ORCHESTRATE_SCRIPT="$ORCHESTRATE_STUB" OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" ORCHESTRATE_STUB_LOG="$ORCH_LOG" PREVIEW_DECISION="promote" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-controller.sh" \
    --repo "$repo" \
    --mode propose_only \
    --trace-id trace-p12-01 \
    --loop-id loop-alpha \
    --horizon-ref h1 \
    --evidence-ref ev://alpha \
    --evidence-ref ev://beta \
    --state-file "$state_file" \
    --telemetry-file "$telemetry_file"

  [ "$status" -eq 0 ]

  run jq -r '.status' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "proposed" ]

  run jq -r '.execution.applyExecuted' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.context.loopId' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-alpha" ]

  run jq -r '.context.horizonRef' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "h1" ]

  run jq -r '.context.evidenceRefs | length' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.mode' "$ORCH_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "dry_run" ]

  run jq -r '.loopId' "$ORCH_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "loop-alpha" ]

  run jq -r '.horizonRef' "$ORCH_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "h1" ]

  run jq -r '.evidenceRefs | length' "$ORCH_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run bash -lc "wc -l < '$telemetry_file'"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "controller guarded_auto_apply denies when decision freshness is stale" {
  local repo="$TEMP_DIR/repo-stale"
  local state_file="$TEMP_DIR/state-stale.json"
  local telemetry_file="$TEMP_DIR/telemetry-stale.jsonl"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_ORCHESTRATE_SCRIPT="$ORCHESTRATE_STUB" OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" ORCHESTRATE_STUB_LOG="$ORCH_LOG" PREVIEW_DECISION="promote" PREVIEW_GENERATED_AT="$(iso_minutes_ago 180)" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-controller.sh" \
    --repo "$repo" \
    --mode guarded_auto_apply \
    --decision-ttl-minutes 30 \
    --by ops-user \
    --approval-ref CAB-1201 \
    --rationale "phase12-stale" \
    --review-by "2099-01-01T00:00:00Z" \
    --state-file "$state_file" \
    --telemetry-file "$telemetry_file"

  [ "$status" -eq 0 ]

  run jq -r '.status' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "hold" ]

  run jq -r '.execution.applyExecuted' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -e '.decision.reasonCodes | index("controller_decision_stale") != null' "$state_file"
  [ "$status" -eq 0 ]

  run jq -r '.context.horizonRef' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]

  run jq -s 'length' "$ORCH_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "controller guarded_auto_apply rolls back deterministically when verification fails" {
  local repo="$TEMP_DIR/repo-rollback"
  local state_file="$TEMP_DIR/state-rollback.json"
  local telemetry_file="$TEMP_DIR/telemetry-rollback.jsonl"

  mkdir -p "$repo"

  run env OPS_MANAGER_PROMOTION_ORCHESTRATE_SCRIPT="$ORCHESTRATE_STUB" OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" ORCHESTRATE_STUB_LOG="$ORCH_LOG" PREVIEW_DECISION="promote" VERIFY_DECISION="hold" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-controller.sh" \
    --repo "$repo" \
    --mode guarded_auto_apply \
    --by ops-user \
    --approval-ref CAB-1202 \
    --rationale "phase12-verify-fail" \
    --review-by "2099-01-01T00:00:00Z" \
    --state-file "$state_file" \
    --telemetry-file "$telemetry_file"

  [ "$status" -eq 0 ]

  run jq -r '.status' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "rolled_back" ]

  run jq -r '.execution.applyExecuted' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.execution.rollbackExecuted' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.verification.status' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "fail" ]

  run jq -e '.decision.reasonCodes | index("controller_verification_failed") != null' "$state_file"
  [ "$status" -eq 0 ]

  run jq -e '.decision.reasonCodes | index("controller_rollback_triggered") != null' "$state_file"
  [ "$status" -eq 0 ]

  run jq -r '.mode' "$ORCH_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = $'dry_run\napply\nrollback' ]
}

@test "controller guarded_auto_apply blocks on budget saturation and keeps seam nullability" {
  local repo="$TEMP_DIR/repo-budget"
  local state_file="$TEMP_DIR/state-budget.json"
  local telemetry_file="$TEMP_DIR/telemetry-budget.jsonl"

  mkdir -p "$repo"

  printf '{"timestamp":"%s","execution":{"action":"apply","expandStep":25}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$telemetry_file"

  run env OPS_MANAGER_PROMOTION_ORCHESTRATE_SCRIPT="$ORCHESTRATE_STUB" OPS_MANAGER_PROMOTION_CI_SCRIPT="$PROMOTION_CI_STUB" ORCHESTRATE_STUB_LOG="$ORCH_LOG" PREVIEW_DECISION="promote" \
    "$PROJECT_ROOT/scripts/ops-manager-promotion-controller.sh" \
    --repo "$repo" \
    --mode guarded_auto_apply \
    --max-applies-per-window 1 \
    --by ops-user \
    --approval-ref CAB-1203 \
    --rationale "phase12-budget" \
    --review-by "2099-01-01T00:00:00Z" \
    --state-file "$state_file" \
    --telemetry-file "$telemetry_file"

  [ "$status" -eq 0 ]

  run jq -r '.status' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "hold" ]

  run jq -e '.decision.reasonCodes | index("controller_budget_apply_count_exceeded") != null' "$state_file"
  [ "$status" -eq 0 ]

  run jq -r '.context.horizonRef' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]

  run jq -s 'length' "$ORCH_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
