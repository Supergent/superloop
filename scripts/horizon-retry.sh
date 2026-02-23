#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/horizon-retry.sh reconcile [options]

Common options:
  --repo <path>                 Repository path (default: .)
  --state-dir <path>            Horizon state directory (default: <repo>/.superloop/horizons)
  --outbox-dir <path>           Outbox directory for filesystem adapter (default: <state-dir>/outbox)
  --directory-file <path>       Horizon directory file path (default: <repo>/.superloop/horizon-directory.json)
  --directory-mode <mode>       Directory mode: off|optional|required (default: optional)
  --horizon-ref <id>            Optional horizon filter
  --recipient-type <type>       Optional recipient type filter
  --limit <n>                   Max dispatched packets to evaluate (default: 50)
  --adapter <filesystem_outbox|stdout>
                                Adapter fallback when directory does not override (default: filesystem_outbox)
  --retry-state-file <path>     Retry state file (default: <state-dir>/retry-state.json)
  --retry-telemetry-file <path> Retry telemetry jsonl (default: <state-dir>/telemetry/retry.jsonl)
  --dead-letter-file <path>     Dead-letter jsonl (default: <state-dir>/telemetry/dead-letter.jsonl)
  --ack-timeout-seconds <n>     Ack timeout before retry/escalation (default: 600)
  --max-retries <n>             Max retries before escalation (default: 3)
  --retry-backoff-seconds <n>   Backoff between retries (default: 120)
  --actor <id>                  Actor used for escalations/failure transitions (default: horizon-retry)
  --reason <text>               Reason used for retry dispatch envelopes (default: packet_retry_dispatch)
  --trace-id <id>               Optional run trace id
  --evidence-ref <ref>          Optional evidence ref, can be repeated
  --dry-run                     Evaluate and plan actions without mutating files
  --pretty                      Pretty-print output JSON

Behavior:
  - Evaluates packets currently in `dispatched` state.
  - If ack timeout has not elapsed: no retry action.
  - If timeout elapsed and retries remain: re-dispatch via adapter.
  - If timeout elapsed and retries exhausted: transition packet to `escalated` and append dead-letter record.
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
  printf 'hrr-%s-%s-%04d\n' "$(date -u +%Y%m%d%H%M%S)" "$$" "$RANDOM"
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

relative_or_original_path() {
  local base="$1"
  local path="$2"
  if [[ "$path" == "$base"/* ]]; then
    echo "${path#$base/}"
  else
    echo "$path"
  fi
}

build_custom_evidence_refs_json() {
  if [[ ${#EVIDENCE_REFS[@]} -eq 0 ]]; then
    echo '[]'
    return 0
  fi
  printf '%s\n' "${EVIDENCE_REFS[@]}" | jq -Rsc 'split("\n")[:-1] | map(select(length > 0))'
}

append_jsonl() {
  local file="$1"
  local payload="$2"
  mkdir -p "$(dirname "$file")"
  jq -c '.' <<<"$payload" >> "$file"
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

resolve_route_and_policy() {
  local packet_json="$1"

  jq -cn \
    --arg default_adapter "$ADAPTER" \
    --arg outbox_dir "$OUTBOX_DIR" \
    --arg directory_mode "$DIRECTORY_MODE" \
    --arg directory_file "$DIRECTORY_FILE" \
    --argjson directory_enabled "$( [[ "$DIRECTORY_ENABLED" == "1" ]] && echo true || echo false )" \
    --argjson directory_contacts "$DIRECTORY_CONTACTS_JSON" \
    --argjson default_ack_timeout "$ACK_TIMEOUT_SECONDS" \
    --argjson default_max_retries "$MAX_RETRIES" \
    --argjson default_backoff "$RETRY_BACKOFF_SECONDS" '
    $packet_json as $packet
    | (($packet.recipient.type // "") | gsub("[^A-Za-z0-9._-]"; "_")) as $safe_type
    | (($packet.recipient.id // "") | gsub("[^A-Za-z0-9._-]"; "_")) as $safe_id
    | (($packet.recipient.type // "") + "|" + ($packet.recipient.id // "")) as $contact_key
    | ($directory_contacts[$contact_key] // null) as $contact
    | (
        if ($directory_enabled and $contact != null and (($contact.dispatchAdapter // "") | length) > 0)
        then $contact.dispatchAdapter
        else $default_adapter
        end
      ) as $adapter
    | (
        if $adapter == "filesystem_outbox"
        then (
          if ($directory_enabled and $contact != null and (($contact.dispatchTarget // "") | length) > 0)
          then (
            if ($contact.dispatchTarget | startswith("/"))
            then $contact.dispatchTarget
            else ($outbox_dir + "/" + $contact.dispatchTarget)
            end
          )
          else ($outbox_dir + "/" + $safe_type + "/" + $safe_id + ".jsonl")
          end
        )
        elif $adapter == "stdout"
        then "stdout://horizon-retry"
        else null
        end
      ) as $target
    | {
        directory: {
          enabled: $directory_enabled,
          mode: $directory_mode,
          file: (if $directory_enabled then $directory_file else null end),
          contactKey: $contact_key,
          matched: ($contact != null)
        },
        route: {
          adapter: $adapter,
          target: $target
        },
        policy: {
          ackTimeoutSeconds: (
            if ($contact != null and ($contact.ackTimeoutSeconds // null) != null and (($contact.ackTimeoutSeconds | type) == "number") and ($contact.ackTimeoutSeconds >= 0) and ($contact.ackTimeoutSeconds == ($contact.ackTimeoutSeconds | floor)))
            then ($contact.ackTimeoutSeconds | floor)
            else $default_ack_timeout
            end
          ),
          maxRetries: (
            if ($contact != null and ($contact.maxRetries // null) != null and (($contact.maxRetries | type) == "number") and ($contact.maxRetries >= 0) and ($contact.maxRetries == ($contact.maxRetries | floor)))
            then ($contact.maxRetries | floor)
            else $default_max_retries
            end
          ),
          retryBackoffSeconds: (
            if ($contact != null and ($contact.retryBackoffSeconds // null) != null and (($contact.retryBackoffSeconds | type) == "number") and ($contact.retryBackoffSeconds >= 0) and ($contact.retryBackoffSeconds == ($contact.retryBackoffSeconds | floor)))
            then ($contact.retryBackoffSeconds | floor)
            else $default_backoff
            end
          )
        }
      }
  ' --argjson packet_json "$packet_json"
}

build_retry_envelope() {
  local packet_json="$1"
  local adapter="$2"
  local target="$3"
  local attempt="$4"

  jq -cn \
    --arg schema_version "v1" \
    --arg timestamp "$(timestamp)" \
    --arg category "horizon_dispatch_retry" \
    --arg trace_id "$TRACE_ID" \
    --arg actor "$ACTOR" \
    --arg adapter "$adapter" \
    --arg target "$target" \
    --arg reason "$REASON" \
    --argjson attempt "$attempt" \
    --argjson packet "$packet_json" \
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
      retryAttempt: $attempt,
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

case "$CMD" in
  reconcile)
    ;;
  *)
    usage
    die "unknown command: $CMD"
    ;;
esac

REPO="."
STATE_DIR=""
OUTBOX_DIR=""
DIRECTORY_FILE=""
DIRECTORY_MODE="optional"
HORIZON_REF_FILTER=""
RECIPIENT_TYPE_FILTER=""
LIMIT="50"
ADAPTER="filesystem_outbox"
RETRY_STATE_FILE=""
RETRY_TELEMETRY_FILE=""
DEAD_LETTER_FILE=""
ACK_TIMEOUT_SECONDS="600"
MAX_RETRIES="3"
RETRY_BACKOFF_SECONDS="120"
ACTOR="horizon-retry"
REASON="packet_retry_dispatch"
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
    --retry-state-file)
      RETRY_STATE_FILE="${2:-}"
      shift 2
      ;;
    --retry-telemetry-file)
      RETRY_TELEMETRY_FILE="${2:-}"
      shift 2
      ;;
    --dead-letter-file)
      DEAD_LETTER_FILE="${2:-}"
      shift 2
      ;;
    --ack-timeout-seconds)
      ACK_TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --max-retries)
      MAX_RETRIES="${2:-}"
      shift 2
      ;;
    --retry-backoff-seconds)
      RETRY_BACKOFF_SECONDS="${2:-}"
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

need_cmd jq

[[ "$LIMIT" =~ ^[0-9]+$ ]] || die "--limit must be an integer >= 0"
[[ "$ACK_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die "--ack-timeout-seconds must be an integer >= 0"
[[ "$MAX_RETRIES" =~ ^[0-9]+$ ]] || die "--max-retries must be an integer >= 0"
[[ "$RETRY_BACKOFF_SECONDS" =~ ^[0-9]+$ ]] || die "--retry-backoff-seconds must be an integer >= 0"

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

REPO="$(cd "$REPO" && pwd)"
if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$REPO/.superloop/horizons"
fi
if [[ "$STATE_DIR" != /* ]]; then
  STATE_DIR="$REPO/$STATE_DIR"
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
if [[ -z "$RETRY_STATE_FILE" ]]; then
  RETRY_STATE_FILE="$STATE_DIR/retry-state.json"
fi
if [[ "$RETRY_STATE_FILE" != /* ]]; then
  RETRY_STATE_FILE="$REPO/$RETRY_STATE_FILE"
fi
if [[ -z "$RETRY_TELEMETRY_FILE" ]]; then
  RETRY_TELEMETRY_FILE="$STATE_DIR/telemetry/retry.jsonl"
fi
if [[ "$RETRY_TELEMETRY_FILE" != /* ]]; then
  RETRY_TELEMETRY_FILE="$REPO/$RETRY_TELEMETRY_FILE"
fi
if [[ -z "$DEAD_LETTER_FILE" ]]; then
  DEAD_LETTER_FILE="$STATE_DIR/telemetry/dead-letter.jsonl"
fi
if [[ "$DEAD_LETTER_FILE" != /* ]]; then
  DEAD_LETTER_FILE="$REPO/$DEAD_LETTER_FILE"
fi

load_directory_contacts "$DIRECTORY_MODE" "$DIRECTORY_FILE"

if [[ -z "$TRACE_ID" ]]; then
  TRACE_ID="${HORIZON_TRACE_ID:-}"
fi
if [[ -z "$TRACE_ID" ]]; then
  TRACE_ID="$(generate_trace_id)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HORIZON_PACKET_SCRIPT="$SCRIPT_DIR/horizon-packet.sh"
[[ -x "$HORIZON_PACKET_SCRIPT" ]] || die "required script not executable: $HORIZON_PACKET_SCRIPT"

PACKETS_DIR="$STATE_DIR/packets"
if [[ -d "$PACKETS_DIR" ]]; then
  mapfile -t PACKET_FILES < <(find "$PACKETS_DIR" -maxdepth 1 -type f -name '*.json' | sort)
else
  PACKET_FILES=()
fi

if [[ ${#PACKET_FILES[@]} -eq 0 ]]; then
  dispatched_packets_json='[]'
else
  dispatched_packets_json="$(jq -s \
    --arg horizon_ref "$HORIZON_REF_FILTER" \
    --arg recipient_type "$RECIPIENT_TYPE_FILTER" \
    '[ .[]
      | select((.status // "") == "dispatched")
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
    | sort_by((.updatedAt // ""), (.packetId // ""))' "${PACKET_FILES[@]}")"
fi

selected_packets_json="$(jq -c --argjson limit "$LIMIT" '
  if $limit == 0 then [] else .[0:$limit] end
' <<<"$dispatched_packets_json")"

if [[ -f "$RETRY_STATE_FILE" ]]; then
  RETRY_STATE_JSON="$(jq -c '.' "$RETRY_STATE_FILE" 2>/dev/null)" || die "invalid retry state file: $RETRY_STATE_FILE"
else
  RETRY_STATE_JSON='{"schemaVersion":"v1","updatedAt":null,"packets":{}}'
fi
RETRY_STATE_JSON="$(jq -c 'if (.packets|type)!="object" then .packets={} else . end | if .schemaVersion==null then .schemaVersion="v1" else . end' <<<"$RETRY_STATE_JSON")"

CUSTOM_EVIDENCE_REFS_JSON="$(build_custom_evidence_refs_json)"
NOW_EPOCH="$(date -u +%s)"
RUN_AT="$(timestamp)"

considered_count=0
retry_due_count=0
retried_count=0
escalated_count=0
blocked_count=0
error_count=0
result_lines=()
dead_letter_lines=()

mapfile -t packet_items < <(jq -c '.[]' <<<"$selected_packets_json")

for packet_json in "${packet_items[@]}"; do
  considered_count=$((considered_count + 1))

  packet_id="$(jq -r '.packetId // empty' <<<"$packet_json")"
  packet_trace_id="$(jq -r '.traceId // empty' <<<"$packet_json")"
  updated_at="$(jq -r '.updatedAt // empty' <<<"$packet_json")"

  resolved_json="$(resolve_route_and_policy "$packet_json")"
  directory_matched="$(jq -r '.directory.matched' <<<"$resolved_json")"
  route_adapter="$(jq -r '.route.adapter // empty' <<<"$resolved_json")"
  route_target="$(jq -r '.route.target // empty' <<<"$resolved_json")"
  safe_target="$(relative_or_original_path "$REPO" "$route_target")"
  ack_timeout="$(jq -r '.policy.ackTimeoutSeconds' <<<"$resolved_json")"
  max_retries="$(jq -r '.policy.maxRetries' <<<"$resolved_json")"
  retry_backoff="$(jq -r '.policy.retryBackoffSeconds' <<<"$resolved_json")"

  blocked_reason=""

  if [[ "$DIRECTORY_MODE" == "required" && "$DIRECTORY_ENABLED" == "1" && "$directory_matched" != "true" ]]; then
    blocked_reason="directory_contact_not_found"
  fi

  if [[ -z "$blocked_reason" ]]; then
    case "$route_adapter" in
      filesystem_outbox|stdout)
        ;;
      *)
        blocked_reason="dispatch_adapter_invalid"
        ;;
    esac
  fi

  if [[ -z "$blocked_reason" && "$route_adapter" == "filesystem_outbox" && -z "$route_target" ]]; then
    blocked_reason="dispatch_target_missing"
  fi

  updated_epoch="$(jq -nr --arg ts "$updated_at" 'try ($ts | fromdateiso8601) catch ""')"
  if [[ -z "$blocked_reason" && -z "$updated_epoch" ]]; then
    blocked_reason="packet_updated_at_invalid"
  fi

  retry_count="$(jq -r --arg packet_id "$packet_id" '.packets[$packet_id].retryCount // 0' <<<"$RETRY_STATE_JSON")"
  last_retry_at="$(jq -r --arg packet_id "$packet_id" '.packets[$packet_id].lastRetryAt // empty' <<<"$RETRY_STATE_JSON")"

  if [[ -n "$blocked_reason" ]]; then
    blocked_count=$((blocked_count + 1))
    result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "blocked" \
      --arg reason "$blocked_reason" \
      --arg adapter "$route_adapter" \
      --arg target "$safe_target" \
      --arg updated_at "$updated_at" '
      {
        packetId: $packet_id,
        status: $status,
        reason: $reason,
        adapter: (if ($adapter|length)>0 then $adapter else null end),
        target: (if ($target|length)>0 then $target else null end),
        updatedAt: (if ($updated_at|length)>0 then $updated_at else null end)
      }
    ')")
    continue
  fi

  age_seconds=$((NOW_EPOCH - updated_epoch))

  if (( age_seconds < ack_timeout )); then
    result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "waiting" \
      --arg reason "ack_timeout_not_reached" \
      --argjson age "$age_seconds" \
      --argjson timeout "$ack_timeout" \
      --argjson retries "$retry_count" '
      {
        packetId: $packet_id,
        status: $status,
        reason: $reason,
        ageSeconds: $age,
        ackTimeoutSeconds: $timeout,
        retryCount: $retries
      }
    ')")
    continue
  fi

  retry_due_count=$((retry_due_count + 1))

  if (( retry_count >= max_retries )); then
    if [[ "$DRY_RUN" != "1" ]]; then
      transition_cmd=("$HORIZON_PACKET_SCRIPT" transition
        --repo "$REPO"
        --state-dir "$STATE_DIR"
        --packet-id "$packet_id"
        --to-status escalated
        --by "$ACTOR"
        --reason "ack_timeout_max_retries_exceeded"
        --note "retry budget exhausted")
      if [[ ${#EVIDENCE_REFS[@]} -gt 0 ]]; then
        for ref in "${EVIDENCE_REFS[@]}"; do
          transition_cmd+=(--evidence-ref "$ref")
        done
      fi

      if ! transition_error="$("${transition_cmd[@]}" 2>&1)"; then
        error_count=$((error_count + 1))
        result_lines+=("$(jq -cn \
          --arg packet_id "$packet_id" \
          --arg status "error" \
          --arg reason "escalation_transition_failed" \
          --arg error "$transition_error" '
          {
            packetId: $packet_id,
            status: $status,
            reason: $reason,
            error: $error
          }
        ')")
        continue
      fi

      RETRY_STATE_JSON="$(jq -c --arg packet_id "$packet_id" --arg at "$RUN_AT" '
        .packets |= (if type == "object" then . else {} end)
        | del(.packets[$packet_id])
        | .updatedAt = $at
      ' <<<"$RETRY_STATE_JSON")"
    fi

    escalated_count=$((escalated_count + 1))

    dead_letter_lines+=("$(jq -cn \
      --arg schema_version "v1" \
      --arg timestamp "$RUN_AT" \
      --arg category "horizon_dead_letter" \
      --arg trace_id "$TRACE_ID" \
      --arg packet_id "$packet_id" \
      --arg horizon_ref "$(jq -r '.horizonRef // empty' <<<"$packet_json")" \
      --arg packet_trace_id "$packet_trace_id" \
      --arg actor "$ACTOR" \
      --arg reason "ack_timeout_max_retries_exceeded" \
      --argjson retries "$retry_count" \
      --argjson max_retries "$max_retries" \
      --argjson age "$age_seconds" '
      {
        schemaVersion: $schema_version,
        timestamp: $timestamp,
        category: $category,
        traceId: $trace_id,
        packetId: $packet_id,
        horizonRef: (if ($horizon_ref|length)>0 then $horizon_ref else null end),
        packetTraceId: (if ($packet_trace_id|length)>0 then $packet_trace_id else null end),
        actor: $actor,
        reason: $reason,
        retryCount: $retries,
        maxRetries: $max_retries,
        ageSeconds: $age
      }
    ')")

    result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "escalated" \
      --arg reason "ack_timeout_max_retries_exceeded" \
      --argjson retries "$retry_count" \
      --argjson max_retries "$max_retries" '
      {
        packetId: $packet_id,
        status: $status,
        reason: $reason,
        retryCount: $retries,
        maxRetries: $max_retries
      }
    ')")
    continue
  fi

  if [[ -n "$last_retry_at" ]]; then
    last_retry_epoch="$(jq -nr --arg ts "$last_retry_at" 'try ($ts | fromdateiso8601) catch ""')"
    if [[ -n "$last_retry_epoch" ]]; then
      elapsed_since_retry=$((NOW_EPOCH - last_retry_epoch))
      if (( elapsed_since_retry < retry_backoff )); then
        blocked_count=$((blocked_count + 1))
        result_lines+=("$(jq -cn \
          --arg packet_id "$packet_id" \
          --arg status "blocked" \
          --arg reason "retry_backoff_active" \
          --argjson elapsed "$elapsed_since_retry" \
          --argjson backoff "$retry_backoff" '
          {
            packetId: $packet_id,
            status: $status,
            reason: $reason,
            elapsedSinceRetrySeconds: $elapsed,
            retryBackoffSeconds: $backoff
          }
        ')")
        continue
      fi
    fi
  fi

  next_retry=$((retry_count + 1))
  envelope_json="$(build_retry_envelope "$packet_json" "$route_adapter" "$safe_target" "$next_retry")"

  if [[ "$DRY_RUN" == "1" ]]; then
    retried_count=$((retried_count + 1))
    result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "dry_run_retry" \
      --arg adapter "$route_adapter" \
      --arg target "$safe_target" \
      --argjson attempt "$next_retry" '
      {
        packetId: $packet_id,
        status: $status,
        adapter: $adapter,
        target: (if ($target|length)>0 then $target else null end),
        retryAttempt: $attempt
      }
    ')")
    continue
  fi

  write_ok=1
  write_error=""
  case "$route_adapter" in
    filesystem_outbox)
      if ! mkdir -p "$(dirname "$route_target")" || ! printf '%s\n' "$envelope_json" >> "$route_target"; then
        write_ok=0
        write_error="failed to append retry envelope: $safe_target"
      fi
      ;;
    stdout)
      :
      ;;
    *)
      write_ok=0
      write_error="unsupported adapter: $route_adapter"
      ;;
  esac

  if [[ "$write_ok" == "0" ]]; then
    error_count=$((error_count + 1))

    "$HORIZON_PACKET_SCRIPT" transition \
      --repo "$REPO" \
      --state-dir "$STATE_DIR" \
      --packet-id "$packet_id" \
      --to-status failed \
      --by "$ACTOR" \
      --reason "adapter_write_failed" \
      --note "$write_error" >/dev/null 2>&1 || true

    result_lines+=("$(jq -cn \
      --arg packet_id "$packet_id" \
      --arg status "error" \
      --arg reason "adapter_write_failed" \
      --arg error "$write_error" '
      {
        packetId: $packet_id,
        status: $status,
        reason: $reason,
        error: $error
      }
    ')")
    continue
  fi

  retried_count=$((retried_count + 1))

  RETRY_STATE_JSON="$(jq -c \
    --arg packet_id "$packet_id" \
    --arg at "$RUN_AT" \
    --argjson retry_count "$next_retry" '
    .packets |= (if type == "object" then . else {} end)
    | .packets[$packet_id] = {
        retryCount: $retry_count,
        lastRetryAt: $at
      }
    | .updatedAt = $at
  ' <<<"$RETRY_STATE_JSON")"

  result_lines+=("$(jq -cn \
    --arg packet_id "$packet_id" \
    --arg status "retried" \
    --arg adapter "$route_adapter" \
    --arg target "$safe_target" \
    --argjson attempt "$next_retry" '
    {
      packetId: $packet_id,
      status: $status,
      adapter: $adapter,
      target: (if ($target|length)>0 then $target else null end),
      retryAttempt: $attempt
    }
  ')")

done

if [[ ${#result_lines[@]} -eq 0 ]]; then
  results_json='[]'
else
  results_json="$(printf '%s\n' "${result_lines[@]}" | jq -s '.')"
fi

result_json="$(jq -cn \
  --arg schema_version "v1" \
  --arg timestamp "$RUN_AT" \
  --arg category "horizon_retry_reconcile" \
  --arg trace_id "$TRACE_ID" \
  --arg actor "$ACTOR" \
  --arg reason "$REASON" \
  --argjson dry_run "$( [[ "$DRY_RUN" == "1" ]] && echo true || echo false )" \
  --arg directory_mode "$DIRECTORY_MODE" \
  --arg directory_file "$DIRECTORY_FILE" \
  --argjson directory_enabled "$( [[ "$DIRECTORY_ENABLED" == "1" ]] && echo true || echo false )" \
  --arg state_file "$RETRY_STATE_FILE" \
  --arg telemetry_file "$RETRY_TELEMETRY_FILE" \
  --arg dead_letter_file "$DEAD_LETTER_FILE" \
  --argjson considered "$considered_count" \
  --argjson due "$retry_due_count" \
  --argjson retried "$retried_count" \
  --argjson escalated "$escalated_count" \
  --argjson blocked "$blocked_count" \
  --argjson errors "$error_count" \
  --argjson results "$results_json" '
  {
    schemaVersion: $schema_version,
    timestamp: $timestamp,
    category: $category,
    traceId: $trace_id,
    actor: $actor,
    reason: $reason,
    dryRun: $dry_run,
    directory: {
      mode: $directory_mode,
      enabled: $directory_enabled,
      file: (if $directory_enabled then $directory_file else null end)
    },
    artifacts: {
      retryStateFile: $state_file,
      retryTelemetryFile: $telemetry_file,
      deadLetterFile: $dead_letter_file
    },
    summary: {
      consideredCount: $considered,
      dueCount: $due,
      retriedCount: $retried,
      escalatedCount: $escalated,
      blockedCount: $blocked,
      errorCount: $errors
    },
    results: $results
  }
')"

if [[ "$DRY_RUN" != "1" ]]; then
  mkdir -p "$(dirname "$RETRY_STATE_FILE")"
  jq -c '.' <<<"$RETRY_STATE_JSON" > "$RETRY_STATE_FILE"

  append_jsonl "$RETRY_TELEMETRY_FILE" "$result_json"

  if [[ ${#dead_letter_lines[@]} -gt 0 ]]; then
    mkdir -p "$(dirname "$DEAD_LETTER_FILE")"
    printf '%s\n' "${dead_letter_lines[@]}" | jq -c '.' >> "$DEAD_LETTER_FILE"
  fi
fi

emit_json "$result_json" "$PRETTY"

if [[ "$error_count" -gt 0 ]]; then
  exit 1
fi
