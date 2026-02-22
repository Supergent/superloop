#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-reconcile.sh --repo <path> --loop <id> [options]

Options:
  --cursor-file <path>   Cursor JSON path. Default: <repo>/.superloop/ops-manager/<loop>/cursor.json
  --state-file <path>    Output state path. Default: <repo>/.superloop/ops-manager/<loop>/state.json
  --max-events <n>       Max incremental events to ingest from poll (default: 0 = all available)
  --from-start           Replay events from line 1 (ignores existing cursor)
  --pretty               Pretty-print resulting state
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

repo=""
loop_id=""
cursor_file=""
state_file=""
max_events="0"
from_start="0"
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
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

snapshot_file="$tmp_dir/snapshot.json"
events_file="$tmp_dir/events.ndjson"

"$script_dir/ops-manager-loop-run-snapshot.sh" --repo "$repo" --loop "$loop_id" > "$snapshot_file"

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

"$script_dir/ops-manager-poll-events.sh" "${poll_args[@]}" > "$events_file"

project_args=(
  --repo "$repo"
  --loop "$loop_id"
  --snapshot-file "$snapshot_file"
  --events-file "$events_file"
  --state-file "$state_file"
)

state_json=$("$script_dir/ops-manager-project-state.sh" "${project_args[@]}")
divergence_any=$(jq -r '.divergence.any // false' <<<"$state_json")

if [[ "$divergence_any" == "true" ]]; then
  escalations_file="$ops_dir/escalations.jsonl"
  jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg loop_id "$loop_id" \
    --arg state_file "$state_file" \
    --arg cursor_file "$cursor_file" \
    --argjson state "$state_json" \
    --arg divergence_summary "$(jq -c '.divergence.flags // {}' <<<"$state_json")" \
    '{
      timestamp: $timestamp,
      loopId: $loop_id,
      category: "divergence_detected",
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

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$state_json"
else
  jq -c '.' <<<"$state_json"
fi
