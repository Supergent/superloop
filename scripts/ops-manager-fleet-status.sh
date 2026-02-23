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
  --handoff-state-file <path>    Fleet handoff state JSON path. Default: <repo>/.superloop/ops-manager/fleet/handoff-state.json
  --handoff-telemetry-file <path> Fleet handoff telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/handoff.jsonl
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
handoff_state_file=""
handoff_telemetry_file=""
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
    --handoff-state-file)
      handoff_state_file="${2:-}"
      shift 2
      ;;
    --handoff-telemetry-file)
      handoff_telemetry_file="${2:-}"
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
if [[ -z "$handoff_state_file" ]]; then
  handoff_state_file="$repo/.superloop/ops-manager/fleet/handoff-state.json"
fi
if [[ -z "$handoff_telemetry_file" ]]; then
  handoff_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl"
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

handoff_state_json='null'
if [[ -f "$handoff_state_file" ]]; then
  handoff_state_json=$(jq -c '.' "$handoff_state_file" 2>/dev/null) || die "invalid handoff state JSON: $handoff_state_file"
fi

latest_handoff_telemetry='null'
if [[ -f "$handoff_telemetry_file" ]]; then
  if line=$(tail -n 1 "$handoff_telemetry_file" 2>/dev/null); then
    if [[ -n "$line" ]]; then
      latest_handoff_telemetry=$(jq -c '.' <<<"$line" 2>/dev/null || echo 'null')
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
  --arg handoff_state_file "$handoff_state_file" \
  --arg handoff_telemetry_file "$handoff_telemetry_file" \
  --argjson registry "$registry_json" \
  --argjson fleet "$fleet_state_json" \
  --argjson policy "$policy_state_json" \
  --argjson handoff "$handoff_state_json" \
  --argjson last_telemetry "$latest_fleet_telemetry" \
  --argjson last_handoff_telemetry "$latest_handoff_telemetry" \
  '
  ($fleet.results // []) as $results
  | ($handoff.execution // {}) as $handoff_execution
  | ($handoff_execution.results // []) as $handoff_results
  | ($policy.summary.byAutonomyReason // {}) as $policy_autonomy_reasons
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
      handoff: (
        if $handoff == null then null
        else {
          mode: ($handoff.mode // null),
          reasonCodes: ($handoff.reasonCodes // []),
          summary: {
            intentCount: ($handoff.summary.intentCount // (($handoff.intents // []) | length)),
            autoEligibleIntentCount: ($handoff.summary.autoEligibleIntentCount // 0),
            manualOnlyIntentCount: ($handoff.summary.manualOnlyIntentCount // 0),
            pendingConfirmationCount: ($handoff.summary.pendingConfirmationCount // 0),
            executedCount: ($handoff.summary.executedCount // 0),
            ambiguousCount: ($handoff.summary.ambiguousCount // 0),
            failedCount: ($handoff.summary.failedCount // 0)
          },
          execution: {
            mode: ($handoff_execution.mode // null),
            requestedBy: ($handoff_execution.requestedBy // null),
            requestedAt: ($handoff_execution.requestedAt // null),
            completedAt: ($handoff_execution.completedAt // null),
            requestedIntentCount: ($handoff_execution.requestedIntentCount // 0),
            executedIntentCount: ($handoff_execution.executedIntentCount // 0),
            executedCount: ($handoff_execution.executedCount // 0),
            ambiguousCount: ($handoff_execution.ambiguousCount // 0),
            failedCount: ($handoff_execution.failedCount // 0),
            byReasonCode: (
              reduce ($handoff_results[] | .reasonCode // empty) as $code ({};
                .[$code] = ((.[$code] // 0) + 1)
              )
            )
          } | with_entries(select(.value != null)),
          byAutonomyReason: (
            reduce (($handoff.intents // [])[] | (.autonomous.reasons // [])[]?) as $reason ({};
              .[$reason] = ((.[$reason] // 0) + 1)
            )
          ),
          pendingManualOnlyCount: (
            [ ($handoff.intents // [])[] | select((.status // "") == "pending_operator_confirmation" and (.autonomous.manualOnly // false) == true) ]
            | length
          ),
          traceId: ($handoff.traceId // null),
          updatedAt: ($handoff.updatedAt // null)
        } | with_entries(select(.value != null))
        end
      ),
      autonomous: (
        if $policy == null and $handoff == null then null
        else {
          mode: (
            if $policy != null then ($policy.mode // "advisory")
            elif $handoff != null then ($handoff.mode // "advisory")
            else "advisory"
            end
          ),
          enabled: (
            if $policy != null then (($policy.mode // "advisory") == "guarded_auto")
            elif $handoff != null then (($handoff.mode // "advisory") == "guarded_auto")
            else false
            end
          ),
          policyReasonCodes: (if $policy == null then [] else ($policy.reasonCodes // []) end),
          handoffReasonCodes: (if $handoff == null then [] else ($handoff.reasonCodes // []) end),
          eligibleCandidateCount: (if $policy == null then 0 else ($policy.autoEligibleCount // 0) end),
          manualOnlyCandidateCount: (if $policy == null then 0 else ($policy.manualOnlyCount // 0) end),
          safetyGateDecisions: {
            byReason: $policy_autonomy_reasons,
            blockedCount: (
              ($policy_autonomy_reasons.autonomous_rollout_scope_excluded // 0)
              + ($policy_autonomy_reasons.autonomous_rollout_canary_excluded // 0)
              + ($policy_autonomy_reasons.autonomous_rollout_paused_manual // 0)
              + ($policy_autonomy_reasons.autonomous_rollout_paused_auto // 0)
              + ($policy_autonomy_reasons.autonomous_autopause_ambiguous_spike // 0)
              + ($policy_autonomy_reasons.autonomous_autopause_failure_spike // 0)
              + ($policy_autonomy_reasons.autonomous_kill_switch_enabled // 0)
              + ($policy_autonomy_reasons.autonomous_cooldown_active // 0)
              + ($policy_autonomy_reasons.autonomous_max_actions_per_run_exceeded // 0)
              + ($policy_autonomy_reasons.autonomous_max_actions_per_loop_exceeded // 0)
            ),
            killSwitchActive: (
              if $policy == null then false
              else (($policy.autonomous.controls.safety.killSwitch // false) == true)
              end
            )
          },
          rollout: (
            if $policy == null then null
            else {
              canaryPercent: ($policy.autonomous.rollout.canaryPercent // null),
              scopeLoopIds: ($policy.autonomous.rollout.scopeLoopIds // []),
              selectorSalt: ($policy.autonomous.rollout.selectorSalt // null),
              candidateBuckets: {
                inScopeCount: ($policy.autonomous.rollout.candidateBuckets.inScopeCount // 0),
                inCohortCount: ($policy.autonomous.rollout.candidateBuckets.inCohortCount // 0),
                outOfCohortCount: ($policy.autonomous.rollout.candidateBuckets.outOfCohortCount // 0)
              },
              pause: {
                active: ($policy.autonomous.rollout.pause.active // false),
                reasons: ($policy.autonomous.rollout.pause.reasons // []),
                manual: ($policy.autonomous.rollout.pause.manual // false),
                auto: {
                  active: ($policy.autonomous.rollout.pause.auto.active // false),
                  reasons: ($policy.autonomous.rollout.pause.auto.reasons // []),
                  metrics: ($policy.autonomous.rollout.pause.auto.metrics // {})
                }
              }
            } | with_entries(select(.value != null))
            end
          ),
          handoff: (
            if $handoff == null then null
            else {
              autoEligibleIntentCount: ($handoff.summary.autoEligibleIntentCount // 0),
              manualOnlyIntentCount: ($handoff.summary.manualOnlyIntentCount // 0),
              pendingManualOnlyCount: (
                [ ($handoff.intents // [])[] | select((.status // "") == "pending_operator_confirmation" and (.autonomous.manualOnly // false) == true) ]
                | length
              ),
              executionMode: ($handoff_execution.mode // null),
              executedCount: ($handoff_execution.executedCount // 0),
              ambiguousCount: ($handoff_execution.ambiguousCount // 0),
              failedCount: ($handoff_execution.failedCount // 0),
              outcomeReasonCodes: (
                reduce ($handoff_results[] | .reasonCode // empty) as $code ({};
                  .[$code] = ((.[$code] // 0) + 1)
                )
              )
            } | with_entries(select(.value != null))
            end
          )
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
      latestHandoffTelemetry: (
        if $last_handoff_telemetry == null then null
        else {
          timestamp: ($last_handoff_telemetry.timestamp // null),
          category: ($last_handoff_telemetry.category // null),
          traceId: ($last_handoff_telemetry.traceId // null),
          execution: {
            mode: ($last_handoff_telemetry.execution.mode // null),
            requestedIntentCount: ($last_handoff_telemetry.execution.requestedIntentCount // null),
            executedCount: ($last_handoff_telemetry.execution.executedCount // null),
            ambiguousCount: ($last_handoff_telemetry.execution.ambiguousCount // null),
            failedCount: ($last_handoff_telemetry.execution.failedCount // null)
          } | with_entries(select(.value != null)),
          reasonCodes: ($last_handoff_telemetry.summary.reasonCodes // [])
        } | with_entries(select(.value != null))
        end
      ),
      files: {
        registryFile: $registry_file,
        fleetStateFile: $fleet_state_file,
        policyStateFile: $policy_state_file,
        fleetTelemetryFile: $fleet_telemetry_file,
        handoffStateFile: $handoff_state_file,
        handoffTelemetryFile: $handoff_telemetry_file
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
