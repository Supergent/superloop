#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-status.sh --repo <path> --loop <id> [options]

Options:
  --state-file <path>     Manager state path. Default: <repo>/.superloop/ops-manager/<loop>/state.json
  --cursor-file <path>    Manager cursor path. Default: <repo>/.superloop/ops-manager/<loop>/cursor.json
  --health-file <path>    Manager health path. Default: <repo>/.superloop/ops-manager/<loop>/health.json
  --intents-file <path>   Manager intents log. Default: <repo>/.superloop/ops-manager/<loop>/intents.jsonl
  --drift-state-file <path>   Profile drift state path. Default: <repo>/.superloop/ops-manager/<loop>/profile-drift.json
  --drift-history-file <path> Profile drift history path. Default: <repo>/.superloop/ops-manager/<loop>/telemetry/profile-drift.jsonl
  --alert-dispatch-state-file <path>      Alert dispatch state path. Default: <repo>/.superloop/ops-manager/<loop>/alert-dispatch-state.json
  --alert-dispatch-telemetry-file <path>  Alert dispatch telemetry JSONL path. Default: <repo>/.superloop/ops-manager/<loop>/telemetry/alerts.jsonl
  --summary-window <n>    Telemetry summary window size (default: 200)
  --pretty                Pretty-print output JSON.
  --help                  Show this help message.
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
state_file=""
cursor_file=""
health_file=""
intents_file=""
drift_state_file=""
drift_history_file=""
alert_dispatch_state_file=""
alert_dispatch_telemetry_file=""
summary_window="200"
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
    --state-file)
      state_file="${2:-}"
      shift 2
      ;;
    --cursor-file)
      cursor_file="${2:-}"
      shift 2
      ;;
    --health-file)
      health_file="${2:-}"
      shift 2
      ;;
    --intents-file)
      intents_file="${2:-}"
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
    --alert-dispatch-state-file)
      alert_dispatch_state_file="${2:-}"
      shift 2
      ;;
    --alert-dispatch-telemetry-file)
      alert_dispatch_telemetry_file="${2:-}"
      shift 2
      ;;
    --summary-window)
      summary_window="${2:-}"
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
if [[ ! "$summary_window" =~ ^[0-9]+$ || "$summary_window" -lt 1 ]]; then
  die "--summary-window must be an integer >= 1"
fi

repo="$(cd "$repo" && pwd)"
ops_dir="$repo/.superloop/ops-manager/$loop_id"
telemetry_dir="$ops_dir/telemetry"
reconcile_telemetry_file="$telemetry_dir/reconcile.jsonl"
control_telemetry_file="$telemetry_dir/control.jsonl"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
telemetry_summary_script="${OPS_MANAGER_TELEMETRY_SUMMARY_SCRIPT:-$script_dir/ops-manager-telemetry-summary.sh}"

if [[ -z "$state_file" ]]; then
  state_file="$ops_dir/state.json"
fi
if [[ -z "$cursor_file" ]]; then
  cursor_file="$ops_dir/cursor.json"
fi
if [[ -z "$health_file" ]]; then
  health_file="$ops_dir/health.json"
fi
if [[ -z "$intents_file" ]]; then
  intents_file="$ops_dir/intents.jsonl"
fi
if [[ -z "$drift_state_file" ]]; then
  drift_state_file="$ops_dir/profile-drift.json"
fi
if [[ -z "$drift_history_file" ]]; then
  drift_history_file="$telemetry_dir/profile-drift.jsonl"
fi
if [[ -z "$alert_dispatch_state_file" ]]; then
  alert_dispatch_state_file="$ops_dir/alert-dispatch-state.json"
fi
if [[ -z "$alert_dispatch_telemetry_file" ]]; then
  alert_dispatch_telemetry_file="$telemetry_dir/alerts.jsonl"
fi

if [[ ! -f "$state_file" && ! -f "$health_file" ]]; then
  die "no status artifacts found for loop: $loop_id"
fi

state_json='{}'
if [[ -f "$state_file" ]]; then
  state_json=$(jq -c '.' "$state_file" 2>/dev/null) || die "invalid state JSON: $state_file"
fi

cursor_json='{}'
if [[ -f "$cursor_file" ]]; then
  cursor_json=$(jq -c '.' "$cursor_file" 2>/dev/null) || die "invalid cursor JSON: $cursor_file"
fi

health_json='{}'
if [[ -f "$health_file" ]]; then
  health_json=$(jq -c '.' "$health_file" 2>/dev/null) || die "invalid health JSON: $health_file"
fi

last_intent_json='null'
if [[ -f "$intents_file" ]]; then
  if line=$(tail -n 1 "$intents_file" 2>/dev/null); then
    if [[ -n "$line" ]]; then
      last_intent_json=$(jq -c '.' <<<"$line" 2>/dev/null || echo 'null')
    fi
  fi
fi

last_reconcile_json='null'
if [[ -f "$reconcile_telemetry_file" ]]; then
  if line=$(tail -n 1 "$reconcile_telemetry_file" 2>/dev/null); then
    if [[ -n "$line" ]]; then
      last_reconcile_json=$(jq -c '.' <<<"$line" 2>/dev/null || echo 'null')
    fi
  fi
fi

last_control_json='null'
if [[ -f "$control_telemetry_file" ]]; then
  if line=$(tail -n 1 "$control_telemetry_file" 2>/dev/null); then
    if [[ -n "$line" ]]; then
      last_control_json=$(jq -c '.' <<<"$line" 2>/dev/null || echo 'null')
    fi
  fi
fi

tuning_summary_json='null'
if [[ -f "$reconcile_telemetry_file" ]]; then
  if summary_output=$(
    "$telemetry_summary_script" \
      --repo "$repo" \
      --loop "$loop_id" \
      --reconcile-telemetry-file "$reconcile_telemetry_file" \
      --control-telemetry-file "$control_telemetry_file" \
      --window "$summary_window" 2>/dev/null
  ); then
    tuning_summary_json=$(jq -c '.' <<<"$summary_output" 2>/dev/null || echo 'null')
  fi
fi

drift_json='null'
if [[ -f "$drift_state_file" ]]; then
  drift_json=$(jq -c '.' "$drift_state_file" 2>/dev/null) || die "invalid drift JSON: $drift_state_file"
elif jq -e '.drift != null' <<<"$state_json" >/dev/null 2>&1; then
  drift_json=$(jq -c '.drift' <<<"$state_json")
fi

alert_dispatch_state_json='null'
if [[ -f "$alert_dispatch_state_file" ]]; then
  alert_dispatch_state_json=$(jq -c '.' "$alert_dispatch_state_file" 2>/dev/null) || die "invalid alert dispatch state JSON: $alert_dispatch_state_file"
fi

last_alert_delivery_json='null'
if [[ -f "$alert_dispatch_telemetry_file" ]]; then
  if line=$(tail -n 1 "$alert_dispatch_telemetry_file" 2>/dev/null); then
    if [[ -n "$line" ]]; then
      last_alert_delivery_json=$(jq -c '.' <<<"$line" 2>/dev/null || echo 'null')
    fi
  fi
fi

status_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$(timestamp)" \
  --arg repo_path "$repo" \
  --arg loop_id "$loop_id" \
  --arg state_file "$state_file" \
  --arg cursor_file "$cursor_file" \
  --arg health_file "$health_file" \
  --arg intents_file "$intents_file" \
  --arg drift_state_file "$drift_state_file" \
  --arg drift_history_file "$drift_history_file" \
  --arg alert_dispatch_state_file "$alert_dispatch_state_file" \
  --arg alert_dispatch_telemetry_file "$alert_dispatch_telemetry_file" \
  --arg reconcile_telemetry_file "$reconcile_telemetry_file" \
  --arg control_telemetry_file "$control_telemetry_file" \
  --argjson state "$state_json" \
  --argjson cursor "$cursor_json" \
  --argjson health_file_json "$health_json" \
  --argjson last_intent "$last_intent_json" \
  --argjson last_reconcile "$last_reconcile_json" \
  --argjson last_control "$last_control_json" \
  --argjson tuning_summary "$tuning_summary_json" \
  --argjson drift "$drift_json" \
  --argjson alert_dispatch_state "$alert_dispatch_state_json" \
  --argjson last_alert_delivery "$last_alert_delivery_json" \
  --argjson summary_window "$summary_window" \
  '{
    schemaVersion: $schema_version,
    generatedAt: $generated_at,
    source: {
      repoPath: $repo_path,
      loopId: $loop_id
    },
    lifecycle: {
      state: ($state.transition.currentState // $state.projection.status // "unknown"),
      confidence: ($state.transition.confidence // null),
      runId: ($state.run.runId // null),
      iteration: ($state.run.iteration // null)
    },
    health: (
      if ($state.health // null) != null then $state.health
      else $health_file_json
      end
    ),
    cursor: {
      eventLineOffset: ($cursor.eventLineOffset // $state.cursor.eventLineOffset // 0),
      eventLineCount: ($cursor.eventLineCount // $state.cursor.eventLineCount // 0)
    },
    control: {
      lastIntent: ($last_intent.intent // null),
      lastStatus: ($last_intent.status // null),
      lastRequestedBy: ($last_intent.requestedBy // null),
      lastTimestamp: ($last_intent.timestamp // null),
      lastTraceId: (
        if ($last_intent.traceId // null) != null then $last_intent.traceId
        else ($last_control.traceId // null)
        end
      )
    },
    reconcile: {
      lastStatus: ($last_reconcile.status // null),
      lastTimestamp: ($last_reconcile.timestamp // null),
      lastTransport: ($last_reconcile.transport // null),
      lastFailureCode: ($last_reconcile.failureCode // null),
      lastDurationSeconds: ($last_reconcile.durationSeconds // null),
      lastTraceId: ($last_reconcile.traceId // null)
    },
    tuning: {
      summaryWindow: $summary_window,
      appliedProfile: (
        if ($state.health.thresholds.profile // null) != null then $state.health.thresholds.profile
        elif ($health_file_json.thresholds.profile // null) != null then $health_file_json.thresholds.profile
        else null
        end
      ),
      recommendedProfile: ($tuning_summary.recommendedProfile // null),
      confidence: ($tuning_summary.confidence // null),
      rationale: ($tuning_summary.rationale // null),
      telemetrySummary: (
        if $tuning_summary == null then null
        else {
          observed: ($tuning_summary.observed // {}),
          source: ($tuning_summary.source // {})
        }
        end
      )
    },
    drift: (
      if $drift != null then $drift
      else ($state.drift // null)
      end
    ),
    alerts: (
      if $alert_dispatch_state == null and $last_alert_delivery == null then null
      else {
        dispatch: (
          if $alert_dispatch_state == null then null
          else {
            status: ($alert_dispatch_state.status // null),
            updatedAt: ($alert_dispatch_state.updatedAt // null),
            processedCount: ($alert_dispatch_state.processedCount // 0),
            dispatchedCount: ($alert_dispatch_state.dispatchedCount // 0),
            skippedCount: ($alert_dispatch_state.skippedCount // 0),
            failedCount: ($alert_dispatch_state.failedCount // 0),
            failureReasonCodes: ($alert_dispatch_state.failureReasonCodes // []),
            escalationsLineOffset: ($alert_dispatch_state.escalationsLineOffset // 0),
            escalationsLineCount: ($alert_dispatch_state.escalationsLineCount // 0),
            lastTraceId: ($alert_dispatch_state.traceId // null)
          } | with_entries(select(.value != null))
          end
        ),
        lastDelivery: (
          if $last_alert_delivery == null then null
          else {
            timestamp: ($last_alert_delivery.timestamp // null),
            status: ($last_alert_delivery.status // null),
            reasonCode: ($last_alert_delivery.reasonCode // null),
            escalationCategory: ($last_alert_delivery.escalationCategory // null),
            eventSeverity: ($last_alert_delivery.eventSeverity // null),
            sinkCount: ($last_alert_delivery.sinkCount // null),
            dispatchedSinkCount: ($last_alert_delivery.dispatchedSinkCount // null),
            failedSinkCount: ($last_alert_delivery.failedSinkCount // null),
            traceId: ($last_alert_delivery.traceId // null),
            escalationTraceId: ($last_alert_delivery.escalationTraceId // null)
          } | with_entries(select(.value != null))
          end
        )
      } | with_entries(select(.value != null))
      end
    ),
    traceLinkage: {
      controlTraceId: (
        if ($last_intent.traceId // null) != null then $last_intent.traceId
        else ($last_control.traceId // null)
        end
      ),
      reconcileTraceId: ($last_reconcile.traceId // null),
      alertTraceId: ($last_alert_delivery.traceId // $alert_dispatch_state.traceId // null),
      sharedTraceId: (
        (
          if ($last_intent.traceId // null) != null then $last_intent.traceId
          else ($last_control.traceId // null)
          end
        ) as $c
        | ($last_reconcile.traceId // null) as $r
        | ($last_alert_delivery.traceId // $alert_dispatch_state.traceId // null) as $a
        | if $r != null and $a != null and $r == $a and ($c == null or $c == $r) then $r else null end
      )
    },
    files: {
      stateFile: $state_file,
      cursorFile: $cursor_file,
      healthFile: $health_file,
      intentsFile: $intents_file,
      driftStateFile: $drift_state_file,
      driftHistoryFile: $drift_history_file,
      alertDispatchStateFile: $alert_dispatch_state_file,
      alertDispatchTelemetryFile: $alert_dispatch_telemetry_file,
      reconcileTelemetryFile: $reconcile_telemetry_file,
      controlTelemetryFile: $control_telemetry_file
    }
  } | with_entries(select(.value != null))')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$status_json"
else
  jq -c '.' <<<"$status_json"
fi
