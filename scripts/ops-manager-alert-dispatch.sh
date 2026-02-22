#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-alert-dispatch.sh --repo <path> --loop <id> [options]

Options:
  --escalations-file <path>          Escalations JSONL path. Default: <repo>/.superloop/ops-manager/<loop>/escalations.jsonl
  --dispatch-state-file <path>       Dispatch state JSON path. Default: <repo>/.superloop/ops-manager/<loop>/alert-dispatch-state.json
  --dispatch-telemetry-file <path>   Dispatch telemetry JSONL path. Default: <repo>/.superloop/ops-manager/<loop>/telemetry/alerts.jsonl
  --trace-id <id>                    Trace id for this dispatch operation (generated when omitted)
  --alert-config-file <path>         Alert sink config JSON path.
  --max-escalations <n>              Maximum new escalation rows to process (default: 0 = all available).
  --pretty                           Pretty-print output JSON.
  --help                             Show this help message.
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

severity_rank() {
  case "$1" in
    info) echo 1 ;;
    warning) echo 2 ;;
    critical) echo 3 ;;
    *) return 1 ;;
  esac
}

repo=""
loop_id=""
escalations_file=""
dispatch_state_file=""
dispatch_telemetry_file=""
trace_id=""
alert_config_file=""
max_escalations="0"
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
    --escalations-file)
      escalations_file="${2:-}"
      shift 2
      ;;
    --dispatch-state-file)
      dispatch_state_file="${2:-}"
      shift 2
      ;;
    --dispatch-telemetry-file)
      dispatch_telemetry_file="${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="${2:-}"
      shift 2
      ;;
    --alert-config-file)
      alert_config_file="${2:-}"
      shift 2
      ;;
    --max-escalations)
      max_escalations="${2:-}"
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
need_cmd curl

if [[ -z "$repo" ]]; then
  die "--repo is required"
fi
if [[ -z "$loop_id" ]]; then
  die "--loop is required"
fi
if [[ ! "$max_escalations" =~ ^[0-9]+$ ]]; then
  die "--max-escalations must be a non-negative integer"
fi

repo="$(cd "$repo" && pwd)"
ops_dir="$repo/.superloop/ops-manager/$loop_id"
telemetry_dir="$ops_dir/telemetry"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
alert_config_script="${OPS_MANAGER_ALERT_SINK_CONFIG_SCRIPT:-$script_dir/ops-manager-alert-sink-config.sh}"

if [[ -z "$escalations_file" ]]; then
  escalations_file="$ops_dir/escalations.jsonl"
fi
if [[ -z "$dispatch_state_file" ]]; then
  dispatch_state_file="$ops_dir/alert-dispatch-state.json"
fi
if [[ -z "$dispatch_telemetry_file" ]]; then
  dispatch_telemetry_file="$telemetry_dir/alerts.jsonl"
fi
if [[ -z "$alert_config_file" && -n "${OPS_MANAGER_ALERT_SINKS_FILE:-}" ]]; then
  alert_config_file="$OPS_MANAGER_ALERT_SINKS_FILE"
fi
if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

mkdir -p "$(dirname "$dispatch_state_file")"
mkdir -p "$(dirname "$dispatch_telemetry_file")"

previous_state='{}'
if [[ -f "$dispatch_state_file" ]]; then
  previous_state=$(jq -c '.' "$dispatch_state_file" 2>/dev/null) || die "invalid dispatch state JSON: $dispatch_state_file"
fi

previous_offset=$(jq -r '.escalationsLineOffset // 0' <<<"$previous_state")
if [[ ! "$previous_offset" =~ ^[0-9]+$ ]]; then
  previous_offset=0
fi

write_state_and_print() {
  local status="$1"
  local processed_count="$2"
  local dispatched_count="$3"
  local skipped_count="$4"
  local failed_count="$5"
  local line_offset="$6"
  local line_count="$7"
  local failure_codes_json="$8"

  local state_json
  state_json=$(jq -cn \
    --arg schema_version "v1" \
    --arg updated_at "$(timestamp)" \
    --arg loop_id "$loop_id" \
    --arg trace_id "$trace_id" \
    --arg escalations_file "$escalations_file" \
    --arg dispatch_telemetry_file "$dispatch_telemetry_file" \
    --arg status "$status" \
    --argjson processed_count "$processed_count" \
    --argjson dispatched_count "$dispatched_count" \
    --argjson skipped_count "$skipped_count" \
    --argjson failed_count "$failed_count" \
    --argjson escalations_line_offset "$line_offset" \
    --argjson escalations_line_count "$line_count" \
    --argjson failure_codes "$failure_codes_json" \
    '{
      schemaVersion: $schema_version,
      updatedAt: $updated_at,
      loopId: $loop_id,
      traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
      escalationsFile: $escalations_file,
      dispatchTelemetryFile: $dispatch_telemetry_file,
      status: $status,
      processedCount: $processed_count,
      dispatchedCount: $dispatched_count,
      skippedCount: $skipped_count,
      failedCount: $failed_count,
      failureReasonCodes: $failure_codes,
      escalationsLineOffset: $escalations_line_offset,
      escalationsLineCount: $escalations_line_count
    }')

  jq -c '.' <<<"$state_json" > "$dispatch_state_file"

  if [[ "$pretty" == "1" ]]; then
    jq '.' <<<"$state_json"
  else
    jq -c '.' <<<"$state_json"
  fi
}

append_telemetry() {
  local entry_json="$1"
  printf '%s\n' "$entry_json" >> "$dispatch_telemetry_file"
}

send_http_json() {
  local url="$1"
  local timeout_seconds="$2"
  local payload_json="$3"
  shift 3
  local -a headers=("$@")

  local response_file
  response_file="$(mktemp)"

  local -a cmd=(curl -sS -m "$timeout_seconds" -o "$response_file" -w "%{http_code}" -X POST "$url" --data "$payload_json")
  local header
  for header in "${headers[@]}"; do
    cmd+=(-H "$header")
  done

  local http_code=""
  local response_body=""
  local response_excerpt=""
  local output=""

  if output=$("${cmd[@]}" 2>&1); then
    http_code="$output"
    response_body=$(cat "$response_file")
    rm -f "$response_file"
    response_excerpt="${response_body//$'\n'/ }"
    response_excerpt="${response_excerpt:0:300}"

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      jq -cn \
        --arg status "success" \
        --argjson http_status "$http_code" \
        --arg message "$response_excerpt" \
        '{status: $status, httpStatus: $http_status, reasonCode: null, message: (if ($message | length) > 0 then $message else null end)}'
      return 0
    fi

    jq -cn \
      --arg status "failed" \
      --arg reason_code "http_error" \
      --argjson http_status "${http_code:-0}" \
      --arg message "$response_excerpt" \
      '{status: $status, reasonCode: $reason_code, httpStatus: $http_status, message: (if ($message | length) > 0 then $message else null end)}'
    return 0
  fi

  rm -f "$response_file"
  output="${output//$'\n'/ }"
  output="${output:0:300}"

  jq -cn \
    --arg status "failed" \
    --arg reason_code "request_failed" \
    --arg message "$output" \
    '{status: $status, reasonCode: $reason_code, httpStatus: null, message: (if ($message | length) > 0 then $message else null end)}'
}

dispatch_to_sink() {
  local sink_json="$1"
  local escalation_json="$2"
  local event_severity="$3"

  local sink_id sink_type timeout_seconds
  sink_id=$(jq -r '.id // empty' <<<"$sink_json")
  sink_type=$(jq -r '.type // empty' <<<"$sink_json")
  timeout_seconds=$(jq -r '.timeoutSeconds // 5' <<<"$sink_json")

  local category loop_for_event escalation_ts
  category=$(jq -r '.category // "unknown"' <<<"$escalation_json")
  loop_for_event=$(jq -r '.loopId // empty' <<<"$escalation_json")
  escalation_ts=$(jq -r '.timestamp // ""' <<<"$escalation_json")
  local escalation_trace_id
  escalation_trace_id=$(jq -r '.traceId // empty' <<<"$escalation_json")
  if [[ -z "$escalation_trace_id" ]]; then
    escalation_trace_id="$trace_id"
  fi
  if [[ -z "$loop_for_event" ]]; then
    loop_for_event="$loop_id"
  fi

  case "$sink_type" in
    webhook)
      local url_env auth_env
      url_env=$(jq -r '.secretRefs.urlEnv // empty' <<<"$sink_json")
      auth_env=$(jq -r '.secretRefs.authTokenEnv // empty' <<<"$sink_json")
      local target_url="${!url_env-}"
      if [[ -z "$target_url" ]]; then
        jq -cn '{status:"failed", reasonCode:"missing_secret", httpStatus:null, message:"webhook url env is unset"}'
        return 0
      fi

      local -a headers=("Content-Type: application/json")
      if [[ -n "$auth_env" && -n "${!auth_env-}" ]]; then
        headers+=("Authorization: Bearer ${!auth_env}")
      fi
      while IFS= read -r header; do
        [[ -n "$header" ]] || continue
        headers+=("$header")
      done < <(jq -r '.config.headers // {} | to_entries[] | "\(.key): \(.value)"' <<<"$sink_json")

      local payload_json
      payload_json=$(jq -cn \
        --arg schema_version "v1" \
        --arg emitted_at "$(timestamp)" \
        --arg trace_id "$escalation_trace_id" \
        --arg repo_path "$repo" \
        --arg loop_id "$loop_for_event" \
        --arg category "$category" \
        --arg severity "$event_severity" \
        --arg sink_id "$sink_id" \
        --arg sink_type "$sink_type" \
        --argjson escalation "$escalation_json" \
        '{
          schemaVersion: $schema_version,
          emittedAt: $emitted_at,
          source: {
            repoPath: $repo_path,
            loopId: $loop_id,
            channel: "ops_manager_alert_dispatch",
            traceId: (if ($trace_id | length) > 0 then $trace_id else null end)
          },
          event: {
            category: $category,
            severity: $severity
          },
          sink: {
            id: $sink_id,
            type: $sink_type
          },
          escalation: $escalation
        }')

      send_http_json "$target_url" "$timeout_seconds" "$payload_json" "${headers[@]}"
      ;;
    slack)
      local webhook_env
      webhook_env=$(jq -r '.secretRefs.webhookUrlEnv // empty' <<<"$sink_json")
      local webhook_url="${!webhook_env-}"
      if [[ -z "$webhook_url" ]]; then
        jq -cn '{status:"failed", reasonCode:"missing_secret", httpStatus:null, message:"slack webhook env is unset"}'
        return 0
      fi

      local channel username icon_emoji
      channel=$(jq -r '.config.channel // empty' <<<"$sink_json")
      username=$(jq -r '.config.username // empty' <<<"$sink_json")
      icon_emoji=$(jq -r '.config.iconEmoji // empty' <<<"$sink_json")

      local text
      text="[ops-manager][$event_severity] $category loop=$loop_for_event trace=$escalation_trace_id"

      local payload_json
      payload_json=$(jq -cn \
        --arg text "$text" \
        --arg channel "$channel" \
        --arg username "$username" \
        --arg icon_emoji "$icon_emoji" \
        --arg escalation_ts "$escalation_ts" \
        --arg trace_id "$escalation_trace_id" \
        '{
          text: $text,
          channel: (if ($channel | length) > 0 then $channel else null end),
          username: (if ($username | length) > 0 then $username else null end),
          icon_emoji: (if ($icon_emoji | length) > 0 then $icon_emoji else null end),
          blocks: [
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: ("*Ops Manager Alert*\\nCategory: `" + $text + "`")
              }
            },
            {
              type: "context",
              elements: [
                {
                  type: "mrkdwn",
                  text: (if ($escalation_ts | length) > 0 then ("Escalation timestamp: `" + $escalation_ts + "`") else "Escalation timestamp unavailable" end)
                },
                {
                  type: "mrkdwn",
                  text: ("Trace: `" + $trace_id + "`")
                }
              ]
            }
          ]
        } | with_entries(select(.value != null))')

      send_http_json "$webhook_url" "$timeout_seconds" "$payload_json" "Content-Type: application/json"
      ;;
    pagerduty_events)
      local routing_env
      routing_env=$(jq -r '.secretRefs.routingKeyEnv // empty' <<<"$sink_json")
      local routing_key="${!routing_env-}"
      if [[ -z "$routing_key" ]]; then
        jq -cn '{status:"failed", reasonCode:"missing_secret", httpStatus:null, message:"pagerduty routing key env is unset"}'
        return 0
      fi

      local pd_source pd_component pd_group pd_class
      pd_source=$(jq -r '.config.source // "superloop-ops-manager"' <<<"$sink_json")
      pd_component=$(jq -r '.config.component // "ops-manager"' <<<"$sink_json")
      pd_group=$(jq -r '.config.group // "loop-run"' <<<"$sink_json")
      pd_class=$(jq -r '.config.class // "escalation"' <<<"$sink_json")

      local dedup_key
      dedup_key="$loop_for_event:$category:$escalation_ts"

      local payload_json
      payload_json=$(jq -cn \
        --arg routing_key "$routing_key" \
        --arg dedup_key "$dedup_key" \
        --arg trace_id "$escalation_trace_id" \
        --arg summary "ops-manager $category ($event_severity) loop=$loop_for_event" \
        --arg severity "$event_severity" \
        --arg source "$pd_source" \
        --arg component "$pd_component" \
        --arg group "$pd_group" \
        --arg class "$pd_class" \
        --argjson escalation "$escalation_json" \
        '{
          routing_key: $routing_key,
          event_action: "trigger",
          dedup_key: $dedup_key,
          payload: {
            summary: $summary,
            severity: $severity,
            source: $source,
            component: $component,
            group: $group,
            class: $class,
            custom_details: {
              escalation: $escalation,
              traceId: (if ($trace_id | length) > 0 then $trace_id else null end)
            }
          }
        }')

      send_http_json "https://events.pagerduty.com/v2/enqueue" "$timeout_seconds" "$payload_json" "Content-Type: application/json"
      ;;
    *)
      jq -cn --arg sink_type "$sink_type" '{status:"failed", reasonCode:"unsupported_sink_type", httpStatus:null, message:("unsupported sink type: " + $sink_type)}'
      ;;
  esac
}

if [[ ! -f "$escalations_file" ]]; then
  write_state_and_print "no_source" 0 0 0 0 "$previous_offset" "$previous_offset" '[]'
  exit 0
fi

line_count=$(wc -l < "$escalations_file" | tr -d ' ')
if [[ ! "$line_count" =~ ^[0-9]+$ ]]; then
  line_count=0
fi

if (( previous_offset > line_count )); then
  die "dispatch state offset is ahead of escalation file: $previous_offset > $line_count"
fi

if (( line_count == previous_offset )); then
  write_state_and_print "no_new_escalations" 0 0 0 0 "$previous_offset" "$line_count" '[]'
  exit 0
fi

if [[ "$max_escalations" -gt 0 ]]; then
  mapfile -t escalation_lines < <(awk -v start="$previous_offset" 'NR > start { print }' "$escalations_file" | head -n "$max_escalations")
else
  mapfile -t escalation_lines < <(awk -v start="$previous_offset" 'NR > start { print }' "$escalations_file")
fi

processed_rows="0"
dispatched_rows="0"
skipped_rows="0"
failed_rows="0"
failure_codes_json='[]'
line_progress="$previous_offset"

for line in "${escalation_lines[@]}"; do
  line_progress=$(( line_progress + 1 ))
  processed_rows=$(( processed_rows + 1 ))

  if [[ -z "${line//[[:space:]]/}" ]]; then
    skipped_rows=$(( skipped_rows + 1 ))
    continue
  fi

  escalation_json=""
  if ! escalation_json=$(jq -c '.' <<<"$line" 2>/dev/null); then
    failed_rows=$(( failed_rows + 1 ))
    failure_codes_json=$(jq -c '. + ["invalid_escalation_json"] | unique' <<<"$failure_codes_json")
    append_telemetry "$(jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg trace_id "$trace_id" \
      --arg status "failed" \
      --arg reason_code "invalid_escalation_json" \
      --arg raw_line "$line" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
        category: "alert_dispatch",
        status: $status,
        reasonCode: $reason_code,
        rawLine: $raw_line
      }')"
    continue
  fi

  escalation_category=$(jq -r '.category // empty' <<<"$escalation_json")
  escalation_timestamp=$(jq -r '.timestamp // ""' <<<"$escalation_json")
  escalation_loop_id=$(jq -r '.loopId // empty' <<<"$escalation_json")
  escalation_severity=$(jq -r '.severity // empty' <<<"$escalation_json")
  escalation_trace_id=$(jq -r '.traceId // empty' <<<"$escalation_json")
  if [[ -z "$escalation_trace_id" ]]; then
    escalation_trace_id="$trace_id"
  fi
  if [[ -z "$escalation_loop_id" ]]; then
    escalation_loop_id="$loop_id"
  fi

  if [[ -z "$escalation_category" ]]; then
    failed_rows=$(( failed_rows + 1 ))
    failure_codes_json=$(jq -c '. + ["missing_escalation_category"] | unique' <<<"$failure_codes_json")
    append_telemetry "$(jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg trace_id "$trace_id" \
      --arg status "failed" \
      --arg reason_code "missing_escalation_category" \
      --argjson escalation "$escalation_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
        category: "alert_dispatch",
        status: $status,
        reasonCode: $reason_code,
        escalation: $escalation
      }')"
    continue
  fi

  resolver_args=()
  if [[ -n "$alert_config_file" ]]; then
    resolver_args+=(--config-file "$alert_config_file")
  fi
  resolver_args+=(--category "$escalation_category")
  if [[ -n "$escalation_severity" ]]; then
    resolver_args+=(--severity "$escalation_severity")
  fi

  route_output=""
  if ! route_output=$("$alert_config_script" "${resolver_args[@]}" 2>&1); then
    failed_rows=$(( failed_rows + 1 ))
    failure_codes_json=$(jq -c '. + ["route_resolution_failed"] | unique' <<<"$failure_codes_json")
    route_output="${route_output//$'\n'/ }"
    route_output="${route_output:0:300}"
    append_telemetry "$(jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg trace_id "$trace_id" \
      --arg escalation_trace_id "$escalation_trace_id" \
      --arg escalation_category "$escalation_category" \
      --arg escalation_timestamp "$escalation_timestamp" \
      --arg status "failed" \
      --arg reason_code "route_resolution_failed" \
      --arg message "$route_output" \
      --argjson escalation "$escalation_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
        escalationTraceId: (if ($escalation_trace_id | length) > 0 then $escalation_trace_id else null end),
        category: "alert_dispatch",
        escalationCategory: $escalation_category,
        escalationTimestamp: (if ($escalation_timestamp | length) > 0 then $escalation_timestamp else null end),
        status: $status,
        reasonCode: $reason_code,
        message: (if ($message | length) > 0 then $message else null end),
        escalation: $escalation
      } | with_entries(select(.value != null))')"
    continue
  fi

  route_json=$(jq -c '.' <<<"$route_output" 2>/dev/null || echo 'null')
  if [[ "$route_json" == "null" ]]; then
    failed_rows=$(( failed_rows + 1 ))
    failure_codes_json=$(jq -c '. + ["invalid_route_resolution"] | unique' <<<"$failure_codes_json")
    append_telemetry "$(jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg trace_id "$trace_id" \
      --arg escalation_trace_id "$escalation_trace_id" \
      --arg escalation_category "$escalation_category" \
      --arg status "failed" \
      --arg reason_code "invalid_route_resolution" \
      --arg raw_output "$route_output" \
      --argjson escalation "$escalation_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
        escalationTraceId: (if ($escalation_trace_id | length) > 0 then $escalation_trace_id else null end),
        category: "alert_dispatch",
        escalationCategory: $escalation_category,
        status: $status,
        reasonCode: $reason_code,
        message: ($raw_output | tostring),
        escalation: $escalation
      }')"
    continue
  fi

  should_dispatch=$(jq -r '.shouldDispatch // false' <<<"$route_json")
  event_severity=$(jq -r '.eventSeverity // "warning"' <<<"$route_json")
  if ! severity_rank "$event_severity" >/dev/null; then
    event_severity="warning"
  fi

  sink_count=$(jq -r '.dispatchableSinks | length' <<<"$route_json")

  if [[ "$should_dispatch" != "true" ]]; then
    skipped_rows=$(( skipped_rows + 1 ))
    append_telemetry "$(jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg trace_id "$trace_id" \
      --arg escalation_trace_id "$escalation_trace_id" \
      --arg escalation_category "$escalation_category" \
      --arg escalation_timestamp "$escalation_timestamp" \
      --arg event_severity "$event_severity" \
      --arg status "skipped" \
      --arg reason_code "severity_below_min" \
      --argjson escalation "$escalation_json" \
      --argjson route "$route_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
        escalationTraceId: (if ($escalation_trace_id | length) > 0 then $escalation_trace_id else null end),
        category: "alert_dispatch",
        escalationCategory: $escalation_category,
        escalationTimestamp: (if ($escalation_timestamp | length) > 0 then $escalation_timestamp else null end),
        eventSeverity: $event_severity,
        status: $status,
        reasonCode: $reason_code,
        escalation: $escalation,
        route: $route,
        sinkCount: 0,
        dispatchedSinkCount: 0,
        failedSinkCount: 0
      } | with_entries(select(.value != null))')"
    continue
  fi

  if [[ "$sink_count" -lt 1 ]]; then
    skipped_rows=$(( skipped_rows + 1 ))
    append_telemetry "$(jq -cn \
      --arg timestamp "$(timestamp)" \
      --arg loop_id "$loop_id" \
      --arg trace_id "$trace_id" \
      --arg escalation_trace_id "$escalation_trace_id" \
      --arg escalation_category "$escalation_category" \
      --arg escalation_timestamp "$escalation_timestamp" \
      --arg event_severity "$event_severity" \
      --arg status "skipped" \
      --arg reason_code "no_dispatchable_sinks" \
      --argjson escalation "$escalation_json" \
      --argjson route "$route_json" \
      '{
        timestamp: $timestamp,
        loopId: $loop_id,
        traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
        escalationTraceId: (if ($escalation_trace_id | length) > 0 then $escalation_trace_id else null end),
        category: "alert_dispatch",
        escalationCategory: $escalation_category,
        escalationTimestamp: (if ($escalation_timestamp | length) > 0 then $escalation_timestamp else null end),
        eventSeverity: $event_severity,
        status: $status,
        reasonCode: $reason_code,
        escalation: $escalation,
        route: $route,
        sinkCount: 0,
        dispatchedSinkCount: 0,
        failedSinkCount: 0
      } | with_entries(select(.value != null))')"
    continue
  fi

  sink_results='[]'
  sink_dispatched_count=0
  sink_failed_count=0

  while IFS= read -r sink_json; do
    [[ -n "$sink_json" ]] || continue

    sink_id=$(jq -r '.id // "unknown"' <<<"$sink_json")
    sink_type=$(jq -r '.type // "unknown"' <<<"$sink_json")

    sink_result=$(dispatch_to_sink "$sink_json" "$escalation_json" "$event_severity")
    sink_result_json=$(jq -c '.' <<<"$sink_result" 2>/dev/null || echo '{"status":"failed","reasonCode":"invalid_sink_result"}')
    sink_status=$(jq -r '.status // "failed"' <<<"$sink_result_json")

    if [[ "$sink_status" == "success" ]]; then
      sink_dispatched_count=$(( sink_dispatched_count + 1 ))
    else
      sink_failed_count=$(( sink_failed_count + 1 ))
      sink_reason=$(jq -r '.reasonCode // "sink_dispatch_failed"' <<<"$sink_result_json")
      failure_codes_json=$(jq -c --arg reason "$sink_reason" '. + [$reason] | unique' <<<"$failure_codes_json")
    fi

    sink_results=$(jq -c \
      --arg sink_id "$sink_id" \
      --arg sink_type "$sink_type" \
      --argjson sink_result "$sink_result_json" \
      '. + [{id: $sink_id, type: $sink_type} + $sink_result]' <<<"$sink_results")
  done < <(jq -c '.dispatchableSinks[]?' <<<"$route_json")

  escalation_status="failed"
  escalation_reason="dispatch_failed"
  if (( sink_failed_count == 0 && sink_dispatched_count > 0 )); then
    escalation_status="dispatched"
    escalation_reason=""
  elif (( sink_dispatched_count > 0 )); then
    escalation_status="partial"
    escalation_reason="partial_dispatch_failure"
  fi

  if [[ "$escalation_status" == "dispatched" ]]; then
    dispatched_rows=$(( dispatched_rows + 1 ))
  elif [[ "$escalation_status" == "partial" ]]; then
    dispatched_rows=$(( dispatched_rows + 1 ))
    failed_rows=$(( failed_rows + 1 ))
  else
    failed_rows=$(( failed_rows + 1 ))
  fi

  append_telemetry "$(jq -cn \
    --arg timestamp "$(timestamp)" \
    --arg loop_id "$escalation_loop_id" \
    --arg trace_id "$trace_id" \
    --arg escalation_trace_id "$escalation_trace_id" \
    --arg escalation_category "$escalation_category" \
    --arg escalation_timestamp "$escalation_timestamp" \
    --arg event_severity "$event_severity" \
    --arg status "$escalation_status" \
    --arg reason_code "$escalation_reason" \
    --argjson escalation "$escalation_json" \
    --argjson route "$route_json" \
    --argjson sink_results "$sink_results" \
    --argjson sink_count "$sink_count" \
    --argjson dispatched_sink_count "$sink_dispatched_count" \
    --argjson failed_sink_count "$sink_failed_count" \
    '{
      timestamp: $timestamp,
      loopId: $loop_id,
      traceId: (if ($trace_id | length) > 0 then $trace_id else null end),
      escalationTraceId: (if ($escalation_trace_id | length) > 0 then $escalation_trace_id else null end),
      category: "alert_dispatch",
      escalationCategory: $escalation_category,
      escalationTimestamp: (if ($escalation_timestamp | length) > 0 then $escalation_timestamp else null end),
      eventSeverity: $event_severity,
      status: $status,
      reasonCode: (if ($reason_code | length) > 0 then $reason_code else null end),
      escalation: $escalation,
      route: $route,
      sinks: $sink_results,
      sinkCount: $sink_count,
      dispatchedSinkCount: $dispatched_sink_count,
      failedSinkCount: $failed_sink_count
    } | with_entries(select(.value != null))')"
done

summary_status="success"
if (( processed_rows == 0 )); then
  summary_status="no_new_escalations"
elif (( failed_rows > 0 && dispatched_rows == 0 )); then
  summary_status="failed"
elif (( failed_rows > 0 )); then
  summary_status="partial"
fi

write_state_and_print "$summary_status" "$processed_rows" "$dispatched_rows" "$skipped_rows" "$failed_rows" "$line_progress" "$line_count" "$failure_codes_json"
