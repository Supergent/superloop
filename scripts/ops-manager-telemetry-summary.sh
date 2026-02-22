#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-telemetry-summary.sh --repo <path> --loop <id> [options]

Options:
  --reconcile-telemetry-file <path>   Reconcile telemetry JSONL path.
  --control-telemetry-file <path>     Control telemetry JSONL path.
  --window <n>                        Number of most recent entries to summarize (default: 200).
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

repo=""
loop_id=""
reconcile_file=""
control_file=""
window="200"
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --loop)
      loop_id="${2:-}"
      shift 2
      ;;
    --reconcile-telemetry-file)
      reconcile_file="${2:-}"
      shift 2
      ;;
    --control-telemetry-file)
      control_file="${2:-}"
      shift 2
      ;;
    --window)
      window="${2:-}"
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
if [[ -z "$loop_id" ]]; then
  die "--loop is required"
fi
if [[ ! "$window" =~ ^[0-9]+$ || "$window" -lt 1 ]]; then
  die "--window must be an integer >= 1"
fi

repo="$(cd "$repo" && pwd)"
ops_dir="$repo/.superloop/ops-manager/$loop_id"
telemetry_dir="$ops_dir/telemetry"

if [[ -z "$reconcile_file" ]]; then
  reconcile_file="$telemetry_dir/reconcile.jsonl"
fi
if [[ -z "$control_file" ]]; then
  control_file="$telemetry_dir/control.jsonl"
fi

if [[ ! -f "$reconcile_file" ]]; then
  die "reconcile telemetry file not found: $reconcile_file"
fi

reconcile_sample="$(mktemp)"
control_sample="$(mktemp)"
trap 'rm -f "$reconcile_sample" "$control_sample"' EXIT

tail -n "$window" "$reconcile_file" > "$reconcile_sample"
if [[ -f "$control_file" ]]; then
  tail -n "$window" "$control_file" > "$control_sample"
else
  : > "$control_sample"
fi

summary_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$(timestamp)" \
  --arg repo_path "$repo" \
  --arg loop_id "$loop_id" \
  --arg reconcile_file "$reconcile_file" \
  --arg control_file "$control_file" \
  --argjson window "$window" \
  --slurpfile rec "$reconcile_sample" \
  --slurpfile ctl "$control_sample" '
  def percentile($arr; $p):
    if ($arr | length) == 0 then null
    else ($arr | sort | .[((($arr | length) - 1) * $p | floor)])
    end;
  def ratio($num; $den): if $den == 0 then 0 else ($num / $den) end;
  def freq_map($arr):
    ($arr
      | group_by(.)
      | map({code: .[0], count: length})
      | sort_by(.count)
      | reverse);

  ($rec // []) as $reconcile
  | ($ctl // []) as $control
  | ($reconcile | length) as $attempts
  | ($reconcile | map(select(.status == "success")) | length) as $success_count
  | ($reconcile | map(select(.status == "failed")) | length) as $failed_count
  | ($reconcile | map(select(.healthStatus == "degraded")) | length) as $degraded_count
  | ($reconcile | map(select(.healthStatus == "critical")) | length) as $critical_count
  | ($reconcile | map(.healthReasonCodes[]?)) as $all_reason_codes
  | ($reconcile | map(.durationSeconds | tonumber? // empty)) as $durations
  | ($control | map(select(.status == "ambiguous" or .reasonCode == "control_ambiguous")) | length) as $ambiguous_count
  | ratio($failed_count; $attempts) as $failed_rate
  | ratio($degraded_count; $attempts) as $degraded_rate
  | ratio($critical_count; $attempts) as $critical_rate
  | (if $attempts >= 100 then "high" elif $attempts >= 30 then "medium" else "low" end) as $confidence
  | (if $attempts == 0 then "balanced"
     elif ($critical_rate >= 0.20 or $failed_rate >= 0.25) then "relaxed"
     elif ($critical_rate == 0 and $degraded_rate <= 0.05 and $failed_rate <= 0.02 and $ambiguous_count == 0) then "strict"
     else "balanced"
     end) as $recommended_profile
  | (if $attempts == 0 then "No telemetry window yet; keep balanced defaults"
     elif $recommended_profile == "relaxed" then "Observed high critical/failure rates; reduce alert noise while stabilizing"
     elif $recommended_profile == "strict" then "Observed stable healthy runs; tighten thresholds for faster detection"
     else "Observed mixed signals; keep balanced thresholds"
     end) as $rationale
  | {
      schemaVersion: $schema_version,
      generatedAt: $generated_at,
      source: {
        repoPath: $repo_path,
        loopId: $loop_id,
        reconcileTelemetryFile: $reconcile_file,
        controlTelemetryFile: $control_file,
        window: $window
      },
      observed: {
        reconcileAttempts: $attempts,
        reconcileSuccessCount: $success_count,
        reconcileFailedCount: $failed_count,
        health: {
          degradedCount: $degraded_count,
          criticalCount: $critical_count,
          degradedRate: $degraded_rate,
          criticalRate: $critical_rate,
          reasonCodeFrequency: freq_map($all_reason_codes)
        },
        control: {
          ambiguousCount: $ambiguous_count
        },
        durationSeconds: {
          p50: percentile($durations; 0.50),
          p95: percentile($durations; 0.95),
          max: (if ($durations | length) == 0 then null else ($durations | max) end)
        }
      },
      recommendedProfile: $recommended_profile,
      confidence: $confidence,
      rationale: $rationale
    }')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$summary_json"
else
  jq -c '.' <<<"$summary_json"
fi
