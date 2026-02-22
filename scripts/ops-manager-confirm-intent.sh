#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-confirm-intent.sh --repo <path> --loop <id> --intent <cancel|approve|reject> [options]

Options:
  --timeout-seconds <n>   Max time to wait for confirmation (default: 30)
  --interval-seconds <n>  Poll interval in seconds (default: 2)
  --help                  Show this help message
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
intent=""
timeout_seconds="30"
interval_seconds="2"

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
    --intent)
      intent="${2:-}"
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
if [[ -z "$intent" ]]; then
  die "--intent is required"
fi
case "$intent" in
  cancel|approve|reject)
    ;;
  *)
    die "intent must be one of: cancel, approve, reject"
    ;;
esac
if [[ ! "$timeout_seconds" =~ ^[0-9]+$ || ! "$interval_seconds" =~ ^[0-9]+$ ]]; then
  die "timeout and interval must be non-negative integers"
fi
if [[ "$interval_seconds" -eq 0 ]]; then
  interval_seconds=1
fi

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
snapshot_script="${OPS_MANAGER_SNAPSHOT_SCRIPT:-$script_dir/ops-manager-loop-run-snapshot.sh}"

start_epoch=$(date +%s)
attempts=0
confirmed="false"
reason="timeout"
observed_status="unknown"
observed_last_event=""
observed_approval_status=""
observed_active="false"

while true; do
  attempts=$((attempts + 1))

  snapshot_json=""
  if snapshot_json=$("$snapshot_script" --repo "$repo" --loop "$loop_id" 2>/dev/null); then
    observed_status=$(jq -r '.run.status // "unknown"' <<<"$snapshot_json")
    observed_last_event=$(jq -r '.health.lastEventName // ""' <<<"$snapshot_json")
    observed_approval_status=$(jq -r '.runtime.approval.status // ""' <<<"$snapshot_json")
    observed_active=$(jq -r '.runtime.superloopState.active // false' <<<"$snapshot_json")
    completion_ok=$(jq -r '.run.summary.completion_ok // false' <<<"$snapshot_json")

    case "$intent" in
      cancel)
        if [[ "$observed_active" != "true" && "$observed_status" != "running" ]]; then
          confirmed="true"
          reason="inactive_not_running"
        fi
        ;;
      approve)
        if [[ "$completion_ok" == "true" || "$observed_status" == "complete" || "$observed_last_event" == "loop_complete" ]]; then
          confirmed="true"
          reason="completion_observed"
        fi
        ;;
      reject)
        if [[ "$observed_approval_status" == "rejected" || "$observed_last_event" == "approval_rejected" || "$observed_last_event" == "approval_decision" ]]; then
          confirmed="true"
          reason="rejection_observed"
        fi
        ;;
    esac
  fi

  if [[ "$confirmed" == "true" ]]; then
    break
  fi

  now_epoch=$(date +%s)
  if (( now_epoch - start_epoch >= timeout_seconds )); then
    break
  fi

  sleep "$interval_seconds"
done

result_json=$(jq -cn \
  --arg intent "$intent" \
  --argjson confirmed "$confirmed" \
  --arg reason "$reason" \
  --argjson attempts "$attempts" \
  --argjson timeout_seconds "$timeout_seconds" \
  --arg observed_status "$observed_status" \
  --arg observed_last_event "$observed_last_event" \
  --arg observed_approval_status "$observed_approval_status" \
  --argjson observed_active "$observed_active" \
  --arg observed_at "$(timestamp)" \
  '{
    intent: $intent,
    confirmed: $confirmed,
    reason: $reason,
    attempts: $attempts,
    timeoutSeconds: $timeout_seconds,
    observedStatus: $observed_status,
    observedLastEvent: (if ($observed_last_event | length) > 0 then $observed_last_event else null end),
    observedApprovalStatus: (if ($observed_approval_status | length) > 0 then $observed_approval_status else null end),
    observedActive: $observed_active,
    observedAt: $observed_at
  }')

jq -c '.' <<<"$result_json"

if [[ "$confirmed" == "true" ]]; then
  exit 0
fi
exit 1
