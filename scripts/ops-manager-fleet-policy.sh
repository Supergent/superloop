#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-fleet-policy.sh --repo <path> [options]

Options:
  --registry-file <path>         Fleet registry JSON path. Default: <repo>/.superloop/ops-manager/fleet/registry.v1.json
  --fleet-state-file <path>      Fleet state JSON path. Default: <repo>/.superloop/ops-manager/fleet/state.json
  --policy-state-file <path>     Policy state JSON output path. Default: <repo>/.superloop/ops-manager/fleet/policy-state.json
  --handoff-telemetry-file <path> Fleet handoff telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/handoff.jsonl
  --policy-telemetry-file <path> Policy telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/policy.jsonl
  --policy-history-file <path>   Candidate history JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/policy-history.jsonl
  --dedupe-window-seconds <n>    Advisory cooldown window for duplicate candidates. Default: registry policy.noiseControls.dedupeWindowSeconds (or 300)
  --trace-id <id>                Policy trace id override. Default: fleet state trace id or generated.
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
handoff_telemetry_file=""
policy_telemetry_file=""
policy_history_file=""
dedupe_window_seconds=""
trace_id=""
pretty="0"
flag_dedupe_window_seconds="0"

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
    --handoff-telemetry-file)
      handoff_telemetry_file="${2:-}"
      shift 2
      ;;
    --policy-telemetry-file)
      policy_telemetry_file="${2:-}"
      shift 2
      ;;
    --policy-history-file)
      policy_history_file="${2:-}"
      shift 2
      ;;
    --dedupe-window-seconds)
      dedupe_window_seconds="${2:-}"
      flag_dedupe_window_seconds="1"
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
if [[ -z "$handoff_telemetry_file" ]]; then
  handoff_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl"
fi
if [[ -z "$policy_telemetry_file" ]]; then
  policy_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/policy.jsonl"
fi
if [[ -z "$policy_history_file" ]]; then
  policy_history_file="$repo/.superloop/ops-manager/fleet/telemetry/policy-history.jsonl"
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

policy_mode="$(jq -r '.policy.mode // "advisory"' <<<"$registry_json")"
if [[ "$policy_mode" != "advisory" && "$policy_mode" != "guarded_auto" ]]; then
  die "unsupported policy mode: $policy_mode"
fi

if [[ "$flag_dedupe_window_seconds" != "1" ]]; then
  dedupe_window_seconds="$(jq -r '.policy.noiseControls.dedupeWindowSeconds // 300' <<<"$registry_json")"
fi
if [[ ! "$dedupe_window_seconds" =~ ^[0-9]+$ ]]; then
  die "--dedupe-window-seconds must be a non-negative integer"
fi

mkdir -p "$(dirname "$policy_state_file")"
mkdir -p "$(dirname "$policy_telemetry_file")"
mkdir -p "$(dirname "$policy_history_file")"

suppressions_json="$(jq -c '.policy.suppressions // {}' <<<"$registry_json")"
autonomous_controls_json="$(jq -c '.policy.autonomous // {}' <<<"$registry_json")"
results_json="$(jq -c '.results // []' <<<"$fleet_state_json")"

history_json='[]'
if [[ -f "$policy_history_file" ]]; then
  history_json=$(jq -cs '.' "$policy_history_file" 2>/dev/null) || die "invalid policy history JSONL: $policy_history_file"
fi

handoff_history_json='[]'
if [[ -f "$handoff_telemetry_file" ]]; then
  handoff_history_json=$(jq -cs '.' "$handoff_telemetry_file" 2>/dev/null) || die "invalid handoff telemetry JSONL: $handoff_telemetry_file"
fi

current_timestamp="$(timestamp)"

candidates_json=$(jq -cn \
  --argjson results "$results_json" \
  --argjson suppressions "$suppressions_json" \
  --argjson history "$history_json" \
  --argjson dedupe_window "$dedupe_window_seconds" \
  --arg now "$current_timestamp" \
  '
  def category_profile($category):
    if $category == "reconcile_failed" then
      {severity: "critical", confidence: "high", rationale: "Loop reconcile failed in fleet fan-out"}
    elif $category == "health_critical" then
      {severity: "critical", confidence: "high", rationale: "Loop health is critical"}
    elif $category == "health_degraded" then
      {severity: "warning", confidence: "medium", rationale: "Loop health is degraded"}
    else
      error("unknown policy category: " + $category)
    end;

  def recommended_intent($category):
    if $category == "reconcile_failed" then "cancel"
    elif $category == "health_critical" then "cancel"
    elif $category == "health_degraded" then "cancel"
    else null
    end;

  def suppression_scope($loop_id; $category):
    if (($suppressions[$loop_id] // []) | index($category)) != null then "loop"
    elif (($suppressions["*"] // []) | index($category)) != null then "global"
    else null
    end;

  def last_unsuppressed_epoch($candidate_id):
    ([ $history[]?
       | select((.candidateId // "") == $candidate_id)
       | select((.suppressed // false) == false)
       | (.timestamp // empty)
       | fromdateiso8601?
     ] | max // null);

  ($now | fromdateiso8601) as $now_epoch
  | [
      $results[] as $r
      | [
          (if ($r.status // "") == "failed" then {
            loopId: $r.loopId,
            category: "reconcile_failed",
            signal: "status_failed",
            traceId: ($r.traceId // null)
          } else empty end),
          (if ($r.healthStatus // "") == "critical" then {
            loopId: $r.loopId,
            category: "health_critical",
            signal: "health_critical",
            traceId: ($r.traceId // null)
          } else empty end),
          (if ($r.healthStatus // "") == "degraded" then {
            loopId: $r.loopId,
            category: "health_degraded",
            signal: "health_degraded",
            traceId: ($r.traceId // null)
          } else empty end)
        ]
      | .[]
      | .candidateId = (.loopId + ":" + .category)
      | . + category_profile(.category)
      | .taxonomyVersion = "v1"
      | .recommendedIntent = recommended_intent(.category)
      | .suppressionScope = suppression_scope(.loopId; .category)
      | .suppressed = (.suppressionScope != null)
      | .suppressionReason = (if .suppressionScope == null then null else "registry_policy_suppression" end)
      | .suppressionSource = (
          if .suppressionScope == "loop" then "policy.suppressions.<loopId>"
          elif .suppressionScope == "global" then "policy.suppressions.*"
          else null
          end
        )
      | .cooldown = (
          if $dedupe_window <= 0 then {
            enabled: false,
            windowSeconds: $dedupe_window,
            active: false,
            remainingSeconds: 0,
            lastUnsuppressedAt: null
          } else
            (last_unsuppressed_epoch(.candidateId)) as $last_epoch
            | (if $last_epoch == null then null else ($now_epoch - $last_epoch) end) as $age
            | {
                enabled: true,
                windowSeconds: $dedupe_window,
                active: ($last_epoch != null and $age < $dedupe_window),
                remainingSeconds: (if $last_epoch != null and $age < $dedupe_window then ($dedupe_window - $age) else 0 end),
                lastUnsuppressedAt: (if $last_epoch == null then null else ($last_epoch | todateiso8601) end)
              }
          end
        )
      | if (.suppressed == false and (.cooldown.active // false)) then
          .suppressed = true
          | .suppressionScope = "cooldown"
          | .suppressionReason = "advisory_cooldown_active"
          | .suppressionSource = "policy.noiseControls.dedupeWindowSeconds"
        else
          .
        end
    ]
  | sort_by(.loopId, .category)
  | unique_by(.candidateId)
  ')

candidates_json=$(jq -cn \
  --arg mode "$policy_mode" \
  --argjson candidates "$candidates_json" \
  --argjson autonomous "$autonomous_controls_json" \
  --argjson history "$history_json" \
  --argjson handoff_history "$handoff_history_json" \
  --arg now "$current_timestamp" \
  '
  def severity_rank($severity):
    if $severity == "critical" then 3
    elif $severity == "warning" then 2
    elif $severity == "info" then 1
    else 0
    end;

  def confidence_rank($confidence):
    if $confidence == "high" then 3
    elif $confidence == "medium" then 2
    elif $confidence == "low" then 1
    else 0
    end;

  def last_autonomous_epoch($candidate_id):
    ([ $history[]?
       | select((.candidateId // "") == $candidate_id)
       | select((.autonomousEligible // false) == true)
       | (.timestamp // empty)
       | fromdateiso8601?
     ] | max // null);

  def bucket_for($seed):
    reduce ($seed | explode[]) as $cp (17; ((. * 31 + $cp) % 1000003))
    | . % 100;

  def to_rate($num; $den):
    if $den <= 0 then 0 else ($num / $den) end;

  def is_autonomous_handoff_event:
    (.category // "") == "fleet_handoff_execute"
    and (.execution.mode // "") == "autonomous";

  ($autonomous.allow.categories // []) as $allowed_categories
  | ($autonomous.allow.intents // []) as $allowed_intents
  | ($autonomous.thresholds.minSeverity // "critical") as $min_severity
  | ($autonomous.thresholds.minConfidence // "high") as $min_confidence
  | ($autonomous.safety.maxActionsPerRun // 1) as $max_actions_per_run
  | ($autonomous.safety.maxActionsPerLoop // 1) as $max_actions_per_loop
  | ($autonomous.safety.cooldownSeconds // 300) as $cooldown_seconds
  | ($autonomous.safety.killSwitch // false) as $kill_switch
  | ($autonomous.rollout // {}) as $rollout
  | ($rollout.canaryPercent // 100) as $canary_percent
  | ($rollout.scope.loopIds // []) as $scope_loop_ids
  | ($rollout.selector.salt // "fleet-autonomous-rollout-v1") as $rollout_salt
  | ($rollout.pause.manual // false) as $rollout_manual_pause
  | ($rollout.autoPause.enabled // true) as $autopause_enabled
  | ($rollout.autoPause.lookbackExecutions // 5) as $autopause_lookback
  | ($rollout.autoPause.minSampleSize // 3) as $autopause_min_samples
  | ($rollout.autoPause.ambiguityRateThreshold // 0.4) as $autopause_amb_threshold
  | ($rollout.autoPause.failureRateThreshold // 0.4) as $autopause_fail_threshold
  | ($now | fromdateiso8601) as $now_epoch
  | (
      [ $handoff_history[]?
        | select(is_autonomous_handoff_event)
      ]
      | sort_by(.timestamp // "")
      | (if $autopause_lookback > 0 then .[-$autopause_lookback:] else . end)
      | {
          windowExecutionCount: length,
          attemptedCount: ([ .[] | (.execution.executedIntentCount // .execution.requestedIntentCount // 0) ] | add // 0),
          executedCount: ([ .[] | (.execution.executedCount // 0) ] | add // 0),
          ambiguousCount: ([ .[] | (.execution.ambiguousCount // 0) ] | add // 0),
          failedCount: ([ .[] | (.execution.failedCount // 0) ] | add // 0)
        }
    ) as $autopause_metrics
  | ($autopause_metrics.attemptedCount) as $autopause_attempted
  | (to_rate($autopause_metrics.ambiguousCount; $autopause_attempted)) as $autopause_amb_rate
  | (to_rate($autopause_metrics.failedCount; $autopause_attempted)) as $autopause_fail_rate
  | ([
      (
        if $autopause_enabled
          and $autopause_attempted >= $autopause_min_samples
          and $autopause_amb_rate >= $autopause_amb_threshold
        then "autonomous_autopause_ambiguous_spike"
        else empty
        end
      ),
      (
        if $autopause_enabled
          and $autopause_attempted >= $autopause_min_samples
          and $autopause_fail_rate >= $autopause_fail_threshold
        then "autonomous_autopause_failure_spike"
        else empty
        end
      )
    ] | unique) as $autopause_trigger_reasons
  | (($autopause_trigger_reasons | length) > 0) as $autopause_triggered
  | ([
      (if $rollout_manual_pause then "autonomous_rollout_paused_manual" else empty end),
      (if $autopause_triggered then "autonomous_rollout_paused_auto" else empty end)
    ] | unique) as $rollout_pause_reasons
  | (($rollout_pause_reasons | length) > 0) as $rollout_pause_active
  | (
      ($candidates // [])
      | map(
          . as $candidate
          | ($candidate.recommendedIntent // null) as $recommended_intent
          | (($allowed_categories | index($candidate.category)) != null) as $category_allowed
          | (
              if $recommended_intent == null then
                false
              else
                (($allowed_intents | index($recommended_intent)) != null)
              end
            ) as $intent_allowed
          | (severity_rank($candidate.severity) >= severity_rank($min_severity)) as $severity_ok
          | (confidence_rank($candidate.confidence) >= confidence_rank($min_confidence)) as $confidence_ok
          | (($scope_loop_ids | length) == 0 or (($scope_loop_ids | index($candidate.loopId)) != null)) as $scope_allowed
          | (bucket_for(($candidate.loopId + "|" + $rollout_salt))) as $rollout_bucket
          | (
              if $canary_percent <= 0 then false
              elif $canary_percent >= 100 then true
              else ($rollout_bucket < $canary_percent)
              end
            ) as $canary_allowed
          | ($scope_allowed and $canary_allowed) as $cohort_allowed
          | ([
              (if $mode != "guarded_auto" then "policy_mode_not_guarded_auto" else empty end),
              (if ($candidate.suppressed // false) == true then "candidate_suppressed" else empty end),
              (if $category_allowed then empty else "category_not_allowlisted" end),
              (if $recommended_intent == null then "no_recommended_intent"
               elif $intent_allowed then empty
               else "intent_not_allowlisted"
               end),
              (if $severity_ok then empty else "severity_below_threshold" end),
              (if $confidence_ok then empty else "confidence_below_threshold" end)
            ] | unique) as $base_reasons
          | (([
              (if $scope_allowed then empty else "autonomous_rollout_scope_excluded" end),
              (if $scope_allowed and $canary_allowed then empty
               elif $scope_allowed then "autonomous_rollout_canary_excluded"
               else empty
               end),
              (if $rollout_manual_pause then "autonomous_rollout_paused_manual" else empty end),
              (if $autopause_triggered then "autonomous_rollout_paused_auto" else empty end)
            ] + $autopause_trigger_reasons) | unique) as $rollout_reasons
          | (($base_reasons + $rollout_reasons) | unique) as $gating_reasons
          | (last_autonomous_epoch($candidate.candidateId)) as $last_auto_epoch
          | (if $last_auto_epoch == null then null else ($now_epoch - $last_auto_epoch) end) as $auto_age
          | $candidate
          | .autonomous = {
              mode: $mode,
              eligible: false,
              manualOnly: true,
              reasons: $gating_reasons,
              gatingReasons: $gating_reasons,
              recommendedIntent: $recommended_intent,
              gates: {
                modeGuardedAuto: ($mode == "guarded_auto"),
                suppressed: ($candidate.suppressed // false),
                categoryAllowed: $category_allowed,
                intentAllowed: $intent_allowed,
                severityMeetsThreshold: $severity_ok,
                confidenceMeetsThreshold: $confidence_ok,
                rolloutScopeAllowed: $scope_allowed,
                rolloutCanarySelected: $canary_allowed
              },
              safety: {
                maxActionsPerRun: $max_actions_per_run,
                maxActionsPerLoop: $max_actions_per_loop,
                cooldownSeconds: $cooldown_seconds,
                killSwitch: $kill_switch,
                cooldown: {
                  active: ($cooldown_seconds > 0 and $last_auto_epoch != null and $auto_age < $cooldown_seconds),
                  remainingSeconds: (if $cooldown_seconds > 0 and $last_auto_epoch != null and $auto_age < $cooldown_seconds then ($cooldown_seconds - $auto_age) else 0 end),
                  lastEligibleAt: (if $last_auto_epoch == null then null else ($last_auto_epoch | todateiso8601) end)
                }
              },
              rollout: {
                canaryPercent: $canary_percent,
                scopeLoopIds: $scope_loop_ids,
                selector: {
                  salt: $rollout_salt,
                  bucket: $rollout_bucket,
                  inScope: $scope_allowed,
                  canarySelected: $canary_allowed,
                  inCohort: $cohort_allowed
                },
                pause: {
                  active: $rollout_pause_active,
                  reasons: $rollout_pause_reasons,
                  manual: $rollout_manual_pause,
                  auto: {
                    enabled: $autopause_enabled,
                    active: $autopause_triggered,
                    reasons: $autopause_trigger_reasons,
                    lookbackExecutions: $autopause_lookback,
                    minSampleSize: $autopause_min_samples,
                    ambiguityRateThreshold: $autopause_amb_threshold,
                    failureRateThreshold: $autopause_fail_threshold,
                    metrics: {
                      windowExecutionCount: $autopause_metrics.windowExecutionCount,
                      attemptedCount: $autopause_attempted,
                      executedCount: $autopause_metrics.executedCount,
                      ambiguousCount: $autopause_metrics.ambiguousCount,
                      failedCount: $autopause_metrics.failedCount,
                      ambiguityRate: $autopause_amb_rate,
                      failureRate: $autopause_fail_rate
                    }
                  }
                }
              }
            }
        )
      | sort_by(.loopId, .category)
    ) as $base_candidates
  | (
      reduce $base_candidates[] as $candidate (
        {
          selectedTotal: 0,
          selectedByLoop: {},
          items: []
        };
        ($candidate.autonomous.gatingReasons // []) as $gating_reasons
        | (($mode == "guarded_auto") and (($candidate.autonomous.safety.cooldown.active // false) == true)) as $cooldown_blocked
        | (($mode == "guarded_auto") and (.selectedTotal >= $max_actions_per_run)) as $run_cap_blocked
        | (($mode == "guarded_auto") and ((.selectedByLoop[$candidate.loopId] // 0) >= $max_actions_per_loop)) as $loop_cap_blocked
        | ([
            (if (($gating_reasons | length) == 0 and $mode == "guarded_auto" and $kill_switch == true) then "autonomous_kill_switch_enabled" else empty end),
            (if (($gating_reasons | length) == 0 and $mode == "guarded_auto" and $kill_switch == false and $cooldown_blocked) then "autonomous_cooldown_active" else empty end),
            (if (($gating_reasons | length) == 0 and $mode == "guarded_auto" and $kill_switch == false and $cooldown_blocked == false and $run_cap_blocked) then "autonomous_max_actions_per_run_exceeded" else empty end),
            (if (($gating_reasons | length) == 0 and $mode == "guarded_auto" and $kill_switch == false and $cooldown_blocked == false and $run_cap_blocked == false and $loop_cap_blocked) then "autonomous_max_actions_per_loop_exceeded" else empty end)
          ] | unique) as $safety_reasons
        | (($gating_reasons + $safety_reasons) | unique) as $final_reasons
        | (($final_reasons | length) == 0) as $eligible
        | (
            $candidate
            | .autonomous.eligible = $eligible
            | .autonomous.manualOnly = (if $eligible then false else true end)
            | .autonomous.reasons = $final_reasons
            | .autonomous.safety.killSwitchActive = ($mode == "guarded_auto" and $kill_switch == true)
            | .autonomous.safety.runCapBlocked = (($final_reasons | index("autonomous_max_actions_per_run_exceeded")) != null)
            | .autonomous.safety.loopCapBlocked = (($final_reasons | index("autonomous_max_actions_per_loop_exceeded")) != null)
          ) as $updated
        | .items += [$updated]
        | if $eligible then
            .selectedTotal += 1
            | .selectedByLoop[$candidate.loopId] = ((.selectedByLoop[$candidate.loopId] // 0) + 1)
          else
            .
          end
      )
      | .items
    )
  ')

policy_state_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg updated_at "$current_timestamp" \
  --arg fleet_id "$(jq -r '.fleetId // "default"' <<<"$fleet_state_json")" \
  --arg trace_id "$trace_id" \
  --arg mode "$policy_mode" \
  --arg fleet_status "$(jq -r '.status // "unknown"' <<<"$fleet_state_json")" \
  --arg fleet_state_file "$fleet_state_file" \
  --arg registry_file "$registry_file" \
  --arg policy_history_file "$policy_history_file" \
  --arg handoff_telemetry_file "$handoff_telemetry_file" \
  --argjson dedupe_window "$dedupe_window_seconds" \
  --argjson evaluated_loop_count "$(jq -r '.results | length' <<<"$fleet_state_json")" \
  --argjson candidates "$candidates_json" \
  --argjson autonomous_controls "$autonomous_controls_json" \
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
    taxonomy: {
      version: "v1",
      categories: [
        {category: "reconcile_failed", severity: "critical", confidence: "high"},
        {category: "health_critical", severity: "critical", confidence: "high"},
        {category: "health_degraded", severity: "warning", confidence: "medium"}
      ]
    },
    noiseControls: {
      dedupeWindowSeconds: $dedupe_window,
      policyHistoryFile: $policy_history_file,
      handoffTelemetryFile: $handoff_telemetry_file
    },
    autonomous: {
      enabled: ($mode == "guarded_auto"),
      controls: $autonomous_controls,
      rollout: {
        canaryPercent: ($autonomous_controls.rollout.canaryPercent // 100),
        scopeLoopIds: ($autonomous_controls.rollout.scope.loopIds // []),
        selectorSalt: ($autonomous_controls.rollout.selector.salt // "fleet-autonomous-rollout-v1"),
        candidateBuckets: {
          inScopeCount: ([ $candidates[] | select((.autonomous.rollout.selector.inScope // false) == true) ] | length),
          inCohortCount: ([ $candidates[] | select((.autonomous.rollout.selector.inCohort // false) == true) ] | length),
          outOfCohortCount: ([ $candidates[] | select((.autonomous.rollout.selector.inScope // false) == true and (.autonomous.rollout.selector.inCohort // false) == false) ] | length)
        },
        pause: (
          if ($candidates | length) == 0 then
            {
              active: false,
              reasons: [],
              manual: ($autonomous_controls.rollout.pause.manual // false),
              auto: {
                enabled: ($autonomous_controls.rollout.autoPause.enabled // true),
                active: false,
                reasons: [],
                lookbackExecutions: ($autonomous_controls.rollout.autoPause.lookbackExecutions // 5),
                minSampleSize: ($autonomous_controls.rollout.autoPause.minSampleSize // 3),
                ambiguityRateThreshold: ($autonomous_controls.rollout.autoPause.ambiguityRateThreshold // 0.4),
                failureRateThreshold: ($autonomous_controls.rollout.autoPause.failureRateThreshold // 0.4),
                metrics: {
                  windowExecutionCount: 0,
                  attemptedCount: 0,
                  executedCount: 0,
                  ambiguousCount: 0,
                  failedCount: 0,
                  ambiguityRate: 0,
                  failureRate: 0
                }
              }
            }
          else
            ($candidates[0].autonomous.rollout.pause // {}) as $pause
            | {
                active: ($pause.active // false),
                reasons: ($pause.reasons // []),
                manual: ($pause.manual // false),
                auto: (
                  ($pause.auto // {}) as $auto
                  | {
                      enabled: ($auto.enabled // true),
                      active: ($auto.active // false),
                      reasons: ($auto.reasons // []),
                      lookbackExecutions: ($auto.lookbackExecutions // 5),
                      minSampleSize: ($auto.minSampleSize // 3),
                      ambiguityRateThreshold: ($auto.ambiguityRateThreshold // 0.4),
                      failureRateThreshold: ($auto.failureRateThreshold // 0.4),
                      metrics: (
                        $auto.metrics
                        // {
                          windowExecutionCount: 0,
                          attemptedCount: 0,
                          executedCount: 0,
                          ambiguousCount: 0,
                          failedCount: 0,
                          ambiguityRate: 0,
                          failureRate: 0
                        }
                      )
                    }
                )
              }
          end
        )
      }
    },
    evaluatedLoopCount: $evaluated_loop_count,
    candidateCount: ($candidates | length),
    unsuppressedCount: ([ $candidates[] | select((.suppressed // false) == false) ] | length),
    suppressedCount: ([ $candidates[] | select((.suppressed // false) == true) ] | length),
    cooldownSuppressedCount: ([ $candidates[] | select((.suppressionReason // "") == "advisory_cooldown_active") ] | length),
    autoEligibleCount: ([ $candidates[] | select((.suppressed // false) == false and (.autonomous.eligible // false) == true) ] | length),
    manualOnlyCount: ([ $candidates[] | select((.suppressed // false) == false and (.autonomous.manualOnly // false) == true) ] | length),
    candidates: $candidates,
    summary: {
      bySeverity: {
        critical: ([ $candidates[] | select(.severity == "critical") ] | length),
        warning: ([ $candidates[] | select(.severity == "warning") ] | length),
        info: ([ $candidates[] | select(.severity == "info") ] | length)
      },
      byConfidence: {
        high: ([ $candidates[] | select(.confidence == "high") ] | length),
        medium: ([ $candidates[] | select(.confidence == "medium") ] | length),
        low: ([ $candidates[] | select(.confidence == "low") ] | length)
      },
      byCategory: (
        reduce $candidates[] as $candidate ({}; .[$candidate.category] = ((.[$candidate.category] // 0) + 1))
      ),
      bySuppressionReason: (
        reduce $candidates[] as $candidate ({};
          if ($candidate.suppressionReason // null) == null then
            .
          else
            .[$candidate.suppressionReason] = ((.[$candidate.suppressionReason] // 0) + 1)
          end
        )
      ),
      byAutonomy: {
        eligible: ([ $candidates[] | select((.suppressed // false) == false and (.autonomous.eligible // false) == true) ] | length),
        manualOnly: ([ $candidates[] | select((.suppressed // false) == false and (.autonomous.manualOnly // false) == true) ] | length)
      },
      byAutonomyReason: (
        reduce $candidates[] as $candidate ({};
          if ($candidate.suppressed // false) == true then
            .
          else
            reduce ($candidate.autonomous.reasons // [])[] as $reason (.;
              .[$reason] = ((.[$reason] // 0) + 1)
            )
          end
        )
      )
    },
    suppressionState: {
      suppressions: $suppressions,
      precedence: ["loop", "global", "cooldown"],
      allowedCategories: ["reconcile_failed", "health_critical", "health_degraded"]
    }
  }
  | .reasonCodes = (
      [
        (if .unsuppressedCount > 0 then "fleet_action_required" else "no_action_required" end),
        (if .suppressedCount > 0 then "fleet_actions_suppressed" else empty end),
        (if .summary.bySuppressionReason.registry_policy_suppression // 0 > 0 then "fleet_actions_policy_suppressed" else empty end),
        (if .summary.bySuppressionReason.advisory_cooldown_active // 0 > 0 then "fleet_actions_deduped" else empty end),
        (if .mode == "guarded_auto" and .autoEligibleCount > 0 then "fleet_auto_candidates_eligible" else empty end),
        (if .mode == "guarded_auto" and .unsuppressedCount > 0 and .autoEligibleCount == 0 then "fleet_auto_candidates_blocked" else empty end),
        (if .mode == "guarded_auto" and (
          (.summary.byAutonomyReason.autonomous_rollout_scope_excluded // 0) > 0
          or (.summary.byAutonomyReason.autonomous_rollout_canary_excluded // 0) > 0
        ) then "fleet_auto_candidates_rollout_gated" else empty end),
        (if .mode == "guarded_auto" and (
          (.summary.byAutonomyReason.autonomous_rollout_paused_manual // 0) > 0
          or (.summary.byAutonomyReason.autonomous_rollout_paused_auto // 0) > 0
        ) then "fleet_auto_candidates_paused" else empty end),
        (if .mode == "guarded_auto" and (.autonomous.rollout.pause.auto.active // false) == true then "fleet_auto_candidates_autopause_triggered" else empty end),
        (if .mode == "guarded_auto" and .summary.byAutonomyReason.autonomous_kill_switch_enabled // 0 > 0 then "fleet_auto_kill_switch_enabled" else empty end),
        (if .mode == "guarded_auto" and (
          (.summary.byAutonomyReason.autonomous_cooldown_active // 0) > 0
          or (.summary.byAutonomyReason.autonomous_max_actions_per_run_exceeded // 0) > 0
          or (.summary.byAutonomyReason.autonomous_max_actions_per_loop_exceeded // 0) > 0
        ) then "fleet_auto_candidates_safety_blocked" else empty end)
      ]
      | unique
    )
  ')

jq -c '.' <<<"$policy_state_json" > "$policy_state_file"

history_entries_json=$(jq -cn \
  --arg timestamp "$current_timestamp" \
  --arg fleet_id "$(jq -r '.fleetId // "default"' <<<"$fleet_state_json")" \
  --arg trace_id "$trace_id" \
  --arg mode "$policy_mode" \
  --argjson candidates "$candidates_json" \
  '
  [
    $candidates[]?
    | {
        timestamp: $timestamp,
        category: "fleet_policy_candidate",
        fleetId: $fleet_id,
        traceId: $trace_id,
        mode: $mode,
        candidateId: .candidateId,
        loopId: .loopId,
        candidateCategory: .category,
        severity: .severity,
        confidence: .confidence,
        recommendedIntent: (.recommendedIntent // null),
        suppressed: (.suppressed // false),
        suppressionReason: (.suppressionReason // null),
        suppressionScope: (.suppressionScope // null),
        suppressionSource: (.suppressionSource // null),
        autonomousEligible: (.autonomous.eligible // false),
        autonomousManualOnly: (
          if (.autonomous.manualOnly // null) == true then true
          elif (.autonomous.eligible // false) == true then false
          else true
          end
        ),
        autonomousReasons: (.autonomous.reasons // []),
        autonomousRolloutInScope: (.autonomous.rollout.selector.inScope // null),
        autonomousRolloutInCohort: (.autonomous.rollout.selector.inCohort // null),
        autonomousRolloutBucket: (.autonomous.rollout.selector.bucket // null),
        autonomousRolloutPauseActive: (.autonomous.rollout.pause.active // null),
        autonomousRolloutPauseReasons: (.autonomous.rollout.pause.reasons // []),
        autonomousAutoPauseActive: (.autonomous.rollout.pause.auto.active // null),
        autonomousAutoPauseReasons: (.autonomous.rollout.pause.auto.reasons // [])
      }
      | with_entries(select(.value != null))
  ]
  ')

jq -c '.[]' <<<"$history_entries_json" >> "$policy_history_file"

jq -cn \
  --arg timestamp "$current_timestamp" \
  --arg fleet_id "$(jq -r '.fleetId // "default"' <<<"$fleet_state_json")" \
  --arg trace_id "$trace_id" \
  --arg mode "$policy_mode" \
  --argjson summary "$(jq -c '{candidateCount, unsuppressedCount, suppressedCount, cooldownSuppressedCount, autoEligibleCount, manualOnlyCount, reasonCodes, summary, noiseControls, autonomous}' <<<"$policy_state_json")" \
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
