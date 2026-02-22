#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-reconcile.sh --repo <path> --loop <id> [options]

Options:
  --transport <local|sprite_service>  Ingestion transport mode (default: local)
  --service-base-url <url>            Sprite service base URL (required for sprite_service)
  --service-token <token>             Sprite service auth token (optional)
  --retry-attempts <n>                Service retry attempts (default: 3)
  --retry-backoff-seconds <n>         Service retry backoff base (default: 1)
  --cursor-file <path>                Cursor JSON path. Default: <repo>/.superloop/ops-manager/<loop>/cursor.json
  --state-file <path>                 Output state path. Default: <repo>/.superloop/ops-manager/<loop>/state.json
  --max-events <n>                    Max incremental events to ingest (default: 0 = all available)
  --from-start                        Replay events from line 1 (ignores existing cursor)
  --pretty                            Pretty-print resulting state
  --help                              Show this help message
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
transport="local"
service_base_url=""
service_token=""
retry_attempts="3"
retry_backoff_seconds="1"
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
    --transport)
      transport="${2:-}"
      shift 2
      ;;
    --service-base-url)
      service_base_url="${2:-}"
      shift 2
      ;;
    --service-token)
      service_token="${2:-}"
      shift 2
      ;;
    --retry-attempts)
      retry_attempts="${2:-}"
      shift 2
      ;;
    --retry-backoff-seconds)
      retry_backoff_seconds="${2:-}"
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
if [[ ! "$retry_attempts" =~ ^[0-9]+$ || "$retry_attempts" -lt 1 ]]; then
  die "--retry-attempts must be an integer >= 1"
fi
if [[ ! "$retry_backoff_seconds" =~ ^[0-9]+$ ]]; then
  die "--retry-backoff-seconds must be a non-negative integer"
fi
case "$transport" in
  local|sprite_service)
    ;;
  *)
    die "--transport must be local or sprite_service"
    ;;
esac

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
client_script="${OPS_MANAGER_SERVICE_CLIENT_SCRIPT:-$script_dir/ops-manager-service-client.sh}"

if [[ -z "$service_token" && -n "${OPS_MANAGER_SERVICE_TOKEN:-}" ]]; then
  service_token="$OPS_MANAGER_SERVICE_TOKEN"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

snapshot_file="$tmp_dir/snapshot.json"
events_file="$tmp_dir/events.ndjson"

if [[ "$transport" == "local" ]]; then
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
else
  if [[ -z "$service_base_url" ]]; then
    die "--service-base-url is required when --transport sprite_service"
  fi
  need_cmd curl

  snapshot_json=$(
    "$client_script" \
      --method GET \
      --base-url "$service_base_url" \
      --path "/ops/snapshot?loopId=$loop_id" \
      --token "$service_token" \
      --retry-attempts "$retry_attempts" \
      --retry-backoff-seconds "$retry_backoff_seconds"
  )
  jq -c '.' <<<"$snapshot_json" > "$snapshot_file"

  start_offset=0
  if [[ "$from_start" != "1" && -f "$cursor_file" ]]; then
    start_offset=$(jq -r '.eventLineOffset // 0' "$cursor_file" 2>/dev/null || echo "0")
    if [[ ! "$start_offset" =~ ^[0-9]+$ ]]; then
      start_offset=0
    fi
  fi

  events_response=$(
    "$client_script" \
      --method GET \
      --base-url "$service_base_url" \
      --path "/ops/events?loopId=$loop_id&cursor=$start_offset&maxEvents=$max_events" \
      --token "$service_token" \
      --retry-attempts "$retry_attempts" \
      --retry-backoff-seconds "$retry_backoff_seconds"
  )

  jq -e '.ok == true and (.events | type == "array") and (.cursor | type == "object")' <<<"$events_response" >/dev/null \
    || die "service /ops/events response shape invalid"

  jq -c '.events[]?' <<<"$events_response" > "$events_file"

  cursor_offset=$(jq -r '.cursor.eventLineOffset // 0' <<<"$events_response")
  cursor_count=$(jq -r '.cursor.eventLineCount // 0' <<<"$events_response")
  if [[ ! "$cursor_offset" =~ ^[0-9]+$ || ! "$cursor_count" =~ ^[0-9]+$ ]]; then
    die "service cursor values are invalid"
  fi

  jq -n \
    --arg schema_version "v1" \
    --arg repo_path "$repo" \
    --arg loop_id "$loop_id" \
    --arg events_path ".superloop/loops/$loop_id/events.jsonl" \
    --arg updated_at "$(timestamp)" \
    --argjson line_offset "$cursor_offset" \
    --argjson line_count "$cursor_count" \
    '{
      schemaVersion: $schema_version,
      repoPath: $repo_path,
      loopId: $loop_id,
      eventsFile: $events_path,
      eventLineOffset: $line_offset,
      eventLineCount: $line_count,
      updatedAt: $updated_at
    }' > "$cursor_file"
fi

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
    --arg timestamp "$(timestamp)" \
    --arg loop_id "$loop_id" \
    --arg state_file "$state_file" \
    --arg cursor_file "$cursor_file" \
    --arg transport "$transport" \
    --argjson state "$state_json" \
    --arg divergence_summary "$(jq -c '.divergence.flags // {}' <<<"$state_json")" \
    '{
      timestamp: $timestamp,
      loopId: $loop_id,
      category: "divergence_detected",
      transport: $transport,
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
