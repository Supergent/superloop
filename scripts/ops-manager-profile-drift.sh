#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-profile-drift.sh --repo <path> --loop <id> [options]

Options:
  --applied-profile <name>             Applied threshold profile.
  --recommended-profile <name>         Recommended threshold profile.
  --thresholds-file <path>             Threshold profile catalog JSON path.
  --recommendation-confidence <level>  Recommendation confidence (low|medium|high).
  --min-confidence <level>             Minimum confidence to count mismatch (default: medium).
  --required-streak <n>                Consecutive eligible mismatches to activate drift (default: 3).
  --summary-window <n>                 Summary window metadata (default: 200).
  --rationale <text>                   Recommendation rationale text.
  --drift-state-file <path>            Drift state JSON path. Default: <repo>/.superloop/ops-manager/<loop>/profile-drift.json
  --drift-history-file <path>          Drift history JSONL path. Default: <repo>/.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl
  --pretty                             Pretty-print output JSON.
  --help                               Show this help message.
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

confidence_rank() {
  case "$1" in
    low) echo 1 ;;
    medium) echo 2 ;;
    high) echo 3 ;;
    *) return 1 ;;
  esac
}

repo=""
loop_id=""
applied_profile=""
recommended_profile=""
thresholds_file=""
recommendation_confidence="low"
min_confidence="medium"
required_streak="3"
summary_window="200"
rationale=""
drift_state_file=""
drift_history_file=""
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
    --applied-profile)
      applied_profile="${2:-}"
      shift 2
      ;;
    --recommended-profile)
      recommended_profile="${2:-}"
      shift 2
      ;;
    --thresholds-file)
      thresholds_file="${2:-}"
      shift 2
      ;;
    --recommendation-confidence)
      recommendation_confidence="${2:-}"
      shift 2
      ;;
    --min-confidence)
      min_confidence="${2:-}"
      shift 2
      ;;
    --required-streak)
      required_streak="${2:-}"
      shift 2
      ;;
    --summary-window)
      summary_window="${2:-}"
      shift 2
      ;;
    --rationale)
      rationale="${2:-}"
      shift 2
      ;;
    --drift-state-file)
      drift_state_file="${2:-}"
      shift 2
      ;;
    --drift-history-file)
      drift_history_file="${2:-}"
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
if [[ ! "$required_streak" =~ ^[0-9]+$ || "$required_streak" -lt 1 ]]; then
  die "--required-streak must be an integer >= 1"
fi
if [[ ! "$summary_window" =~ ^[0-9]+$ || "$summary_window" -lt 1 ]]; then
  die "--summary-window must be an integer >= 1"
fi
if ! confidence_rank "$recommendation_confidence" >/dev/null; then
  die "--recommendation-confidence must be one of: low, medium, high"
fi
if ! confidence_rank "$min_confidence" >/dev/null; then
  die "--min-confidence must be one of: low, medium, high"
fi

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
ops_dir="$repo/.superloop/ops-manager/$loop_id"
telemetry_dir="$ops_dir/telemetry"

if [[ -z "$thresholds_file" && -n "${OPS_MANAGER_THRESHOLD_PROFILES_FILE:-}" ]]; then
  thresholds_file="$OPS_MANAGER_THRESHOLD_PROFILES_FILE"
fi
if [[ -z "$thresholds_file" ]]; then
  thresholds_file="$root_dir/config/ops-manager-threshold-profiles.v1.json"
fi
if ! jq -e '.profiles | type == "object"' "$thresholds_file" >/dev/null 2>&1; then
  die "invalid threshold profiles file: $thresholds_file"
fi
if [[ -n "$applied_profile" ]] && ! jq -e --arg p "$applied_profile" '.profiles[$p] != null' "$thresholds_file" >/dev/null 2>&1; then
  die "unknown applied profile: $applied_profile"
fi
if [[ -n "$recommended_profile" ]] && ! jq -e --arg p "$recommended_profile" '.profiles[$p] != null' "$thresholds_file" >/dev/null 2>&1; then
  die "unknown recommended profile: $recommended_profile"
fi

if [[ -z "$drift_state_file" ]]; then
  drift_state_file="$ops_dir/profile-drift.json"
fi
if [[ -z "$drift_history_file" ]]; then
  drift_history_file="$telemetry_dir/profile-drift.jsonl"
fi

mkdir -p "$(dirname "$drift_state_file")"
mkdir -p "$(dirname "$drift_history_file")"

previous_json='{}'
if [[ -f "$drift_state_file" ]]; then
  previous_json=$(jq -c '.' "$drift_state_file" 2>/dev/null) || die "invalid drift state JSON: $drift_state_file"
fi

previous_streak=$(jq -r '.mismatchStreak // 0' <<<"$previous_json")
if [[ ! "$previous_streak" =~ ^[0-9]+$ ]]; then
  previous_streak=0
fi
previous_active=$(jq -r '.driftActive // false' <<<"$previous_json")

recommendation_rank=$(confidence_rank "$recommendation_confidence")
minimum_rank=$(confidence_rank "$min_confidence")
confidence_ok="false"
if (( recommendation_rank >= minimum_rank )); then
  confidence_ok="true"
fi

mismatch="false"
if [[ -n "$applied_profile" && -n "$recommended_profile" && "$applied_profile" != "$recommended_profile" ]]; then
  mismatch="true"
fi

eligible_mismatch="false"
if [[ "$mismatch" == "true" && "$confidence_ok" == "true" ]]; then
  eligible_mismatch="true"
fi

mismatch_streak=0
if [[ "$eligible_mismatch" == "true" ]]; then
  mismatch_streak=$(( previous_streak + 1 ))
fi

drift_active="false"
if (( mismatch_streak >= required_streak )); then
  drift_active="true"
fi

transition_to_active="false"
transition_to_resolved="false"
if [[ "$drift_active" == "true" && "$previous_active" != "true" ]]; then
  transition_to_active="true"
fi
if [[ "$drift_active" != "true" && "$previous_active" == "true" ]]; then
  transition_to_resolved="true"
fi

status="aligned"
reason_code=""
if [[ -z "$recommended_profile" ]]; then
  status="no_recommendation"
elif [[ "$mismatch" != "true" ]]; then
  status="aligned"
elif [[ "$confidence_ok" != "true" ]]; then
  status="insufficient_confidence"
elif [[ "$drift_active" == "true" ]]; then
  status="drift_active"
  reason_code="profile_drift_detected"
else
  status="mismatch_pending"
fi

drift_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg updated_at "$(timestamp)" \
  --arg loop_id "$loop_id" \
  --arg applied_profile "$applied_profile" \
  --arg recommended_profile "$recommended_profile" \
  --arg recommendation_confidence "$recommendation_confidence" \
  --arg min_confidence "$min_confidence" \
  --argjson required_streak "$required_streak" \
  --argjson summary_window "$summary_window" \
  --argjson mismatch_streak "$mismatch_streak" \
  --argjson recommendation_rank "$recommendation_rank" \
  --argjson minimum_rank "$minimum_rank" \
  --argjson mismatch "$mismatch" \
  --argjson confidence_ok "$confidence_ok" \
  --argjson eligible_mismatch "$eligible_mismatch" \
  --argjson drift_active "$drift_active" \
  --argjson transition_to_active "$transition_to_active" \
  --argjson transition_to_resolved "$transition_to_resolved" \
  --arg status "$status" \
  --arg reason_code "$reason_code" \
  --arg rationale "$rationale" \
  '{
    schemaVersion: $schema_version,
    updatedAt: $updated_at,
    loopId: $loop_id,
    status: $status,
    reasonCode: (if ($reason_code | length) > 0 then $reason_code else null end),
    appliedProfile: (if ($applied_profile | length) > 0 then $applied_profile else null end),
    recommendedProfile: (if ($recommended_profile | length) > 0 then $recommended_profile else null end),
    recommendationConfidence: $recommendation_confidence,
    minimumConfidence: $min_confidence,
    recommendationRank: $recommendation_rank,
    minimumRank: $minimum_rank,
    requiredStreak: $required_streak,
    summaryWindow: $summary_window,
    mismatch: $mismatch,
    confidenceOk: $confidence_ok,
    eligibleMismatch: $eligible_mismatch,
    mismatchStreak: $mismatch_streak,
    driftActive: $drift_active,
    transitioned: {
      toActive: $transition_to_active,
      toResolved: $transition_to_resolved
    },
    rationale: (if ($rationale | length) > 0 then $rationale else null end),
    action: (
      if $drift_active == true then "review_threshold_profile"
      elif $status == "mismatch_pending" then "monitor_additional_windows"
      elif $status == "insufficient_confidence" then "collect_more_confident_telemetry"
      else null
      end
    )
  } | with_entries(select(.value != null))')

jq -c '.' <<<"$drift_json" > "$drift_state_file"

history_entry=$(jq -cn \
  --arg timestamp "$(timestamp)" \
  --arg loop_id "$loop_id" \
  --argjson drift "$drift_json" \
  '{
    timestamp: $timestamp,
    loopId: $loop_id,
    category: "profile_drift_evaluation",
    drift: $drift
  }')
printf '%s\n' "$history_entry" >> "$drift_history_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$drift_json"
else
  jq -c '.' <<<"$drift_json"
fi
