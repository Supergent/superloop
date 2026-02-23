#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-fleet-reconcile.sh --repo <path> [options]

Options:
  --registry-file <path>        Fleet registry JSON path. Default: <repo>/.superloop/ops-manager/fleet/registry.v1.json
  --fleet-state-file <path>     Fleet state JSON output path. Default: <repo>/.superloop/ops-manager/fleet/state.json
  --fleet-telemetry-file <path> Fleet reconcile telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/reconcile.jsonl
  --max-parallel <n>            Max concurrent loop reconciles (default: 2)
  --deterministic-order          Sort loops by loopId before fan-out.
  --max-events <n>              Max events per loop reconcile pass-through.
  --from-start                  Replay from start for each loop reconcile pass.
  --trace-id <id>               Fleet reconcile trace id (generated when omitted).
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

classify_failure_code() {
  local msg="$1"
  local lower
  lower="$(tr '[:upper:]' '[:lower:]' <<<"$msg")"

  if [[ "$lower" == *"missing required artifact"* || "$lower" == *"events artifact"* ]]; then
    echo "missing_runtime_artifacts"
    return 0
  fi
  if [[ "$lower" == *"service request failed"* || "$lower" == *"transport_unreachable"* || "$lower" == *"connection refused"* ]]; then
    echo "transport_unreachable"
    return 0
  fi
  if [[ "$lower" == *"invalid"*"json"* || "$lower" == *"invalid payload"* ]]; then
    echo "invalid_transport_payload"
    return 0
  fi

  echo "reconcile_failed"
}

extract_json_object() {
  local raw="$1"
  local parsed=""

  if parsed=$(jq -c '.' <<<"$raw" 2>/dev/null); then
    printf '%s\n' "$parsed"
    return 0
  fi

  local last_line=""
  last_line="$(printf '%s\n' "$raw" | awk 'NF {line=$0} END {print line}')"
  if [[ -n "$last_line" ]] && parsed=$(jq -c '.' <<<"$last_line" 2>/dev/null); then
    printf '%s\n' "$parsed"
    return 0
  fi

  return 1
}

reason_code_from_failure_json() {
  local failure_json="$1"

  jq -r '
    (.reasonCodes // []) as $codes
    | (.transport.failureCode // "") as $failure
    | if (($codes | index("transport_unreachable")) != null) then
        "transport_unreachable"
      elif (($codes | index("invalid_transport_payload")) != null) then
        "invalid_transport_payload"
      elif (($codes | index("projection_failed")) != null) then
        "projection_failed"
      elif (($codes | index("reconcile_failed")) != null) then
        "reconcile_failed"
      elif ($failure == "snapshot_unavailable" or $failure == "events_unavailable" or $failure == "service_request_failed") then
        "transport_unreachable"
      elif ($failure == "service_response_invalid") then
        "invalid_transport_payload"
      elif ($failure | length) > 0 then
        $failure
      else
        empty
      end
  ' <<<"$failure_json" 2>/dev/null || true
}

repo=""
registry_file=""
fleet_state_file=""
fleet_telemetry_file=""
max_parallel="2"
deterministic_order="0"
max_events=""
from_start="0"
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
    --fleet-telemetry-file)
      fleet_telemetry_file="${2:-}"
      shift 2
      ;;
    --max-parallel)
      max_parallel="${2:-}"
      shift 2
      ;;
    --deterministic-order)
      deterministic_order="1"
      shift
      ;;
    --max-events)
      max_events="${2:-}"
      shift 2
      ;;
    --from-start)
      from_start="1"
      shift
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
need_cmd mktemp

if [[ -z "$repo" ]]; then
  die "--repo is required"
fi
if [[ ! "$max_parallel" =~ ^[0-9]+$ || "$max_parallel" -lt 1 ]]; then
  die "--max-parallel must be an integer >= 1"
fi
if [[ -n "$max_events" && (! "$max_events" =~ ^[0-9]+$) ]]; then
  die "--max-events must be a non-negative integer"
fi

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
registry_script="${OPS_MANAGER_FLEET_REGISTRY_SCRIPT:-$script_dir/ops-manager-fleet-registry.sh}"
reconcile_script="${OPS_MANAGER_RECONCILE_SCRIPT:-$script_dir/ops-manager-reconcile.sh}"

if [[ -z "$registry_file" ]]; then
  registry_file="$repo/.superloop/ops-manager/fleet/registry.v1.json"
fi
if [[ -z "$fleet_state_file" ]]; then
  fleet_state_file="$repo/.superloop/ops-manager/fleet/state.json"
fi
if [[ -z "$fleet_telemetry_file" ]]; then
  fleet_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/reconcile.jsonl"
fi
if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

mkdir -p "$(dirname "$fleet_state_file")"
mkdir -p "$(dirname "$fleet_telemetry_file")"

registry_json=$("$registry_script" --repo "$repo" --registry-file "$registry_file")
fleet_id="$(jq -r '.fleetId // "default"' <<<"$registry_json")"

if [[ "$deterministic_order" == "1" ]]; then
  loops_json=$(jq -c '.loops | sort_by(.loopId)' <<<"$registry_json")
else
  loops_json=$(jq -c '.loops' <<<"$registry_json")
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

run_single_loop() {
  local loop_json="$1"
  local result_file="$2"

  local loop_id transport enabled service_base_url service_token_env retry_attempts retry_backoff
  local sprite_json metadata_json
  loop_id="$(jq -r '.loopId' <<<"$loop_json")"
  transport="$(jq -r '.transport // "local"' <<<"$loop_json")"
  enabled="$(jq -r 'if (.enabled // true) then "true" else "false" end' <<<"$loop_json")"
  service_base_url="$(jq -r '.service.baseUrl // empty' <<<"$loop_json")"
  service_token_env="$(jq -r '.service.tokenEnv // empty' <<<"$loop_json")"
  retry_attempts="$(jq -r '.service.retryAttempts // 3' <<<"$loop_json")"
  retry_backoff="$(jq -r '.service.retryBackoffSeconds // 1' <<<"$loop_json")"
  sprite_json="$(jq -c '.sprite // {}' <<<"$loop_json")"
  metadata_json="$(jq -c '.metadata // {}' <<<"$loop_json")"

  local loop_trace_id
  loop_trace_id="${trace_id}-${loop_id//[^a-zA-Z0-9._-]/-}"

  local started_at ended_at start_epoch end_epoch duration_seconds
  started_at="$(timestamp)"
  start_epoch="$(date -u +%s)"

  local status="success"
  local reason_code=""
  local reconcile_output=""
  local reconcile_status="success"
  local health_status="unknown"
  local health_reason_codes='[]'
  local transition_state=""

  local state_file="$repo/.superloop/ops-manager/$loop_id/state.json"
  local health_file="$repo/.superloop/ops-manager/$loop_id/health.json"
  local cursor_file="$repo/.superloop/ops-manager/$loop_id/cursor.json"
  local reconcile_telemetry_file="$repo/.superloop/ops-manager/$loop_id/telemetry/reconcile.jsonl"

  if [[ "$enabled" != "true" ]]; then
    status="skipped"
    reason_code="loop_disabled"
    reconcile_status="skipped"
  elif [[ "$transport" == "sprite_service" && -z "$service_base_url" ]]; then
    status="failed"
    reason_code="missing_service_base_url"
    reconcile_status="failed"
  elif [[ -n "$service_token_env" && -z "${!service_token_env:-}" ]]; then
    status="failed"
    reason_code="missing_service_token_env"
    reconcile_status="failed"
  else
    local -a cmd
    cmd=("$reconcile_script" --repo "$repo" --loop "$loop_id" --transport "$transport" --trace-id "$loop_trace_id")
    if [[ -n "$max_events" ]]; then
      cmd+=(--max-events "$max_events")
    fi
    if [[ "$from_start" == "1" ]]; then
      cmd+=(--from-start)
    fi
    if [[ "$transport" == "sprite_service" ]]; then
      cmd+=(--service-base-url "$service_base_url" --retry-attempts "$retry_attempts" --retry-backoff-seconds "$retry_backoff")
      if [[ -n "$service_token_env" ]]; then
        cmd+=(--service-token "${!service_token_env}")
      fi
    fi

    if reconcile_output="$("${cmd[@]}" 2>&1)"; then
      local reconcile_json
      reconcile_json="$(jq -c '.' <<<"$reconcile_output" 2>/dev/null || echo 'null')"
      health_status="$(jq -r '.health.status // "unknown"' <<<"$reconcile_json" 2>/dev/null || echo "unknown")"
      health_reason_codes="$(jq -c '.health.reasonCodes // []' <<<"$reconcile_json" 2>/dev/null || echo '[]')"
      transition_state="$(jq -r '.transition.currentState // empty' <<<"$reconcile_json" 2>/dev/null || true)"
    else
      status="failed"
      reconcile_status="failed"
      failure_json="null"
      if failure_json="$(extract_json_object "$reconcile_output")"; then
        health_status="$(jq -r '.status // "unknown"' <<<"$failure_json" 2>/dev/null || echo "unknown")"
        health_reason_codes="$(jq -c '.reasonCodes // []' <<<"$failure_json" 2>/dev/null || echo '[]')"
        reason_code="$(reason_code_from_failure_json "$failure_json")"
      fi
      if [[ -z "$reason_code" ]]; then
        reason_code="$(classify_failure_code "$reconcile_output")"
      fi
    fi
  fi

  ended_at="$(timestamp)"
  end_epoch="$(date -u +%s)"
  duration_seconds=$(( ${end_epoch:-0} - ${start_epoch:-0} ))
  if (( duration_seconds < 0 )); then
    duration_seconds=0
  fi

  local output_excerpt=""
  if [[ "$status" != "success" ]]; then
    output_excerpt="$(tr '\n' ' ' <<<"$reconcile_output" | sed 's/[[:space:]]\+/ /g' | cut -c1-600)"
  fi

  jq -cn \
    --arg timestamp "$ended_at" \
    --arg started_at "$started_at" \
    --arg loop_id "$loop_id" \
    --arg transport "$transport" \
    --arg enabled "$enabled" \
    --arg status "$status" \
    --arg reason_code "$reason_code" \
    --arg reconcile_status "$reconcile_status" \
    --arg health_status "$health_status" \
    --arg transition_state "$transition_state" \
    --arg trace_id "$loop_trace_id" \
    --arg output_excerpt "$output_excerpt" \
    --arg state_file "$state_file" \
    --arg health_file "$health_file" \
    --arg cursor_file "$cursor_file" \
    --arg reconcile_telemetry_file "$reconcile_telemetry_file" \
    --argjson sprite "$sprite_json" \
    --argjson metadata "$metadata_json" \
    --argjson duration_seconds "$duration_seconds" \
    --argjson health_reason_codes "$health_reason_codes" \
    '{
      timestamp: $timestamp,
      startedAt: $started_at,
      loopId: $loop_id,
      transport: $transport,
      enabled: ($enabled == "true"),
      status: $status,
      reasonCode: (if ($reason_code | length) > 0 then $reason_code else null end),
      reconcileStatus: $reconcile_status,
      healthStatus: $health_status,
      healthReasonCodes: $health_reason_codes,
      transitionState: (if ($transition_state | length) > 0 then $transition_state else null end),
      durationSeconds: $duration_seconds,
      traceId: $trace_id,
      outputExcerpt: (if ($output_excerpt | length) > 0 then $output_excerpt else null end),
      sprite: $sprite,
      metadata: $metadata,
      files: {
        stateFile: $state_file,
        healthFile: $health_file,
        cursorFile: $cursor_file,
        reconcileTelemetryFile: $reconcile_telemetry_file
      }
    } | with_entries(select(.value != null))' > "$result_file"
}

started_at="$(timestamp)"
start_epoch="$(date -u +%s)"

pids=()
active_result_files=()
completed_result_files=()

launch_loop() {
  local loop_json="$1"
  local result_file
  result_file="$(mktemp "$tmp_dir/loop-result.XXXXXX.json")"
  run_single_loop "$loop_json" "$result_file" &
  pids+=("$!")
  active_result_files+=("$result_file")
}

reap_first() {
  local pid="${pids[0]}"
  local result_file="${active_result_files[0]}"
  wait "$pid" || true
  completed_result_files+=("$result_file")

  if (( ${#pids[@]} > 1 )); then
    pids=("${pids[@]:1}")
    active_result_files=("${active_result_files[@]:1}")
  else
    pids=()
    active_result_files=()
  fi
}

while IFS= read -r loop_line; do
  [[ -z "$loop_line" ]] && continue
  launch_loop "$loop_line"
  if (( ${#pids[@]} >= max_parallel )); then
    reap_first
  fi
done < <(jq -c '.[]' <<<"$loops_json")

while (( ${#pids[@]} > 0 )); do
  reap_first
done

if (( ${#completed_result_files[@]} == 0 )); then
  die "fleet reconcile produced no loop results"
fi

results_json="$(jq -cs '.' "${completed_result_files[@]}")"

loop_count="$(jq -r 'length' <<<"$results_json")"
success_count="$(jq -r '[.[] | select(.status == "success")] | length' <<<"$results_json")"
failed_count="$(jq -r '[.[] | select(.status == "failed")] | length' <<<"$results_json")"
skipped_count="$(jq -r '[.[] | select(.status == "skipped")] | length' <<<"$results_json")"

fleet_status="success"
if (( failed_count > 0 && success_count > 0 )); then
  fleet_status="partial_failure"
elif (( failed_count > 0 && success_count == 0 )); then
  fleet_status="failed"
fi

reason_codes_json="$(jq -cn \
  --argjson results "$results_json" \
  --argjson success_count "$success_count" \
  --argjson failed_count "$failed_count" \
  --argjson skipped_count "$skipped_count" \
  '
  [
    (if $failed_count > 0 and $success_count > 0 then "fleet_partial_failure" else empty end),
    (if $failed_count > 0 and $success_count == 0 then "fleet_reconcile_failed" else empty end),
    (if ([ $results[] | select(.healthStatus == "critical") ] | length) > 0 then "fleet_health_critical"
     elif ([ $results[] | select(.healthStatus == "degraded") ] | length) > 0 then "fleet_health_degraded"
     else empty end),
    (if $skipped_count > 0 then "fleet_loop_skipped" else empty end)
  ] | unique
  ')"

ended_at="$(timestamp)"
end_epoch="$(date -u +%s)"
duration_seconds=$(( ${end_epoch:-0} - ${start_epoch:-0} ))
if (( duration_seconds < 0 )); then
  duration_seconds=0
fi

fleet_state_json="$(jq -cn \
  --arg schema_version "v1" \
  --arg timestamp "$ended_at" \
  --arg started_at "$started_at" \
  --arg fleet_id "$fleet_id" \
  --arg trace_id "$trace_id" \
  --arg status "$fleet_status" \
  --arg deterministic_order "$deterministic_order" \
  --argjson max_parallel "$max_parallel" \
  --argjson from_start "$from_start" \
  --argjson max_events "${max_events:-0}" \
  --argjson loop_count "$loop_count" \
  --argjson success_count "$success_count" \
  --argjson failed_count "$failed_count" \
  --argjson skipped_count "$skipped_count" \
  --argjson duration_seconds "$duration_seconds" \
  --argjson reason_codes "$reason_codes_json" \
  --argjson results "$results_json" \
  '{
    schemaVersion: $schema_version,
    updatedAt: $timestamp,
    startedAt: $started_at,
    fleetId: $fleet_id,
    traceId: $trace_id,
    status: $status,
    reasonCodes: $reason_codes,
    loopCount: $loop_count,
    successCount: $success_count,
    failedCount: $failed_count,
    skippedCount: $skipped_count,
    durationSeconds: $duration_seconds,
    execution: {
      maxParallel: $max_parallel,
      deterministicOrder: ($deterministic_order == "1"),
      fromStart: ($from_start == 1),
      maxEvents: $max_events
    },
    results: $results
  }')"

jq -c '.' <<<"$fleet_state_json" > "$fleet_state_file"

jq -cn \
  --arg timestamp "$ended_at" \
  --arg fleet_id "$fleet_id" \
  --arg trace_id "$trace_id" \
  --arg status "$fleet_status" \
  --argjson loop_count "$loop_count" \
  --argjson success_count "$success_count" \
  --argjson failed_count "$failed_count" \
  --argjson skipped_count "$skipped_count" \
  --argjson duration_seconds "$duration_seconds" \
  --argjson reason_codes "$reason_codes_json" \
  --argjson results "$results_json" \
  '{
    timestamp: $timestamp,
    category: "fleet_reconcile",
    fleetId: $fleet_id,
    traceId: $trace_id,
    status: $status,
    reasonCodes: $reason_codes,
    loopCount: $loop_count,
    successCount: $success_count,
    failedCount: $failed_count,
    skippedCount: $skipped_count,
    durationSeconds: $duration_seconds,
    results: $results
  }' >> "$fleet_telemetry_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$fleet_state_json"
else
  jq -c '.' <<<"$fleet_state_json"
fi
