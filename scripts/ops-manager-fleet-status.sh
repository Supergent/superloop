#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-fleet-status.sh --repo <path> [options]

Options:
  --registry-file <path>         Fleet registry JSON path. Default: <repo>/.superloop/ops-manager/fleet/registry.v1.json
  --fleet-state-file <path>      Fleet state JSON path. Default: <repo>/.superloop/ops-manager/fleet/state.json
  --policy-state-file <path>     Fleet policy state JSON path. Default: <repo>/.superloop/ops-manager/fleet/policy-state.json
  --fleet-telemetry-file <path>  Fleet reconcile telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/reconcile.jsonl
  --pretty                       Pretty-print output JSON.
  --help                         Show this help message.
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
registry_file=""
fleet_state_file=""
policy_state_file=""
fleet_telemetry_file=""
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
    --fleet-telemetry-file)
      fleet_telemetry_file="${2:-}"
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
if [[ -z "$fleet_telemetry_file" ]]; then
  fleet_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/reconcile.jsonl"
fi

if [[ ! -f "$fleet_state_file" ]]; then
  die "fleet state file not found: $fleet_state_file"
fi

registry_json=$("$registry_script" --repo "$repo" --registry-file "$registry_file")
fleet_state_json=$(jq -c '.' "$fleet_state_file" 2>/dev/null) || die "invalid fleet state JSON: $fleet_state_file"

policy_state_json='null'
if [[ -f "$policy_state_file" ]]; then
  policy_state_json=$(jq -c '.' "$policy_state_file" 2>/dev/null) || die "invalid policy state JSON: $policy_state_file"
fi

latest_fleet_telemetry='null'
if [[ -f "$fleet_telemetry_file" ]]; then
  if line=$(tail -n 1 "$fleet_telemetry_file" 2>/dev/null); then
    if [[ -n "$line" ]]; then
      latest_fleet_telemetry=$(jq -c '.' <<<"$line" 2>/dev/null || echo 'null')
    fi
  fi
fi

status_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$(timestamp)" \
  --arg repo_path "$repo" \
  --arg registry_file "$registry_file" \
  --arg fleet_state_file "$fleet_state_file" \
  --arg policy_state_file "$policy_state_file" \
  --arg fleet_telemetry_file "$fleet_telemetry_file" \
  --argjson registry "$registry_json" \
  --argjson fleet "$fleet_state_json" \
  --argjson policy "$policy_state_json" \
  --argjson last_telemetry "$latest_fleet_telemetry" \
  '
  ($fleet.results // []) as $results
  | {
      schemaVersion: $schema_version,
      generatedAt: $generated_at,
      source: {
        repoPath: $repo_path,
        fleetId: ($fleet.fleetId // $registry.fleetId // "default")
      },
      fleet: {
        status: ($fleet.status // "unknown"),
        reasonCodes: ($fleet.reasonCodes // []),
        loopCount: ($fleet.loopCount // ($results | length)),
        successCount: ($fleet.successCount // ([ $results[] | select(.status == "success") ] | length)),
        failedCount: ($fleet.failedCount // ([ $results[] | select(.status == "failed") ] | length)),
        skippedCount: ($fleet.skippedCount // ([ $results[] | select(.status == "skipped") ] | length)),
        startedAt: ($fleet.startedAt // null),
        updatedAt: ($fleet.updatedAt // null),
        durationSeconds: ($fleet.durationSeconds // null),
        traceId: ($fleet.traceId // null),
        partialFailure: (
          (($fleet.failedCount // 0) > 0) and (($fleet.successCount // 0) > 0)
        )
      },
      healthRollup: {
        healthy: ([ $results[] | select((.healthStatus // "unknown") == "healthy") ] | length),
        degraded: ([ $results[] | select((.healthStatus // "unknown") == "degraded") ] | length),
        critical: ([ $results[] | select((.healthStatus // "unknown") == "critical") ] | length),
        unknown: ([ $results[] | select((.healthStatus // "unknown") == "unknown") ] | length)
      },
      exceptions: {
        reconcileFailures: ([ $results[] | select(.status == "failed") | .loopId ] | unique),
        criticalLoops: ([ $results[] | select(.healthStatus == "critical") | .loopId ] | unique),
        degradedLoops: ([ $results[] | select(.healthStatus == "degraded") | .loopId ] | unique),
        skippedLoops: ([ $results[] | select(.status == "skipped") | .loopId ] | unique)
      },
      policy: (
        if $policy == null then null
        else {
          mode: ($policy.mode // "advisory"),
          candidateCount: ($policy.candidateCount // 0),
          unsuppressedCount: ($policy.unsuppressedCount // 0),
          suppressedCount: ($policy.suppressedCount // 0),
          reasonCodes: ($policy.reasonCodes // []),
          topCandidates: (
            ($policy.candidates // [])
            | sort_by(
                if .severity == "critical" then 0
                elif .severity == "warning" then 1
                else 2
                end
              )
            | .[0:5]
          ),
          traceId: ($policy.traceId // null),
          updatedAt: ($policy.updatedAt // null)
        } | with_entries(select(.value != null))
        end
      ),
      loops: (
        $results
        | map({
            loopId: .loopId,
            status: (.status // "unknown"),
            reasonCode: (.reasonCode // null),
            reconcileStatus: (.reconcileStatus // null),
            healthStatus: (.healthStatus // "unknown"),
            healthReasonCodes: (.healthReasonCodes // []),
            transitionState: (.transitionState // null),
            durationSeconds: (.durationSeconds // null),
            traceId: (.traceId // null),
            transport: (.transport // "local"),
            sprite: (.sprite // {}),
            artifacts: {
              stateFile: (.files.stateFile // null),
              healthFile: (.files.healthFile // null),
              cursorFile: (.files.cursorFile // null),
              reconcileTelemetryFile: (.files.reconcileTelemetryFile // null)
            }
          } | with_entries(select(.value != null)))
      ),
      traceLinkage: {
        fleetTraceId: ($fleet.traceId // null),
        policyTraceId: ($policy.traceId // null),
        loopTraceIds: ([ $results[] | .traceId // empty ] | unique),
        sharedTraceId: (
          [ $results[] | .traceId // empty ]
          | unique as $ids
          | if ($ids | length) == 1 and ($ids[0] // "") != "" and (($fleet.traceId // "") == "" or $ids[0] == ($fleet.traceId // "")) then
              $ids[0]
            else
              null
            end
        )
      },
      latestTelemetry: (
        if $last_telemetry == null then null
        else {
          timestamp: ($last_telemetry.timestamp // null),
          status: ($last_telemetry.status // null),
          reasonCodes: ($last_telemetry.reasonCodes // [])
        } | with_entries(select(.value != null))
        end
      ),
      files: {
        registryFile: $registry_file,
        fleetStateFile: $fleet_state_file,
        policyStateFile: $policy_state_file,
        fleetTelemetryFile: $fleet_telemetry_file
      }
    }
  | .fleet.reasonCodes = (
      (
        .fleet.reasonCodes
        + (if .fleet.failedCount > 0 and .fleet.successCount > 0 then ["fleet_partial_failure"] else [] end)
        + (if .healthRollup.critical > 0 then ["fleet_health_critical"]
           elif .healthRollup.degraded > 0 then ["fleet_health_degraded"]
           else [] end)
      )
      | unique
    )
  ')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$status_json"
else
  jq -c '.' <<<"$status_json"
fi
