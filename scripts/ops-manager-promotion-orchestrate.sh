#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-promotion-orchestrate.sh --repo <path> --mode <dry_run|apply|rollback> [options]

Options:
  --mode <dry_run|apply|rollback>  Orchestration mode.
  --apply-intent <expand|resume>   Apply intent when mode=apply (default: expand).
  --expand-step <n>                Expand step for apply intent=expand (default: 25).
  --repo <path>                    Repository path.

  --fleet-status-file <path>       Promotion CI input override.
  --handoff-telemetry-file <path>  Promotion CI input override.
  --drill-state-file <path>        Promotion CI input override.
  --window-executions <n>          Promotion CI threshold override.
  --min-sample-size <n>            Promotion CI threshold override.
  --max-ambiguity-rate <0..1>      Promotion CI threshold override.
  --max-failure-rate <0..1>        Promotion CI threshold override.
  --max-manual-backlog <n>         Promotion CI threshold override.
  --max-drill-age-hours <n>        Promotion CI threshold override.
  --skip-on-missing-evidence       Forwarded to promotion CI evaluator.
  --fail-on-hold                   Forwarded to promotion CI evaluator.

  --promotion-ci-result-file <path>  Promotion CI JSON result path.
  --promotion-ci-summary-file <path> Promotion CI markdown summary path.
  --result-file <path>               Orchestration JSON result path.
  --summary-file <path>              Orchestration markdown summary path.

  --idempotency-key <key>          Forwarded to promotion apply.
  --trace-id <id>                  Forwarded to promotion CI/apply.
  --loop-id <id>                   Optional loop identifier for seam tracking.
  --horizon-ref <id>               Optional horizon reference for seam tracking.
  --evidence-ref <ref>             Optional evidence reference. May be repeated.
  --by <actor>                     Governance actor for apply/rollback.
  --approval-ref <id>              Governance approval reference for apply/rollback.
  --rationale <text>               Governance rationale for apply/rollback.
  --review-by <iso8601>            Governance review deadline for apply/rollback.

  --pretty                         Pretty-print JSON output.
  --help                           Show this help message.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "missing required command: $cmd"
  fi
}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

repo=""
mode=""
apply_intent="expand"
expand_step="25"

fleet_status_file=""
handoff_telemetry_file=""
drill_state_file=""
window_executions=""
min_sample_size=""
max_ambiguity_rate=""
max_failure_rate=""
max_manual_backlog=""
max_drill_age_hours=""
skip_on_missing_evidence="0"
fail_on_hold="0"

promotion_ci_result_file=""
promotion_ci_summary_file=""
result_file=""
summary_file=""

idempotency_key=""
trace_id=""
loop_id=""
horizon_ref=""
evidence_refs=()
actor=""
approval_ref=""
rationale=""
review_by=""
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      mode="${2:-}"
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
    --repo)
      repo="${2:-}"
      shift 2
      ;;

    --fleet-status-file)
      fleet_status_file="${2:-}"
      shift 2
      ;;
    --handoff-telemetry-file)
      handoff_telemetry_file="${2:-}"
      shift 2
      ;;
    --drill-state-file)
      drill_state_file="${2:-}"
      shift 2
      ;;
    --window-executions)
      window_executions="${2:-}"
      shift 2
      ;;
    --min-sample-size)
      min_sample_size="${2:-}"
      shift 2
      ;;
    --max-ambiguity-rate)
      max_ambiguity_rate="${2:-}"
      shift 2
      ;;
    --max-failure-rate)
      max_failure_rate="${2:-}"
      shift 2
      ;;
    --max-manual-backlog)
      max_manual_backlog="${2:-}"
      shift 2
      ;;
    --max-drill-age-hours)
      max_drill_age_hours="${2:-}"
      shift 2
      ;;
    --skip-on-missing-evidence)
      skip_on_missing_evidence="1"
      shift
      ;;
    --fail-on-hold)
      fail_on_hold="1"
      shift
      ;;

    --promotion-ci-result-file)
      promotion_ci_result_file="${2:-}"
      shift 2
      ;;
    --promotion-ci-summary-file)
      promotion_ci_summary_file="${2:-}"
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

    --idempotency-key)
      idempotency_key="${2:-}"
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

    --pretty)
      pretty="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

need_cmd jq

if [[ -z "$repo" ]]; then
  die "--repo is required"
fi
if [[ "$mode" != "dry_run" && "$mode" != "apply" && "$mode" != "rollback" ]]; then
  die "--mode must be one of dry_run, apply, rollback"
fi
if [[ "$apply_intent" != "expand" && "$apply_intent" != "resume" ]]; then
  die "--apply-intent must be one of expand, resume"
fi
if ! [[ "$expand_step" =~ ^[0-9]+$ ]] || (( expand_step < 1 )) || (( expand_step > 100 )); then
  die "--expand-step must be an integer between 1 and 100"
fi

if [[ "$mode" == "apply" || "$mode" == "rollback" ]]; then
  [[ -n "$actor" ]] || die "--by is required for mode $mode"
  [[ -n "$approval_ref" ]] || die "--approval-ref is required for mode $mode"
  [[ -n "$rationale" ]] || die "--rationale is required for mode $mode"
  [[ -n "$review_by" ]] || die "--review-by is required for mode $mode"
fi

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
promotion_ci_script="${OPS_MANAGER_PROMOTION_CI_SCRIPT:-$script_dir/ops-manager-promotion-ci.sh}"
promotion_apply_script="${OPS_MANAGER_PROMOTION_APPLY_SCRIPT:-$script_dir/ops-manager-promotion-apply.sh}"

if [[ -z "$promotion_ci_result_file" ]]; then
  promotion_ci_result_file="$repo/.superloop/ops-manager/fleet/promotion-ci-result.json"
fi
if [[ -z "$promotion_ci_summary_file" ]]; then
  promotion_ci_summary_file="$repo/.superloop/ops-manager/fleet/promotion-ci-summary.md"
fi
if [[ -z "$result_file" ]]; then
  result_file="$repo/.superloop/ops-manager/fleet/promotion-orchestrate-result.json"
fi
if [[ -z "$summary_file" ]]; then
  summary_file="$repo/.superloop/ops-manager/fleet/promotion-orchestrate-summary.md"
fi

custom_evidence_refs_json='[]'
if [[ ${#evidence_refs[@]} -gt 0 ]]; then
  custom_evidence_refs_json="$(printf '%s\n' "${evidence_refs[@]}" | jq -Rsc 'split("\n")[:-1] | map(select(length > 0))')"
fi

mkdir -p "$(dirname "$result_file")"
mkdir -p "$(dirname "$summary_file")"

ci_cmd=("$promotion_ci_script" --repo "$repo" --result-file "$promotion_ci_result_file" --summary-file "$promotion_ci_summary_file")
if [[ -n "$fleet_status_file" ]]; then
  ci_cmd+=(--fleet-status-file "$fleet_status_file")
fi
if [[ -n "$handoff_telemetry_file" ]]; then
  ci_cmd+=(--handoff-telemetry-file "$handoff_telemetry_file")
fi
if [[ -n "$drill_state_file" ]]; then
  ci_cmd+=(--drill-state-file "$drill_state_file")
fi
if [[ -n "$window_executions" ]]; then
  ci_cmd+=(--window-executions "$window_executions")
fi
if [[ -n "$min_sample_size" ]]; then
  ci_cmd+=(--min-sample-size "$min_sample_size")
fi
if [[ -n "$max_ambiguity_rate" ]]; then
  ci_cmd+=(--max-ambiguity-rate "$max_ambiguity_rate")
fi
if [[ -n "$max_failure_rate" ]]; then
  ci_cmd+=(--max-failure-rate "$max_failure_rate")
fi
if [[ -n "$max_manual_backlog" ]]; then
  ci_cmd+=(--max-manual-backlog "$max_manual_backlog")
fi
if [[ -n "$max_drill_age_hours" ]]; then
  ci_cmd+=(--max-drill-age-hours "$max_drill_age_hours")
fi
if [[ "$skip_on_missing_evidence" == "1" ]]; then
  ci_cmd+=(--skip-on-missing-evidence)
fi
if [[ "$fail_on_hold" == "1" ]]; then
  ci_cmd+=(--fail-on-hold)
fi
if [[ -n "$trace_id" ]]; then
  ci_cmd+=(--trace-id "$trace_id")
fi

set +e
ci_output="$(${ci_cmd[@]} 2>&1)"
ci_status=$?
set -e

if [[ "$ci_status" -ne 0 ]]; then
  printf '%s\n' "$ci_output" >&2
  exit "$ci_status"
fi

[[ -f "$promotion_ci_result_file" ]] || die "promotion CI result file not found: $promotion_ci_result_file"
ci_result_json="$(jq -c '.' "$promotion_ci_result_file" 2>/dev/null)" || die "invalid promotion CI result JSON: $promotion_ci_result_file"

decision="$(jq -r '.summary.decision // "unknown"' <<<"$ci_result_json")"
failed_gates_csv="$(jq -r '(.summary.failedGates // []) | join(", ")' <<<"$ci_result_json")"
reason_codes_csv="$(jq -r '(.summary.reasonCodes // []) | join(", ")' <<<"$ci_result_json")"

action_status="preview"
apply_executed="false"
apply_intent_effective="null"
apply_record_json="null"

if [[ "$mode" == "apply" || "$mode" == "rollback" ]]; then
  apply_cmd=("$promotion_apply_script" --repo "$repo" --promotion-state-file "$promotion_ci_result_file" --intent "$([ "$mode" = "apply" ] && printf '%s' "$apply_intent" || printf 'rollback')" --by "$actor" --approval-ref "$approval_ref" --rationale "$rationale" --review-by "$review_by")
  if [[ "$mode" == "apply" && "$apply_intent" == "expand" ]]; then
    apply_cmd+=(--expand-step "$expand_step")
  fi
  if [[ -n "$idempotency_key" ]]; then
    apply_cmd+=(--idempotency-key "$idempotency_key")
  fi
  if [[ -n "$trace_id" ]]; then
    apply_cmd+=(--trace-id "$trace_id")
  fi
  if [[ -n "$loop_id" ]]; then
    apply_cmd+=(--loop-id "$loop_id")
  fi
  if [[ -n "$horizon_ref" ]]; then
    apply_cmd+=(--horizon-ref "$horizon_ref")
  fi
  if [[ ${#evidence_refs[@]} -gt 0 ]]; then
    for evidence_ref in "${evidence_refs[@]}"; do
      apply_cmd+=(--evidence-ref "$evidence_ref")
    done
  fi

  set +e
  apply_output="$(${apply_cmd[@]} 2>&1)"
  apply_status=$?
  set -e
  if [[ "$apply_status" -ne 0 ]]; then
    printf '%s\n' "$apply_output" >&2
    exit "$apply_status"
  fi

  apply_record_json="$(jq -c '.' <<<"$apply_output" 2>/dev/null)" || die "promotion apply output was not valid JSON"
  apply_executed="true"
  apply_intent_effective="$(jq -r '.intent // empty' <<<"$apply_record_json")"
  if [[ "$mode" == "rollback" ]]; then
    action_status="rolled_back"
  else
    action_status="applied"
  fi
fi

orchestrate_trace_id="$trace_id"
if [[ -z "$orchestrate_trace_id" ]]; then
  orchestrate_trace_id="$(jq -r '.traceId // empty' <<<"$apply_record_json" 2>/dev/null || true)"
fi
orchestrate_loop_id="$loop_id"
if [[ -z "$orchestrate_loop_id" ]]; then
  orchestrate_loop_id="$(jq -r '.loopId // empty' <<<"$apply_record_json" 2>/dev/null || true)"
fi
orchestrate_horizon_ref="$horizon_ref"
if [[ -z "$orchestrate_horizon_ref" ]]; then
  orchestrate_horizon_ref="$(jq -r '.horizonRef // empty' <<<"$apply_record_json" 2>/dev/null || true)"
fi
orchestrate_evidence_refs_json="$(jq -cn \
  --arg promotion_ci_result_file "$promotion_ci_result_file" \
  --arg promotion_ci_summary_file "$promotion_ci_summary_file" \
  --argjson custom_refs "$custom_evidence_refs_json" \
  --argjson apply_record "$apply_record_json" \
  '
  ($apply_record.evidenceRefs // []) as $apply_refs
  | ($apply_record.files // {}) as $files
  | (
      $custom_refs
      + [$promotion_ci_result_file, $promotion_ci_summary_file, ($files.promotionStateFile // null), ($files.applyStateFile // null)]
      + $apply_refs
    )
  | map(select(type == "string" and length > 0))
  | unique
  ')"

orchestrate_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg timestamp "$(timestamp)" \
  --arg mode "$mode" \
  --arg status "$action_status" \
  --arg decision "$decision" \
  --arg trace_id "$orchestrate_trace_id" \
  --arg loop_id "$orchestrate_loop_id" \
  --arg horizon_ref "$orchestrate_horizon_ref" \
  --argjson evidence_refs "$orchestrate_evidence_refs_json" \
  --arg result_file "$result_file" \
  --arg summary_file "$summary_file" \
  --arg promotion_ci_result_file "$promotion_ci_result_file" \
  --arg promotion_ci_summary_file "$promotion_ci_summary_file" \
  --arg failed_gates_csv "$failed_gates_csv" \
  --arg reason_codes_csv "$reason_codes_csv" \
  --argjson ci_result "$ci_result_json" \
  --argjson apply_record "$apply_record_json" \
  --argjson apply_executed "$apply_executed" \
  --arg apply_intent_effective "$apply_intent_effective" \
  --arg idempotency_key "$idempotency_key" \
  '{
    schemaVersion: $schema_version,
    timestamp: $timestamp,
    mode: $mode,
    status: $status,
    decision: $decision,
    traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
    loopId: (if ($loop_id | length) > 0 then $loop_id else null end),
    horizonRef: (if ($horizon_ref | length) > 0 then $horizon_ref else null end),
    evidenceRefs: $evidence_refs,
    summary: {
      failedGates: ($ci_result.summary.failedGates // []),
      reasonCodes: ($ci_result.summary.reasonCodes // [])
    },
    apply: {
      executed: $apply_executed,
      intent: (if $apply_intent_effective == "" or $apply_intent_effective == "null" then null else $apply_intent_effective end),
      idempotencyKey: (if ($idempotency_key | length) > 0 then $idempotency_key else null end),
      record: (if $apply_executed then $apply_record else null end)
    },
    files: {
      resultFile: $result_file,
      summaryFile: $summary_file,
      promotionCiResultFile: $promotion_ci_result_file,
      promotionCiSummaryFile: $promotion_ci_summary_file
    }
  }')

jq -c '.' <<<"$orchestrate_json" > "$result_file"

{
  echo "## Ops Manager Promotion Orchestration"
  echo
  echo "Mode: \`$mode\`"
  echo
  echo "Status: \`$action_status\`"
  echo
  echo "Promotion decision: \`$decision\`"
  echo
  echo "Failed gates: ${failed_gates_csv:-none}"
  echo
  echo "Reason codes: ${reason_codes_csv:-none}"
  if [[ "$apply_executed" == "true" ]]; then
    echo
    echo "Apply intent: \`$apply_intent_effective\`"
  fi
  echo
  echo "Result JSON: \`$result_file\`"
  echo
  echo "Promotion CI result: \`$promotion_ci_result_file\`"
} > "$summary_file"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$summary_file" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$orchestrate_json"
else
  jq -c '.' <<<"$orchestrate_json"
fi
