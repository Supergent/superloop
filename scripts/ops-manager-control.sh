#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-control.sh --repo <path> --loop <id> --intent <cancel|approve|reject> [options]

Options:
  --by <name>            Actor identity for approve/reject (default: $USER)
  --note <text>          Optional decision note for approve/reject
  --timeout-seconds <n>  Confirmation timeout seconds (default: 30)
  --interval-seconds <n> Confirmation poll interval seconds (default: 2)
  --no-confirm           Skip confirmation polling
  --help                 Show this help message
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
by="${USER:-unknown}"
note=""
timeout_seconds="30"
interval_seconds="2"
do_confirm="1"

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
    --no-confirm)
      do_confirm="0"
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

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
superloop_bin="${SUPERLOOP_BIN:-$root_dir/superloop.sh}"
confirm_script="${OPS_MANAGER_CONFIRM_SCRIPT:-$script_dir/ops-manager-confirm-intent.sh}"

ops_dir="$repo/.superloop/ops-manager/$loop_id"
intents_file="$ops_dir/intents.jsonl"
mkdir -p "$ops_dir"

command=("$superloop_bin")
case "$intent" in
  cancel)
    command+=(cancel --repo "$repo")
    ;;
  approve)
    command+=(approve --repo "$repo" --loop "$loop_id" --by "$by")
    if [[ -n "$note" ]]; then
      command+=(--note "$note")
    fi
    ;;
  reject)
    command+=(approve --repo "$repo" --loop "$loop_id" --by "$by" --reject)
    if [[ -n "$note" ]]; then
      command+=(--note "$note")
    fi
    ;;
esac

command_pretty=$(printf '%q ' "${command[@]}")
command_pretty="${command_pretty% }"

cmd_output_file="$(mktemp)"
confirm_output_file="$(mktemp)"
trap 'rm -f "$cmd_output_file" "$confirm_output_file"' EXIT

status="failed_command"
confirmed="false"
confirm_json='null'
exit_code=0
confirm_exit_code=0

if "${command[@]}" >"$cmd_output_file" 2>&1; then
  status="executed"
  if [[ "$do_confirm" == "1" ]]; then
    if "$confirm_script" \
      --repo "$repo" \
      --loop "$loop_id" \
      --intent "$intent" \
      --timeout-seconds "$timeout_seconds" \
      --interval-seconds "$interval_seconds" >"$confirm_output_file" 2>&1; then
      status="confirmed"
      confirmed="true"
      confirm_json=$(jq -c '.' "$confirm_output_file" 2>/dev/null || echo 'null')
    else
      confirm_exit_code=$?
      status="ambiguous"
      confirm_json=$(jq -c '.' "$confirm_output_file" 2>/dev/null || echo 'null')
    fi
  else
    status="executed_unconfirmed"
  fi
else
  exit_code=$?
  status="failed_command"
fi

command_output=$(tail -n 40 "$cmd_output_file" | sed 's/\r$//' || true)

entry_json=$(jq -cn \
  --arg timestamp "$(timestamp)" \
  --arg loop_id "$loop_id" \
  --arg intent "$intent" \
  --arg requested_by "$by" \
  --arg note "$note" \
  --arg status "$status" \
  --arg command "$command_pretty" \
  --argjson exit_code "$exit_code" \
  --argjson confirm_exit_code "$confirm_exit_code" \
  --argjson confirmed "$confirmed" \
  --arg output "$command_output" \
  --argjson confirm "$confirm_json" \
  '{
    timestamp: $timestamp,
    loopId: $loop_id,
    intent: $intent,
    requestedBy: $requested_by,
    note: (if ($note | length) > 0 then $note else null end),
    status: $status,
    command: $command,
    exitCode: $exit_code,
    confirmExitCode: $confirm_exit_code,
    confirmed: $confirmed,
    commandOutput: (if ($output | length) > 0 then $output else null end),
    confirm: (if $confirm == null then null else $confirm end)
  } | with_entries(select(.value != null))')

printf '%s\n' "$entry_json" >> "$intents_file"

jq -c '.' <<<"$entry_json"

case "$status" in
  confirmed|executed_unconfirmed)
    exit 0
    ;;
  ambiguous)
    exit 2
    ;;
  *)
    exit 1
    ;;
esac
