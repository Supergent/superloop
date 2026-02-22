#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-health.sh [options]

Options:
  --state-file <path>                         Optional manager state JSON file.
  --transport-health-file <path>              Optional transport health JSON file.
  --intents-file <path>                       Optional intents JSONL file.
  --transport <local|sprite_service>          Transport mode label (default: local)
  --threshold-profile <name>                  Optional applied threshold profile label.
  --ingest-status <success|failed>            Reconcile ingest result (default: success)
  --failure-code <code>                       Optional reconcile failure code.
  --degraded-ingest-lag-seconds <n>           Degraded threshold (default: 300)
  --critical-ingest-lag-seconds <n>           Critical threshold (default: 900)
  --degraded-transport-failure-streak <n>     Degraded threshold (default: 2)
  --critical-transport-failure-streak <n>     Critical threshold (default: 4)
  --now <timestamp>                           Override current UTC time (ISO-8601)
  --pretty                                    Pretty-print output JSON.
  --help                                      Show this help message.
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

state_file=""
transport_health_file=""
intents_file=""
transport="local"
threshold_profile=""
ingest_status="success"
failure_code=""
degraded_ingest_lag_seconds="300"
critical_ingest_lag_seconds="900"
degraded_transport_failure_streak="2"
critical_transport_failure_streak="4"
now_value=""
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file)
      state_file="${2:-}"
      shift 2
      ;;
    --transport-health-file)
      transport_health_file="${2:-}"
      shift 2
      ;;
    --intents-file)
      intents_file="${2:-}"
      shift 2
      ;;
    --transport)
      transport="${2:-}"
      shift 2
      ;;
    --threshold-profile)
      threshold_profile="${2:-}"
      shift 2
      ;;
    --ingest-status)
      ingest_status="${2:-}"
      shift 2
      ;;
    --failure-code)
      failure_code="${2:-}"
      shift 2
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
    --now)
      now_value="${2:-}"
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

case "$transport" in
  local|sprite_service)
    ;;
  *)
    die "--transport must be local or sprite_service"
    ;;
esac
case "$ingest_status" in
  success|failed)
    ;;
  *)
    die "--ingest-status must be success or failed"
    ;;
esac

for value_name in degraded_ingest_lag_seconds critical_ingest_lag_seconds degraded_transport_failure_streak critical_transport_failure_streak; do
  value="${!value_name}"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    die "${value_name//_/\-} must be a non-negative integer"
  fi
done

if (( critical_ingest_lag_seconds < degraded_ingest_lag_seconds )); then
  die "critical ingest lag threshold must be >= degraded threshold"
fi
if (( critical_transport_failure_streak < degraded_transport_failure_streak )); then
  die "critical transport failure threshold must be >= degraded threshold"
fi

now_iso="$now_value"
if [[ -z "$now_iso" ]]; then
  now_iso="$(timestamp)"
fi

now_epoch=$(jq -rn --arg t "$now_iso" '($t | fromdateiso8601? // empty)' 2>/dev/null || true)
if [[ -z "$now_epoch" || ! "$now_epoch" =~ ^[0-9]+$ ]]; then
  die "--now must be an ISO-8601 UTC timestamp"
fi

state_json='{}'
if [[ -n "$state_file" && -f "$state_file" ]]; then
  state_json=$(jq -c '.' "$state_file" 2>/dev/null) || die "invalid state JSON: $state_file"
fi

transport_json='{}'
if [[ -n "$transport_health_file" && -f "$transport_health_file" ]]; then
  transport_json=$(jq -c '.' "$transport_health_file" 2>/dev/null) || die "invalid transport health JSON: $transport_health_file"
fi

last_intent_status=""
if [[ -n "$intents_file" && -f "$intents_file" ]]; then
  if tail_line=$(tail -n 1 "$intents_file" 2>/dev/null); then
    if [[ -n "$tail_line" ]]; then
      last_intent_status=$(jq -r '.status // empty' <<<"$tail_line" 2>/dev/null || echo "")
    fi
  fi
fi

divergence_any=$(jq -r '.divergence.any // false' <<<"$state_json")
last_event_at=$(jq -r '.projection.lastEventAt // empty' <<<"$state_json")
lifecycle_state=$(jq -r '.transition.currentState // (.projection.status // "unknown")' <<<"$state_json")

ingest_lag_seconds=""
if [[ -n "$last_event_at" ]]; then
  event_epoch=$(jq -rn --arg t "$last_event_at" '($t | fromdateiso8601? // empty)' 2>/dev/null || true)
  if [[ -n "$event_epoch" && "$event_epoch" =~ ^[0-9]+$ ]]; then
    lag=$(( now_epoch - event_epoch ))
    if (( lag < 0 )); then
      lag=0
    fi
    ingest_lag_seconds="$lag"
  fi
fi

transport_failure_streak=$(jq -r '.failureStreak // 0' <<<"$transport_json")
if [[ ! "$transport_failure_streak" =~ ^[0-9]+$ ]]; then
  transport_failure_streak="0"
fi
last_transport_failure_code=$(jq -r '.lastFailureCode // empty' <<<"$transport_json")

reasons_tmp="$(mktemp)"
trap 'rm -f "$reasons_tmp"' EXIT

health_rank=0

add_reason() {
  local code="$1"
  local severity="$2"
  local metric="${3:-}"
  local observed="${4:-}"
  local threshold="${5:-}"

  jq -cn \
    --arg code "$code" \
    --arg severity "$severity" \
    --arg metric "$metric" \
    --arg observed "$observed" \
    --arg threshold "$threshold" \
    '{
      code: $code,
      severity: $severity,
      metric: (if ($metric | length) > 0 then $metric else null end),
      observed: (if ($observed | length) > 0 then $observed else null end),
      threshold: (if ($threshold | length) > 0 then $threshold else null end)
    } | with_entries(select(.value != null))' >> "$reasons_tmp"

  case "$severity" in
    critical)
      health_rank=2
      ;;
    degraded)
      if (( health_rank < 1 )); then
        health_rank=1
      fi
      ;;
  esac
}

if [[ "$divergence_any" == "true" ]]; then
  add_reason "divergence_detected" "degraded" "divergence.any" "true" "false"
fi

case "$last_intent_status" in
  ambiguous)
    add_reason "control_ambiguous" "degraded" "control.status" "$last_intent_status" "confirmed"
    ;;
  failed_command)
    add_reason "control_failed_command" "degraded" "control.status" "$last_intent_status" "confirmed"
    ;;
esac

if [[ -n "$ingest_lag_seconds" ]]; then
  if (( ingest_lag_seconds >= critical_ingest_lag_seconds )); then
    add_reason "ingest_stale" "critical" "ingestLagSeconds" "$ingest_lag_seconds" "$critical_ingest_lag_seconds"
  elif (( ingest_lag_seconds >= degraded_ingest_lag_seconds )); then
    add_reason "ingest_stale" "degraded" "ingestLagSeconds" "$ingest_lag_seconds" "$degraded_ingest_lag_seconds"
  fi
fi

if (( transport_failure_streak >= critical_transport_failure_streak )); then
  add_reason "transport_unreachable" "critical" "transportFailureStreak" "$transport_failure_streak" "$critical_transport_failure_streak"
elif (( transport_failure_streak >= degraded_transport_failure_streak )); then
  add_reason "transport_unreachable" "degraded" "transportFailureStreak" "$transport_failure_streak" "$degraded_transport_failure_streak"
fi

if [[ "$ingest_status" == "failed" ]]; then
  case "$failure_code" in
    snapshot_unavailable|events_unavailable|service_request_failed)
      add_reason "transport_unreachable" "degraded" "ingestStatus" "failed" "success"
      ;;
    service_response_invalid)
      add_reason "invalid_transport_payload" "degraded" "ingestStatus" "failed" "success"
      ;;
    projection_failed)
      add_reason "projection_failed" "degraded" "ingestStatus" "failed" "success"
      ;;
    "")
      add_reason "reconcile_failed" "degraded" "ingestStatus" "failed" "success"
      ;;
    *)
      add_reason "$failure_code" "degraded" "ingestStatus" "failed" "success"
      ;;
  esac
fi

if [[ -s "$reasons_tmp" ]]; then
  reasons_json=$(jq -cs 'unique_by(.code + ":" + .severity)' "$reasons_tmp")
else
  reasons_json='[]'
fi
reason_codes=$(jq -c '[.[].code] | unique' <<<"$reasons_json")

health_status="healthy"
if (( health_rank == 2 )); then
  health_status="critical"
elif (( health_rank == 1 )); then
  health_status="degraded"
fi

health_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg updated_at "$now_iso" \
  --arg status "$health_status" \
  --arg transport "$transport" \
  --arg threshold_profile "$threshold_profile" \
  --arg ingest_status "$ingest_status" \
  --arg failure_code "$failure_code" \
  --arg last_transport_failure_code "$last_transport_failure_code" \
  --arg lifecycle_state "$lifecycle_state" \
  --arg last_intent_status "$last_intent_status" \
  --arg last_event_at "$last_event_at" \
  --arg ingest_lag "$ingest_lag_seconds" \
  --argjson transport_failure_streak "$transport_failure_streak" \
  --argjson degraded_ingest "$degraded_ingest_lag_seconds" \
  --argjson critical_ingest "$critical_ingest_lag_seconds" \
  --argjson degraded_streak "$degraded_transport_failure_streak" \
  --argjson critical_streak "$critical_transport_failure_streak" \
  --argjson reason_codes "$reason_codes" \
  --argjson reasons "$reasons_json" \
  '{
    schemaVersion: $schema_version,
    updatedAt: $updated_at,
    status: $status,
    reasonCodes: $reason_codes,
    reasons: $reasons,
    metrics: {
      ingestLagSeconds: (if ($ingest_lag | length) > 0 then ($ingest_lag | tonumber) else null end),
      transportFailureStreak: $transport_failure_streak,
      lastControlStatus: (if ($last_intent_status | length) > 0 then $last_intent_status else null end),
      lifecycleState: $lifecycle_state
    },
    thresholds: {
      profile: (if ($threshold_profile | length) > 0 then $threshold_profile else null end),
      degradedIngestLagSeconds: $degraded_ingest,
      criticalIngestLagSeconds: $critical_ingest,
      degradedTransportFailureStreak: $degraded_streak,
      criticalTransportFailureStreak: $critical_streak
    },
    transport: {
      mode: $transport,
      ingestStatus: $ingest_status,
      failureCode: (if ($failure_code | length) > 0 then $failure_code else null end),
      lastFailureCode: (if ($last_transport_failure_code | length) > 0 then $last_transport_failure_code else null end)
    },
    evidence: {
      lastEventAt: (if ($last_event_at | length) > 0 then $last_event_at else null end)
    }
  }')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$health_json"
else
  jq -c '.' <<<"$health_json"
fi
