#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-promotion-ci.sh --repo <path> [options]

Options:
  --fleet-status-file <path>       Precomputed fleet status JSON path.
  --handoff-telemetry-file <path>  Fleet handoff telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/handoff.jsonl
  --drill-state-file <path>        Promotion drill state JSON path. Default: <repo>/.superloop/ops-manager/fleet/drills/promotion.v1.json
  --promotion-state-file <path>    Promotion state JSON output path. Default: <repo>/.superloop/ops-manager/fleet/promotion-state.json
  --promotion-telemetry-file <path> Promotion telemetry JSONL output path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/promotion.jsonl
  --summary-file <path>            Markdown summary output path. Default: <repo>/.superloop/ops-manager/fleet/promotion-ci-summary.md
  --result-file <path>             JSON result output path. Default: <repo>/.superloop/ops-manager/fleet/promotion-ci-result.json
  --window-executions <n>          Promotion evaluator window size.
  --min-sample-size <n>            Promotion evaluator min autonomous sample.
  --max-ambiguity-rate <0..1>      Promotion evaluator ambiguity threshold.
  --max-failure-rate <0..1>        Promotion evaluator failure threshold.
  --max-manual-backlog <n>         Promotion evaluator manual backlog threshold.
  --max-drill-age-hours <n>        Promotion evaluator drill staleness threshold.
  --trace-id <id>                  Trace id forwarded to evaluator.
  --fail-on-hold                   Exit non-zero when promotion decision is hold.
  --skip-on-missing-evidence       Emit skipped decision and exit 0 when required evidence files are missing.
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
fleet_status_file=""
handoff_telemetry_file=""
drill_state_file=""
promotion_state_file=""
promotion_telemetry_file=""
summary_file=""
result_file=""
window_executions=""
min_sample_size=""
max_ambiguity_rate=""
max_failure_rate=""
max_manual_backlog=""
max_drill_age_hours=""
trace_id=""
fail_on_hold="0"
skip_on_missing_evidence="0"
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
    --summary-file)
      summary_file="${2:-}"
      shift 2
      ;;
    --result-file)
      result_file="${2:-}"
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
    --skip-on-missing-evidence)
      skip_on_missing_evidence="1"
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

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
promotion_script="${OPS_MANAGER_PROMOTION_GATES_SCRIPT:-$script_dir/ops-manager-promotion-gates.sh}"

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
if [[ -z "$summary_file" ]]; then
  summary_file="$repo/.superloop/ops-manager/fleet/promotion-ci-summary.md"
fi
if [[ -z "$result_file" ]]; then
  result_file="$repo/.superloop/ops-manager/fleet/promotion-ci-result.json"
fi

mkdir -p "$(dirname "$summary_file")"
mkdir -p "$(dirname "$result_file")"

missing_paths=()
if [[ -n "$fleet_status_file" && ! -f "$fleet_status_file" ]]; then
  missing_paths+=("$fleet_status_file")
fi
if [[ ! -f "$handoff_telemetry_file" ]]; then
  missing_paths+=("$handoff_telemetry_file")
fi
if [[ ! -f "$drill_state_file" ]]; then
  missing_paths+=("$drill_state_file")
fi

if [[ "$skip_on_missing_evidence" == "1" && "${#missing_paths[@]}" -gt 0 ]]; then
  skipped_json=$(jq -cn \
    --arg schema_version "v1" \
    --arg generated_at "$(timestamp)" \
    --arg repo_path "$repo" \
    --argjson missing_paths "$(printf '%s\n' "${missing_paths[@]}" | jq -R . | jq -s .)" \
    '{
      schemaVersion: $schema_version,
      generatedAt: $generated_at,
      source: {
        repoPath: $repo_path
      },
      summary: {
        decision: "skipped",
        promote: false,
        reasonCodes: ["promotion_ci_missing_evidence"],
        missingEvidencePaths: $missing_paths
      }
    }')

  jq -c '.' <<<"$skipped_json" > "$result_file"
  {
    echo "## Ops Manager Promotion CI"
    echo
    echo "Decision: \`skipped\`"
    echo
    echo "Reason codes: \`promotion_ci_missing_evidence\`"
    echo
    echo "Missing evidence paths:"
    for path in "${missing_paths[@]}"; do
      echo "- \\`$path\\`"
    done
  } > "$summary_file"

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat "$summary_file" >> "$GITHUB_STEP_SUMMARY"
  fi

  if [[ "$pretty" == "1" ]]; then
    jq '.' <<<"$skipped_json"
  else
    jq -c '.' <<<"$skipped_json"
  fi
  exit 0
fi

cmd=("$promotion_script" --repo "$repo" --handoff-telemetry-file "$handoff_telemetry_file" --drill-state-file "$drill_state_file" --promotion-state-file "$promotion_state_file" --promotion-telemetry-file "$promotion_telemetry_file")
if [[ -n "$fleet_status_file" ]]; then
  cmd+=(--fleet-status-file "$fleet_status_file")
fi
if [[ -n "$window_executions" ]]; then
  cmd+=(--window-executions "$window_executions")
fi
if [[ -n "$min_sample_size" ]]; then
  cmd+=(--min-sample-size "$min_sample_size")
fi
if [[ -n "$max_ambiguity_rate" ]]; then
  cmd+=(--max-ambiguity-rate "$max_ambiguity_rate")
fi
if [[ -n "$max_failure_rate" ]]; then
  cmd+=(--max-failure-rate "$max_failure_rate")
fi
if [[ -n "$max_manual_backlog" ]]; then
  cmd+=(--max-manual-backlog "$max_manual_backlog")
fi
if [[ -n "$max_drill_age_hours" ]]; then
  cmd+=(--max-drill-age-hours "$max_drill_age_hours")
fi
if [[ -n "$trace_id" ]]; then
  cmd+=(--trace-id "$trace_id")
fi
if [[ "$pretty" == "1" ]]; then
  cmd+=(--pretty)
fi
if [[ "$fail_on_hold" == "1" ]]; then
  cmd+=(--fail-on-hold)
fi

set +e
promotion_output="$(${cmd[@]} 2>&1)"
promotion_status=$?
set -e

if ! promotion_json="$(jq -c '.' <<<"$promotion_output" 2>/dev/null)"; then
  printf '%s\n' "$promotion_output" >&2
  exit "$promotion_status"
fi

jq -c '.' <<<"$promotion_json" > "$result_file"

decision="$(jq -r '.summary.decision // "unknown"' <<<"$promotion_json")"
failed_gates_csv="$(jq -r '(.summary.failedGates // []) | join(", ")' <<<"$promotion_json")"
reason_codes_csv="$(jq -r '(.summary.reasonCodes // []) | join(", ")' <<<"$promotion_json")"

{
  echo "## Ops Manager Promotion CI"
  echo
  echo "Decision: \`$decision\`"
  echo
  echo "Failed gates: ${failed_gates_csv:-none}"
  echo
  echo "Reason codes: ${reason_codes_csv:-none}"
  echo
  echo "Result JSON: \\`$result_file\\`"
  echo
  echo "Promotion state: \\`$promotion_state_file\\`"
  echo
  echo "Promotion telemetry: \\`$promotion_telemetry_file\\`"
} > "$summary_file"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$summary_file" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$promotion_json"
else
  jq -c '.' <<<"$promotion_json"
fi

exit "$promotion_status"
