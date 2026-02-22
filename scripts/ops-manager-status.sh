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
ops_dir="$repo/.superloop/ops-manager/$loop_id"
telemetry_dir="$ops_dir/telemetry"
reconcile_telemetry_file="$telemetry_dir/reconcile.jsonl"

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

status_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$(timestamp)" \
  --arg repo_path "$repo" \
  --arg loop_id "$loop_id" \
  --arg state_file "$state_file" \
  --arg cursor_file "$cursor_file" \
  --arg health_file "$health_file" \
  --arg intents_file "$intents_file" \
  --arg reconcile_telemetry_file "$reconcile_telemetry_file" \
  --argjson state "$state_json" \
  --argjson cursor "$cursor_json" \
  --argjson health_file_json "$health_json" \
  --argjson last_intent "$last_intent_json" \
  --argjson last_reconcile "$last_reconcile_json" \
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
      lastTimestamp: ($last_intent.timestamp // null)
    },
    reconcile: {
      lastStatus: ($last_reconcile.status // null),
      lastTimestamp: ($last_reconcile.timestamp // null),
      lastTransport: ($last_reconcile.transport // null),
      lastFailureCode: ($last_reconcile.failureCode // null),
      lastDurationSeconds: ($last_reconcile.durationSeconds // null)
    },
    files: {
      stateFile: $state_file,
      cursorFile: $cursor_file,
      healthFile: $health_file,
      intentsFile: $intents_file,
      reconcileTelemetryFile: $reconcile_telemetry_file
    }
  } | with_entries(select(.value != null))')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$status_json"
else
  jq -c '.' <<<"$status_json"
fi
