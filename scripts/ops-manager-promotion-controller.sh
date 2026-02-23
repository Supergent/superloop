#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-promotion-controller.sh --repo <path> [options]

Options:
  --repo <path>                       Repository path.
  --mode <propose_only|guarded_auto_apply>
                                     Controller mode (default: propose_only).
  --apply-intent <expand|resume>      Apply intent used when guarded auto-apply executes (default: expand).
  --expand-step <n>                   Expand step for apply intent=expand (default: 25).

  --decision-ttl-minutes <n>          Maximum allowed age for promotion decision artifact (default: 60).
  --budget-window-hours <n>           Rolling budget window for apply/expand accounting (default: 24).
  --max-applies-per-window <n>        Maximum applies allowed in the budget window (default: 1).
  --max-expand-step-per-window <n>    Maximum cumulative expand step allowed in the budget window (default: 25).
  --cooldown-minutes <n>              Minimum minutes between apply/rollback mutations (default: 60).
  --freeze-windows-file <path>        Optional JSON freeze windows file; active freeze blocks auto-apply.

  --fleet-status-file <path>          Promotion evaluator input override.
  --handoff-telemetry-file <path>     Promotion evaluator input override.
  --drill-state-file <path>           Promotion evaluator input override.
  --window-executions <n>             Promotion evaluator threshold override.
  --min-sample-size <n>               Promotion evaluator threshold override.
  --max-ambiguity-rate <0..1>         Promotion evaluator threshold override.
  --max-failure-rate <0..1>           Promotion evaluator threshold override.
  --max-manual-backlog <n>            Promotion evaluator threshold override.
  --max-drill-age-hours <n>           Promotion evaluator threshold override.
  --skip-on-missing-evidence          Forwarded to evaluate/verify promotion CI.

  --promotion-ci-result-file <path>   Evaluate-stage promotion CI result output.
  --promotion-ci-summary-file <path>  Evaluate-stage promotion CI summary output.
  --verify-result-file <path>         Verify-stage promotion CI result output.
  --verify-summary-file <path>        Verify-stage promotion CI summary output.

  --preview-result-file <path>        Preview orchestration result output.
  --preview-summary-file <path>       Preview orchestration summary output.
  --apply-result-file <path>          Apply orchestration result output.
  --apply-summary-file <path>         Apply orchestration summary output.
  --rollback-result-file <path>       Rollback orchestration result output.
  --rollback-summary-file <path>      Rollback orchestration summary output.

  --state-file <path>                 Controller state JSON path.
  --telemetry-file <path>             Controller telemetry JSONL path.

  --idempotency-key <key>             Optional idempotency key forwarded to apply orchestration.
  --trace-id <id>                     Trace id used across controller and downstream scripts.
  --loop-id <id>                      Optional loop context id for additive seam metadata.
  --horizon-ref <id>                  Optional horizon reference for additive seam metadata.
  --evidence-ref <ref>                Optional evidence reference (repeatable).

  --by <actor>                        Governance actor identity (required for guarded_auto_apply).
  --approval-ref <id>                 Governance approval reference (required for guarded_auto_apply).
  --rationale <text>                  Governance rationale (required for guarded_auto_apply).
  --review-by <iso8601>               Governance review deadline (required for guarded_auto_apply).

  --pretty                            Pretty-print output JSON.
  --help                              Show this help message.
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

generate_trace_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
    return 0
  fi
  printf 'trace-%s-%s-%04d\n' "$(date -u +%Y%m%d%H%M%S)" "$$" "$RANDOM"
}

is_int_ge() {
  local value="$1"
  local min="$2"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min ))
}

append_eval_overrides() {
  local -n cmd_ref="$1"

  if [[ -n "$fleet_status_file" ]]; then
    cmd_ref+=(--fleet-status-file "$fleet_status_file")
  fi
  if [[ -n "$handoff_telemetry_file" ]]; then
    cmd_ref+=(--handoff-telemetry-file "$handoff_telemetry_file")
  fi
  if [[ -n "$drill_state_file" ]]; then
    cmd_ref+=(--drill-state-file "$drill_state_file")
  fi
  if [[ -n "$window_executions" ]]; then
    cmd_ref+=(--window-executions "$window_executions")
  fi
  if [[ -n "$min_sample_size" ]]; then
    cmd_ref+=(--min-sample-size "$min_sample_size")
  fi
  if [[ -n "$max_ambiguity_rate" ]]; then
    cmd_ref+=(--max-ambiguity-rate "$max_ambiguity_rate")
  fi
  if [[ -n "$max_failure_rate" ]]; then
    cmd_ref+=(--max-failure-rate "$max_failure_rate")
  fi
  if [[ -n "$max_manual_backlog" ]]; then
    cmd_ref+=(--max-manual-backlog "$max_manual_backlog")
  fi
  if [[ -n "$max_drill_age_hours" ]]; then
    cmd_ref+=(--max-drill-age-hours "$max_drill_age_hours")
  fi
  if [[ "$skip_on_missing_evidence" == "1" ]]; then
    cmd_ref+=(--skip-on-missing-evidence)
  fi
}

append_context_flags() {
  local -n cmd_ref="$1"

  if [[ -n "$trace_id" ]]; then
    cmd_ref+=(--trace-id "$trace_id")
  fi
  if [[ -n "$loop_id" ]]; then
    cmd_ref+=(--loop-id "$loop_id")
  fi
  if [[ -n "$horizon_ref" ]]; then
    cmd_ref+=(--horizon-ref "$horizon_ref")
  fi
  if (( ${#evidence_refs[@]} > 0 )); then
    local ref
    for ref in "${evidence_refs[@]}"; do
      cmd_ref+=(--evidence-ref "$ref")
    done
  fi
}

repo=""
controller_mode="propose_only"
apply_intent="expand"
expand_step="25"

decision_ttl_minutes="60"
budget_window_hours="24"
max_applies_per_window="1"
max_expand_step_per_window="25"
cooldown_minutes="60"
freeze_windows_file=""

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

promotion_ci_result_file=""
promotion_ci_summary_file=""
verify_result_file=""
verify_summary_file=""

preview_result_file=""
preview_summary_file=""
apply_result_file=""
apply_summary_file=""
rollback_result_file=""
rollback_summary_file=""

state_file=""
telemetry_file=""

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
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --mode)
      controller_mode="${2:-}"
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

    --decision-ttl-minutes)
      decision_ttl_minutes="${2:-}"
      shift 2
      ;;
    --budget-window-hours)
      budget_window_hours="${2:-}"
      shift 2
      ;;
    --max-applies-per-window)
      max_applies_per_window="${2:-}"
      shift 2
      ;;
    --max-expand-step-per-window)
      max_expand_step_per_window="${2:-}"
      shift 2
      ;;
    --cooldown-minutes)
      cooldown_minutes="${2:-}"
      shift 2
      ;;
    --freeze-windows-file)
      freeze_windows_file="${2:-}"
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

    --promotion-ci-result-file)
      promotion_ci_result_file="${2:-}"
      shift 2
      ;;
    --promotion-ci-summary-file)
      promotion_ci_summary_file="${2:-}"
      shift 2
      ;;
    --verify-result-file)
      verify_result_file="${2:-}"
      shift 2
      ;;
    --verify-summary-file)
      verify_summary_file="${2:-}"
      shift 2
      ;;

    --preview-result-file)
      preview_result_file="${2:-}"
      shift 2
      ;;
    --preview-summary-file)
      preview_summary_file="${2:-}"
      shift 2
      ;;
    --apply-result-file)
      apply_result_file="${2:-}"
      shift 2
      ;;
    --apply-summary-file)
      apply_summary_file="${2:-}"
      shift 2
      ;;
    --rollback-result-file)
      rollback_result_file="${2:-}"
      shift 2
      ;;
    --rollback-summary-file)
      rollback_summary_file="${2:-}"
      shift 2
      ;;

    --state-file)
      state_file="${2:-}"
      shift 2
      ;;
    --telemetry-file)
      telemetry_file="${2:-}"
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
if [[ "$controller_mode" != "propose_only" && "$controller_mode" != "guarded_auto_apply" ]]; then
  die "--mode must be one of propose_only, guarded_auto_apply"
fi
if [[ "$apply_intent" != "expand" && "$apply_intent" != "resume" ]]; then
  die "--apply-intent must be one of expand, resume"
fi
if ! [[ "$expand_step" =~ ^[0-9]+$ ]] || (( expand_step < 1 )) || (( expand_step > 100 )); then
  die "--expand-step must be an integer between 1 and 100"
fi
if ! is_int_ge "$decision_ttl_minutes" 1; then
  die "--decision-ttl-minutes must be an integer >= 1"
fi
if ! is_int_ge "$budget_window_hours" 1; then
  die "--budget-window-hours must be an integer >= 1"
fi
if ! is_int_ge "$max_applies_per_window" 0; then
  die "--max-applies-per-window must be an integer >= 0"
fi
if ! is_int_ge "$max_expand_step_per_window" 0; then
  die "--max-expand-step-per-window must be an integer >= 0"
fi
if ! is_int_ge "$cooldown_minutes" 0; then
  die "--cooldown-minutes must be an integer >= 0"
fi

if [[ "$controller_mode" == "guarded_auto_apply" ]]; then
  [[ -n "$actor" ]] || die "--by is required for mode guarded_auto_apply"
  [[ -n "$approval_ref" ]] || die "--approval-ref is required for mode guarded_auto_apply"
  [[ -n "$rationale" ]] || die "--rationale is required for mode guarded_auto_apply"
  [[ -n "$review_by" ]] || die "--review-by is required for mode guarded_auto_apply"
fi

if [[ -n "$freeze_windows_file" && ! -f "$freeze_windows_file" ]]; then
  die "freeze windows file not found: $freeze_windows_file"
fi

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
promotion_ci_script="${OPS_MANAGER_PROMOTION_CI_SCRIPT:-$script_dir/ops-manager-promotion-ci.sh}"
promotion_orchestrate_script="${OPS_MANAGER_PROMOTION_ORCHESTRATE_SCRIPT:-$script_dir/ops-manager-promotion-orchestrate.sh}"

if [[ -z "$promotion_ci_result_file" ]]; then
  promotion_ci_result_file="$repo/.superloop/ops-manager/fleet/promotion-controller-ci-result.json"
fi
if [[ -z "$promotion_ci_summary_file" ]]; then
  promotion_ci_summary_file="$repo/.superloop/ops-manager/fleet/promotion-controller-ci-summary.md"
fi
if [[ -z "$verify_result_file" ]]; then
  verify_result_file="$repo/.superloop/ops-manager/fleet/promotion-controller-verify-ci-result.json"
fi
if [[ -z "$verify_summary_file" ]]; then
  verify_summary_file="$repo/.superloop/ops-manager/fleet/promotion-controller-verify-ci-summary.md"
fi

if [[ -z "$preview_result_file" ]]; then
  preview_result_file="$repo/.superloop/ops-manager/fleet/promotion-controller-preview-result.json"
fi
if [[ -z "$preview_summary_file" ]]; then
  preview_summary_file="$repo/.superloop/ops-manager/fleet/promotion-controller-preview-summary.md"
fi
if [[ -z "$apply_result_file" ]]; then
  apply_result_file="$repo/.superloop/ops-manager/fleet/promotion-controller-apply-result.json"
fi
if [[ -z "$apply_summary_file" ]]; then
  apply_summary_file="$repo/.superloop/ops-manager/fleet/promotion-controller-apply-summary.md"
fi
if [[ -z "$rollback_result_file" ]]; then
  rollback_result_file="$repo/.superloop/ops-manager/fleet/promotion-controller-rollback-result.json"
fi
if [[ -z "$rollback_summary_file" ]]; then
  rollback_summary_file="$repo/.superloop/ops-manager/fleet/promotion-controller-rollback-summary.md"
fi

if [[ -z "$state_file" ]]; then
  state_file="$repo/.superloop/ops-manager/fleet/promotion-controller-state.json"
fi
if [[ -z "$telemetry_file" ]]; then
  telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/promotion-controller.jsonl"
fi

if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

mkdir -p "$(dirname "$promotion_ci_result_file")"
mkdir -p "$(dirname "$promotion_ci_summary_file")"
mkdir -p "$(dirname "$verify_result_file")"
mkdir -p "$(dirname "$verify_summary_file")"
mkdir -p "$(dirname "$preview_result_file")"
mkdir -p "$(dirname "$preview_summary_file")"
mkdir -p "$(dirname "$apply_result_file")"
mkdir -p "$(dirname "$apply_summary_file")"
mkdir -p "$(dirname "$rollback_result_file")"
mkdir -p "$(dirname "$rollback_summary_file")"
mkdir -p "$(dirname "$state_file")"
mkdir -p "$(dirname "$telemetry_file")"

evidence_refs_json='[]'
if (( ${#evidence_refs[@]} > 0 )); then
  evidence_refs_json="$(printf '%s\n' "${evidence_refs[@]}" | jq -R . | jq -s .)"
fi

previous_state_json='null'
if [[ -f "$state_file" ]]; then
  previous_state_json="$(jq -c '.' "$state_file" 2>/dev/null)" || die "invalid prior controller state JSON: $state_file"
fi

run_timestamp="$(timestamp)"
now_epoch="$(jq -rn --arg ts "$run_timestamp" '$ts | fromdateiso8601')"

preview_cmd=(
  "$promotion_orchestrate_script"
  --repo "$repo"
  --mode dry_run
  --promotion-ci-result-file "$promotion_ci_result_file"
  --promotion-ci-summary-file "$promotion_ci_summary_file"
  --result-file "$preview_result_file"
  --summary-file "$preview_summary_file"
)
append_eval_overrides preview_cmd
append_context_flags preview_cmd

set +e
preview_output="$("${preview_cmd[@]}" 2>&1)"
preview_status=$?
set -e
if [[ "$preview_status" -ne 0 ]]; then
  printf '%s\n' "$preview_output" >&2
  exit "$preview_status"
fi

[[ -f "$preview_result_file" ]] || die "preview result file not found: $preview_result_file"
preview_json="$(jq -c '.' "$preview_result_file" 2>/dev/null)" || die "invalid preview JSON: $preview_result_file"
[[ -f "$promotion_ci_result_file" ]] || die "evaluate promotion CI result file not found: $promotion_ci_result_file"
promotion_ci_json="$(jq -c '.' "$promotion_ci_result_file" 2>/dev/null)" || die "invalid evaluate promotion CI JSON: $promotion_ci_result_file"

promotion_decision="$(jq -r '.decision // "unknown"' <<<"$preview_json")"
promotion_reason_codes_json="$(jq -c '(.summary.reasonCodes // [])' <<<"$preview_json")"
promotion_failed_gates_json="$(jq -c '(.summary.failedGates // [])' <<<"$preview_json")"

decision_generated_at="$(jq -r '.generatedAt // empty' <<<"$promotion_ci_json")"
decision_age_seconds_json='null'
freshness_reasons_json='[]'
if [[ -z "$decision_generated_at" ]]; then
  freshness_reasons_json='["controller_decision_timestamp_invalid"]'
else
  decision_epoch="$(jq -rn --arg ts "$decision_generated_at" '$ts | fromdateiso8601? // empty')"
  if [[ -z "$decision_epoch" ]]; then
    freshness_reasons_json='["controller_decision_timestamp_invalid"]'
  else
    decision_age_seconds=$(( now_epoch - decision_epoch ))
    if (( decision_age_seconds < 0 )); then
      decision_age_seconds=0
    fi
    decision_age_seconds_json="$decision_age_seconds"
    if (( decision_age_seconds > decision_ttl_minutes * 60 )); then
      freshness_reasons_json='["controller_decision_stale"]'
    fi
  fi
fi
freshness_pass="$(jq -e 'length == 0' <<<"$freshness_reasons_json" >/dev/null && echo true || echo false)"

history_json='[]'
if [[ -f "$telemetry_file" ]]; then
  history_json="$(jq -cs '.' "$telemetry_file" 2>/dev/null)" || die "invalid controller telemetry JSONL: $telemetry_file"
fi

lookback_start_epoch=$(( now_epoch - (budget_window_hours * 3600) ))
cooldown_seconds=$(( cooldown_minutes * 60 ))

budget_eval_json="$(jq -cn \
  --argjson history "$history_json" \
  --argjson lookback_start "$lookback_start_epoch" \
  --argjson now_epoch "$now_epoch" \
  --argjson cooldown_seconds "$cooldown_seconds" \
  --argjson max_applies "$max_applies_per_window" \
  --argjson max_expand "$max_expand_step_per_window" \
  --argjson candidate_expand "$expand_step" \
  --arg apply_intent "$apply_intent" \
  '
  [
    $history[]?
    | . as $row
    | (($row.timestamp // "") | fromdateiso8601?) as $epoch
    | select($epoch != null and $epoch >= $lookback_start)
    | {row: $row, epoch: $epoch}
  ] as $window
  | ([ $window[] | select((.row.execution.action // "") == "apply") ]) as $applies
  | ($applies | length) as $apply_count
  | ([ $applies[] | (.row.execution.expandStep // 0) ] | add // 0) as $expand_sum
  | ([
      $window[]
      | select(((.row.execution.action // "") == "apply") or ((.row.execution.action // "") == "rollback"))
      | .epoch
    ] | max?) as $last_mutation_epoch
  | (if $last_mutation_epoch == null then null else ($now_epoch - $last_mutation_epoch) end) as $since_last_mutation
  | {
      applyCount: $apply_count,
      expandStepSum: $expand_sum,
      lastMutationEpoch: $last_mutation_epoch,
      cooldownRemainingSeconds: (
        if $since_last_mutation == null then 0
        elif $since_last_mutation < $cooldown_seconds then ($cooldown_seconds - $since_last_mutation)
        else 0
        end
      ),
      reasons: (
        []
        + (if $apply_count >= $max_applies then ["controller_budget_apply_count_exceeded"] else [] end)
        + (if ($apply_intent == "expand" and ($expand_sum + $candidate_expand) > $max_expand) then ["controller_budget_expand_step_exceeded"] else [] end)
        + (if ($since_last_mutation != null and $since_last_mutation < $cooldown_seconds) then ["controller_budget_cooldown_active"] else [] end)
      )
    }
  ' )"

freeze_eval_json='{"active":false,"reasons":[],"matched":[],"windows":[]}'
if [[ -n "$freeze_windows_file" ]]; then
  freeze_windows_json="$(jq -c '.' "$freeze_windows_file" 2>/dev/null)" || die "invalid freeze windows JSON: $freeze_windows_file"
  freeze_eval_json="$(jq -cn \
    --argjson freeze "$freeze_windows_json" \
    --arg now_ts "$run_timestamp" \
    '
    ($now_ts | fromdateiso8601) as $now_epoch
    | [
        ($freeze.windows // [])[]?
        | {
            start: (.start // .startAt // ""),
            end: (.end // .endAt // ""),
            reason: (.reason // "controller_budget_freeze_window_active")
          }
      ] as $windows
    | reduce $windows[] as $w ({active: false, reasons: [], matched: [], invalid: false, windows: $windows};
        ($w.start | fromdateiso8601?) as $s
        | ($w.end | fromdateiso8601?) as $e
        | if ($s == null or $e == null or $e < $s) then
            .invalid = true
          elif ($now_epoch >= $s and $now_epoch <= $e) then
            .active = true
            | .reasons += ["controller_budget_freeze_window_active"]
            | .matched += [{start: $w.start, end: $w.end, reason: $w.reason}]
          else
            .
          end
      )
    ' )"
  if [[ "$(jq -r '.invalid' <<<"$freeze_eval_json")" == "true" ]]; then
    die "freeze windows file contains invalid window entries: $freeze_windows_file"
  fi
fi

budget_reasons_json="$(jq -cn --argjson budget "$(jq -c '.reasons' <<<"$budget_eval_json")" --argjson freeze "$(jq -c '.reasons' <<<"$freeze_eval_json")" '$budget + $freeze | unique | sort')"

planned_action="propose"
if [[ "$controller_mode" == "guarded_auto_apply" ]]; then
  if [[ "$promotion_decision" != "promote" ]]; then
    planned_action="hold"
  elif [[ "$(jq -r 'length' <<<"$freshness_reasons_json")" -gt 0 || "$(jq -r 'length' <<<"$budget_reasons_json")" -gt 0 ]]; then
    planned_action="hold"
  else
    planned_action="apply"
  fi
fi

apply_executed="false"
rollback_executed="false"
verify_ran="false"
verification_status="skipped"
verification_decision=""
verification_reason_codes_json='[]'
executed_action="$planned_action"
final_status="proposed"

if [[ "$planned_action" == "hold" ]]; then
  final_status="hold"
elif [[ "$planned_action" == "apply" ]]; then
  apply_cmd=(
    "$promotion_orchestrate_script"
    --repo "$repo"
    --mode apply
    --apply-intent "$apply_intent"
    --expand-step "$expand_step"
    --promotion-ci-result-file "$promotion_ci_result_file"
    --promotion-ci-summary-file "$promotion_ci_summary_file"
    --result-file "$apply_result_file"
    --summary-file "$apply_summary_file"
    --by "$actor"
    --approval-ref "$approval_ref"
    --rationale "$rationale"
    --review-by "$review_by"
  )
  if [[ -n "$idempotency_key" ]]; then
    apply_cmd+=(--idempotency-key "$idempotency_key")
  fi
  append_eval_overrides apply_cmd
  append_context_flags apply_cmd

  set +e
  apply_output="$("${apply_cmd[@]}" 2>&1)"
  apply_status=$?
  set -e
  if [[ "$apply_status" -ne 0 ]]; then
    printf '%s\n' "$apply_output" >&2
    exit "$apply_status"
  fi

  [[ -f "$apply_result_file" ]] || die "apply orchestration result file not found: $apply_result_file"
  jq -c '.' "$apply_result_file" >/dev/null 2>&1 || die "invalid apply orchestration JSON: $apply_result_file"
  apply_executed="true"
  executed_action="apply"
  verify_ran="true"

  verify_cmd=(
    "$promotion_ci_script"
    --repo "$repo"
    --result-file "$verify_result_file"
    --summary-file "$verify_summary_file"
  )
  append_eval_overrides verify_cmd
  if [[ -n "$trace_id" ]]; then
    verify_cmd+=(--trace-id "$trace_id")
  fi

  set +e
  verify_output="$("${verify_cmd[@]}" 2>&1)"
  verify_status=$?
  set -e

  if [[ "$verify_status" -ne 0 ]]; then
    verification_status="fail"
    verification_reason_codes_json='["controller_verification_command_failed"]'
  elif [[ ! -f "$verify_result_file" ]]; then
    verification_status="fail"
    verification_reason_codes_json='["controller_verification_result_missing"]'
  else
    verify_json="$(jq -c '.' "$verify_result_file" 2>/dev/null)" || {
      verification_status="fail"
      verification_reason_codes_json='["controller_verification_result_invalid"]'
      verify_json='null'
    }

    if [[ "$verification_status" != "fail" ]]; then
      verification_decision="$(jq -r '.summary.decision // "unknown"' <<<"$verify_json")"
      if [[ "$verification_decision" == "promote" ]]; then
        verification_status="pass"
      else
        verification_status="fail"
        verification_reason_codes_json='["controller_verification_failed"]'
      fi
    fi
  fi

  if [[ "$verification_status" == "fail" ]]; then
    rollback_cmd=(
      "$promotion_orchestrate_script"
      --repo "$repo"
      --mode rollback
      --promotion-ci-result-file "$promotion_ci_result_file"
      --promotion-ci-summary-file "$promotion_ci_summary_file"
      --result-file "$rollback_result_file"
      --summary-file "$rollback_summary_file"
      --by "$actor"
      --approval-ref "$approval_ref"
      --rationale "$rationale"
      --review-by "$review_by"
    )
    append_eval_overrides rollback_cmd
    append_context_flags rollback_cmd

    set +e
    rollback_output="$("${rollback_cmd[@]}" 2>&1)"
    rollback_status=$?
    set -e
    if [[ "$rollback_status" -ne 0 ]]; then
      printf '%s\n' "$rollback_output" >&2
      exit "$rollback_status"
    fi

    [[ -f "$rollback_result_file" ]] || die "rollback orchestration result file not found: $rollback_result_file"
    jq -c '.' "$rollback_result_file" >/dev/null 2>&1 || die "invalid rollback orchestration JSON: $rollback_result_file"

    rollback_executed="true"
    executed_action="rollback"
    final_status="rolled_back"
  else
    final_status="applied"
  fi
fi

controller_reason_codes_json="$(jq -cn \
  --arg mode "$controller_mode" \
  --arg decision "$promotion_decision" \
  --arg planned_action "$planned_action" \
  --arg executed_action "$executed_action" \
  --argjson freshness "$freshness_reasons_json" \
  --argjson budget "$budget_reasons_json" \
  --argjson verification "$verification_reason_codes_json" \
  --argjson rollback_executed "$rollback_executed" \
  '
  []
  + $freshness
  + $budget
  + $verification
  + (if ($mode == "guarded_auto_apply" and $decision != "promote") then ["controller_decision_not_promote"] else [] end)
  + (if ($rollback_executed == true and ($verification | length) > 0) then ["controller_rollback_triggered"] else [] end)
  | unique | sort
  ' )"

controller_json="$(jq -cn \
  --arg schema_version "v1" \
  --arg timestamp "$run_timestamp" \
  --arg category "promotion_controller_run" \
  --arg mode "$controller_mode" \
  --arg status "$final_status" \
  --arg promotion_decision "$promotion_decision" \
  --arg planned_action "$planned_action" \
  --arg executed_action "$executed_action" \
  --arg apply_intent "$apply_intent" \
  --arg idempotency_key "$idempotency_key" \
  --arg trace_id "$trace_id" \
  --arg loop_id "$loop_id" \
  --arg horizon_ref "$horizon_ref" \
  --arg state_file "$state_file" \
  --arg telemetry_file "$telemetry_file" \
  --arg promotion_ci_result_file "$promotion_ci_result_file" \
  --arg promotion_ci_summary_file "$promotion_ci_summary_file" \
  --arg verify_result_file "$verify_result_file" \
  --arg verify_summary_file "$verify_summary_file" \
  --arg preview_result_file "$preview_result_file" \
  --arg preview_summary_file "$preview_summary_file" \
  --arg apply_result_file "$apply_result_file" \
  --arg apply_summary_file "$apply_summary_file" \
  --arg rollback_result_file "$rollback_result_file" \
  --arg rollback_summary_file "$rollback_summary_file" \
  --arg verification_status "$verification_status" \
  --arg verification_decision "$verification_decision" \
  --argjson decision_ttl_minutes "$decision_ttl_minutes" \
  --argjson decision_age_seconds "$decision_age_seconds_json" \
  --argjson freshness_pass "$freshness_pass" \
  --argjson freshness_reasons "$freshness_reasons_json" \
  --argjson budget_window_hours "$budget_window_hours" \
  --argjson max_applies_per_window "$max_applies_per_window" \
  --argjson max_expand_step_per_window "$max_expand_step_per_window" \
  --argjson cooldown_minutes "$cooldown_minutes" \
  --argjson budget_eval "$budget_eval_json" \
  --argjson freeze_eval "$freeze_eval_json" \
  --argjson budget_reasons "$budget_reasons_json" \
  --argjson controller_reason_codes "$controller_reason_codes_json" \
  --argjson promotion_reason_codes "$promotion_reason_codes_json" \
  --argjson promotion_failed_gates "$promotion_failed_gates_json" \
  --argjson verification_reason_codes "$verification_reason_codes_json" \
  --argjson apply_executed "$apply_executed" \
  --argjson rollback_executed "$rollback_executed" \
  --argjson verify_ran "$verify_ran" \
  --argjson expand_step "$expand_step" \
  --argjson evidence_refs "$evidence_refs_json" \
  --argjson previous_state "$previous_state_json" \
  '
  {
    schemaVersion: $schema_version,
    timestamp: $timestamp,
    category: $category,
    mode: $mode,
    status: $status,
    decision: {
      promotionDecision: $promotion_decision,
      promotionReasonCodes: $promotion_reason_codes,
      failedGates: $promotion_failed_gates,
      freshness: {
        pass: $freshness_pass,
        ttlMinutes: $decision_ttl_minutes,
        ageSeconds: $decision_age_seconds,
        reasons: $freshness_reasons
      },
      budget: {
        windowHours: $budget_window_hours,
        maxAppliesPerWindow: $max_applies_per_window,
        maxExpandStepPerWindow: $max_expand_step_per_window,
        cooldownMinutes: $cooldown_minutes,
        applyCountInWindow: ($budget_eval.applyCount // 0),
        expandStepInWindow: ($budget_eval.expandStepSum // 0),
        cooldownRemainingSeconds: ($budget_eval.cooldownRemainingSeconds // 0),
        freezeWindowActive: ($freeze_eval.active // false),
        freezeWindowsMatched: ($freeze_eval.matched // []),
        reasons: $budget_reasons
      },
      reasonCodes: $controller_reason_codes
    },
    execution: {
      plannedAction: $planned_action,
      action: $executed_action,
      applyExecuted: $apply_executed,
      rollbackExecuted: $rollback_executed,
      applyIntent: (if $apply_executed then $apply_intent else null end),
      expandStep: (if $apply_executed and $apply_intent == "expand" then $expand_step else null end),
      idempotencyKey: (if ($idempotency_key | length) > 0 then $idempotency_key else null end),
      governance: {
        actor: (if ($mode == "guarded_auto_apply" and ($status == "applied" or $status == "rolled_back" or $planned_action == "hold")) then null else null end),
        by: (if ($mode == "guarded_auto_apply" and ($status == "applied" or $status == "rolled_back" or $planned_action == "hold")) then null else null end)
      }
    },
    verification: {
      ran: $verify_ran,
      status: $verification_status,
      decision: (if ($verification_decision | length) > 0 then $verification_decision else null end),
      reasonCodes: $verification_reason_codes
    },
    context: {
      traceId: $trace_id,
      loopId: (if ($loop_id | length) > 0 then $loop_id else null end),
      horizonRef: (if ($horizon_ref | length) > 0 then $horizon_ref else null end),
      evidenceRefs: $evidence_refs
    },
    files: {
      stateFile: $state_file,
      telemetryFile: $telemetry_file,
      promotionCiResultFile: $promotion_ci_result_file,
      promotionCiSummaryFile: $promotion_ci_summary_file,
      verifyResultFile: $verify_result_file,
      verifySummaryFile: $verify_summary_file,
      previewResultFile: $preview_result_file,
      previewSummaryFile: $preview_summary_file,
      applyResultFile: $apply_result_file,
      applySummaryFile: $apply_summary_file,
      rollbackResultFile: $rollback_result_file,
      rollbackSummaryFile: $rollback_summary_file
    },
    observed: {
      hasPreviousState: ($previous_state != null),
      previousStatus: ($previous_state.status // null),
      previousTimestamp: ($previous_state.timestamp // null)
    }
  }
  ' )"

# overwrite placeholder governance object with actual values while keeping JSON construction centralized.
controller_json="$(jq -c \
  --arg actor "$actor" \
  --arg approval_ref "$approval_ref" \
  --arg rationale "$rationale" \
  --arg review_by "$review_by" \
  '.execution.governance = {
      actor: (if ($actor | length) > 0 then $actor else null end),
      approvalRef: (if ($approval_ref | length) > 0 then $approval_ref else null end),
      rationale: (if ($rationale | length) > 0 then $rationale else null end),
      reviewBy: (if ($review_by | length) > 0 then $review_by else null end)
    }
  ' <<<"$controller_json")"

jq -c '.' <<<"$controller_json" > "$state_file"
jq -c '.' <<<"$controller_json" >> "$telemetry_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$controller_json"
else
  jq -c '.' <<<"$controller_json"
fi
