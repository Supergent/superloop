#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/horizon-orchestrate.sh <plan|dispatch> [options]

Common options:
  --repo <path>                       Repository path (default: .)
  --state-dir <path>                  Horizon state directory (default: <repo>/.superloop/horizons)
  --orchestrator-telemetry-file <p>   Orchestrator telemetry JSONL path (default: <state-dir>/telemetry/orchestrator.jsonl)
  --outbox-dir <path>                 Outbox directory for filesystem adapter (default: <state-dir>/outbox)
  --directory-file <path>             Horizon directory file path (default: <repo>/.superloop/horizon-directory.json)
  --directory-mode <mode>             Directory mode: off|optional|required (default: optional)
  --horizon-ref <id>                  Optional horizon filter
  --recipient-type <type>             Optional recipient type filter
  --limit <n>                         Max queued packets to select (default: 20)
  --adapter <filesystem_outbox|stdout> Dispatch adapter fallback (default: filesystem_outbox)
  --actor <id>                        Actor recorded on transitions (default: horizon-orchestrator)
  --reason <text>                     Transition reason for queued->dispatched (default: packet_dispatched_by_orchestrator)
  --note <text>                       Optional transition note
  --trace-id <id>                     Optional orchestrator run trace id
  --evidence-ref <ref>                Optional evidence ref, can be repeated
  --pretty                            Pretty-print JSON output

Dispatch options:
  --dry-run                           Build dispatch plan but do not mutate packets or emit deliveries

Commands:
  plan     Produce deterministic dispatch plan with freshness and routing annotations
  dispatch Execute dispatch plan (or preview with --dry-run)
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
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
  printf 'hor-%s-%s-%04d\n' "$(date -u +%Y%m%d%H%M%S)" "$$" "$RANDOM"
}

emit_json() {
  local json="$1"
  local pretty="${2:-0}"
  if [[ "$pretty" == "1" ]]; then
    jq '.' <<<"$json"
  else
    jq -c '.' <<<"$json"
  fi
}

build_custom_evidence_refs_json() {
  if [[ ${#EVIDENCE_REFS[@]} -eq 0 ]]; then
    echo '[]'
    return 0
  fi
  printf '%s\n' "${EVIDENCE_REFS[@]}" | jq -Rsc 'split("\n")[:-1] | map(select(length > 0))'
}

relative_or_original_path() {
  local base="$1"
  local path="$2"
  if [[ "$path" == "$base"/* ]]; then
    echo "${path#$base/}"
  else
    echo "$path"
  fi
}

append_orchestrator_telemetry() {
  local telemetry_file="$1"
  local payload_json="$2"
  mkdir -p "$(dirname "$telemetry_file")"
  jq -c '.' <<<"$payload_json" >> "$telemetry_file"
}

load_directory_contacts() {
  local mode="$1"
  local file="$2"

  DIRECTORY_ENABLED="0"
  DIRECTORY_CONTACTS_JSON='{}'

  if [[ "$mode" == "off" ]]; then
    return 0
  fi

  if [[ ! -f "$file" ]]; then
    if [[ "$mode" == "required" ]]; then
      die "directory mode is required but file is missing: $file"
    fi
    return 0
  fi

  jq -e '
    .version == 1 and
    (.contacts | type == "array") and
    ([.contacts[] | .recipient.type + "|" + .recipient.id] | length == (unique | length))
  ' "$file" >/dev/null || die "invalid horizon directory file: $file"

  DIRECTORY_CONTACTS_JSON="$(jq -c '
    .contacts
    | map({
        key: ((.recipient.type // "") + "|" + (.recipient.id // "")),
        value: {
          dispatchAdapter: (.dispatch.adapter // null),
          dispatchTarget: (.dispatch.target // null),
          ackTimeoutSeconds: (.ack.timeout_seconds // null),
          maxRetries: (.ack.max_retries // null),
          retryBackoffSeconds: (.ack.retry_backoff_seconds // null)
        }
      })
    | from_entries
  ' "$file")"

  DIRECTORY_ENABLED="1"
}

build_plan() {
  local packets_json="$1"

  jq -cn \
    --arg default_adapter "$ADAPTER" \
    --arg outbox_dir "$OUTBOX_DIR" \
    --arg directory_mode "$DIRECTORY_MODE" \
    --arg directory_file "$DIRECTORY_FILE" \
    --argjson directory_enabled "$( [[ "$DIRECTORY_ENABLED" == "1" ]] && echo true || echo false )" \
    --argjson directory_contacts "$DIRECTORY_CONTACTS_JSON" \
    --argjson now_epoch "$NOW_EPOCH" '
    [ $packets_json[]
      | . as $packet
      | ((try (($packet.createdAt // "") | fromdateiso8601) catch null)) as $created_epoch
      | (if $packet.ttlSeconds == null then null else (try ($packet.ttlSeconds | tonumber) catch null) end) as $ttl_seconds
      | (($packet.recipient.type // "") | gsub("[^A-Za-z0-9._-]"; "_")) as $safe_type
      | (($packet.recipient.id // "") | gsub("[^A-Za-z0-9._-]"; "_")) as $safe_id
      | (($packet.recipient.type // "") + "|" + ($packet.recipient.id // "")) as $contact_key
      | ($directory_contacts[$contact_key] // null) as $directory_contact
      | (
          if ($directory_enabled and $directory_contact != null and (($directory_contact.dispatchAdapter // "") | length) > 0)
          then $directory_contact.dispatchAdapter
          else $default_adapter
          end
        ) as $route_adapter
      | (
          if $route_adapter == "filesystem_outbox"
          then (
            if ($directory_enabled and $directory_contact != null and (($directory_contact.dispatchTarget // "") | length) > 0)
            then (
              if ($directory_contact.dispatchTarget | startswith("/"))
              then $directory_contact.dispatchTarget
              else ($outbox_dir + "/" + $directory_contact.dispatchTarget)
              end
            )
            else ($outbox_dir + "/" + $safe_type + "/" + $safe_id + ".jsonl")
            end
          )
          elif $route_adapter == "stdout"
          then "stdout://horizon-orchestrate"
          else null
          end
        ) as $dispatch_target
      | (
          [
            (if $created_epoch == null then "packet_created_at_invalid" else empty end),
            (if ($ttl_seconds != null and $created_epoch != null and (($now_epoch - $created_epoch) > $ttl_seconds)) then "packet_ttl_expired" else empty end),
            (if (($packet.recipient.type // "") | length) == 0 then "packet_recipient_type_missing" else empty end),
            (if (($packet.recipient.id // "") | length) == 0 then "packet_recipient_id_missing" else empty end),
            (if ($directory_mode == "required" and $directory_enabled and $directory_contact == null) then "directory_contact_not_found" else empty end),
            (if ($route_adapter != "filesystem_outbox" and $route_adapter != "stdout") then "dispatch_adapter_invalid" else empty end),
            (if ($route_adapter == "filesystem_outbox" and (($dispatch_target // "") | length) == 0) then "dispatch_target_missing" else empty end)
          ]
        ) as $blocked_reasons
      | {
          packetId: ($packet.packetId // null),
          horizonRef: ($packet.horizonRef // null),
          traceId: ($packet.traceId // null),
          loopId: ($packet.loopId // null),
          status: ($packet.status // null),
          sender: ($packet.sender // null),
          recipient: ($packet.recipient // {type: null, id: null}),
          intent: ($packet.intent // null),
          createdAt: ($packet.createdAt // null),
          ttlSeconds: (if $ttl_seconds == null then null else $ttl_seconds end),
          ageSeconds: (if $created_epoch == null then null else ($now_epoch - $created_epoch) end),
          blockedReasons: $blocked_reasons,
          dispatchable: (($blocked_reasons | length) == 0),
          dispatchRoute: {
            adapter: $route_adapter,
            target: $dispatch_target
          },
          ackPolicy: {
            timeoutSeconds: (
              if ($directory_contact != null and ($directory_contact.ackTimeoutSeconds // null) != null and (($directory_contact.ackTimeoutSeconds | type) == "number") and ($directory_contact.ackTimeoutSeconds >= 0) and ($directory_contact.ackTimeoutSeconds == ($directory_contact.ackTimeoutSeconds | floor)))
              then $directory_contact.ackTimeoutSeconds
              else null
              end
            ),
            maxRetries: (
              if ($directory_contact != null and ($directory_contact.maxRetries // null) != null and (($directory_contact.maxRetries | type) == "number") and ($directory_contact.maxRetries >= 0) and ($directory_contact.maxRetries == ($directory_contact.maxRetries | floor)))
              then $directory_contact.maxRetries
              else null
              end
            ),
            retryBackoffSeconds: (
              if ($directory_contact != null and ($directory_contact.retryBackoffSeconds // null) != null and (($directory_contact.retryBackoffSeconds | type) == "number") and ($directory_contact.retryBackoffSeconds >= 0) and ($directory_contact.retryBackoffSeconds == ($directory_contact.retryBackoffSeconds | floor)))
              then $directory_contact.retryBackoffSeconds
              else null
              end
            )
          },
          directory: {
            enabled: $directory_enabled,
            mode: $directory_mode,
            file: (if $directory_enabled then $directory_file else null end),
            matched: ($directory_contact != null),
            contactKey: $contact_key
          }
        }
    ]
  ' --argjson packets_json "$packets_json"
}

build_envelope() {
  local item_json="$1"
  local item_adapter="$2"
  local safe_target="$3"

  jq -cn \
    --arg schema_version "v1" \
    --arg timestamp "$(timestamp)" \
    --arg category "horizon_dispatch" \
    --arg trace_id "$TRACE_ID" \
    --arg actor "$ACTOR" \
    --arg adapter "$item_adapter" \
    --arg target "$safe_target" \
    --arg reason "$REASON" \
    --arg note "$NOTE" \
    --argjson packet "$item_json" \
    --argjson evidence_refs "$CUSTOM_EVIDENCE_REFS_JSON" '
    {
      schemaVersion: $schema_version,
      timestamp: $timestamp,
      category: $category,
      traceId: $trace_id,
      actor: $actor,
      adapter: $adapter,
      target: (if ($target | length) > 0 then $target else null end),
      reason: $reason,
      note: (if ($note | length) > 0 then $note else null end),
      packet: {
        packetId: ($packet.packetId // null),
        horizonRef: ($packet.horizonRef // null),
        loopId: ($packet.loopId // null),
        sender: ($packet.sender // null),
        recipient: ($packet.recipient // {type: null, id: null}),
        intent: ($packet.intent // null),
        traceId: ($packet.traceId // null)
      },
      evidenceRefs: $evidence_refs
    }
  '
}

CMD="${1:-}"
if [[ -z "$CMD" || "$CMD" == "--help" || "$CMD" == "-h" ]]; then
  usage
  [[ -n "$CMD" ]] && exit 0 || exit 1
fi
shift

REPO="."
STATE_DIR=""
ORCHESTRATOR_TELEMETRY_FILE=""
OUTBOX_DIR=""
DIRECTORY_FILE=""
DIRECTORY_MODE="optional"
HORIZON_REF_FILTER=""
RECIPIENT_TYPE_FILTER=""
LIMIT="20"
ADAPTER="filesystem_outbox"
ACTOR="horizon-orchestrator"
REASON="packet_dispatched_by_orchestrator"
NOTE=""
TRACE_ID=""
DRY_RUN="0"
PRETTY="0"
EVIDENCE_REFS=()
DIRECTORY_ENABLED="0"
DIRECTORY_CONTACTS_JSON='{}'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --orchestrator-telemetry-file)
      ORCHESTRATOR_TELEMETRY_FILE="${2:-}"
      shift 2
      ;;
    --outbox-dir)
      OUTBOX_DIR="${2:-}"
      shift 2
      ;;
    --directory-file)
      DIRECTORY_FILE="${2:-}"
      shift 2
      ;;
    --directory-mode)
      DIRECTORY_MODE="${2:-}"
      shift 2
      ;;
    --horizon-ref)
      HORIZON_REF_FILTER="${2:-}"
      shift 2
      ;;
    --recipient-type)
      RECIPIENT_TYPE_FILTER="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --adapter)
      ADAPTER="${2:-}"
      shift 2
      ;;
    --actor)
      ACTOR="${2:-}"
      shift 2
      ;;
    --reason)
      REASON="${2:-}"
      shift 2
      ;;
    --note)
      NOTE="${2:-}"
      shift 2
      ;;
    --trace-id)
      TRACE_ID="${2:-}"
      shift 2
      ;;
    --evidence-ref)
      EVIDENCE_REFS+=("${2:-}")
      shift 2
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --pretty)
      PRETTY="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$CMD" in
  plan|dispatch)
    ;;
  *)
    usage
    die "unknown command: $CMD"
    ;;
esac

need_cmd jq

[[ "$LIMIT" =~ ^[0-9]+$ ]] || die "--limit must be an integer >= 0"
(( LIMIT >= 0 )) || die "--limit must be an integer >= 0"

case "$ADAPTER" in
  filesystem_outbox|stdout)
    ;;
  *)
    die "invalid --adapter: $ADAPTER"
    ;;
esac

case "$DIRECTORY_MODE" in
  off|optional|required)
    ;;
  *)
    die "invalid --directory-mode: $DIRECTORY_MODE"
    ;;
esac

if [[ -z "$ACTOR" ]]; then
  die "--actor must be non-empty"
fi
if [[ -z "$REASON" ]]; then
  die "--reason must be non-empty"
fi

REPO="$(cd "$REPO" && pwd)"
if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$REPO/.superloop/horizons"
fi
if [[ "$STATE_DIR" != /* ]]; then
  STATE_DIR="$REPO/$STATE_DIR"
fi
if [[ -z "$ORCHESTRATOR_TELEMETRY_FILE" ]]; then
  ORCHESTRATOR_TELEMETRY_FILE="$STATE_DIR/telemetry/orchestrator.jsonl"
fi
if [[ "$ORCHESTRATOR_TELEMETRY_FILE" != /* ]]; then
  ORCHESTRATOR_TELEMETRY_FILE="$REPO/$ORCHESTRATOR_TELEMETRY_FILE"
fi
if [[ -z "$OUTBOX_DIR" ]]; then
  OUTBOX_DIR="$STATE_DIR/outbox"
fi
if [[ "$OUTBOX_DIR" != /* ]]; then
  OUTBOX_DIR="$REPO/$OUTBOX_DIR"
fi
if [[ -z "$DIRECTORY_FILE" ]]; then
  DIRECTORY_FILE="$REPO/.superloop/horizon-directory.json"
fi
if [[ "$DIRECTORY_FILE" != /* ]]; then
  DIRECTORY_FILE="$REPO/$DIRECTORY_FILE"
fi

load_directory_contacts "$DIRECTORY_MODE" "$DIRECTORY_FILE"

if [[ -z "$TRACE_ID" ]]; then
  TRACE_ID="${HORIZON_TRACE_ID:-}"
fi
if [[ -z "$TRACE_ID" ]]; then
  TRACE_ID="$(generate_trace_id)"
fi

PACKETS_DIR="$STATE_DIR/packets"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HORIZON_PACKET_SCRIPT="$SCRIPT_DIR/horizon-packet.sh"
[[ -x "$HORIZON_PACKET_SCRIPT" ]] || die "required script not executable: $HORIZON_PACKET_SCRIPT"

CUSTOM_EVIDENCE_REFS_JSON="$(build_custom_evidence_refs_json)"
NOW_EPOCH="$(date -u +%s)"
RUN_AT="$(timestamp)"

if [[ -d "$PACKETS_DIR" ]]; then
  mapfile -t PACKET_FILES < <(find "$PACKETS_DIR" -maxdepth 1 -type f -name '*.json' | sort)
else
  PACKET_FILES=()
fi

if [[ ${#PACKET_FILES[@]} -eq 0 ]]; then
  queued_packets_json='[]'
else
  queued_packets_json="$(jq -s \
    --arg horizon_ref "$HORIZON_REF_FILTER" \
    --arg recipient_type "$RECIPIENT_TYPE_FILTER" \
    '[ .[]
      | select((.status // "") == "queued")
      | select(
          if ($horizon_ref | length) > 0
          then (.horizonRef // "") == $horizon_ref
          else true
          end
        )
      | select(
          if ($recipient_type | length) > 0
          then (.recipient.type // "") == $recipient_type
          else true
          end
        )
    ]
    | sort_by((.createdAt // ""), (.packetId // ""))' "${PACKET_FILES[@]}")"
fi

selected_packets_json="$(jq -c --argjson limit "$LIMIT" '
  if $limit == 0 then [] else .[0:$limit] end
' <<<"$queued_packets_json")"

plan_items_json="$(build_plan "$selected_packets_json")"

plan_summary_json="$(jq -c '
  {
    selectedCount: length,
    dispatchableCount: ([ .[] | select(.dispatchable == true) ] | length),
    blockedCount: ([ .[] | select(.dispatchable == false) ] | length),
    blockedByReason: (
      [ .[] | .blockedReasons[] ]
      | reduce .[] as $reason ({}; .[$reason] = ((.[$reason] // 0) + 1))
    )
  }
' <<<"$plan_items_json")"

plan_json="$(jq -cn \
  --arg schema_version "v1" \
  --arg timestamp "$RUN_AT" \
  --arg trace_id "$TRACE_ID" \
  --arg command "$CMD" \
  --arg adapter "$ADAPTER" \
  --arg horizon_ref "$HORIZON_REF_FILTER" \
  --arg recipient_type "$RECIPIENT_TYPE_FILTER" \
  --arg directory_mode "$DIRECTORY_MODE" \
  --arg directory_file "$DIRECTORY_FILE" \
  --argjson directory_enabled "$( [[ "$DIRECTORY_ENABLED" == "1" ]] && echo true || echo false )" \
  --argjson limit "$LIMIT" \
  --argjson dry_run "$( [[ "$DRY_RUN" == "1" ]] && echo true || echo false )" \
  --arg state_dir "$STATE_DIR" \
  --arg outbox_dir "$OUTBOX_DIR" \
  --arg orchestrator_telemetry_file "$ORCHESTRATOR_TELEMETRY_FILE" \
  --arg actor "$ACTOR" \
  --arg reason "$REASON" \
  --arg note "$NOTE" \
  --argjson evidence_refs "$CUSTOM_EVIDENCE_REFS_JSON" \
  --argjson plan_items "$plan_items_json" \
  --argjson plan_summary "$plan_summary_json" '
  {
    schemaVersion: $schema_version,
    timestamp: $timestamp,
    category: "horizon_orchestrator_run",
    traceId: $trace_id,
    command: $command,
    adapter: $adapter,
    dryRun: $dry_run,
    filters: {
      horizonRef: (if ($horizon_ref | length) > 0 then $horizon_ref else null end),
      recipientType: (if ($recipient_type | length) > 0 then $recipient_type else null end),
      limit: $limit
    },
    directory: {
      mode: $directory_mode,
      enabled: $directory_enabled,
      file: (if $directory_enabled then $directory_file else null end)
    },
    context: {
      stateDir: $state_dir,
      outboxDir: $outbox_dir,
      orchestratorTelemetryFile: $orchestrator_telemetry_file,
      actor: $actor,
      reason: $reason,
      note: (if ($note | length) > 0 then $note else null end),
      evidenceRefs: $evidence_refs
    },
    summary: $plan_summary,
    items: $plan_items
  }
')"

if [[ "$CMD" == "plan" ]]; then
  append_orchestrator_telemetry "$ORCHESTRATOR_TELEMETRY_FILE" "$plan_json"
  emit_json "$plan_json" "$PRETTY"
  exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
  dispatch_json="$(jq -c '. + {
    execution: {
      status: "dry_run",
      attemptedCount: 0,
      dispatchedCount: 0,
      failedCount: 0,
      blockedCount: (.summary.blockedCount // 0),
      results: []
    }
  }' <<<"$plan_json")"
  append_orchestrator_telemetry "$ORCHESTRATOR_TELEMETRY_FILE" "$dispatch_json"
  emit_json "$dispatch_json" "$PRETTY"
  exit 0
fi

mapfile -t dispatch_items < <(jq -c '.items[] | select(.dispatchable == true)' <<<"$plan_json")

dispatch_result_lines=()
dispatched_count=0
failed_count=0
exit_code=0

for item_json in "${dispatch_items[@]}"; do
  packet_id="$(jq -r '.packetId // empty' <<<"$item_json")"
  item_adapter="$(jq -r '.dispatchRoute.adapter // empty' <<<"$item_json")"
  dispatch_target="$(jq -r '.dispatchRoute.target // empty' <<<"$item_json")"
  safe_target="$(relative_or_original_path "$REPO" "$dispatch_target")"

  transition_cmd=("$HORIZON_PACKET_SCRIPT" transition
    --repo "$REPO"
    --state-dir "$STATE_DIR"
    --packet-id "$packet_id"
    --to-status dispatched
    --by "$ACTOR"
    --reason "$REASON")

  if [[ -n "$NOTE" ]]; then
    transition_cmd+=(--note "$NOTE")
  fi
  if [[ ${#EVIDENCE_REFS[@]} -gt 0 ]]; then
    for ref in "${EVIDENCE_REFS[@]}"; do
      transition_cmd+=(--evidence-ref "$ref")
    done
  fi

  if ! transition_output="$("${transition_cmd[@]}" 2>&1)"; then
    failed_count=$((failed_count + 1))
    exit_code=1
    dispatch_result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "failed" \
      --arg reason_code "dispatch_transition_failed" \
      --arg error "$transition_output" \
      --arg adapter "$item_adapter" \
      --arg target "$safe_target" '
      {
        packetId: $packet_id,
        status: $status,
        reasonCode: $reason_code,
        adapter: $adapter,
        target: (if ($target | length) > 0 then $target else null end),
        error: $error
      }
    ')")
    continue
  fi

  envelope_json="$(build_envelope "$item_json" "$item_adapter" "$safe_target")"

  write_ok=1
  write_error=""
  case "$item_adapter" in
    filesystem_outbox)
      if ! mkdir -p "$(dirname "$dispatch_target")" || ! printf '%s\n' "$envelope_json" >> "$dispatch_target"; then
        write_ok=0
        write_error="failed to append outbox envelope: $safe_target"
      fi
      ;;
    stdout)
      :
      ;;
    *)
      write_ok=0
      write_error="unsupported adapter selected at dispatch time: $item_adapter"
      ;;
  esac

  if [[ "$write_ok" == "0" ]]; then
    failed_count=$((failed_count + 1))
    exit_code=1

    "$HORIZON_PACKET_SCRIPT" transition \
      --repo "$REPO" \
      --state-dir "$STATE_DIR" \
      --packet-id "$packet_id" \
      --to-status failed \
      --by "$ACTOR" \
      --reason "adapter_write_failed" \
      --note "$write_error" >/dev/null 2>&1 || true

    dispatch_result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "failed" \
      --arg reason_code "adapter_write_failed" \
      --arg error "$write_error" \
      --arg adapter "$item_adapter" \
      --arg target "$safe_target" '
      {
        packetId: $packet_id,
        status: $status,
        reasonCode: $reason_code,
        adapter: $adapter,
        target: (if ($target | length) > 0 then $target else null end),
        error: $error
      }
    ')")
    continue
  fi

  dispatched_count=$((dispatched_count + 1))

  if [[ "$item_adapter" == "stdout" ]]; then
    dispatch_result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "dispatched" \
      --arg adapter "$item_adapter" \
      --arg target "$safe_target" \
      --argjson envelope "$envelope_json" '
      {
        packetId: $packet_id,
        status: $status,
        adapter: $adapter,
        target: (if ($target | length) > 0 then $target else null end),
        envelope: $envelope
      }
    ')")
  else
    dispatch_result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "dispatched" \
      --arg adapter "$item_adapter" \
      --arg target "$safe_target" '
      {
        packetId: $packet_id,
        status: $status,
        adapter: $adapter,
        target: (if ($target | length) > 0 then $target else null end)
      }
    ')")
  fi

done

if [[ ${#dispatch_result_lines[@]} -eq 0 ]]; then
  dispatch_results_json='[]'
else
  dispatch_results_json="$(printf '%s\n' "${dispatch_result_lines[@]}" | jq -s '.')"
fi

attempted_count="${#dispatch_items[@]}"

execution_status="success"
if [[ "$failed_count" -gt 0 ]]; then
  execution_status="partial_failure"
fi

final_json="$(jq -c \
  --arg status "$execution_status" \
  --argjson attempted "$attempted_count" \
  --argjson dispatched "$dispatched_count" \
  --argjson failed "$failed_count" \
  --argjson blocked "$(jq -r '.summary.blockedCount // 0' <<<"$plan_json")" \
  --argjson results "$dispatch_results_json" '
  . + {
    execution: {
      status: $status,
      attemptedCount: $attempted,
      dispatchedCount: $dispatched,
      failedCount: $failed,
      blockedCount: $blocked,
      results: $results
    }
  }
' <<<"$plan_json")"

append_orchestrator_telemetry "$ORCHESTRATOR_TELEMETRY_FILE" "$final_json"
emit_json "$final_json" "$PRETTY"
exit "$exit_code"
