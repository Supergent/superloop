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
  --threshold-profile <name>                     Threshold profile name from catalog (default: catalog default)
  --thresholds-file <path>                       Threshold profile catalog JSON path
  --drift-min-confidence <level>                 Minimum drift confidence (low|medium|high, default: medium)
  --drift-required-streak <n>                    Consecutive mismatches before active drift (default: 3)
  --drift-summary-window <n>                     Telemetry summary window for drift (default: 200)
  --drift-state-file <path>                      Drift state JSON path. Default: <repo>/.superloop/ops-manager/<loop>/profile-drift.json
  --drift-history-file <path>                    Drift history JSONL path. Default: <repo>/.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl
  --alerts-enabled <true|false>                  Enable alert dispatch pass (default: true)
  --alert-config-file <path>                     Alert sink config JSON path
  --alert-dispatch-state-file <path>             Alert dispatch state path. Default: <repo>/.superloop/ops-manager/<loop>/alert-dispatch-state.json
  --alert-dispatch-telemetry-file <path>         Alert dispatch telemetry JSONL path. Default: <repo>/.superloop/ops-manager/<loop>/telemetry/alerts.jsonl
  --heartbeat-state-file <path>                  Heartbeat state JSON path. Default: <repo>/.superloop/ops-manager/<loop>/heartbeat.json
  --heartbeat-telemetry-file <path>              Heartbeat telemetry JSONL path. Default: <repo>/.superloop/ops-manager/<loop>/telemetry/heartbeat.jsonl
  --degraded-ingest-lag-seconds <n>              Degraded ingest staleness threshold (default: 300)
  --critical-ingest-lag-seconds <n>              Critical ingest staleness threshold (default: 900)
  --degraded-heartbeat-lag-seconds <n>           Degraded heartbeat staleness threshold (default: 120)
  --critical-heartbeat-lag-seconds <n>           Critical heartbeat staleness threshold (default: 300)
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
threshold_profile=""
thresholds_file=""
drift_min_confidence="medium"
drift_required_streak="3"
drift_summary_window="200"
drift_state_file=""
drift_history_file=""
alerts_enabled="true"
alert_config_file=""
alert_dispatch_state_file=""
alert_dispatch_telemetry_file=""
heartbeat_state_file=""
heartbeat_telemetry_file=""
degraded_ingest_lag_seconds="300"
critical_ingest_lag_seconds="900"
degraded_heartbeat_lag_seconds="120"
critical_heartbeat_lag_seconds="300"
degraded_transport_failure_streak="2"
critical_transport_failure_streak="4"
pretty="0"
flag_degraded_ingest_lag_seconds="0"
flag_critical_ingest_lag_seconds="0"
flag_degraded_transport_failure_streak="0"
flag_critical_transport_failure_streak="0"
flag_drift_min_confidence="0"
flag_drift_required_streak="0"
flag_drift_summary_window="0"
flag_alerts_enabled="0"

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
    --threshold-profile)
      threshold_profile="${2:-}"
      shift 2
      ;;
    --thresholds-file)
      thresholds_file="${2:-}"
      shift 2
      ;;
    --drift-min-confidence)
      drift_min_confidence="${2:-}"
      flag_drift_min_confidence="1"
      shift 2
      ;;
    --drift-required-streak)
      drift_required_streak="${2:-}"
      flag_drift_required_streak="1"
      shift 2
      ;;
    --drift-summary-window)
      drift_summary_window="${2:-}"
      flag_drift_summary_window="1"
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
    --alerts-enabled)
      alerts_enabled="${2:-}"
      flag_alerts_enabled="1"
      shift 2
      ;;
    --alert-config-file)
      alert_config_file="${2:-}"
      shift 2
      ;;
    --alert-dispatch-state-file)
      alert_dispatch_state_file="${2:-}"
      shift 2
      ;;
    --alert-dispatch-telemetry-file)
      alert_dispatch_telemetry_file="${2:-}"
      shift 2
      ;;
    --heartbeat-state-file)
      heartbeat_state_file="${2:-}"
      shift 2
      ;;
    --heartbeat-telemetry-file)
      heartbeat_telemetry_file="${2:-}"
      shift 2
      ;;
    --degraded-ingest-lag-seconds)
      degraded_ingest_lag_seconds="${2:-}"
      flag_degraded_ingest_lag_seconds="1"
      shift 2
      ;;
    --critical-ingest-lag-seconds)
      critical_ingest_lag_seconds="${2:-}"
      flag_critical_ingest_lag_seconds="1"
      shift 2
      ;;
    --degraded-heartbeat-lag-seconds)
      degraded_heartbeat_lag_seconds="${2:-}"
      shift 2
      ;;
    --critical-heartbeat-lag-seconds)
      critical_heartbeat_lag_seconds="${2:-}"
      shift 2
      ;;
    --degraded-transport-failure-streak)
      degraded_transport_failure_streak="${2:-}"
      flag_degraded_transport_failure_streak="1"
      shift 2
      ;;
    --critical-transport-failure-streak)
      critical_transport_failure_streak="${2:-}"
      flag_critical_transport_failure_streak="1"
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
if [[ ! "$drift_required_streak" =~ ^[0-9]+$ || "$drift_required_streak" -lt 1 ]]; then
  die "--drift-required-streak must be an integer >= 1"
fi
if [[ ! "$drift_summary_window" =~ ^[0-9]+$ || "$drift_summary_window" -lt 1 ]]; then
  die "--drift-summary-window must be an integer >= 1"
fi
case "$alerts_enabled" in
  true|false)
    ;;
  *)
    die "--alerts-enabled must be true or false"
    ;;
esac

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
threshold_profile_script="${OPS_MANAGER_THRESHOLD_PROFILE_SCRIPT:-$script_dir/ops-manager-threshold-profile.sh}"
telemetry_summary_script="${OPS_MANAGER_TELEMETRY_SUMMARY_SCRIPT:-$script_dir/ops-manager-telemetry-summary.sh}"
profile_drift_script="${OPS_MANAGER_PROFILE_DRIFT_SCRIPT:-$script_dir/ops-manager-profile-drift.sh}"
alert_dispatch_script="${OPS_MANAGER_ALERT_DISPATCH_SCRIPT:-$script_dir/ops-manager-alert-dispatch.sh}"
root_dir="$(cd "$script_dir/.." && pwd)"

if [[ -z "$service_header" && -n "${OPS_MANAGER_SERVICE_TOKEN:-}" ]]; then
  service_header="$OPS_MANAGER_SERVICE_TOKEN"
fi
if [[ -z "$threshold_profile" && -n "${OPS_MANAGER_THRESHOLD_PROFILE:-}" ]]; then
  threshold_profile="$OPS_MANAGER_THRESHOLD_PROFILE"
fi
if [[ -z "$thresholds_file" && -n "${OPS_MANAGER_THRESHOLD_PROFILES_FILE:-}" ]]; then
  thresholds_file="$OPS_MANAGER_THRESHOLD_PROFILES_FILE"
fi
if [[ "$flag_alerts_enabled" != "1" && -n "${OPS_MANAGER_ALERTS_ENABLED:-}" ]]; then
  alerts_enabled="$OPS_MANAGER_ALERTS_ENABLED"
fi
if [[ -z "$alert_config_file" && -n "${OPS_MANAGER_ALERT_SINKS_FILE:-}" ]]; then
  alert_config_file="$OPS_MANAGER_ALERT_SINKS_FILE"
fi
if [[ "$flag_drift_min_confidence" != "1" && -n "${OPS_MANAGER_DRIFT_MIN_CONFIDENCE:-}" ]]; then
  drift_min_confidence="$OPS_MANAGER_DRIFT_MIN_CONFIDENCE"
fi
if [[ "$flag_drift_required_streak" != "1" && -n "${OPS_MANAGER_DRIFT_REQUIRED_STREAK:-}" ]]; then
  drift_required_streak="$OPS_MANAGER_DRIFT_REQUIRED_STREAK"
fi
if [[ "$flag_drift_summary_window" != "1" && -n "${OPS_MANAGER_DRIFT_SUMMARY_WINDOW:-}" ]]; then
  drift_summary_window="$OPS_MANAGER_DRIFT_SUMMARY_WINDOW"
fi
if [[ -z "$thresholds_file" ]]; then
  thresholds_file="$root_dir/config/ops-manager-threshold-profiles.v1.json"
fi

profile_args=(--profiles-file "$thresholds_file")
if [[ -n "$threshold_profile" ]]; then
  profile_args+=(--profile "$threshold_profile")
fi
profile_resolved_json=$("$threshold_profile_script" "${profile_args[@]}")
threshold_profile=$(jq -r '.profile // empty' <<<"$profile_resolved_json")

if [[ "$flag_degraded_ingest_lag_seconds" != "1" ]]; then
  degraded_ingest_lag_seconds=$(jq -r '.values.degradedIngestLagSeconds' <<<"$profile_resolved_json")
fi
if [[ "$flag_critical_ingest_lag_seconds" != "1" ]]; then
  critical_ingest_lag_seconds=$(jq -r '.values.criticalIngestLagSeconds' <<<"$profile_resolved_json")
fi
if [[ "$flag_degraded_transport_failure_streak" != "1" ]]; then
  degraded_transport_failure_streak=$(jq -r '.values.degradedTransportFailureStreak' <<<"$profile_resolved_json")
fi
if [[ "$flag_critical_transport_failure_streak" != "1" ]]; then
  critical_transport_failure_streak=$(jq -r '.values.criticalTransportFailureStreak' <<<"$profile_resolved_json")
fi

case "$drift_min_confidence" in
  low|medium|high)
    ;;
  *)
    die "--drift-min-confidence must be one of: low, medium, high"
    ;;
esac
if [[ ! "$drift_required_streak" =~ ^[0-9]+$ || "$drift_required_streak" -lt 1 ]]; then
  die "--drift-required-streak must be an integer >= 1"
fi
if [[ ! "$drift_summary_window" =~ ^[0-9]+$ || "$drift_summary_window" -lt 1 ]]; then
  die "--drift-summary-window must be an integer >= 1"
fi

for threshold_name in degraded_ingest_lag_seconds critical_ingest_lag_seconds degraded_heartbeat_lag_seconds critical_heartbeat_lag_seconds degraded_transport_failure_streak critical_transport_failure_streak; do
  threshold_value="${!threshold_name}"
  if [[ ! "$threshold_value" =~ ^[0-9]+$ ]]; then
    die "${threshold_name//_/\-} must be a non-negative integer"
  fi
done
if (( critical_ingest_lag_seconds < degraded_ingest_lag_seconds )); then
  die "critical ingest lag threshold must be >= degraded threshold"
fi
if (( critical_heartbeat_lag_seconds < degraded_heartbeat_lag_seconds )); then
  die "critical heartbeat lag threshold must be >= degraded threshold"
fi
if (( critical_transport_failure_streak < degraded_transport_failure_streak )); then
  die "critical transport failure threshold must be >= degraded threshold"
fi

telemetry_dir="$ops_dir/telemetry"
escalations_file="$ops_dir/escalations.jsonl"
reconcile_telemetry_file="$telemetry_dir/reconcile.jsonl"
control_telemetry_file="$telemetry_dir/control.jsonl"
transport_health_file="$telemetry_dir/transport-health.json"
health_file="$ops_dir/health.json"
intents_file="$ops_dir/intents.jsonl"
if [[ -z "$alert_dispatch_state_file" ]]; then
  alert_dispatch_state_file="$ops_dir/alert-dispatch-state.json"
fi
if [[ -z "$alert_dispatch_telemetry_file" ]]; then
  alert_dispatch_telemetry_file="$telemetry_dir/alerts.jsonl"
fi
if [[ -z "$heartbeat_state_file" ]]; then
  heartbeat_state_file="$ops_dir/heartbeat.json"
fi
if [[ -z "$heartbeat_telemetry_file" ]]; then
  heartbeat_telemetry_file="$telemetry_dir/heartbeat.jsonl"
fi
if [[ -z "$drift_state_file" ]]; then
  drift_state_file="$ops_dir/profile-drift.json"
fi
if [[ -z "$drift_history_file" ]]; then
  drift_history_file="$telemetry_dir/profile-drift.jsonl"
fi
mkdir -p "$telemetry_dir"
mkdir -p "$(dirname "$heartbeat_state_file")"
mkdir -p "$(dirname "$heartbeat_telemetry_file")"

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
tuning_summary_json='null'
drift_json='null'
alert_dispatch_json='null'

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
    --arg threshold_profile "$threshold_profile" \
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
      thresholdProfile: (if ($threshold_profile | length) > 0 then $threshold_profile else null end),
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

persist_heartbeat_observation() {
  if [[ ! -f "$snapshot_file" ]]; then
    return 0
  fi

  local heartbeat_json
  heartbeat_json=$(jq -c '.runtime.heartbeat // null' "$snapshot_file" 2>/dev/null || echo 'null')
  if [[ "$heartbeat_json" == "null" ]]; then
    return 0
  fi

  local now_iso
  now_iso="$(timestamp)"
  local now_epoch
  now_epoch=$(jq -rn --arg t "$now_iso" '($t | fromdateiso8601? // empty)' 2>/dev/null || true)
  if [[ -z "$now_epoch" || ! "$now_epoch" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  local heartbeat_at
  heartbeat_at=$(jq -r '.timestamp // .updatedAt // empty' <<<"$heartbeat_json")
  if [[ -z "$heartbeat_at" ]]; then
    jq -cn \
      --arg timestamp "$now_iso" \
      --arg loop_id "$loop_id" \
      --arg transport "$transport" \
      --arg status "failed" \
      --arg reason_code "missing_heartbeat_timestamp" \
      --argjson heartbeat "$heartbeat_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        transport: $transport,
        category: "runtime_heartbeat",
        status: $status,
        reasonCode: $reason_code,
        heartbeat: $heartbeat
      }' >> "$heartbeat_telemetry_file"
    return 0
  fi

  local heartbeat_epoch
  heartbeat_epoch=$(jq -rn --arg t "$heartbeat_at" '($t | fromdateiso8601? // empty)' 2>/dev/null || true)
  if [[ -z "$heartbeat_epoch" || ! "$heartbeat_epoch" =~ ^[0-9]+$ ]]; then
    jq -cn \
      --arg timestamp "$now_iso" \
      --arg loop_id "$loop_id" \
      --arg transport "$transport" \
      --arg status "failed" \
      --arg reason_code "invalid_heartbeat_timestamp" \
      --arg heartbeat_at "$heartbeat_at" \
      --argjson heartbeat "$heartbeat_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        transport: $transport,
        category: "runtime_heartbeat",
        status: $status,
        reasonCode: $reason_code,
        heartbeatAt: $heartbeat_at,
        heartbeat: $heartbeat
      }' >> "$heartbeat_telemetry_file"
    return 0
  fi

  local heartbeat_lag=$(( now_epoch - heartbeat_epoch ))
  if (( heartbeat_lag < 0 )); then
    heartbeat_lag=0
  fi

  local freshness_status="fresh"
  local reason_code=""
  if (( heartbeat_lag >= critical_heartbeat_lag_seconds )); then
    freshness_status="critical"
    reason_code="runtime_heartbeat_stale"
  elif (( heartbeat_lag >= degraded_heartbeat_lag_seconds )); then
    freshness_status="degraded"
    reason_code="runtime_heartbeat_stale"
  fi

  local heartbeat_state_json
  heartbeat_state_json=$(jq -cn \
    --arg schema_version "v1" \
    --arg updated_at "$now_iso" \
    --arg loop_id "$loop_id" \
    --arg transport "$transport" \
    --arg heartbeat_at "$heartbeat_at" \
    --arg freshness_status "$freshness_status" \
    --arg reason_code "$reason_code" \
    --argjson heartbeat_lag_seconds "$heartbeat_lag" \
    --argjson degraded_threshold "$degraded_heartbeat_lag_seconds" \
    --argjson critical_threshold "$critical_heartbeat_lag_seconds" \
    --argjson heartbeat "$heartbeat_json" \
    '{
      schemaVersion: $schema_version,
      updatedAt: $updated_at,
      loopId: $loop_id,
      transport: $transport,
      lastHeartbeatAt: $heartbeat_at,
      heartbeatLagSeconds: $heartbeat_lag_seconds,
      freshnessStatus: $freshness_status,
      reasonCode: (if ($reason_code | length) > 0 then $reason_code else null end),
      thresholds: {
        degradedHeartbeatLagSeconds: $degraded_threshold,
        criticalHeartbeatLagSeconds: $critical_threshold
      },
      heartbeat: $heartbeat
    } | with_entries(select(.value != null))')
  jq -c '.' <<<"$heartbeat_state_json" > "$heartbeat_state_file"

  jq -cn \
    --arg timestamp "$now_iso" \
    --arg loop_id "$loop_id" \
    --arg transport "$transport" \
    --arg status "$freshness_status" \
    --arg reason_code "$reason_code" \
    --arg heartbeat_at "$heartbeat_at" \
    --argjson heartbeat_lag_seconds "$heartbeat_lag" \
    --argjson heartbeat "$heartbeat_json" \
    '{
      timestamp: $timestamp,
      loopId: $loop_id,
      transport: $transport,
      category: "runtime_heartbeat",
      status: $status,
      reasonCode: (if ($reason_code | length) > 0 then $reason_code else null end),
      heartbeatAt: $heartbeat_at,
      heartbeatLagSeconds: $heartbeat_lag_seconds,
      heartbeat: $heartbeat
    } | with_entries(select(.value != null))' >> "$heartbeat_telemetry_file"
}

run_profile_drift_evaluation() {
  local summary_output=""
  tuning_summary_json='null'
  drift_json='null'

  if [[ -f "$reconcile_telemetry_file" ]]; then
    if summary_output=$(
      "$telemetry_summary_script" \
        --repo "$repo" \
        --loop "$loop_id" \
        --reconcile-telemetry-file "$reconcile_telemetry_file" \
        --control-telemetry-file "$control_telemetry_file" \
        --window "$drift_summary_window" 2>/dev/null
    ); then
      tuning_summary_json=$(jq -c '.' <<<"$summary_output" 2>/dev/null || echo 'null')
    fi
  fi

  local applied_profile="$threshold_profile"
  if [[ -z "$applied_profile" ]]; then
    applied_profile=$(jq -r '.thresholds.profile // empty' <<<"$health_json")
  fi

  local recommended_profile=""
  local recommendation_confidence="low"
  local recommendation_rationale=""
  if [[ "$tuning_summary_json" != "null" ]]; then
    recommended_profile=$(jq -r '.recommendedProfile // empty' <<<"$tuning_summary_json")
    recommendation_confidence=$(jq -r '.confidence // "low"' <<<"$tuning_summary_json")
    recommendation_rationale=$(jq -r '.rationale // empty' <<<"$tuning_summary_json")
  fi

  local drift_args=(
    --repo "$repo"
    --loop "$loop_id"
    --applied-profile "$applied_profile"
    --recommended-profile "$recommended_profile"
    --thresholds-file "$thresholds_file"
    --recommendation-confidence "$recommendation_confidence"
    --min-confidence "$drift_min_confidence"
    --required-streak "$drift_required_streak"
    --summary-window "$drift_summary_window"
    --drift-state-file "$drift_state_file"
    --drift-history-file "$drift_history_file"
  )
  if [[ -n "$recommendation_rationale" ]]; then
    drift_args+=(--rationale "$recommendation_rationale")
  fi

  local drift_output
  drift_output=$("$profile_drift_script" "${drift_args[@]}")
  drift_json=$(jq -c '.' <<<"$drift_output")
}

run_alert_dispatch() {
  alert_dispatch_json='null'
  if [[ "$alerts_enabled" != "true" ]]; then
    return 0
  fi

  local dispatch_args=(
    --repo "$repo"
    --loop "$loop_id"
    --escalations-file "$escalations_file"
    --dispatch-state-file "$alert_dispatch_state_file"
    --dispatch-telemetry-file "$alert_dispatch_telemetry_file"
  )
  if [[ -n "$alert_config_file" ]]; then
    dispatch_args+=(--alert-config-file "$alert_config_file")
  fi

  local dispatch_output=""
  if dispatch_output=$("$alert_dispatch_script" "${dispatch_args[@]}" 2>&1); then
    alert_dispatch_json=$(jq -c '.' <<<"$dispatch_output" 2>/dev/null || echo 'null')
    return 0
  fi

  local dispatch_error
  dispatch_error=$(printf '%s\n' "$dispatch_output" | tail -n 40 | sed 's/\r$//' || true)
  alert_dispatch_json=$(jq -cn \
    --arg status "failed_command" \
    --arg message "$dispatch_error" \
    '{status: $status, message: (if ($message | length) > 0 then $message else null end)} | with_entries(select(.value != null))')

  jq -cn \
    --arg timestamp "$(timestamp)" \
    --arg loop_id "$loop_id" \
    --arg status "failed_command" \
    --arg reason_code "alert_dispatch_failed" \
    --arg message "$dispatch_error" \
    '{
      timestamp: $timestamp,
      loopId: $loop_id,
      category: "alert_dispatch",
      status: $status,
      reasonCode: $reason_code,
      message: (if ($message | length) > 0 then $message else null end)
    } | with_entries(select(.value != null))' >> "$alert_dispatch_telemetry_file"
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

if [[ "$ingest_status" == "success" ]]; then
  persist_heartbeat_observation
fi

health_json=$(
  "$health_script" \
    --state-file "$state_file" \
    --heartbeat-state-file "$heartbeat_state_file" \
    --transport-health-file "$transport_health_file" \
    --intents-file "$intents_file" \
    --transport "$transport" \
    --threshold-profile "$threshold_profile" \
    --ingest-status "$ingest_status" \
    --failure-code "$failure_code" \
    --degraded-ingest-lag-seconds "$degraded_ingest_lag_seconds" \
    --critical-ingest-lag-seconds "$critical_ingest_lag_seconds" \
    --degraded-heartbeat-lag-seconds "$degraded_heartbeat_lag_seconds" \
    --critical-heartbeat-lag-seconds "$critical_heartbeat_lag_seconds" \
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
run_profile_drift_evaluation

if [[ -f "$state_file" && "$drift_json" != "null" ]]; then
  state_with_drift=$(jq -c \
    --argjson drift "$drift_json" \
    --argjson tuning_summary "$tuning_summary_json" \
    '. + {drift: $drift}
     + (
       if $tuning_summary == null then {}
       else {
         tuning: {
           appliedProfile: (.health.thresholds.profile // null),
           recommendedProfile: ($tuning_summary.recommendedProfile // null),
           confidence: ($tuning_summary.confidence // null),
           rationale: ($tuning_summary.rationale // null),
           summaryWindow: ($tuning_summary.source.window // null),
           telemetrySummary: {
             observed: ($tuning_summary.observed // {}),
             source: ($tuning_summary.source // {})
           }
         }
       }
       end
     )' "$state_file")
  jq -c '.' <<<"$state_with_drift" > "$state_file"

  if [[ "$ingest_status" == "success" ]]; then
    state_json="$state_with_drift"
  fi
fi

if [[ "$drift_json" != "null" ]]; then
  drift_to_active=$(jq -r '.transitioned.toActive // false' <<<"$drift_json")
  if [[ "$drift_to_active" == "true" ]]; then
    jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg transport "$transport" \
      --arg state_file "$state_file" \
      --arg drift_state_file "$drift_state_file" \
      --arg drift_history_file "$drift_history_file" \
      --argjson drift "$drift_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        category: "profile_drift_detected",
        transport: $transport,
        stateFile: $state_file,
        driftStateFile: $drift_state_file,
        driftHistoryFile: $drift_history_file,
        reasonCode: ($drift.reasonCode // "profile_drift_detected"),
        drift: {
          status: ($drift.status // "unknown"),
          appliedProfile: ($drift.appliedProfile // null),
          recommendedProfile: ($drift.recommendedProfile // null),
          recommendationConfidence: ($drift.recommendationConfidence // null),
          mismatchStreak: ($drift.mismatchStreak // 0),
          requiredStreak: ($drift.requiredStreak // 0),
          action: ($drift.action // null),
          rationale: ($drift.rationale // null)
        }
      } | with_entries(select(.value != null))' >> "$escalations_file"
  fi
fi

run_alert_dispatch

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
