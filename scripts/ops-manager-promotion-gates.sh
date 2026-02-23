#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-promotion-gates.sh --repo <path> [options]

Options:
  --fleet-status-file <path>      Precomputed fleet status JSON path. Default: invoke ops-manager-fleet-status.sh
  --handoff-telemetry-file <path> Fleet handoff telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/handoff.jsonl
  --drill-state-file <path>       Promotion drill state JSON path. Default: <repo>/.superloop/ops-manager/fleet/drills/promotion.v1.json
  --promotion-state-file <path>   Promotion decision state JSON path. Default: <repo>/.superloop/ops-manager/fleet/promotion-state.json
  --promotion-telemetry-file <path> Promotion decision telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/promotion.jsonl
  --window-executions <n>         Number of most recent autonomous handoff executions to evaluate. Default: 20
  --min-sample-size <n>           Minimum autonomous execution sample size required. Default: 20
  --max-ambiguity-rate <0..1>     Maximum ambiguity rate to allow promotion. Default: 0.2
  --max-failure-rate <0..1>       Maximum failure rate to allow promotion. Default: 0.2
  --max-manual-backlog <n>        Maximum manual backlog to allow promotion. Default: 5
  --max-drill-age-hours <n>       Maximum age (hours) allowed for required drill evidence. Default: 168
  --trace-id <id>                 Promotion trace id override.
  --fail-on-hold                  Exit non-zero when decision is hold.
  --pretty                        Pretty-print output JSON.
  --help                          Show this help message.
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

is_rate() {
  local value="$1"
  [[ "$value" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] || return 1
  awk -v v="$value" 'BEGIN { exit !(v >= 0 && v <= 1) }'
}

repo=""
fleet_status_file=""
handoff_telemetry_file=""
drill_state_file=""
promotion_state_file=""
promotion_telemetry_file=""
window_executions="20"
min_sample_size="20"
max_ambiguity_rate="0.2"
max_failure_rate="0.2"
max_manual_backlog="5"
max_drill_age_hours="168"
trace_id=""
fail_on_hold="0"
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --promotion-state-file)
      promotion_state_file="${2:-}"
      shift 2
      ;;
    --promotion-telemetry-file)
      promotion_telemetry_file="${2:-}"
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
    --trace-id)
      trace_id="${2:-}"
      shift 2
      ;;
    --fail-on-hold)
      fail_on_hold="1"
      shift
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

if ! is_int_ge "$window_executions" 1; then
  die "--window-executions must be an integer >= 1"
fi
if ! is_int_ge "$min_sample_size" 1; then
  die "--min-sample-size must be an integer >= 1"
fi
if ! is_rate "$max_ambiguity_rate"; then
  die "--max-ambiguity-rate must be a number between 0 and 1"
fi
if ! is_rate "$max_failure_rate"; then
  die "--max-failure-rate must be a number between 0 and 1"
fi
if ! is_int_ge "$max_manual_backlog" 0; then
  die "--max-manual-backlog must be an integer >= 0"
fi
if ! is_int_ge "$max_drill_age_hours" 1; then
  die "--max-drill-age-hours must be an integer >= 1"
fi

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status_script="${OPS_MANAGER_FLEET_STATUS_SCRIPT:-$script_dir/ops-manager-fleet-status.sh}"

if [[ -z "$handoff_telemetry_file" ]]; then
  handoff_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl"
fi
if [[ -z "$drill_state_file" ]]; then
  drill_state_file="$repo/.superloop/ops-manager/fleet/drills/promotion.v1.json"
fi
if [[ -z "$promotion_state_file" ]]; then
  promotion_state_file="$repo/.superloop/ops-manager/fleet/promotion-state.json"
fi
if [[ -z "$promotion_telemetry_file" ]]; then
  promotion_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/promotion.jsonl"
fi

if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

status_source="generated"
if [[ -n "$fleet_status_file" ]]; then
  [[ -f "$fleet_status_file" ]] || die "fleet status file not found: $fleet_status_file"
  status_json="$(jq -c '.' "$fleet_status_file" 2>/dev/null)" || die "invalid fleet status JSON: $fleet_status_file"
  status_source="file"
else
  status_json="$($status_script --repo "$repo")" || die "failed to read fleet status via $status_script"
  status_json="$(jq -c '.' <<<"$status_json" 2>/dev/null)" || die "fleet status output was not valid JSON"
fi

handoff_missing="0"
handoff_invalid="0"
handoff_history_json='[]'
if [[ -f "$handoff_telemetry_file" ]]; then
  handoff_history_json="$(jq -cs '.' "$handoff_telemetry_file" 2>/dev/null)" || handoff_invalid="1"
  if [[ "$handoff_invalid" == "1" ]]; then
    handoff_history_json='[]'
  fi
else
  handoff_missing="1"
fi

drill_missing="0"
drill_invalid="0"
drill_state_json='null'
if [[ -f "$drill_state_file" ]]; then
  drill_state_json="$(jq -c '.' "$drill_state_file" 2>/dev/null)" || drill_invalid="1"
  if [[ "$drill_invalid" == "1" ]]; then
    drill_state_json='null'
  fi
else
  drill_missing="1"
fi

generated_at="$(timestamp)"

promotion_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$generated_at" \
  --arg trace_id "$trace_id" \
  --arg repo_path "$repo" \
  --arg status_source "$status_source" \
  --arg fleet_status_file "${fleet_status_file:-}" \
  --arg handoff_telemetry_file "$handoff_telemetry_file" \
  --arg drill_state_file "$drill_state_file" \
  --arg promotion_state_file "$promotion_state_file" \
  --arg promotion_telemetry_file "$promotion_telemetry_file" \
  --argjson status "$status_json" \
  --argjson handoff_history "$handoff_history_json" \
  --argjson drill_state "$drill_state_json" \
  --argjson handoff_missing "$handoff_missing" \
  --argjson handoff_invalid "$handoff_invalid" \
  --argjson drill_missing "$drill_missing" \
  --argjson drill_invalid "$drill_invalid" \
  --argjson window_executions "$window_executions" \
  --argjson min_sample_size "$min_sample_size" \
  --argjson max_ambiguity_rate "$max_ambiguity_rate" \
  --argjson max_failure_rate "$max_failure_rate" \
  --argjson max_manual_backlog "$max_manual_backlog" \
  --argjson max_drill_age_hours "$max_drill_age_hours" \
  '
  def rate($num; $den): if $den > 0 then ($num / $den) else 0 end;
  def gate_status($pass): if $pass then "pass" else "fail" end;
  def take_last($arr; $count):
    if ($arr | length) > $count then $arr[-$count:] else $arr end;

  [
    "autonomous_governance_authority_missing",
    "autonomous_governance_review_deadline_missing",
    "autonomous_governance_review_expired"
  ] as $required_governance_reason_codes
  | ["kill_switch", "sprite_service_outage", "ambiguous_retry_guard"] as $required_drills
  | ($generated_at | fromdateiso8601?) as $generated_epoch
  | ($status.autonomous // {}) as $autonomous
  | ($autonomous.governance // {}) as $governance
  | (($governance.reasonCodes // []) | map(tostring) | unique) as $governance_reason_codes
  | (reduce $required_governance_reason_codes[] as $code ([];
      if ($governance_reason_codes | index($code)) != null then
        . + [("promotion_" + ($code | sub("^autonomous_"; "")))]
      else
        .
      end
    )) as $governance_required_failures
  | ([]
      + (if (($autonomous.enabled // false) == false) then ["promotion_policy_mode_not_guarded_auto"] else [] end)
      + (if (($governance.posture // "") != "active") then ["promotion_governance_posture_not_active"] else [] end)
      + (if (($governance.blocksAutonomous // false) == true) then ["promotion_governance_blocks_autonomous"] else [] end)
      + $governance_required_failures
    ) as $governance_fail_reasons
  | (($governance_fail_reasons | length) == 0) as $governance_pass

  | ([
      $handoff_history[]?
      | select((.category // "") == "fleet_handoff_execute" and (.execution.mode // "") == "autonomous")
    ]) as $autonomous_runs
  | (take_last($autonomous_runs; $window_executions)) as $window_runs
  | ($window_runs | length) as $window_run_count
  | ([ $window_runs[] | (.execution.requestedIntentCount // 0) ] | add // 0) as $attempted
  | ([ $window_runs[] | (.execution.executedCount // 0) ] | add // 0) as $executed
  | ([ $window_runs[] | (.execution.ambiguousCount // 0) ] | add // 0) as $ambiguous
  | ([ $window_runs[] | (.execution.failedCount // 0) ] | add // 0) as $failed
  | (rate($ambiguous; $attempted)) as $ambiguity_rate
  | (rate($failed; $attempted)) as $failure_rate
  | ([]
      + (if $handoff_missing == 1 then ["promotion_handoff_telemetry_missing"] else [] end)
      + (if $handoff_invalid == 1 then ["promotion_handoff_telemetry_invalid"] else [] end)
      + (if $window_run_count < $min_sample_size then ["promotion_autonomous_sample_insufficient"] else [] end)
      + (if ($window_run_count >= $min_sample_size and $attempted == 0) then ["promotion_autonomous_attempts_zero"] else [] end)
      + (if ($attempted > 0 and $ambiguity_rate > $max_ambiguity_rate) then ["promotion_autonomous_ambiguity_rate_exceeded"] else [] end)
      + (if ($attempted > 0 and $failure_rate > $max_failure_rate) then ["promotion_autonomous_failure_rate_exceeded"] else [] end)
    ) as $reliability_fail_reasons
  | (($reliability_fail_reasons | length) == 0) as $reliability_pass

  | ($autonomous.outcomeRollup.manual_backlog // null) as $manual_backlog
  | ([]
      + (if $manual_backlog == null then ["promotion_manual_backlog_unavailable"] else [] end)
      + (if ($manual_backlog != null and $manual_backlog > $max_manual_backlog) then ["promotion_manual_backlog_exceeded"] else [] end)
    ) as $manual_backlog_fail_reasons
  | (($manual_backlog_fail_reasons | length) == 0) as $manual_backlog_pass

  | (($autonomous.rollout.autopause.active // $autonomous.rollout.state.autoPauseActive // false) == true) as $autopause_active
  | ($autonomous.safetyGateDecisions.byPath // null) as $by_path
  | ["policyGated", "rolloutGated", "governanceGated", "transportGated"] as $required_paths
  | (if (($by_path | type) == "object") then
      [ $required_paths[] as $path | select(($by_path | has($path)) | not) | $path ]
    else
      $required_paths
    end) as $missing_paths
  | ([]
      + (if $autopause_active then ["promotion_autopause_active"] else [] end)
      + (if (($missing_paths | length) > 0) then ["promotion_suppression_paths_missing"] else [] end)
    ) as $safety_fail_reasons
  | (($safety_fail_reasons | length) == 0) as $safety_pass

  | ($drill_state.drills // []) as $drills
  | (reduce $required_drills[] as $id ([];
      ($drills | map(select((.id // "") == $id)) | .[0]) as $drill
      | if $drill == null then
          . + [("promotion_drill_missing_" + $id)]
        else
          (($drill.completedAt // null) | fromdateiso8601?) as $completed_epoch
          | (if ($completed_epoch != null and $generated_epoch != null) then (($generated_epoch - $completed_epoch) / 3600) else null end) as $age_hours
          | .
            + (if (($drill.status // "") != "pass") then [("promotion_drill_not_passed_" + $id)] else [] end)
            + (if $completed_epoch == null then [("promotion_drill_timestamp_invalid_" + $id)] else [] end)
            + (if ($completed_epoch != null and $age_hours > $max_drill_age_hours) then [("promotion_drill_stale_" + $id)] else [] end)
        end
    )) as $drill_failures_by_id
  | ([]
      + (if $drill_missing == 1 then ["promotion_drill_state_missing"] else [] end)
      + (if $drill_invalid == 1 then ["promotion_drill_state_invalid"] else [] end)
      + (if ($drill_missing == 0 and $drill_invalid == 0) then $drill_failures_by_id else [] end)
    ) as $drill_fail_reasons
  | (($drill_fail_reasons | length) == 0) as $drill_pass

  | [
      {name: "governance", pass: $governance_pass, reasons: $governance_fail_reasons},
      {name: "outcome_reliability", pass: $reliability_pass, reasons: $reliability_fail_reasons},
      {name: "manual_backlog", pass: $manual_backlog_pass, reasons: $manual_backlog_fail_reasons},
      {name: "safety_suppression", pass: $safety_pass, reasons: $safety_fail_reasons},
      {name: "drill_recency", pass: $drill_pass, reasons: $drill_fail_reasons}
    ] as $gate_results
  | ($gate_results | map(select(.pass == false) | .name)) as $failed_gates
  | ($gate_results | map(.reasons[]) | unique | sort) as $reason_codes
  | (($failed_gates | length) == 0) as $promote
  | {
      schemaVersion: $schema_version,
      generatedAt: $generated_at,
      traceId: $trace_id,
      source: {
        repoPath: $repo_path,
        fleetStatusSource: $status_source,
        fleetStatusFile: (if $fleet_status_file == "" then null else $fleet_status_file end),
        handoffTelemetryFile: $handoff_telemetry_file,
        drillStateFile: $drill_state_file,
        promotionStateFile: $promotion_state_file,
        promotionTelemetryFile: $promotion_telemetry_file
      },
      thresholds: {
        windowExecutions: $window_executions,
        minSampleSize: $min_sample_size,
        maxAmbiguityRate: $max_ambiguity_rate,
        maxFailureRate: $max_failure_rate,
        maxManualBacklog: $max_manual_backlog,
        maxDrillAgeHours: $max_drill_age_hours
      },
      summary: {
        decision: (if $promote then "promote" else "hold" end),
        promote: $promote,
        gatePassCount: ($gate_results | map(select(.pass == true)) | length),
        gateFailCount: ($failed_gates | length),
        failedGates: $failed_gates,
        reasonCodes: $reason_codes
      },
      gates: {
        governance: {
          status: gate_status($governance_pass),
          reasons: $governance_fail_reasons,
          posture: ($governance.posture // null),
          blocksAutonomous: ($governance.blocksAutonomous // false),
          reasonCodes: $governance_reason_codes
        },
        outcomeReliability: {
          status: gate_status($reliability_pass),
          reasons: $reliability_fail_reasons,
          sampleRuns: $window_run_count,
          attempted: $attempted,
          executed: $executed,
          ambiguous: $ambiguous,
          failed: $failed,
          ambiguityRate: $ambiguity_rate,
          failureRate: $failure_rate
        },
        manualBacklog: {
          status: gate_status($manual_backlog_pass),
          reasons: $manual_backlog_fail_reasons,
          manualBacklog: $manual_backlog
        },
        safetySuppression: {
          status: gate_status($safety_pass),
          reasons: $safety_fail_reasons,
          autopauseActive: $autopause_active,
          missingPaths: $missing_paths,
          byPath: (if (($by_path | type) == "object") then $by_path else null end)
        },
        drillRecency: {
          status: gate_status($drill_pass),
          reasons: $drill_fail_reasons,
          requiredDrills: $required_drills,
          drills: (if ($drill_missing == 0 and $drill_invalid == 0) then $drills else [] end)
        }
      }
    }
  ')

mkdir -p "$(dirname "$promotion_state_file")"
mkdir -p "$(dirname "$promotion_telemetry_file")"

jq -c '.' <<<"$promotion_json" > "$promotion_state_file"
jq -c '.' <<<"$promotion_json" >> "$promotion_telemetry_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$promotion_json"
else
  jq -c '.' <<<"$promotion_json"
fi

if [[ "$fail_on_hold" == "1" ]]; then
  decision="$(jq -r '.summary.decision' <<<"$promotion_json")"
  if [[ "$decision" == "hold" ]]; then
    exit 2
  fi
fi
