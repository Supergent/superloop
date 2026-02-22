#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-poll-events.sh --repo <path> --loop <id> [options]

Options:
  --cursor-file <path>  Cursor JSON path. Default: <repo>/.superloop/loops/<loop>/ops-manager.cursor.json
  --from-start          Ignore existing cursor and emit from first line.
  --max-events <n>      Emit at most n events in this call (n > 0).
  --help                Show this help message.
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
cursor_file=""
from_start="0"
max_events="0"

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
    --from-start)
      from_start="1"
      shift
      ;;
    --max-events)
      max_events="${2:-}"
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
if [[ ! "$max_events" =~ ^[0-9]+$ ]]; then
  die "--max-events must be a non-negative integer"
fi

repo="$(cd "$repo" && pwd)"
loop_dir="$repo/.superloop/loops/$loop_id"
events_file="$loop_dir/events.jsonl"

if [[ -z "$cursor_file" ]]; then
  cursor_file="$loop_dir/ops-manager.cursor.json"
fi

if [[ ! -d "$loop_dir" ]]; then
  die "required artifact root missing: $loop_dir"
fi
if [[ ! -f "$events_file" ]]; then
  die "required artifact missing: $events_file"
fi

total_lines=$(wc -l < "$events_file" | tr -d ' ')
if [[ -z "$total_lines" ]]; then
  total_lines="0"
fi

start_offset="0"
if [[ "$from_start" != "1" && -f "$cursor_file" ]]; then
  cursor_json=$(jq -c '.' "$cursor_file" 2>/dev/null) || die "invalid JSON in cursor file: $cursor_file"
  start_offset=$(jq -r '.eventLineOffset // 0' <<<"$cursor_json")
fi

if [[ ! "$start_offset" =~ ^[0-9]+$ ]]; then
  die "invalid cursor offset in $cursor_file"
fi
if [[ "$start_offset" -gt "$total_lines" ]]; then
  die "cursor offset ($start_offset) exceeds available events ($total_lines); reset cursor or use --from-start"
fi

lines_emitted=0
last_emitted_line="$start_offset"
line_no=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))
  if [[ "$line_no" -le "$start_offset" ]]; then
    continue
  fi

  if [[ -z "$line" ]]; then
    continue
  fi

  event_json=$(printf '%s\n' "$line" | jq -c '.' 2>/dev/null) || die "invalid JSON event at line $line_no in $events_file"

  event_name=$(jq -r '(.event // .type // "")' <<<"$event_json")
  event_timestamp=$(jq -r '.timestamp // ""' <<<"$event_json")
  run_id=$(jq -r '.run_id // "unknown"' <<<"$event_json")
  iteration=$(jq -r '(.iteration // 0) | tonumber? // 0' <<<"$event_json")
  role=$(jq -r '.role // ""' <<<"$event_json")
  status=$(jq -r '.status // ""' <<<"$event_json")
  message=$(jq -r '.message // ""' <<<"$event_json")
  payload=$(jq -c '.data // null' <<<"$event_json")

  if [[ -z "$event_name" ]]; then
    die "missing event name at line $line_no in $events_file"
  fi
  if [[ -z "$event_timestamp" ]]; then
    die "missing event timestamp at line $line_no in $events_file"
  fi

  jq -cn \
    --arg schema_version "v1" \
    --arg emitted_at "$(timestamp)" \
    --arg repo_path "$repo" \
    --arg loop_id "$loop_id" \
    --argjson line_offset "$line_no" \
    --argjson line_count "$total_lines" \
    --arg run_id "$run_id" \
    --argjson iteration "$iteration" \
    --arg event_timestamp "$event_timestamp" \
    --arg event_name "$event_name" \
    --arg role "$role" \
    --arg status "$status" \
    --arg message "$message" \
    --argjson payload "$payload" \
    --argjson raw "$event_json" \
    '{
      schemaVersion: $schema_version,
      envelopeType: "loop_run_event",
      emittedAt: $emitted_at,
      source: {
        repoPath: $repo_path,
        loopId: $loop_id
      },
      cursor: {
        eventLineOffset: $line_offset,
        eventLineCount: $line_count
      },
      run: {
        runId: $run_id,
        iteration: $iteration
      },
      event: {
        timestamp: $event_timestamp,
        name: $event_name,
        role: (if ($role | length) > 0 then $role else null end),
        status: (if ($status | length) > 0 then $status else null end),
        message: (if ($message | length) > 0 then $message else null end),
        payload: $payload,
        raw: $raw
      }
    }'

  lines_emitted=$((lines_emitted + 1))
  last_emitted_line="$line_no"

  if [[ "$max_events" -gt 0 && "$lines_emitted" -ge "$max_events" ]]; then
    break
  fi
done < "$events_file"

mkdir -p "$(dirname "$cursor_file")"
tmp_cursor="$(mktemp)"

jq -n \
  --arg schema_version "v1" \
  --arg repo_path "$repo" \
  --arg loop_id "$loop_id" \
  --arg events_path "${events_file#$repo/}" \
  --arg updated_at "$(timestamp)" \
  --argjson line_offset "$last_emitted_line" \
  --argjson line_count "$total_lines" \
  '{
    schemaVersion: $schema_version,
    repoPath: $repo_path,
    loopId: $loop_id,
    eventsFile: $events_path,
    eventLineOffset: $line_offset,
    eventLineCount: $line_count,
    updatedAt: $updated_at
  }' > "$tmp_cursor"

mv "$tmp_cursor" "$cursor_file"
