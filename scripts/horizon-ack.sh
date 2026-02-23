#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/horizon-ack.sh ingest [options]

Common options:
  --repo <path>               Repository path (default: .)
  --state-dir <path>          Horizon state directory (default: <repo>/.superloop/horizons)
  --file <path>               Receipt JSONL file path (default: stdin)
  --ack-state-file <path>     Ack dedupe state file (default: <state-dir>/ack-state.json)
  --ack-telemetry-file <path> Ack telemetry JSONL file (default: <state-dir>/telemetry/ack.jsonl)
  --retry-state-file <path>   Retry state file (default: <state-dir>/retry-state.json)
  --actor <id>                Default actor for transitions (default: horizon-ack)
  --reason <text>             Default reason for acknowledged receipts (default: delivery_acknowledged)
  --dry-run                   Validate/process receipts without mutating packet/state artifacts
  --pretty                    Pretty-print JSON output

Receipt contract (JSONL, one object per line):
  required fields:
    - schemaVersion: "v1"
    - packetId: string
    - traceId: string
    - status: acknowledged|failed|escalated|cancelled
  optional fields:
    - receiptId: string (dedupe key; if absent, a hash key is derived)
    - by: string
    - reason: string
    - note: string
    - evidenceRefs: string[]
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

emit_json() {
  local json="$1"
  local pretty="${2:-0}"
  if [[ "$pretty" == "1" ]]; then
    jq '.' <<<"$json"
  else
    jq -c '.' <<<"$json"
  fi
}

hash_text() {
  local value="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$value" | openssl dgst -sha256 | awk '{print $2}'
    return 0
  fi
  printf 'fallback-%s-%s\n' "$$" "$RANDOM"
}

append_telemetry() {
  local telemetry_file="$1"
  local payload_json="$2"
  mkdir -p "$(dirname "$telemetry_file")"
  jq -c '.' <<<"$payload_json" >> "$telemetry_file"
}

CMD="${1:-}"
if [[ -z "$CMD" || "$CMD" == "--help" || "$CMD" == "-h" ]]; then
  usage
  [[ -n "$CMD" ]] && exit 0 || exit 1
fi
shift

case "$CMD" in
  ingest)
    ;;
  *)
    usage
    die "unknown command: $CMD"
    ;;
esac

REPO="."
STATE_DIR=""
INPUT_FILE="-"
ACK_STATE_FILE=""
ACK_TELEMETRY_FILE=""
RETRY_STATE_FILE=""
ACTOR="horizon-ack"
DEFAULT_REASON="delivery_acknowledged"
DRY_RUN="0"
PRETTY="0"

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
    --file)
      INPUT_FILE="${2:-}"
      shift 2
      ;;
    --ack-state-file)
      ACK_STATE_FILE="${2:-}"
      shift 2
      ;;
    --ack-telemetry-file)
      ACK_TELEMETRY_FILE="${2:-}"
      shift 2
      ;;
    --retry-state-file)
      RETRY_STATE_FILE="${2:-}"
      shift 2
      ;;
    --actor)
      ACTOR="${2:-}"
      shift 2
      ;;
    --reason)
      DEFAULT_REASON="${2:-}"
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

REPO="$(cd "$REPO" && pwd)"
if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR="$REPO/.superloop/horizons"
fi
if [[ "$STATE_DIR" != /* ]]; then
  STATE_DIR="$REPO/$STATE_DIR"
fi
if [[ -z "$ACK_STATE_FILE" ]]; then
  ACK_STATE_FILE="$STATE_DIR/ack-state.json"
fi
if [[ "$ACK_STATE_FILE" != /* ]]; then
  ACK_STATE_FILE="$REPO/$ACK_STATE_FILE"
fi
if [[ -z "$ACK_TELEMETRY_FILE" ]]; then
  ACK_TELEMETRY_FILE="$STATE_DIR/telemetry/ack.jsonl"
fi
if [[ "$ACK_TELEMETRY_FILE" != /* ]]; then
  ACK_TELEMETRY_FILE="$REPO/$ACK_TELEMETRY_FILE"
fi
if [[ -z "$RETRY_STATE_FILE" ]]; then
  RETRY_STATE_FILE="$STATE_DIR/retry-state.json"
fi
if [[ "$RETRY_STATE_FILE" != /* ]]; then
  RETRY_STATE_FILE="$REPO/$RETRY_STATE_FILE"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HORIZON_PACKET_SCRIPT="$SCRIPT_DIR/horizon-packet.sh"
[[ -x "$HORIZON_PACKET_SCRIPT" ]] || die "required script not executable: $HORIZON_PACKET_SCRIPT"

if [[ "$INPUT_FILE" != "-" && ! -f "$INPUT_FILE" ]]; then
  die "receipt file not found: $INPUT_FILE"
fi

if [[ -f "$ACK_STATE_FILE" ]]; then
  ACK_STATE_JSON="$(jq -c '.' "$ACK_STATE_FILE" 2>/dev/null)" || die "invalid ack state file: $ACK_STATE_FILE"
else
  ACK_STATE_JSON='{"schemaVersion":"v1","updatedAt":null,"processedKeys":{}}'
fi

ACK_STATE_JSON="$(jq -c '
  if (.processedKeys | type) != "object" then .processedKeys = {} else . end
  | if .schemaVersion == null then .schemaVersion = "v1" else . end
  | if (.updatedAt // null) == null then . else . end
' <<<"$ACK_STATE_JSON")"

if [[ -f "$RETRY_STATE_FILE" ]]; then
  RETRY_STATE_JSON="$(jq -c '.' "$RETRY_STATE_FILE" 2>/dev/null)" || die "invalid retry state file: $RETRY_STATE_FILE"
else
  RETRY_STATE_JSON='{"schemaVersion":"v1","updatedAt":null,"packets":{}}'
fi

RETRY_STATE_JSON="$(jq -c '
  if (.packets | type) != "object" then .packets = {} else . end
  | if .schemaVersion == null then .schemaVersion = "v1" else . end
' <<<"$RETRY_STATE_JSON")"

processed_count=0
mutated_count=0
duplicate_count=0
rejected_count=0
error_count=0
result_lines=()

input_stream="$INPUT_FILE"
if [[ "$INPUT_FILE" == "-" ]]; then
  input_stream="/dev/stdin"
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ -z "${line//[[:space:]]/}" ]]; then
    continue
  fi

  received_at="$(timestamp)"
  line_hash="$(hash_text "$line")"

  if ! receipt_json="$(jq -c '.' <<<"$line" 2>/dev/null)"; then
    rejected_count=$((rejected_count + 1))
    result_lines+=("$(jq -cn --arg status "rejected" --arg reason "invalid_json" --arg line_hash "$line_hash" --arg received_at "$received_at" '{status:$status,reason:$reason,lineHash:$line_hash,receivedAt:$received_at}')")
    continue
  fi

  schema_version="$(jq -r '.schemaVersion // empty' <<<"$receipt_json")"
  packet_id="$(jq -r '.packetId // empty' <<<"$receipt_json")"
  trace_id="$(jq -r '.traceId // empty' <<<"$receipt_json")"
  receipt_status="$(jq -r '.status // empty' <<<"$receipt_json")"
  receipt_id="$(jq -r '.receiptId // empty' <<<"$receipt_json")"
  receipt_actor="$(jq -r '.by // empty' <<<"$receipt_json")"
  receipt_reason="$(jq -r '.reason // empty' <<<"$receipt_json")"
  receipt_note="$(jq -r '.note // empty' <<<"$receipt_json")"

  if [[ -z "$receipt_id" ]]; then
    receipt_id="ack-${line_hash}"
  fi

  if [[ "$schema_version" != "v1" || -z "$packet_id" || -z "$trace_id" ]]; then
    rejected_count=$((rejected_count + 1))
    result_lines+=("$(jq -cn --arg packet_id "$packet_id" --arg trace_id "$trace_id" --arg receipt_id "$receipt_id" --arg status "rejected" --arg reason "missing_required_fields" --arg received_at "$received_at" '{packetId:(if ($packet_id|length)>0 then $packet_id else null end),traceId:(if ($trace_id|length)>0 then $trace_id else null end),receiptId:$receipt_id,status:$status,reason:$reason,receivedAt:$received_at}')")
    continue
  fi

  case "$receipt_status" in
    acknowledged|failed|escalated|cancelled)
      ;;
    *)
      rejected_count=$((rejected_count + 1))
      result_lines+=("$(jq -cn --arg packet_id "$packet_id" --arg trace_id "$trace_id" --arg receipt_id "$receipt_id" --arg status "rejected" --arg reason "invalid_status" --arg receipt_status "$receipt_status" --arg received_at "$received_at" '{packetId:$packet_id,traceId:$trace_id,receiptId:$receipt_id,status:$status,reason:$reason,receiptStatus:(if ($receipt_status|length)>0 then $receipt_status else null end),receivedAt:$received_at}')")
      continue
      ;;
  esac

  if jq -e --arg key "$receipt_id" '.processedKeys[$key] != null' <<<"$ACK_STATE_JSON" >/dev/null; then
    duplicate_count=$((duplicate_count + 1))
    result_lines+=("$(jq -cn --arg packet_id "$packet_id" --arg trace_id "$trace_id" --arg receipt_id "$receipt_id" --arg status "duplicate" --arg reason "already_processed" --arg received_at "$received_at" '{packetId:$packet_id,traceId:$trace_id,receiptId:$receipt_id,status:$status,reason:$reason,receivedAt:$received_at}')")
    continue
  fi

  packet_file="$STATE_DIR/packets/$packet_id.json"
  if [[ ! -f "$packet_file" ]]; then
    rejected_count=$((rejected_count + 1))
    result_lines+=("$(jq -cn --arg packet_id "$packet_id" --arg trace_id "$trace_id" --arg receipt_id "$receipt_id" --arg status "rejected" --arg reason "packet_not_found" --arg received_at "$received_at" '{packetId:$packet_id,traceId:$trace_id,receiptId:$receipt_id,status:$status,reason:$reason,receivedAt:$received_at}')")
    continue
  fi

  current_status="$(jq -r '.status // empty' "$packet_file")"
  if [[ -z "$current_status" ]]; then
    rejected_count=$((rejected_count + 1))
    result_lines+=("$(jq -cn --arg packet_id "$packet_id" --arg trace_id "$trace_id" --arg receipt_id "$receipt_id" --arg status "rejected" --arg reason "packet_status_missing" --arg received_at "$received_at" '{packetId:$packet_id,traceId:$trace_id,receiptId:$receipt_id,status:$status,reason:$reason,receivedAt:$received_at}')")
    continue
  fi

  transition_required="1"
  case "$receipt_status" in
    acknowledged)
      if [[ "$current_status" == "acknowledged" || "$current_status" == "in_progress" || "$current_status" == "completed" ]]; then
        transition_required="0"
      fi
      ;;
    failed)
      if [[ "$current_status" == "failed" || "$current_status" == "escalated" || "$current_status" == "cancelled" ]]; then
        transition_required="0"
      fi
      ;;
    escalated)
      if [[ "$current_status" == "escalated" || "$current_status" == "cancelled" ]]; then
        transition_required="0"
      fi
      ;;
    cancelled)
      if [[ "$current_status" == "cancelled" ]]; then
        transition_required="0"
      fi
      ;;
  esac

  if [[ -z "$receipt_actor" ]]; then
    receipt_actor="$ACTOR"
  fi
  if [[ -z "$receipt_reason" ]]; then
    case "$receipt_status" in
      acknowledged)
        receipt_reason="$DEFAULT_REASON"
        ;;
      failed)
        receipt_reason="delivery_failed"
        ;;
      escalated)
        receipt_reason="delivery_escalated"
        ;;
      cancelled)
        receipt_reason="delivery_cancelled"
        ;;
    esac
  fi

  transition_error=""
  if [[ "$transition_required" == "1" && "$DRY_RUN" != "1" ]]; then
    transition_cmd=("$HORIZON_PACKET_SCRIPT" transition
      --repo "$REPO"
      --state-dir "$STATE_DIR"
      --packet-id "$packet_id"
      --to-status "$receipt_status"
      --by "$receipt_actor"
      --reason "$receipt_reason")

    if [[ -n "$receipt_note" ]]; then
      transition_cmd+=(--note "$receipt_note")
    fi

    mapfile -t receipt_refs < <(jq -r '.evidenceRefs // [] | .[]' <<<"$receipt_json")
    if [[ ${#receipt_refs[@]} -gt 0 ]]; then
      for ref in "${receipt_refs[@]}"; do
        if [[ -n "$ref" ]]; then
          transition_cmd+=(--evidence-ref "$ref")
        fi
      done
    fi

    if ! transition_output="$("${transition_cmd[@]}" 2>&1)"; then
      transition_error="$transition_output"
      error_count=$((error_count + 1))
    fi
  fi

  if [[ -n "$transition_error" ]]; then
    result_lines+=("$(jq -cn --arg packet_id "$packet_id" --arg trace_id "$trace_id" --arg receipt_id "$receipt_id" --arg status "error" --arg reason "transition_failed" --arg error "$transition_error" --arg received_at "$received_at" '{packetId:$packet_id,traceId:$trace_id,receiptId:$receipt_id,status:$status,reason:$reason,error:$error,receivedAt:$received_at}')")
    continue
  fi

  processed_count=$((processed_count + 1))
  if [[ "$transition_required" == "1" ]]; then
    mutated_count=$((mutated_count + 1))
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    ACK_STATE_JSON="$(jq -c \
      --arg key "$receipt_id" \
      --arg at "$received_at" \
      --arg packet_id "$packet_id" \
      --arg trace_id "$trace_id" \
      --arg receipt_status "$receipt_status" '
      .processedKeys[$key] = {
        at: $at,
        packetId: $packet_id,
        traceId: $trace_id,
        status: $receipt_status
      }
      | .updatedAt = $at
    ' <<<"$ACK_STATE_JSON")"

    if [[ "$receipt_status" == "acknowledged" ]]; then
      RETRY_STATE_JSON="$(jq -c --arg packet_id "$packet_id" --arg at "$received_at" '
        .packets |= (if type == "object" then . else {} end)
        | del(.packets[$packet_id])
        | .updatedAt = $at
      ' <<<"$RETRY_STATE_JSON")"
    fi
  fi

  result_status="processed"
  if [[ "$transition_required" == "0" ]]; then
    result_status="noop"
  elif [[ "$DRY_RUN" == "1" ]]; then
    result_status="dry_run"
  fi

  result_lines+=("$(jq -cn \
    --arg packet_id "$packet_id" \
    --arg trace_id "$trace_id" \
    --arg receipt_id "$receipt_id" \
    --arg receipt_status "$receipt_status" \
    --arg result_status "$result_status" \
    --arg current_status "$current_status" \
    --arg actor "$receipt_actor" \
    --arg reason "$receipt_reason" \
    --arg received_at "$received_at" '
    {
      packetId: $packet_id,
      traceId: $trace_id,
      receiptId: $receipt_id,
      receiptStatus: $receipt_status,
      resultStatus: $result_status,
      fromStatus: $current_status,
      actor: $actor,
      reason: $reason,
      receivedAt: $received_at
    }
  ')")

done < "$input_stream"

if [[ ${#result_lines[@]} -eq 0 ]]; then
  results_json='[]'
else
  results_json="$(printf '%s\n' "${result_lines[@]}" | jq -s '.')"
fi

run_timestamp="$(timestamp)"
result_json="$(jq -cn \
  --arg schema_version "v1" \
  --arg timestamp "$run_timestamp" \
  --arg category "horizon_ack_ingest" \
  --arg actor "$ACTOR" \
  --arg default_reason "$DEFAULT_REASON" \
  --argjson dry_run "$( [[ "$DRY_RUN" == "1" ]] && echo true || echo false )" \
  --arg file "$INPUT_FILE" \
  --arg state_file "$ACK_STATE_FILE" \
  --arg telemetry_file "$ACK_TELEMETRY_FILE" \
  --arg retry_state_file "$RETRY_STATE_FILE" \
  --argjson processed "$processed_count" \
  --argjson mutated "$mutated_count" \
  --argjson duplicate "$duplicate_count" \
  --argjson rejected "$rejected_count" \
  --argjson errors "$error_count" \
  --argjson results "$results_json" '
  {
    schemaVersion: $schema_version,
    timestamp: $timestamp,
    category: $category,
    actor: $actor,
    defaultReason: $default_reason,
    dryRun: $dry_run,
    input: {
      file: (if $file == "-" then "stdin" else $file end)
    },
    artifacts: {
      ackStateFile: $state_file,
      ackTelemetryFile: $telemetry_file,
      retryStateFile: $retry_state_file
    },
    summary: {
      processedCount: $processed,
      mutatedCount: $mutated,
      duplicateCount: $duplicate,
      rejectedCount: $rejected,
      errorCount: $errors
    },
    results: $results
  }
')"

if [[ "$DRY_RUN" != "1" ]]; then
  mkdir -p "$(dirname "$ACK_STATE_FILE")"
  jq -c '.' <<<"$ACK_STATE_JSON" > "$ACK_STATE_FILE"

  mkdir -p "$(dirname "$RETRY_STATE_FILE")"
  jq -c '.' <<<"$RETRY_STATE_JSON" > "$RETRY_STATE_FILE"

  append_telemetry "$ACK_TELEMETRY_FILE" "$result_json"
fi

emit_json "$result_json" "$PRETTY"

if [[ "$error_count" -gt 0 ]]; then
  exit 1
fi
