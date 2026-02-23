#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-fleet-handoff.sh --repo <path> [options]

Options:
  --registry-file <path>         Fleet registry JSON path. Default: <repo>/.superloop/ops-manager/fleet/registry.v1.json
  --policy-state-file <path>     Fleet policy state JSON path. Default: <repo>/.superloop/ops-manager/fleet/policy-state.json
  --handoff-state-file <path>    Fleet handoff JSON output path. Default: <repo>/.superloop/ops-manager/fleet/handoff-state.json
  --handoff-telemetry-file <path> Fleet handoff telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/handoff.jsonl
  --trace-id <id>                Handoff trace id override. Default: policy trace id or generated.
  --idempotency-prefix <value>   Idempotency prefix for generated intents (default: fleet-handoff)
  --execute                      Execute selected pending intents via ops-manager-control.sh.
  --confirm                      Required with --execute (explicit operator confirmation gate).
  --loop <id>                    Filter execution to a loop id (repeatable).
  --intent-id <id>               Filter execution to an intent id (repeatable).
  --by <name>                    Operator identity for executed intents (default: $USER)
  --note <text>                  Optional note attached to executed intents.
  --timeout-seconds <n>          Confirmation timeout passed to control command (default: 30)
  --interval-seconds <n>         Confirmation poll interval passed to control command (default: 2)
  --no-runtime-confirm           Skip runtime confirmation polling when executing controls.
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
policy_state_file=""
handoff_state_file=""
handoff_telemetry_file=""
trace_id=""
idempotency_prefix="fleet-handoff"
execute="0"
confirm_execute="0"
by="${USER:-unknown}"
note=""
timeout_seconds="30"
interval_seconds="2"
do_runtime_confirm="1"
pretty="0"

declare -a selected_loops=()
declare -a selected_intent_ids=()

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
    --policy-state-file)
      policy_state_file="${2:-}"
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
    --trace-id)
      trace_id="${2:-}"
      shift 2
      ;;
    --idempotency-prefix)
      idempotency_prefix="${2:-}"
      shift 2
      ;;
    --execute)
      execute="1"
      shift
      ;;
    --confirm)
      confirm_execute="1"
      shift
      ;;
    --loop)
      selected_loops+=("${2:-}")
      shift 2
      ;;
    --intent-id)
      selected_intent_ids+=("${2:-}")
      shift 2
      ;;
    --by)
      by="${2:-}"
      shift 2
      ;;
    --note)
      note="${2:-}"
      shift 2
      ;;
    --timeout-seconds)
      timeout_seconds="${2:-}"
      shift 2
      ;;
    --interval-seconds)
      interval_seconds="${2:-}"
      shift 2
      ;;
    --no-runtime-confirm)
      do_runtime_confirm="0"
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
if [[ -z "$idempotency_prefix" ]]; then
  die "--idempotency-prefix must be non-empty"
fi
if [[ ! "$timeout_seconds" =~ ^[0-9]+$ || ! "$interval_seconds" =~ ^[0-9]+$ ]]; then
  die "timeout and interval must be non-negative integers"
fi
if [[ "$execute" == "1" && "$confirm_execute" != "1" ]]; then
  die "--execute requires --confirm to enforce explicit operator confirmation"
fi

for loop_id in "${selected_loops[@]}"; do
  if [[ -z "$loop_id" ]]; then
    die "--loop requires a non-empty value"
  fi
done
for intent_id in "${selected_intent_ids[@]}"; do
  if [[ -z "$intent_id" ]]; then
    die "--intent-id requires a non-empty value"
  fi
done

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
registry_script="${OPS_MANAGER_FLEET_REGISTRY_SCRIPT:-$script_dir/ops-manager-fleet-registry.sh}"
control_script="${OPS_MANAGER_CONTROL_SCRIPT:-$script_dir/ops-manager-control.sh}"

if [[ -z "$registry_file" ]]; then
  registry_file="$repo/.superloop/ops-manager/fleet/registry.v1.json"
fi
if [[ -z "$policy_state_file" ]]; then
  policy_state_file="$repo/.superloop/ops-manager/fleet/policy-state.json"
fi
if [[ -z "$handoff_state_file" ]]; then
  handoff_state_file="$repo/.superloop/ops-manager/fleet/handoff-state.json"
fi
if [[ -z "$handoff_telemetry_file" ]]; then
  handoff_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/handoff.jsonl"
fi

if [[ ! -f "$policy_state_file" ]]; then
  die "policy state file not found: $policy_state_file"
fi

mkdir -p "$(dirname "$handoff_state_file")"
mkdir -p "$(dirname "$handoff_telemetry_file")"

registry_json=$("$registry_script" --repo "$repo" --registry-file "$registry_file")
policy_state_json=$(jq -c '.' "$policy_state_file" 2>/dev/null) || die "invalid policy state JSON: $policy_state_file"

policy_mode="$(jq -r '.mode // "advisory"' <<<"$policy_state_json")"
if [[ "$policy_mode" != "advisory" ]]; then
  die "unsupported policy mode in phase 8 baseline: $policy_mode"
fi

if [[ -z "$trace_id" ]]; then
  trace_id="$(jq -r '.traceId // empty' <<<"$policy_state_json")"
fi
if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

generated_at="$(timestamp)"

handoff_state_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$generated_at" \
  --arg trace_id "$trace_id" \
  --arg registry_file "$registry_file" \
  --arg policy_state_file "$policy_state_file" \
  --arg idempotency_prefix "$idempotency_prefix" \
  --argjson registry "$registry_json" \
  --argjson policy "$policy_state_json" \
  '
  def slug:
    tostring
    | ascii_downcase
    | gsub("[^a-z0-9._-]"; "-")
    | gsub("-+"; "-")
    | gsub("(^-)|(-$)"; "");

  ($registry.loops // [] | map({key: .loopId, value: .}) | from_entries) as $loop_map
  | ($policy.candidates // []) as $all_candidates
  | ($all_candidates | map(select((.suppressed // false) == false))) as $unsuppressed
  | ($policy.traceId // $trace_id) as $policy_trace_id
  | {
      schemaVersion: $schema_version,
      generatedAt: $generated_at,
      updatedAt: $generated_at,
      fleetId: ($policy.fleetId // $registry.fleetId // "default"),
      traceId: $trace_id,
      policyTraceId: $policy_trace_id,
      mode: ($policy.mode // "advisory"),
      source: {
        registryFile: $registry_file,
        policyStateFile: $policy_state_file
      },
      control: {
        idempotencyPrefix: $idempotency_prefix,
        requiresOperatorConfirmation: true
      },
      intents: (
        $unsuppressed
        | map(
            . as $candidate
            | ($loop_map[$candidate.loopId] // {}) as $loop
            | (if ($candidate.category // "") == "reconcile_failed" then "cancel"
               elif ($candidate.category // "") == "health_critical" then "cancel"
               elif ($candidate.category // "") == "health_degraded" then "cancel"
               else null
               end) as $intent
            | select($intent != null)
            | {
                intentId: (($candidate.candidateId // ($candidate.loopId + ":" + ($candidate.category // "unknown"))) + ":" + $intent),
                candidateId: ($candidate.candidateId // ($candidate.loopId + ":" + ($candidate.category // "unknown"))),
                loopId: $candidate.loopId,
                category: ($candidate.category // null),
                severity: ($candidate.severity // null),
                confidence: ($candidate.confidence // null),
                rationale: ($candidate.rationale // null),
                signal: ($candidate.signal // null),
                intent: $intent,
                status: "pending_operator_confirmation",
                requiresOperatorConfirmation: true,
                fleetTraceId: $trace_id,
                policyTraceId: $policy_trace_id,
                candidateTraceId: ($candidate.traceId // null),
                idempotencyKey: (
                  [
                    ($idempotency_prefix | slug),
                    ($trace_id | slug),
                    ($candidate.loopId | slug),
                    (($candidate.category // "unknown") | slug),
                    ($intent | slug)
                  ]
                  | map(select(length > 0))
                  | join("-")
                ),
                transport: ($loop.transport // "local"),
                service: (
                  {
                    baseUrl: ($loop.service.baseUrl // null),
                    tokenEnv: ($loop.service.tokenEnv // null),
                    retryAttempts: ($loop.service.retryAttempts // 3),
                    retryBackoffSeconds: ($loop.service.retryBackoffSeconds // 1)
                  }
                  | with_entries(select(.value != null))
                ),
                metadata: ($loop.metadata // {})
              }
            | with_entries(select(.value != null))
          )
        | sort_by(.loopId, .category, .intent)
      )
    }
  | .summary = {
      candidateCount: ($all_candidates | length),
      unsuppressedCandidateCount: ($unsuppressed | length),
      intentCount: (.intents | length),
      pendingConfirmationCount: ([ .intents[] | select(.status == "pending_operator_confirmation") ] | length),
      executedCount: ([ .intents[] | select(.status == "executed") ] | length),
      ambiguousCount: ([ .intents[] | select(.status == "execution_ambiguous") ] | length),
      failedCount: ([ .intents[] | select(.status == "execution_failed") ] | length)
    }
  | .reasonCodes = (
      [
        (if .summary.intentCount > 0 then "fleet_handoff_action_required" else "fleet_handoff_no_action" end),
        (if .summary.pendingConfirmationCount > 0 then "fleet_handoff_confirmation_pending" else empty end),
        (if .summary.intentCount < .summary.unsuppressedCandidateCount then "fleet_handoff_partial_mapping" else empty end),
        (if .summary.unsuppressedCandidateCount > 0 and .summary.intentCount == 0 then "fleet_handoff_unmapped_candidates" else empty end)
      ]
      | unique
    )
  ')

jq -cn \
  --arg timestamp "$generated_at" \
  --arg fleet_id "$(jq -r '.fleetId // "default"' <<<"$handoff_state_json")" \
  --arg trace_id "$trace_id" \
  --arg mode "$(jq -r '.mode // "advisory"' <<<"$handoff_state_json")" \
  --argjson summary "$(jq -c '{summary, reasonCodes, policyTraceId}' <<<"$handoff_state_json")" \
  '{
    timestamp: $timestamp,
    category: "fleet_handoff_plan",
    fleetId: $fleet_id,
    traceId: $trace_id,
    mode: $mode,
    summary: $summary
  }' >> "$handoff_telemetry_file"

if [[ "$execute" == "1" ]]; then
  selected_loops_json="$(printf '%s\n' "${selected_loops[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
  selected_intent_ids_json="$(printf '%s\n' "${selected_intent_ids[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"

  unmatched_loop_filters="$(jq -r \
    --argjson loops "$selected_loops_json" \
    '
    if ($loops | length) == 0 then
      []
    else
      ([ .intents[]?.loopId ] | unique) as $available
      | [ $loops[] | select(($available | index(.)) == null) ]
    end
    | .[]?
    ' <<<"$handoff_state_json")"
  if [[ -n "$unmatched_loop_filters" ]]; then
    die "loop filter not found in handoff intents: $(tr '\n' ',' <<<"$unmatched_loop_filters" | sed 's/,$//')"
  fi

  unmatched_intent_filters="$(jq -r \
    --argjson intent_ids "$selected_intent_ids_json" \
    '
    if ($intent_ids | length) == 0 then
      []
    else
      ([ .intents[]?.intentId ] | unique) as $available
      | [ $intent_ids[] | select(($available | index(.)) == null) ]
    end
    | .[]?
    ' <<<"$handoff_state_json")"
  if [[ -n "$unmatched_intent_filters" ]]; then
    die "intent filter not found in handoff intents: $(tr '\n' ',' <<<"$unmatched_intent_filters" | sed 's/,$//')"
  fi

  execution_targets_json="$(jq -cn \
    --argjson handoff "$handoff_state_json" \
    --argjson loops "$selected_loops_json" \
    --argjson intent_ids "$selected_intent_ids_json" \
    '
    ($handoff.intents // [])
    | map(select((.status // "") == "pending_operator_confirmation"))
    | (if ($loops | length) > 0 then map(select(($loops | index(.loopId)) != null)) else . end)
    | (if ($intent_ids | length) > 0 then map(select(($intent_ids | index(.intentId)) != null)) else . end)
    ' )"

  target_count="$(jq -r 'length' <<<"$execution_targets_json")"
  execution_started_at="$(timestamp)"
  results_file="$(mktemp)"
  trap 'rm -f "$results_file"' EXIT

  if [[ "$target_count" -gt 0 ]]; then
    while IFS= read -r target_line; do
      [[ -z "$target_line" ]] && continue

      loop_id="$(jq -r '.loopId' <<<"$target_line")"
      intent_value="$(jq -r '.intent' <<<"$target_line")"
      intent_id="$(jq -r '.intentId' <<<"$target_line")"
      transport="$(jq -r '.transport // "local"' <<<"$target_line")"
      idempotency_key="$(jq -r '.idempotencyKey // empty' <<<"$target_line")"
      service_base_url="$(jq -r '.service.baseUrl // empty' <<<"$target_line")"
      service_token_env="$(jq -r '.service.tokenEnv // empty' <<<"$target_line")"
      retry_attempts="$(jq -r '.service.retryAttempts // 3' <<<"$target_line")"
      retry_backoff_seconds="$(jq -r '.service.retryBackoffSeconds // 1' <<<"$target_line")"

      effective_note="fleet_handoff:$intent_id"
      if [[ -n "$note" ]]; then
        effective_note="$note | fleet_handoff:$intent_id"
      fi

      control_trace_id="$trace_id"
      if [[ -z "$idempotency_key" ]]; then
        idempotency_key="$idempotency_prefix-$loop_id-$intent_value"
      fi

      action_status="failed"
      control_exit_code=1
      control_json='null'
      action_reason="control_failed_command"

      if [[ "$transport" == "sprite_service" && -z "$service_base_url" ]]; then
        action_reason="missing_service_base_url"
      else
        cmd=(
          "$control_script"
          --repo "$repo"
          --loop "$loop_id"
          --intent "$intent_value"
          --transport "$transport"
          --trace-id "$control_trace_id"
          --idempotency-key "$idempotency_key"
          --by "$by"
          --note "$effective_note"
          --timeout-seconds "$timeout_seconds"
          --interval-seconds "$interval_seconds"
        )

        if [[ "$do_runtime_confirm" != "1" ]]; then
          cmd+=(--no-confirm)
        fi

        if [[ "$transport" == "sprite_service" ]]; then
          cmd+=(
            --service-base-url "$service_base_url"
            --retry-attempts "$retry_attempts"
            --retry-backoff-seconds "$retry_backoff_seconds"
          )
          if [[ -n "$service_token_env" && -n "${!service_token_env:-}" ]]; then
            cmd+=(--service-token "${!service_token_env}")
          fi
        fi

        control_output=""
        if control_output="$("${cmd[@]}" 2>&1)"; then
          control_exit_code=0
        else
          control_exit_code=$?
        fi
        control_json="$(jq -c '.' <<<"$control_output" 2>/dev/null || echo 'null')"

        if [[ "$control_exit_code" -eq 0 ]]; then
          action_status="executed"
          action_reason="control_confirmed"
        elif [[ "$control_exit_code" -eq 2 ]]; then
          action_status="ambiguous"
          action_reason="control_ambiguous"
        else
          action_status="failed"
          action_reason="control_failed_command"
        fi
      fi

      jq -cn \
        --arg intent_id "$intent_id" \
        --arg loop_id "$loop_id" \
        --arg intent "$intent_value" \
        --arg trace_id "$control_trace_id" \
        --arg idempotency_key "$idempotency_key" \
        --arg requested_by "$by" \
        --arg executed_at "$(timestamp)" \
        --arg status "$action_status" \
        --arg reason "$action_reason" \
        --argjson control_exit_code "$control_exit_code" \
        --argjson control "$control_json" \
        '{
          intentId: $intent_id,
          loopId: $loop_id,
          intent: $intent,
          traceId: $trace_id,
          idempotencyKey: $idempotency_key,
          requestedBy: $requested_by,
          executedAt: $executed_at,
          status: $status,
          reasonCode: $reason,
          controlExitCode: $control_exit_code,
          control: (if $control == null then null else $control end)
        } | with_entries(select(.value != null))' >> "$results_file"
    done < <(jq -c '.[]' <<<"$execution_targets_json")
  fi

  execution_results_json="$(jq -cs '.' "$results_file")"
  execution_completed_at="$(timestamp)"

  handoff_state_json="$(jq -cn \
    --argjson handoff "$handoff_state_json" \
    --argjson results "$execution_results_json" \
    --argjson target_count "$target_count" \
    --arg started_at "$execution_started_at" \
    --arg completed_at "$execution_completed_at" \
    --arg requested_by "$by" \
    --arg note "$note" \
    '
    ($results | map({key: .intentId, value: .}) | from_entries) as $result_map
    | $handoff
    | .updatedAt = $completed_at
    | .execution = {
        requestedBy: $requested_by,
        requestedAt: $started_at,
        completedAt: $completed_at,
        note: (if ($note | length) > 0 then $note else null end),
        requestedIntentCount: $target_count,
        executedIntentCount: ($results | length),
        executedCount: ([ $results[] | select(.status == "executed") ] | length),
        ambiguousCount: ([ $results[] | select(.status == "ambiguous") ] | length),
        failedCount: ([ $results[] | select(.status == "failed") ] | length),
        results: $results
      } | with_entries(select(.value != null))
    | .intents = (
        .intents
        | map(
            . as $intent
            | ($result_map[$intent.intentId] // null) as $result
            | if $result == null then
                $intent
              else
                $intent + {
                  status: (
                    if $result.status == "executed" then "executed"
                    elif $result.status == "ambiguous" then "execution_ambiguous"
                    else "execution_failed"
                    end
                  ),
                  execution: {
                    executedAt: ($result.executedAt // null),
                    requestedBy: ($result.requestedBy // null),
                    status: ($result.status // null),
                    reasonCode: ($result.reasonCode // null),
                    traceId: ($result.traceId // null),
                    idempotencyKey: ($result.idempotencyKey // null),
                    controlExitCode: ($result.controlExitCode // null),
                    controlStatus: ($result.control.status // null),
                    confirmed: ($result.control.confirmed // null)
                  } | with_entries(select(.value != null))
                }
            end
          )
      )
    | .summary = {
        candidateCount: (.summary.candidateCount // 0),
        unsuppressedCandidateCount: (.summary.unsuppressedCandidateCount // 0),
        intentCount: (.intents | length),
        pendingConfirmationCount: ([ .intents[] | select(.status == "pending_operator_confirmation") ] | length),
        executedCount: ([ .intents[] | select(.status == "executed") ] | length),
        ambiguousCount: ([ .intents[] | select(.status == "execution_ambiguous") ] | length),
        failedCount: ([ .intents[] | select(.status == "execution_failed") ] | length)
      }
    | .reasonCodes = (
        [
          (if .summary.intentCount > 0 then "fleet_handoff_action_required" else "fleet_handoff_no_action" end),
          (if .summary.pendingConfirmationCount > 0 then "fleet_handoff_confirmation_pending" else empty end),
          (if .summary.executedCount > 0 then "fleet_handoff_executed" else empty end),
          (if .summary.ambiguousCount > 0 then "fleet_handoff_execution_ambiguous" else empty end),
          (if .summary.failedCount > 0 then "fleet_handoff_execution_failed" else empty end)
        ]
        | unique
      )
    ')"

  jq -cn \
    --arg timestamp "$execution_completed_at" \
    --arg fleet_id "$(jq -r '.fleetId // "default"' <<<"$handoff_state_json")" \
    --arg trace_id "$trace_id" \
    --argjson execution "$(jq -c '.execution // {}' <<<"$handoff_state_json")" \
    --argjson summary "$(jq -c '{summary, reasonCodes}' <<<"$handoff_state_json")" \
    '{
      timestamp: $timestamp,
      category: "fleet_handoff_execute",
      fleetId: $fleet_id,
      traceId: $trace_id,
      execution: $execution,
      summary: $summary
    }' >> "$handoff_telemetry_file"
fi

jq -c '.' <<<"$handoff_state_json" > "$handoff_state_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$handoff_state_json"
else
  jq -c '.' <<<"$handoff_state_json"
fi
