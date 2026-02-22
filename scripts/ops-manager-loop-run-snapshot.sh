#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-loop-run-snapshot.sh --repo <path> --loop <id> [options]

Options:
  --run-id <id>   Override inferred run id in emitted snapshot.
  --pretty        Pretty-print JSON output.
  --help          Show this help message.
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

file_mtime_epoch() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "null"
    return 0
  fi

  if stat -f "%m" "$path" >/dev/null 2>&1; then
    stat -f "%m" "$path"
    return 0
  fi

  if stat -c "%Y" "$path" >/dev/null 2>&1; then
    stat -c "%Y" "$path"
    return 0
  fi

  echo "null"
}

file_sha256() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo ""
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi

  echo ""
}

file_ref_json() {
  local repo="$1"
  local path="$2"

  local display_path="$path"
  if [[ "$path" == "$repo/"* ]]; then
    display_path="${path#$repo/}"
  fi

  local exists="false"
  local size_bytes="0"
  local line_count="0"
  local sha=""
  local mtime_epoch="null"

  if [[ -f "$path" ]]; then
    exists="true"
    size_bytes=$(wc -c < "$path" | tr -d ' ')
    line_count=$(wc -l < "$path" | tr -d ' ')
    sha=$(file_sha256 "$path")
    mtime_epoch=$(file_mtime_epoch "$path")
  fi

  jq -cn \
    --arg path "$display_path" \
    --argjson exists "$exists" \
    --argjson size_bytes "$size_bytes" \
    --argjson line_count "$line_count" \
    --arg sha "$sha" \
    --argjson mtime_epoch "$mtime_epoch" \
    '{
      path: $path,
      exists: $exists,
      sizeBytes: $size_bytes,
      lineCount: $line_count,
      sha256: (if ($sha | length) > 0 then $sha else null end),
      mtimeEpoch: $mtime_epoch
    }'
}

json_or_null_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    jq -c '.' "$path" 2>/dev/null || die "invalid JSON in $path"
  else
    echo 'null'
  fi
}

repo=""
loop_id=""
requested_run_id=""
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
    --run-id)
      requested_run_id="${2:-}"
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

repo="$(cd "$repo" && pwd)"
superloop_dir="$repo/.superloop"
loop_dir="$superloop_dir/loops/$loop_id"

state_file="$superloop_dir/state.json"
active_run_file="$superloop_dir/active-run.json"
approval_file="$loop_dir/approval.json"
events_file="$loop_dir/events.jsonl"
summary_file="$loop_dir/run-summary.json"
heartbeat_file="$loop_dir/heartbeat.v1.json"

if [[ ! -d "$loop_dir" ]]; then
  die "required artifact root missing: $loop_dir"
fi
if [[ ! -f "$events_file" ]]; then
  die "required artifact missing: $events_file"
fi

event_line_count=$(wc -l < "$events_file" | tr -d ' ')
if [[ -z "$event_line_count" ]]; then
  event_line_count="0"
fi

last_event_json='null'
if [[ "$event_line_count" -gt 0 ]]; then
  last_event_json=$(tail -n 1 "$events_file" | jq -c '.' 2>/dev/null) || die "invalid JSON in final events line: $events_file"
fi

state_json=$(json_or_null_file "$state_file")
active_run_json=$(json_or_null_file "$active_run_file")
approval_json=$(json_or_null_file "$approval_file")
summary_json=$(json_or_null_file "$summary_file")
heartbeat_json=$(json_or_null_file "$heartbeat_file")
latest_summary_entry=$(jq -cn --argjson s "$summary_json" '$s.entries[-1] // null')

resolved_run_id="$requested_run_id"
if [[ -z "$resolved_run_id" ]]; then
  resolved_run_id=$(jq -rn --argjson summary "$latest_summary_entry" --argjson event "$last_event_json" '
    ($summary.run_id // "") as $summary_run |
    ($event.run_id // "") as $event_run |
    if ($summary_run | length) > 0 then
      $summary_run
    elif ($event_run | length) > 0 then
      $event_run
    else
      "unknown"
    end
  ')
fi

resolved_iteration=$(jq -rn --argjson summary "$latest_summary_entry" --argjson event "$last_event_json" --argjson state "$state_json" '
  ($summary.iteration // $event.iteration // $state.iteration // 0) | tonumber? // 0
')

run_status=$(jq -rn --arg loop_id "$loop_id" --argjson state "$state_json" --argjson approval "$approval_json" --argjson summary "$latest_summary_entry" --argjson event "$last_event_json" '
  def in_list($name; $list): ($list | index($name)) != null;

  ($event.event // $event.type // "") as $event_name |
  ($event.status // "") as $event_status |

  if ($approval != null and (($approval.status // "") == "pending")) then
    "awaiting_approval"
  elif ($summary != null and (($summary.completion_ok // false) == true)) then
    "complete"
  elif ($state != null and (($state.active // false) == true) and (($state.current_loop_id // "") == $loop_id)) then
    "running"
  elif in_list($event_name; ["loop_stop", "rate_limit_stop", "no_progress_stop"]) then
    "stopped"
  elif in_list($event_status; ["error", "timeout", "blocked", "rate_limited"]) then
    "failed"
  elif ($state != null and (($state.active // false) == false) and $summary != null) then
    "idle"
  else
    "unknown"
  end
')

last_event_at=$(jq -rn --argjson event "$last_event_json" '($event.timestamp // "")')
last_event_name=$(jq -rn --argjson event "$last_event_json" '($event.event // $event.type // "")')
last_summary_at=$(jq -rn --argjson summary "$summary_json" --argjson latest "$latest_summary_entry" '
  ($summary.updated_at // $latest.ended_at // "")
')
has_pending_approval=$(jq -rn --argjson approval "$approval_json" 'if $approval != null and (($approval.status // "") == "pending") then true else false end')
gates_json=$(jq -cn --argjson latest "$latest_summary_entry" '$latest.gates // null')
stuck_json=$(jq -cn --argjson latest "$latest_summary_entry" '$latest.stuck // null')

events_ref=$(file_ref_json "$repo" "$events_file")
summary_ref=$(file_ref_json "$repo" "$summary_file")
state_ref=$(file_ref_json "$repo" "$state_file")
active_run_ref=$(file_ref_json "$repo" "$active_run_file")
approval_ref=$(file_ref_json "$repo" "$approval_file")
heartbeat_ref=$(file_ref_json "$repo" "$heartbeat_file")

snapshot_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg emitted_at "$(timestamp)" \
  --arg repo_path "$repo" \
  --arg loop_id "$loop_id" \
  --arg run_id "$resolved_run_id" \
  --arg run_status "$run_status" \
  --arg last_event_at "$last_event_at" \
  --arg last_event_name "$last_event_name" \
  --arg last_summary_at "$last_summary_at" \
  --argjson iteration "$resolved_iteration" \
  --argjson state "$state_json" \
  --argjson active_run "$active_run_json" \
  --argjson approval "$approval_json" \
  --argjson heartbeat "$heartbeat_json" \
  --argjson latest_summary "$latest_summary_entry" \
  --argjson events_ref "$events_ref" \
  --argjson summary_ref "$summary_ref" \
  --argjson state_ref "$state_ref" \
  --argjson active_run_ref "$active_run_ref" \
  --argjson approval_ref "$approval_ref" \
  --argjson heartbeat_ref "$heartbeat_ref" \
  --argjson event_count "$event_line_count" \
  --argjson sequence_value "$event_line_count" \
  --argjson has_pending_approval "$has_pending_approval" \
  --argjson gates "$gates_json" \
  --argjson stuck "$stuck_json" \
  '{
    schemaVersion: $schema_version,
    envelopeType: "loop_run_snapshot",
    emittedAt: $emitted_at,
    source: {
      repoPath: $repo_path,
      loopId: $loop_id
    },
    run: {
      runId: $run_id,
      iteration: $iteration,
      status: $run_status,
      summary: $latest_summary
    },
    runtime: {
      superloopState: $state,
      activeRun: $active_run,
      approval: $approval,
      heartbeat: $heartbeat
    },
    artifacts: {
      events: $events_ref,
      runSummary: $summary_ref,
      state: $state_ref,
      activeRun: $active_run_ref,
      approval: $approval_ref,
      heartbeat: $heartbeat_ref
    },
    sequence: {
      source: "cursor_event_line_offset",
      value: $sequence_value
    },
    cursor: {
      eventLineOffset: $event_count,
      eventLineCount: $event_count
    },
    health: {
      eventCount: $event_count,
      lastEventAt: (if ($last_event_at | length) > 0 then $last_event_at else null end),
      lastEventName: (if ($last_event_name | length) > 0 then $last_event_name else null end),
      lastSummaryAt: (if ($last_summary_at | length) > 0 then $last_summary_at else null end),
      hasPendingApproval: $has_pending_approval,
      gates: $gates,
      stuck: $stuck
    }
  }')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$snapshot_json"
else
  jq -c '.' <<<"$snapshot_json"
fi
