#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/horizon-packet.sh <create|transition|show|list> [options]

Common options:
  --repo <path>             Repository path (default: .)
  --state-dir <path>        Horizon state directory (default: <repo>/.superloop/horizons)
  --telemetry-file <path>   Packet telemetry jsonl path (default: <state-dir>/telemetry/packets.jsonl)
  --pretty                  Pretty-print JSON output

Create options:
  --packet-id <id>          Packet identifier (required)
  --horizon-ref <id>        Horizon identifier (required)
  --sender <id>             Sender identifier (required)
  --recipient-type <type>   Recipient type (required)
  --recipient-id <id>       Recipient identifier (required)
  --intent <text>           Packet intent (required)
  --loop-id <id>            Optional loop identifier linked to this packet
  --authority <text>        Optional authority descriptor
  --trace-id <id>           Optional trace identifier
  --ttl-seconds <n>         Optional packet freshness TTL in seconds
  --evidence-ref <ref>      Optional evidence ref, can be repeated

Transition options:
  --packet-id <id>          Packet identifier (required)
  --to-status <status>      Target status (required)
  --by <id>                 Actor applying transition (required)
  --reason <text>           Transition reason (required)
  --note <text>             Optional transition note
  --evidence-ref <ref>      Optional evidence ref, can be repeated

Show options:
  --packet-id <id>          Packet identifier (required)

List options:
  --horizon-ref <id>        Filter by horizon identifier
  --status <status>         Filter by packet status

Statuses:
  queued, dispatched, acknowledged, in_progress, completed, failed, escalated, cancelled
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
  printf 'hpk-%s-%s-%04d\n' "$(date -u +%Y%m%d%H%M%S)" "$$" "$RANDOM"
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

is_valid_status() {
  local status="$1"
  case "$status" in
    queued|dispatched|acknowledged|in_progress|completed|failed|escalated|cancelled)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_transition_allowed() {
  local from_status="$1"
  local to_status="$2"
  case "$from_status" in
    queued)
      [[ "$to_status" == "dispatched" || "$to_status" == "cancelled" || "$to_status" == "escalated" ]]
      ;;
    dispatched)
      [[ "$to_status" == "acknowledged" || "$to_status" == "failed" || "$to_status" == "escalated" || "$to_status" == "cancelled" ]]
      ;;
    acknowledged)
      [[ "$to_status" == "in_progress" || "$to_status" == "failed" || "$to_status" == "escalated" || "$to_status" == "cancelled" ]]
      ;;
    in_progress)
      [[ "$to_status" == "completed" || "$to_status" == "failed" || "$to_status" == "escalated" || "$to_status" == "cancelled" ]]
      ;;
    failed)
      [[ "$to_status" == "escalated" || "$to_status" == "cancelled" ]]
      ;;
    escalated)
      [[ "$to_status" == "in_progress" || "$to_status" == "completed" || "$to_status" == "cancelled" ]]
      ;;
    completed|cancelled)
      false
      ;;
    *)
      false
      ;;
  esac
}

build_custom_evidence_refs_json() {
  if [[ ${#EVIDENCE_REFS[@]} -eq 0 ]]; then
    echo '[]'
    return 0
  fi
  printf '%s\n' "${EVIDENCE_REFS[@]}" | jq -Rsc 'split("\n")[:-1] | map(select(length > 0))'
}

append_telemetry() {
  local telemetry_file="$1"
  local packet_file="$2"
  local packet_json="$3"
  local action="$4"
  local from_status="$5"
  local to_status="$6"
  local actor="$7"
  local reason="$8"
  local note="$9"
  local evidence_refs_json="${10}"

  mkdir -p "$(dirname "$telemetry_file")"

  jq -cn \
    --arg schema_version "v1" \
    --arg timestamp "$(timestamp)" \
    --arg category "horizon_packet" \
    --arg action "$action" \
    --arg packet_file "$packet_file" \
    --arg from_status "$from_status" \
    --arg to_status "$to_status" \
    --arg actor "$actor" \
    --arg reason "$reason" \
    --arg note "$note" \
    --argjson packet "$packet_json" \
    --argjson evidence_refs "$evidence_refs_json" \
    '{
      schemaVersion: $schema_version,
      timestamp: $timestamp,
      category: $category,
      action: $action,
      packetId: ($packet.packetId // null),
      horizonRef: ($packet.horizonRef // null),
      status: ($packet.status // null),
      fromStatus: (if ($from_status | length) > 0 then $from_status else null end),
      toStatus: (if ($to_status | length) > 0 then $to_status else null end),
      by: (if ($actor | length) > 0 then $actor else null end),
      reason: (if ($reason | length) > 0 then $reason else null end),
      note: (if ($note | length) > 0 then $note else null end),
      traceId: ($packet.traceId // null),
      evidenceRefs: $evidence_refs,
      packetFile: $packet_file
    }' >> "$telemetry_file"
}

packet_file_for_id() {
  local packets_dir="$1"
  local packet_id="$2"
  echo "$packets_dir/$packet_id.json"
}

require_non_empty() {
  local value="$1"
  local name="$2"
  [[ -n "$value" ]] || die "$name is required"
}

CMD="${1:-}"
if [[ -z "$CMD" || "$CMD" == "--help" || "$CMD" == "-h" ]]; then
  usage
  [[ -n "$CMD" ]] && exit 0 || exit 1
fi
shift

REPO="."
STATE_DIR=""
TELEMETRY_FILE=""
PACKET_ID=""
HORIZON_REF=""
SENDER=""
RECIPIENT_TYPE=""
RECIPIENT_ID=""
INTENT=""
LOOP_ID=""
AUTHORITY=""
TRACE_ID=""
TTL_SECONDS=""
TO_STATUS=""
ACTOR=""
REASON=""
NOTE=""
STATUS_FILTER=""
PRETTY="0"
EVIDENCE_REFS=()

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
    --telemetry-file)
      TELEMETRY_FILE="${2:-}"
      shift 2
      ;;
    --packet-id)
      PACKET_ID="${2:-}"
      shift 2
      ;;
    --horizon-ref)
      HORIZON_REF="${2:-}"
      shift 2
      ;;
    --sender)
      SENDER="${2:-}"
      shift 2
      ;;
    --recipient-type)
      RECIPIENT_TYPE="${2:-}"
      shift 2
      ;;
    --recipient-id)
      RECIPIENT_ID="${2:-}"
      shift 2
      ;;
    --intent)
      INTENT="${2:-}"
      shift 2
      ;;
    --loop-id)
      LOOP_ID="${2:-}"
      shift 2
      ;;
    --authority)
      AUTHORITY="${2:-}"
      shift 2
      ;;
    --trace-id)
      TRACE_ID="${2:-}"
      shift 2
      ;;
    --ttl-seconds)
      TTL_SECONDS="${2:-}"
      shift 2
      ;;
    --to-status)
      TO_STATUS="${2:-}"
      shift 2
      ;;
    --by)
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
    --status)
      STATUS_FILTER="${2:-}"
      shift 2
      ;;
    --evidence-ref)
      EVIDENCE_REFS+=("${2:-}")
      shift 2
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

REPO="$(cd "$REPO" && pwd)"
if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$REPO/.superloop/horizons"
fi
if [[ "$STATE_DIR" != /* ]]; then
  STATE_DIR="$REPO/$STATE_DIR"
fi
PACKETS_DIR="$STATE_DIR/packets"
if [[ -z "$TELEMETRY_FILE" ]]; then
  TELEMETRY_FILE="$STATE_DIR/telemetry/packets.jsonl"
fi
if [[ "$TELEMETRY_FILE" != /* ]]; then
  TELEMETRY_FILE="$REPO/$TELEMETRY_FILE"
fi

CUSTOM_EVIDENCE_REFS_JSON="$(build_custom_evidence_refs_json)"

case "$CMD" in
  create)
    require_non_empty "$PACKET_ID" "--packet-id"
    require_non_empty "$HORIZON_REF" "--horizon-ref"
    require_non_empty "$SENDER" "--sender"
    require_non_empty "$RECIPIENT_TYPE" "--recipient-type"
    require_non_empty "$RECIPIENT_ID" "--recipient-id"
    require_non_empty "$INTENT" "--intent"

    if [[ -n "$TTL_SECONDS" ]]; then
      [[ "$TTL_SECONDS" =~ ^[0-9]+$ ]] || die "--ttl-seconds must be an integer >= 0"
    fi

    mkdir -p "$PACKETS_DIR"
    packet_file="$(packet_file_for_id "$PACKETS_DIR" "$PACKET_ID")"
    [[ ! -f "$packet_file" ]] || die "packet already exists: $PACKET_ID"

    if [[ -z "$TRACE_ID" ]]; then
      TRACE_ID="${HORIZON_TRACE_ID:-}"
    fi
    if [[ -z "$TRACE_ID" ]]; then
      TRACE_ID="$(generate_trace_id)"
    fi

    created_at="$(timestamp)"
    packet_json="$(jq -cn \
      --arg schema_version "v1" \
      --arg packet_id "$PACKET_ID" \
      --arg horizon_ref "$HORIZON_REF" \
      --arg sender "$SENDER" \
      --arg recipient_type "$RECIPIENT_TYPE" \
      --arg recipient_id "$RECIPIENT_ID" \
      --arg intent "$INTENT" \
      --arg loop_id "$LOOP_ID" \
      --arg authority "$AUTHORITY" \
      --arg trace_id "$TRACE_ID" \
      --arg created_at "$created_at" \
      --arg ttl_seconds "$TTL_SECONDS" \
      --argjson evidence_refs "$CUSTOM_EVIDENCE_REFS_JSON" \
      '{
        schemaVersion: $schema_version,
        packetId: $packet_id,
        horizonRef: $horizon_ref,
        sender: $sender,
        recipient: {
          type: $recipient_type,
          id: $recipient_id
        },
        intent: $intent,
        loopId: (if ($loop_id | length) > 0 then $loop_id else null end),
        authority: (if ($authority | length) > 0 then $authority else null end),
        traceId: $trace_id,
        ttlSeconds: (if ($ttl_seconds | length) > 0 then ($ttl_seconds | tonumber) else null end),
        status: "queued",
        createdAt: $created_at,
        updatedAt: $created_at,
        completedAt: null,
        evidenceRefs: $evidence_refs,
        transitions: [
          {
            at: $created_at,
            fromStatus: null,
            toStatus: "queued",
            by: $sender,
            reason: "packet_created",
            note: null,
            evidenceRefs: $evidence_refs
          }
        ]
      }')"

    jq -c '.' <<<"$packet_json" > "$packet_file"
    append_telemetry "$TELEMETRY_FILE" "$packet_file" "$packet_json" "create" "" "queued" "$SENDER" "packet_created" "" "$CUSTOM_EVIDENCE_REFS_JSON"
    emit_json "$packet_json" "$PRETTY"
    ;;

  transition)
    require_non_empty "$PACKET_ID" "--packet-id"
    require_non_empty "$TO_STATUS" "--to-status"
    require_non_empty "$ACTOR" "--by"
    require_non_empty "$REASON" "--reason"

    is_valid_status "$TO_STATUS" || die "invalid --to-status: $TO_STATUS"

    packet_file="$(packet_file_for_id "$PACKETS_DIR" "$PACKET_ID")"
    [[ -f "$packet_file" ]] || die "packet not found: $PACKET_ID"

    packet_json="$(jq -c '.' "$packet_file" 2>/dev/null)" || die "invalid packet JSON: $packet_file"
    from_status="$(jq -r '.status // empty' <<<"$packet_json")"
    is_valid_status "$from_status" || die "packet has invalid current status: $from_status"
    is_transition_allowed "$from_status" "$TO_STATUS" || die "transition from $from_status to $TO_STATUS is not allowed"

    existing_evidence_refs_json="$(jq -c '.evidenceRefs // []' <<<"$packet_json")"
    merged_evidence_refs_json="$(jq -cn \
      --argjson existing "$existing_evidence_refs_json" \
      --argjson incoming "$CUSTOM_EVIDENCE_REFS_JSON" \
      '($existing + $incoming) | map(select(type == "string" and length > 0)) | unique')"

    updated_at="$(timestamp)"
    updated_packet_json="$(jq -cn \
      --argjson packet "$packet_json" \
      --arg from_status "$from_status" \
      --arg to_status "$TO_STATUS" \
      --arg actor "$ACTOR" \
      --arg reason "$REASON" \
      --arg note "$NOTE" \
      --arg updated_at "$updated_at" \
      --argjson merged_refs "$merged_evidence_refs_json" \
      --argjson new_refs "$CUSTOM_EVIDENCE_REFS_JSON" \
      '($packet
        | .status = $to_status
        | .updatedAt = $updated_at
        | .completedAt = (
            if $to_status == "completed"
            then (.completedAt // $updated_at)
            else .completedAt
            end
          )
        | .evidenceRefs = $merged_refs
        | .transitions += [
            {
              at: $updated_at,
              fromStatus: $from_status,
              toStatus: $to_status,
              by: $actor,
              reason: $reason,
              note: (if ($note | length) > 0 then $note else null end),
              evidenceRefs: $new_refs
            }
          ]
      )')"

    jq -c '.' <<<"$updated_packet_json" > "$packet_file"
    append_telemetry "$TELEMETRY_FILE" "$packet_file" "$updated_packet_json" "transition" "$from_status" "$TO_STATUS" "$ACTOR" "$REASON" "$NOTE" "$CUSTOM_EVIDENCE_REFS_JSON"
    emit_json "$updated_packet_json" "$PRETTY"
    ;;

  show)
    require_non_empty "$PACKET_ID" "--packet-id"
    packet_file="$(packet_file_for_id "$PACKETS_DIR" "$PACKET_ID")"
    [[ -f "$packet_file" ]] || die "packet not found: $PACKET_ID"
    packet_json="$(jq -c '.' "$packet_file" 2>/dev/null)" || die "invalid packet JSON: $packet_file"
    emit_json "$packet_json" "$PRETTY"
    ;;

  list)
    if [[ -n "$STATUS_FILTER" ]]; then
      is_valid_status "$STATUS_FILTER" || die "invalid --status: $STATUS_FILTER"
    fi

    if [[ ! -d "$PACKETS_DIR" ]]; then
      emit_json "[]" "$PRETTY"
      exit 0
    fi

    mapfile -t packet_files < <(find "$PACKETS_DIR" -maxdepth 1 -type f -name '*.json' | sort)
    if [[ ${#packet_files[@]} -eq 0 ]]; then
      emit_json "[]" "$PRETTY"
      exit 0
    fi

    list_json="$(jq -s \
      --arg horizon_ref "$HORIZON_REF" \
      --arg status_filter "$STATUS_FILTER" \
      '[ .[]
        | select(
            if ($horizon_ref | length) > 0
            then (.horizonRef // "") == $horizon_ref
            else true
            end
          )
        | select(
            if ($status_filter | length) > 0
            then (.status // "") == $status_filter
            else true
            end
          )
      ]' "${packet_files[@]}")"
    emit_json "$list_json" "$PRETTY"
    ;;

  *)
    usage
    die "unknown command: $CMD"
    ;;
esac
