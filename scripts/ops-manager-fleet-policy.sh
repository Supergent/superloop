#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-fleet-policy.sh --repo <path> [options]

Options:
  --registry-file <path>        Fleet registry JSON path. Default: <repo>/.superloop/ops-manager/fleet/registry.v1.json
  --fleet-state-file <path>     Fleet state JSON path. Default: <repo>/.superloop/ops-manager/fleet/state.json
  --policy-state-file <path>    Policy state JSON output path. Default: <repo>/.superloop/ops-manager/fleet/policy-state.json
  --policy-telemetry-file <path> Policy telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/policy.jsonl
  --trace-id <id>               Policy trace id override. Default: fleet state trace id or generated.
  --pretty                      Pretty-print output JSON.
  --help                        Show this help message.
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

repo=""
registry_file=""
fleet_state_file=""
policy_state_file=""
policy_telemetry_file=""
trace_id=""
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --registry-file)
      registry_file="${2:-}"
      shift 2
      ;;
    --fleet-state-file)
      fleet_state_file="${2:-}"
      shift 2
      ;;
    --policy-state-file)
      policy_state_file="${2:-}"
      shift 2
      ;;
    --policy-telemetry-file)
      policy_telemetry_file="${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="${2:-}"
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

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
registry_script="${OPS_MANAGER_FLEET_REGISTRY_SCRIPT:-$script_dir/ops-manager-fleet-registry.sh}"

if [[ -z "$registry_file" ]]; then
  registry_file="$repo/.superloop/ops-manager/fleet/registry.v1.json"
fi
if [[ -z "$fleet_state_file" ]]; then
  fleet_state_file="$repo/.superloop/ops-manager/fleet/state.json"
fi
if [[ -z "$policy_state_file" ]]; then
  policy_state_file="$repo/.superloop/ops-manager/fleet/policy-state.json"
fi
if [[ -z "$policy_telemetry_file" ]]; then
  policy_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/policy.jsonl"
fi

if [[ ! -f "$fleet_state_file" ]]; then
  die "fleet state file not found: $fleet_state_file"
fi

registry_json=$("$registry_script" --repo "$repo" --registry-file "$registry_file")
fleet_state_json=$(jq -c '.' "$fleet_state_file" 2>/dev/null) || die "invalid fleet state JSON: $fleet_state_file"

if [[ -z "$trace_id" ]]; then
  trace_id="$(jq -r '.traceId // empty' <<<"$fleet_state_json")"
fi
if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

mkdir -p "$(dirname "$policy_state_file")"
mkdir -p "$(dirname "$policy_telemetry_file")"

policy_mode="$(jq -r '.policy.mode // "advisory"' <<<"$registry_json")"
if [[ "$policy_mode" != "advisory" ]]; then
  die "unsupported policy mode in phase 8 baseline: $policy_mode"
fi

suppressions_json="$(jq -c '.policy.suppressions // {}' <<<"$registry_json")"

candidates_json=$(jq -cn \
  --argjson results "$(jq -c '.results // []' <<<"$fleet_state_json")" \
  --argjson suppressions "$suppressions_json" \
  '
  def suppression_matches($loop_id; $category):
    ((($suppressions[$loop_id] // []) + ($suppressions["*"] // [])) | index($category)) != null;

  [
    $results[] as $r
    | [
        (if ($r.status // "") == "failed" then {
          loopId: $r.loopId,
          category: "reconcile_failed",
          severity: "critical",
          confidence: "high",
          rationale: "Loop reconcile failed in fleet fan-out",
          recommendedIntent: null,
          traceId: ($r.traceId // null)
        } else empty end),
        (if ($r.healthStatus // "") == "critical" then {
          loopId: $r.loopId,
          category: "health_critical",
          severity: "critical",
          confidence: "high",
          rationale: "Loop health is critical",
          recommendedIntent: null,
          traceId: ($r.traceId // null)
        } else empty end),
        (if ($r.healthStatus // "") == "degraded" then {
          loopId: $r.loopId,
          category: "health_degraded",
          severity: "warning",
          confidence: "medium",
          rationale: "Loop health is degraded",
          recommendedIntent: null,
          traceId: ($r.traceId // null)
        } else empty end)
      ]
      | .[]
      | . as $candidate
      | . + {
          suppressed: suppression_matches($candidate.loopId; $candidate.category),
          suppressionReason: (
            if suppression_matches($candidate.loopId; $candidate.category) then
              "registry_policy_suppression"
            else
              null
            end
          )
        }
  ]
  ')

policy_state_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg updated_at "$(timestamp)" \
  --arg fleet_id "$(jq -r '.fleetId // "default"' <<<"$fleet_state_json")" \
  --arg trace_id "$trace_id" \
  --arg mode "$policy_mode" \
  --arg fleet_status "$(jq -r '.status // "unknown"' <<<"$fleet_state_json")" \
  --arg fleet_state_file "$fleet_state_file" \
  --arg registry_file "$registry_file" \
  --argjson evaluated_loop_count "$(jq -r '.results | length' <<<"$fleet_state_json")" \
  --argjson candidates "$candidates_json" \
  --argjson suppressions "$suppressions_json" \
  '
  {
    schemaVersion: $schema_version,
    updatedAt: $updated_at,
    fleetId: $fleet_id,
    traceId: $trace_id,
    mode: $mode,
    fleetStatus: $fleet_status,
    source: {
      fleetStateFile: $fleet_state_file,
      registryFile: $registry_file
    },
    evaluatedLoopCount: $evaluated_loop_count,
    candidateCount: ($candidates | length),
    unsuppressedCount: ([ $candidates[] | select((.suppressed // false) == false) ] | length),
    suppressedCount: ([ $candidates[] | select((.suppressed // false) == true) ] | length),
    candidates: $candidates,
    summary: {
      bySeverity: {
        critical: ([ $candidates[] | select(.severity == "critical") ] | length),
        warning: ([ $candidates[] | select(.severity == "warning") ] | length),
        info: ([ $candidates[] | select(.severity == "info") ] | length)
      },
      byCategory: (
        reduce $candidates[] as $candidate ({}; .[$candidate.category] = ((.[$candidate.category] // 0) + 1))
      )
    },
    suppressionState: {
      suppressions: $suppressions
    }
  }
  | .reasonCodes = (
      [
        (if .unsuppressedCount > 0 then "fleet_action_required" else "no_action_required" end),
        (if .suppressedCount > 0 then "fleet_actions_suppressed" else empty end)
      ]
      | unique
    )
  ')

jq -c '.' <<<"$policy_state_json" > "$policy_state_file"

jq -cn \
  --arg timestamp "$(timestamp)" \
  --arg fleet_id "$(jq -r '.fleetId // "default"' <<<"$fleet_state_json")" \
  --arg trace_id "$trace_id" \
  --arg mode "$policy_mode" \
  --argjson summary "$(jq -c '{candidateCount, unsuppressedCount, suppressedCount, reasonCodes, summary}' <<<"$policy_state_json")" \
  '{
    timestamp: $timestamp,
    category: "fleet_policy",
    fleetId: $fleet_id,
    traceId: $trace_id,
    mode: $mode,
    summary: $summary
  }' >> "$policy_telemetry_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$policy_state_json"
else
  jq -c '.' <<<"$policy_state_json"
fi
