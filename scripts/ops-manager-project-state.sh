#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-project-state.sh --repo <path> --loop <id> [options]

Options:
  --snapshot-file <path>  Use existing loop_run_snapshot envelope JSON.
  --events-file <path>    Optional NDJSON file of loop_run_event envelopes.
  --state-file <path>     Output path. Default: <repo>/.superloop/ops-manager/<loop>/state.json
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
snapshot_file=""
events_file=""
state_file=""
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
    --snapshot-file)
      snapshot_file="${2:-}"
      shift 2
      ;;
    --events-file)
      events_file="${2:-}"
      shift 2
      ;;
    --state-file)
      state_file="${2:-}"
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
if [[ -z "$state_file" ]]; then
  state_file="$repo/.superloop/ops-manager/$loop_id/state.json"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$snapshot_file" ]]; then
  snapshot_file="$(mktemp)"
  "$script_dir/ops-manager-loop-run-snapshot.sh" --repo "$repo" --loop "$loop_id" > "$snapshot_file"
fi

if [[ ! -f "$snapshot_file" ]]; then
  die "snapshot file not found: $snapshot_file"
fi

snapshot_json=$(jq -c '.' "$snapshot_file" 2>/dev/null) || die "invalid snapshot JSON: $snapshot_file"

snapshot_ok=$(jq -r --arg loop "$loop_id" '
  if (.schemaVersion == "v1"
      and .envelopeType == "loop_run_snapshot"
      and ((.source.loopId // "") == $loop))
  then "true" else "false" end
' <<<"$snapshot_json")
if [[ "$snapshot_ok" != "true" ]]; then
  die "snapshot envelope is invalid or loop id mismatch"
fi

last_event_envelope='null'
last_event_name=""
if [[ -n "$events_file" ]]; then
  if [[ ! -f "$events_file" ]]; then
    die "events file not found: $events_file"
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    event_json=$(printf '%s\n' "$line" | jq -c '.') || die "invalid event envelope in $events_file"

    event_ok=$(jq -r --arg loop "$loop_id" '
      if (.schemaVersion == "v1"
          and .envelopeType == "loop_run_event"
          and ((.source.loopId // "") == $loop)
          and ((.event.name // "") != ""))
      then "true" else "false" end
    ' <<<"$event_json")
    if [[ "$event_ok" != "true" ]]; then
      die "event envelope is invalid or loop id mismatch"
    fi

    last_event_envelope="$event_json"
    last_event_name=$(jq -r '.event.name // ""' <<<"$event_json")
  done < "$events_file"
fi

previous_state="none"
previous_cursor_offset="0"
if [[ -f "$state_file" ]]; then
  prev_json=$(jq -c '.' "$state_file" 2>/dev/null || echo "{}")
  previous_state=$(jq -r '.transition.currentState // "none"' <<<"$prev_json")
  previous_cursor_offset=$(jq -r '.cursor.eventLineOffset // 0' <<<"$prev_json")
fi

current_state=$(jq -r '.run.status // "unknown"' <<<"$snapshot_json")
run_id=$(jq -r '.run.runId // "unknown"' <<<"$snapshot_json")
iteration=$(jq -r '(.run.iteration // 0) | tonumber? // 0' <<<"$snapshot_json")
has_pending_approval=$(jq -r 'if (.runtime.approval // null) != null and ((.runtime.approval.status // "") == "pending") then true else false end' <<<"$snapshot_json")
completion_ok=$(jq -r '.run.summary.completion_ok // false' <<<"$snapshot_json")
state_active=$(jq -r '.runtime.superloopState.active // false' <<<"$snapshot_json")
cursor_offset=$(jq -r '.cursor.eventLineOffset // 0' <<<"$snapshot_json")
cursor_count=$(jq -r '.cursor.eventLineCount // 0' <<<"$snapshot_json")

if [[ -n "$last_event_name" ]]; then
  triggering_signal="event:$last_event_name"
else
  triggering_signal="snapshot_status:$current_state"
fi

active_mismatch="false"
if [[ "$state_active" != "true" && -n "$last_event_name" ]]; then
  case "$last_event_name" in
    iteration_start|role_start|role_end|iteration_end|tests_start|tests_end|validation_start|validation_end)
      active_mismatch="true"
      ;;
  esac
fi

approval_completion_conflict="false"
if [[ "$has_pending_approval" == "true" && "$completion_ok" == "true" ]]; then
  approval_completion_conflict="true"
fi

cursor_regression="false"
if [[ "$previous_cursor_offset" =~ ^[0-9]+$ && "$cursor_offset" =~ ^[0-9]+$ ]]; then
  if (( previous_cursor_offset > cursor_offset )); then
    cursor_regression="true"
  fi
fi

divergence_any="false"
if [[ "$active_mismatch" == "true" || "$approval_completion_conflict" == "true" || "$cursor_regression" == "true" ]]; then
  divergence_any="true"
fi

confidence="high"
if [[ "$divergence_any" == "true" ]]; then
  confidence="low"
elif [[ -z "$last_event_name" ]]; then
  confidence="medium"
fi

state_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$(timestamp)" \
  --arg repo_path "$repo" \
  --arg loop_id "$loop_id" \
  --arg run_id "$run_id" \
  --argjson iteration "$iteration" \
  --arg previous_state "$previous_state" \
  --arg triggering_signal "$triggering_signal" \
  --arg current_state "$current_state" \
  --arg confidence "$confidence" \
  --argjson has_pending_approval "$has_pending_approval" \
  --argjson completion_ok "$completion_ok" \
  --argjson cursor_offset "$cursor_offset" \
  --argjson cursor_count "$cursor_count" \
  --argjson active_mismatch "$active_mismatch" \
  --argjson approval_completion_conflict "$approval_completion_conflict" \
  --argjson cursor_regression "$cursor_regression" \
  --argjson divergence_any "$divergence_any" \
  --arg snapshot_file "$snapshot_file" \
  --arg events_file "$events_file" \
  --argjson snapshot "$snapshot_json" \
  --argjson last_event "$last_event_envelope" \
  '{
    schemaVersion: $schema_version,
    generatedAt: $generated_at,
    source: {
      repoPath: $repo_path,
      loopId: $loop_id
    },
    run: {
      runId: $run_id,
      iteration: $iteration
    },
    transition: {
      previousState: $previous_state,
      triggeringSignal: $triggering_signal,
      currentState: $current_state,
      confidence: $confidence
    },
    projection: {
      status: $current_state,
      hasPendingApproval: $has_pending_approval,
      completionOk: $completion_ok,
      gates: ($snapshot.health.gates // null),
      stuck: ($snapshot.health.stuck // null),
      active: ($snapshot.runtime.superloopState.active // null),
      lastEventName: ($snapshot.health.lastEventName // null),
      lastEventAt: ($snapshot.health.lastEventAt // null)
    },
    cursor: {
      eventLineOffset: $cursor_offset,
      eventLineCount: $cursor_count
    },
    divergence: {
      any: $divergence_any,
      flags: {
        activeMismatch: $active_mismatch,
        approvalCompletionConflict: $approval_completion_conflict,
        cursorRegression: $cursor_regression
      }
    },
    evidence: {
      snapshotFile: $snapshot_file,
      eventsFile: (if ($events_file | length) > 0 then $events_file else null end),
      snapshotEnvelope: {
        runStatus: ($snapshot.run.status // "unknown"),
        lastEventName: ($snapshot.health.lastEventName // null),
        hasPendingApproval: (if ($snapshot.runtime.approval // null) != null and (($snapshot.runtime.approval.status // "") == "pending") then true else false end)
      },
      lastEventEnvelope: $last_event
    }
  }')

mkdir -p "$(dirname "$state_file")"
if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$state_json" > "$state_file"
  jq '.' "$state_file"
else
  jq -c '.' <<<"$state_json" > "$state_file"
  cat "$state_file"
fi
