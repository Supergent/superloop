#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-reconcile.sh --repo <path> --loop <id> [options]

Options:
  --transport <local|sprite_service>             Ingestion transport mode (default: local)
  --service-base-url <url>                       Sprite service base URL (required for sprite_service)
  --service-token <token>                        Sprite service auth token (optional)
  --retry-attempts <n>                           Service retry attempts (default: 3)
  --retry-backoff-seconds <n>                    Service retry backoff base (default: 1)
  --cursor-file <path>                           Cursor JSON path. Default: <repo>/.superloop/ops-manager/<loop>/cursor.json
  --state-file <path>                            Output state path. Default: <repo>/.superloop/ops-manager/<loop>/state.json
  --max-events <n>                               Max incremental events to ingest (default: 0 = all available)
  --from-start                                   Replay events from line 1 (ignores existing cursor)
  --degraded-ingest-lag-seconds <n>              Degraded ingest staleness threshold (default: 300)
  --critical-ingest-lag-seconds <n>              Critical ingest staleness threshold (default: 900)
  --degraded-transport-failure-streak <n>        Degraded transport failure streak threshold (default: 2)
  --critical-transport-failure-streak <n>        Critical transport failure streak threshold (default: 4)
  --pretty                                       Pretty-print resulting state/health
  --help                                         Show this help message
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
transport="local"
service_base_url=""
service_header=""
retry_attempts="3"
retry_backoff_seconds="1"
cursor_file=""
state_file=""
max_events="0"
from_start="0"
degraded_ingest_lag_seconds="300"
critical_ingest_lag_seconds="900"
degraded_transport_failure_streak="2"
critical_transport_failure_streak="4"
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
    --transport)
      transport="${2:-}"
      shift 2
      ;;
    --service-base-url)
      service_base_url="${2:-}"
      shift 2
      ;;
    --service-token)
      service_header="${2:-}"
      shift 2
      ;;
    --retry-attempts)
      retry_attempts="${2:-}"
      shift 2
      ;;
    --retry-backoff-seconds)
      retry_backoff_seconds="${2:-}"
      shift 2
      ;;
    --cursor-file)
      cursor_file="${2:-}"
      shift 2
      ;;
    --state-file)
      state_file="${2:-}"
      shift 2
      ;;
    --max-events)
      max_events="${2:-}"
      shift 2
      ;;
    --from-start)
      from_start="1"
      shift
      ;;
    --degraded-ingest-lag-seconds)
      degraded_ingest_lag_seconds="${2:-}"
      shift 2
      ;;
    --critical-ingest-lag-seconds)
      critical_ingest_lag_seconds="${2:-}"
      shift 2
      ;;
    --degraded-transport-failure-streak)
      degraded_transport_failure_streak="${2:-}"
      shift 2
      ;;
    --critical-transport-failure-streak)
      critical_transport_failure_streak="${2:-}"
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
if [[ ! "$max_events" =~ ^[0-9]+$ ]]; then
  die "--max-events must be a non-negative integer"
fi
if [[ ! "$retry_attempts" =~ ^[0-9]+$ || "$retry_attempts" -lt 1 ]]; then
  die "--retry-attempts must be an integer >= 1"
fi
if [[ ! "$retry_backoff_seconds" =~ ^[0-9]+$ ]]; then
  die "--retry-backoff-seconds must be a non-negative integer"
fi
for threshold_name in degraded_ingest_lag_seconds critical_ingest_lag_seconds degraded_transport_failure_streak critical_transport_failure_streak; do
  threshold_value="${!threshold_name}"
  if [[ ! "$threshold_value" =~ ^[0-9]+$ ]]; then
    die "${threshold_name//_/\-} must be a non-negative integer"
  fi
done
if (( critical_ingest_lag_seconds < degraded_ingest_lag_seconds )); then
  die "critical ingest lag threshold must be >= degraded threshold"
fi
if (( critical_transport_failure_streak < degraded_transport_failure_streak )); then
  die "critical transport failure threshold must be >= degraded threshold"
fi

case "$transport" in
  local|sprite_service)
    ;;
  *)
    die "--transport must be local or sprite_service"
    ;;
esac

repo="$(cd "$repo" && pwd)"
ops_dir="$repo/.superloop/ops-manager/$loop_id"
if [[ -z "$cursor_file" ]]; then
  cursor_file="$ops_dir/cursor.json"
fi
if [[ -z "$state_file" ]]; then
  state_file="$ops_dir/state.json"
fi

mkdir -p "$ops_dir"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
client_script="${OPS_MANAGER_SERVICE_CLIENT_SCRIPT:-$script_dir/ops-manager-service-client.sh}"
health_script="${OPS_MANAGER_HEALTH_SCRIPT:-$script_dir/ops-manager-health.sh}"

if [[ -z "$service_header" && -n "${OPS_MANAGER_SERVICE_TOKEN:-}" ]]; then
  service_header="$OPS_MANAGER_SERVICE_TOKEN"
fi

telemetry_dir="$ops_dir/telemetry"
reconcile_telemetry_file="$telemetry_dir/reconcile.jsonl"
transport_health_file="$telemetry_dir/transport-health.json"
health_file="$ops_dir/health.json"
intents_file="$ops_dir/intents.jsonl"
mkdir -p "$telemetry_dir"

previous_health_status="healthy"
previous_health_reason_codes='[]'
if [[ -f "$health_file" ]]; then
  previous_health_json=$(jq -c '.' "$health_file" 2>/dev/null || echo "{}")
  previous_health_status=$(jq -r '.status // "healthy"' <<<"$previous_health_json")
  previous_health_reason_codes=$(jq -c '.reasonCodes // []' <<<"$previous_health_json")
fi

cursor_start_offset="0"
if [[ "$from_start" != "1" && -f "$cursor_file" ]]; then
  cursor_start_offset=$(jq -r '.eventLineOffset // 0' "$cursor_file" 2>/dev/null || echo "0")
  if [[ ! "$cursor_start_offset" =~ ^[0-9]+$ ]]; then
    cursor_start_offset="0"
  fi
fi

reconcile_started_at="$(timestamp)"
reconcile_started_epoch=$(date -u +%s)

ingest_status="success"
failure_code=""
failure_message=""
state_json=""

transport_failure_streak="0"
health_json='{}'
health_status="healthy"
health_reason_codes='[]'

append_reconcile_telemetry() {
  local end_offset="0"
  if [[ -f "$cursor_file" ]]; then
    end_offset=$(jq -r '.eventLineOffset // 0' "$cursor_file" 2>/dev/null || echo "0")
  fi
  if [[ ! "$end_offset" =~ ^[0-9]+$ ]]; then
    end_offset="0"
  fi

  local events_ingested="0"
  if [[ -f "$events_file" ]]; then
    events_ingested=$(sed '/^$/d' "$events_file" | wc -l | tr -d ' ')
  fi
  if [[ ! "$events_ingested" =~ ^[0-9]+$ ]]; then
    events_ingested="0"
  fi

  local reconcile_completed_at
  reconcile_completed_at="$(timestamp)"
  local reconcile_completed_epoch
  reconcile_completed_epoch=$(date -u +%s)
  local duration_seconds=$(( reconcile_completed_epoch - reconcile_started_epoch ))
  if (( duration_seconds < 0 )); then
    duration_seconds=0
  fi

  jq -cn \
    --arg timestamp "$reconcile_completed_at" \
    --arg started_at "$reconcile_started_at" \
    --arg loop_id "$loop_id" \
    --arg transport "$transport" \
    --arg status "$ingest_status" \
    --arg failure_code "$failure_code" \
    --arg failure_message "$failure_message" \
    --argjson cursor_start_offset "$cursor_start_offset" \
    --argjson cursor_end_offset "$end_offset" \
    --argjson events_ingested "$events_ingested" \
    --argjson max_events "$max_events" \
    --argjson from_start "$from_start" \
    --argjson retry_attempts "$retry_attempts" \
    --argjson retry_backoff_seconds "$retry_backoff_seconds" \
    --argjson duration_seconds "$duration_seconds" \
    --argjson transport_failure_streak "$transport_failure_streak" \
    --arg health_status "$health_status" \
    --argjson health_reason_codes "$health_reason_codes" \
    '{
      timestamp: $timestamp,
      startedAt: $started_at,
      loopId: $loop_id,
      transport: $transport,
      status: $status,
      failureCode: (if ($failure_code | length) > 0 then $failure_code else null end),
      failureMessage: (if ($failure_message | length) > 0 then $failure_message else null end),
      cursorOffsetBefore: $cursor_start_offset,
      cursorOffsetAfter: $cursor_end_offset,
      eventsIngested: $events_ingested,
      maxEvents: $max_events,
      fromStart: ($from_start == 1),
      retryAttempts: $retry_attempts,
      retryBackoffSeconds: $retry_backoff_seconds,
      durationSeconds: $duration_seconds,
      transportFailureStreak: $transport_failure_streak,
      healthStatus: $health_status,
      healthReasonCodes: $health_reason_codes
    } | with_entries(select(.value != null))' >> "$reconcile_telemetry_file"
}

update_transport_health() {
  local next_status="$1"
  local next_failure_code="$2"

  local previous_json="{}"
  if [[ -f "$transport_health_file" ]]; then
    previous_json=$(jq -c '.' "$transport_health_file" 2>/dev/null || echo "{}")
  fi

  local previous_streak
  previous_streak=$(jq -r '.failureStreak // 0' <<<"$previous_json")
  if [[ ! "$previous_streak" =~ ^[0-9]+$ ]]; then
    previous_streak=0
  fi
  local previous_last_success
  previous_last_success=$(jq -r '.lastSuccessAt // empty' <<<"$previous_json")
  local previous_last_failure
  previous_last_failure=$(jq -r '.lastFailureAt // empty' <<<"$previous_json")

  local updated_at
  updated_at="$(timestamp)"
  local last_success="$previous_last_success"
  local last_failure="$previous_last_failure"

  if [[ "$next_status" == "success" ]]; then
    transport_failure_streak="0"
    last_success="$updated_at"
  else
    transport_failure_streak=$(( previous_streak + 1 ))
    last_failure="$updated_at"
  fi

  jq -cn \
    --arg schema_version "v1" \
    --arg updated_at "$updated_at" \
    --arg transport "$transport" \
    --arg status "$next_status" \
    --arg failure_code "$next_failure_code" \
    --arg last_success "$last_success" \
    --arg last_failure "$last_failure" \
    --argjson failure_streak "$transport_failure_streak" \
    '{
      schemaVersion: $schema_version,
      updatedAt: $updated_at,
      transport: $transport,
      lastResult: $status,
      failureStreak: $failure_streak,
      lastFailureCode: (if ($failure_code | length) > 0 then $failure_code else null end),
      lastSuccessAt: (if ($last_success | length) > 0 then $last_success else null end),
      lastFailureAt: (if ($last_failure | length) > 0 then $last_failure else null end)
    } | with_entries(select(.value != null))' > "$transport_health_file"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

snapshot_file="$tmp_dir/snapshot.json"
events_file="$tmp_dir/events.ndjson"

if [[ "$transport" == "local" ]]; then
  if ! "$script_dir/ops-manager-loop-run-snapshot.sh" --repo "$repo" --loop "$loop_id" > "$snapshot_file" 2>"$tmp_dir/snapshot.err"; then
    ingest_status="failed"
    failure_code="snapshot_unavailable"
    failure_message=$(tail -n 40 "$tmp_dir/snapshot.err" | sed 's/\r$//' || true)
  fi

  if [[ "$ingest_status" == "success" ]]; then
    poll_args=(
      --repo "$repo"
      --loop "$loop_id"
      --cursor-file "$cursor_file"
    )
    if [[ "$from_start" == "1" ]]; then
      poll_args+=(--from-start)
    fi
    if [[ "$max_events" -gt 0 ]]; then
      poll_args+=(--max-events "$max_events")
    fi

    if ! "$script_dir/ops-manager-poll-events.sh" "${poll_args[@]}" > "$events_file" 2>"$tmp_dir/events.err"; then
      ingest_status="failed"
      failure_code="events_unavailable"
      failure_message=$(tail -n 40 "$tmp_dir/events.err" | sed 's/\r$//' || true)
    fi
  fi
else
  if [[ -z "$service_base_url" ]]; then
    die "--service-base-url is required when --transport sprite_service"
  fi
  need_cmd curl

  snapshot_json=""
  if snapshot_json=$(
    "$client_script" \
      --method GET \
      --base-url "$service_base_url" \
      --path "/ops/snapshot?loopId=$loop_id" \
      --token "$service_header" \
      --retry-attempts "$retry_attempts" \
      --retry-backoff-seconds "$retry_backoff_seconds" 2>&1
  ); then
    jq -c '.' <<<"$snapshot_json" > "$snapshot_file"
  else
    ingest_status="failed"
    failure_code="service_request_failed"
    failure_message=$(printf '%s\n' "$snapshot_json" | tail -n 40 | sed 's/\r$//' || true)
  fi

  start_offset="0"
  if [[ "$from_start" != "1" && -f "$cursor_file" ]]; then
    start_offset=$(jq -r '.eventLineOffset // 0' "$cursor_file" 2>/dev/null || echo "0")
    if [[ ! "$start_offset" =~ ^[0-9]+$ ]]; then
      start_offset="0"
    fi
  fi

  events_response=""
  if [[ "$ingest_status" == "success" ]]; then
    if events_response=$(
      "$client_script" \
        --method GET \
        --base-url "$service_base_url" \
        --path "/ops/events?loopId=$loop_id&cursor=$start_offset&maxEvents=$max_events" \
        --token "$service_header" \
        --retry-attempts "$retry_attempts" \
        --retry-backoff-seconds "$retry_backoff_seconds" 2>&1
    ); then
      :
    else
      ingest_status="failed"
      failure_code="service_request_failed"
      failure_message=$(printf '%s\n' "$events_response" | tail -n 40 | sed 's/\r$//' || true)
    fi
  fi

  if [[ "$ingest_status" == "success" ]]; then
    if ! jq -e '.ok == true and (.events | type == "array") and (.cursor | type == "object")' <<<"$events_response" >/dev/null; then
      ingest_status="failed"
      failure_code="service_response_invalid"
      failure_message="service /ops/events response shape invalid"
    fi
  fi

  if [[ "$ingest_status" == "success" ]]; then
    jq -c '.events[]?' <<<"$events_response" > "$events_file"

    cursor_offset=$(jq -r '.cursor.eventLineOffset // 0' <<<"$events_response")
    cursor_count=$(jq -r '.cursor.eventLineCount // 0' <<<"$events_response")
    if [[ ! "$cursor_offset" =~ ^[0-9]+$ || ! "$cursor_count" =~ ^[0-9]+$ ]]; then
      ingest_status="failed"
      failure_code="service_response_invalid"
      failure_message="service cursor values are invalid"
    else
      jq -n \
        --arg schema_version "v1" \
        --arg repo_path "$repo" \
        --arg loop_id "$loop_id" \
        --arg events_path ".superloop/loops/$loop_id/events.jsonl" \
        --arg updated_at "$(timestamp)" \
        --argjson line_offset "$cursor_offset" \
        --argjson line_count "$cursor_count" \
        '{
          schemaVersion: $schema_version,
          repoPath: $repo_path,
          loopId: $loop_id,
          eventsFile: $events_path,
          eventLineOffset: $line_offset,
          eventLineCount: $line_count,
          updatedAt: $updated_at
        }' > "$cursor_file"
    fi
  fi
fi

if [[ "$ingest_status" == "success" ]]; then
  project_args=(
    --repo "$repo"
    --loop "$loop_id"
    --snapshot-file "$snapshot_file"
    --events-file "$events_file"
    --state-file "$state_file"
  )

  if state_json=$("$script_dir/ops-manager-project-state.sh" "${project_args[@]}" 2>&1); then
    :
  else
    ingest_status="failed"
    failure_code="projection_failed"
    failure_message=$(printf '%s\n' "$state_json" | tail -n 40 | sed 's/\r$//' || true)
    state_json=""
  fi
fi

if [[ "$ingest_status" == "success" ]]; then
  update_transport_health "success" ""
else
  update_transport_health "failed" "$failure_code"
fi

health_json=$(
  "$health_script" \
    --state-file "$state_file" \
    --transport-health-file "$transport_health_file" \
    --intents-file "$intents_file" \
    --transport "$transport" \
    --ingest-status "$ingest_status" \
    --failure-code "$failure_code" \
    --degraded-ingest-lag-seconds "$degraded_ingest_lag_seconds" \
    --critical-ingest-lag-seconds "$critical_ingest_lag_seconds" \
    --degraded-transport-failure-streak "$degraded_transport_failure_streak" \
    --critical-transport-failure-streak "$critical_transport_failure_streak" \
    --now "$(timestamp)"
)

jq -c '.' <<<"$health_json" > "$health_file"
health_status=$(jq -r '.status // "healthy"' <<<"$health_json")
health_reason_codes=$(jq -c '.reasonCodes // []' <<<"$health_json")

if [[ "$ingest_status" == "success" ]]; then
  state_json=$(jq -c --argjson health "$health_json" '. + {health: $health}' <<<"$state_json")
  jq -c '.' <<<"$state_json" > "$state_file"
else
  if [[ -f "$state_file" ]]; then
    fallback_state=$(jq -c '.' "$state_file" 2>/dev/null || echo '{}')
    fallback_state=$(jq -c --argjson health "$health_json" '. + {health: $health}' <<<"$fallback_state")
    jq -c '.' <<<"$fallback_state" > "$state_file"
  fi
fi

escalations_file="$ops_dir/escalations.jsonl"

if [[ "$ingest_status" == "success" ]]; then
  divergence_any=$(jq -r '.divergence.any // false' <<<"$state_json")
  if [[ "$divergence_any" == "true" ]]; then
    jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg state_file "$state_file" \
      --arg cursor_file "$cursor_file" \
      --arg transport "$transport" \
      --argjson state "$state_json" \
      --arg divergence_summary "$(jq -c '.divergence.flags // {}' <<<"$state_json")" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        category: "divergence_detected",
        transport: $transport,
        stateFile: $state_file,
        cursorFile: $cursor_file,
        divergenceFlags: ($divergence_summary | fromjson? // {}),
        state: {
          transition: ($state.transition // {}),
          projection: ($state.projection // {}),
          cursor: ($state.cursor // {})
        }
      }' >> "$escalations_file"
  fi
fi

if [[ "$health_status" != "healthy" ]]; then
  if [[ "$previous_health_status" != "$health_status" || "$previous_health_reason_codes" != "$health_reason_codes" ]]; then
    jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg transport "$transport" \
      --arg category "health_${health_status}" \
      --arg state_file "$state_file" \
      --arg cursor_file "$cursor_file" \
      --arg health_file "$health_file" \
      --arg ingest_status "$ingest_status" \
      --arg failure_code "$failure_code" \
      --argjson health "$health_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        category: $category,
        transport: $transport,
        ingestStatus: $ingest_status,
        failureCode: (if ($failure_code | length) > 0 then $failure_code else null end),
        stateFile: $state_file,
        cursorFile: $cursor_file,
        healthFile: $health_file,
        healthStatus: ($health.status // "unknown"),
        reasonCodes: ($health.reasonCodes // []),
        reasons: ($health.reasons // [])
      } | with_entries(select(.value != null))' >> "$escalations_file"
  fi
fi

append_reconcile_telemetry

if [[ "$ingest_status" == "success" ]]; then
  if [[ "$pretty" == "1" ]]; then
    jq '.' <<<"$state_json"
  else
    jq -c '.' <<<"$state_json"
  fi
  exit 0
fi

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$health_json"
else
  jq -c '.' <<<"$health_json"
fi
exit 1
