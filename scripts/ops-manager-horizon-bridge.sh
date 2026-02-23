#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-horizon-bridge.sh --repo <path> [options]

Options:
  --repo <path>                  Repository path.
  --outbox-dir <path>            Horizon outbox directory (default: <repo>/.superloop/horizons/outbox).
  --claims-dir <path>            Bridge claims directory (default: <repo>/.superloop/ops-manager/fleet/horizon-bridge-claims).
  --queue-file <path>            Bridge queue artifact path (default: <repo>/.superloop/ops-manager/fleet/horizon-bridge-queue.json).
  --state-file <path>            Bridge state artifact path (default: <repo>/.superloop/ops-manager/fleet/horizon-bridge-state.json).
  --telemetry-file <path>        Bridge telemetry JSONL path (default: <repo>/.superloop/ops-manager/fleet/telemetry/horizon-bridge.jsonl).
  --max-files <n>                Max outbox files to claim per run (default: 0, unlimited).
  --trace-id <id>                Optional run trace id.
  --pretty                       Pretty-print output JSON.
  --help                         Show this help message.
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
  printf 'trace-%s-%s-%04d\n' "$(date -u +%Y%m%d%H%M%S)" "$$" "$RANDOM"
}

is_int_ge() {
  local value="$1"
  local min="$2"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min ))
}

repo=""
outbox_dir=""
claims_dir=""
queue_file=""
state_file=""
telemetry_file=""
max_files="0"
trace_id=""
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --outbox-dir)
      outbox_dir="${2:-}"
      shift 2
      ;;
    --claims-dir)
      claims_dir="${2:-}"
      shift 2
      ;;
    --queue-file)
      queue_file="${2:-}"
      shift 2
      ;;
    --state-file)
      state_file="${2:-}"
      shift 2
      ;;
    --telemetry-file)
      telemetry_file="${2:-}"
      shift 2
      ;;
    --max-files)
      max_files="${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="${2:-}"
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
need_cmd find

[[ -n "$repo" ]] || die "--repo is required"
if ! is_int_ge "$max_files" 0; then
  die "--max-files must be an integer >= 0"
fi

repo="$(cd "$repo" && pwd)"

if [[ -z "$outbox_dir" ]]; then
  outbox_dir="$repo/.superloop/horizons/outbox"
fi
if [[ "$outbox_dir" != /* ]]; then
  outbox_dir="$repo/$outbox_dir"
fi

if [[ -z "$claims_dir" ]]; then
  claims_dir="$repo/.superloop/ops-manager/fleet/horizon-bridge-claims"
fi
if [[ "$claims_dir" != /* ]]; then
  claims_dir="$repo/$claims_dir"
fi

if [[ -z "$queue_file" ]]; then
  queue_file="$repo/.superloop/ops-manager/fleet/horizon-bridge-queue.json"
fi
if [[ "$queue_file" != /* ]]; then
  queue_file="$repo/$queue_file"
fi

if [[ -z "$state_file" ]]; then
  state_file="$repo/.superloop/ops-manager/fleet/horizon-bridge-state.json"
fi
if [[ "$state_file" != /* ]]; then
  state_file="$repo/$state_file"
fi

if [[ -z "$telemetry_file" ]]; then
  telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/horizon-bridge.jsonl"
fi
if [[ "$telemetry_file" != /* ]]; then
  telemetry_file="$repo/$telemetry_file"
fi

if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

claims_inflight_dir="$claims_dir/inflight"
claims_processed_dir="$claims_dir/processed"
claims_rejected_dir="$claims_dir/rejected"

mkdir -p "$claims_inflight_dir"
mkdir -p "$claims_processed_dir"
mkdir -p "$claims_rejected_dir"
mkdir -p "$(dirname "$queue_file")"
mkdir -p "$(dirname "$state_file")"
mkdir -p "$(dirname "$telemetry_file")"

run_started_at="$(timestamp)"
run_epoch_ns="$(date -u +%s%N)"

prior_queue_json='{"schemaVersion":"v1","generatedAt":null,"updatedAt":null,"traceId":null,"intents":[],"summary":{"intentCount":0,"pendingConfirmationCount":0},"reasonCodes":[]}'
if [[ -f "$queue_file" ]]; then
  prior_queue_json="$(jq -c '.' "$queue_file" 2>/dev/null)" || die "invalid bridge queue JSON: $queue_file"
fi
queue_intents_json="$(jq -c '(.intents // [])' <<<"$prior_queue_json")"

prior_state_json='null'
if [[ -f "$state_file" ]]; then
  prior_state_json="$(jq -c '.' "$state_file" 2>/dev/null)" || die "invalid bridge state JSON: $state_file"
fi

declare -A dedupe_seen=()
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  dedupe_seen["$key"]=1
done < <(jq -r '.dedupe.keys[]? // empty' <<<"$prior_state_json")
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  dedupe_seen["$key"]=1
done < <(jq -r '.[]? | (.packetId // empty) + "::" + (.traceId // empty)' <<<"$queue_intents_json")

declare -a candidate_files=()
if [[ -d "$outbox_dir" ]]; then
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    candidate_files+=("$path")
  done < <(find "$outbox_dir" -type f -name '*.jsonl' | LC_ALL=C sort)
fi

declare -a claimed_files=()
claimed_count=0
for src_file in "${candidate_files[@]}"; do
  if (( max_files > 0 && claimed_count >= max_files )); then
    break
  fi

  rel_path="${src_file#"$outbox_dir"/}"
  if [[ "$rel_path" == "$src_file" ]]; then
    rel_path="$(basename "$src_file")"
  fi
  claim_file="$claims_inflight_dir/$rel_path.claim.$run_epoch_ns.$$"
  mkdir -p "$(dirname "$claim_file")"
  if mv "$src_file" "$claim_file" 2>/dev/null; then
    claimed_files+=("$claim_file")
    claimed_count=$(( claimed_count + 1 ))
  fi
done

declare -a newly_queued_intents=()
queued_envelopes=0
duplicate_envelopes=0
invalid_envelopes=0
rejected_files=0
processed_files=0

declare -a claimed_rel_paths=()
declare -a processed_rel_paths=()
declare -a rejected_rel_paths=()
file_records_tmp="$(mktemp)"
trap 'rm -f "$file_records_tmp"' EXIT

for claim_file in "${claimed_files[@]}"; do
  rel_claim="${claim_file#"$claims_inflight_dir"/}"
  claimed_rel_paths+=("$rel_claim")

  total_lines=0
  file_invalid_count=0
  file_duplicate_count=0
  file_queued_count=0
  file_contract_reason="none"
  declare -a file_intents=()
  declare -A file_dedupe=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    total_lines=$(( total_lines + 1 ))
    [[ -z "$line" ]] && continue

    envelope_json="$(jq -c '.' <<<"$line" 2>/dev/null || true)"
    if [[ -z "$envelope_json" ]]; then
      file_invalid_count=$(( file_invalid_count + 1 ))
      file_contract_reason="contract_invalid_json"
      continue
    fi

    eval_json="$(jq -cn --argjson env "$envelope_json" '
      {
        missing: [
          (if (($env.schemaVersion // null) == null or (($env.schemaVersion // "") | tostring | length) == 0) then "schemaVersion" else empty end),
          (if (($env.traceId // null) == null or (($env.traceId // "") | tostring | length) == 0) then "traceId" else empty end),
          (if (($env.packet.packetId // null) == null or (($env.packet.packetId // "") | tostring | length) == 0) then "packet.packetId" else empty end),
          (if (($env.packet.recipient.type // null) == null or (($env.packet.recipient.type // "") | tostring | length) == 0) then "packet.recipient.type" else empty end),
          (if (($env.packet.recipient.id // null) == null or (($env.packet.recipient.id // "") | tostring | length) == 0) then "packet.recipient.id" else empty end),
          (if (($env.packet.intent // null) == null or (($env.packet.intent // "") | tostring | length) == 0) then "packet.intent" else empty end),
          (if (($env.evidenceRefs // null) == null) then "evidenceRefs" else empty end)
        ],
        schemaSupported: (($env.schemaVersion // "") == "v1"),
        evidenceRefsIsArray: ((($env.evidenceRefs // null) != null) and (($env.evidenceRefs | type) == "array")),
        normalized: {
          schemaVersion: ($env.schemaVersion // null),
          traceId: ($env.traceId // null),
          packetId: ($env.packet.packetId // null),
          recipientType: ($env.packet.recipient.type // null),
          recipientId: ($env.packet.recipient.id // null),
          intent: ($env.packet.intent // null),
          evidenceRefs: (if (($env.evidenceRefs | type) == "array") then $env.evidenceRefs else [] end)
        }
      }')"

    missing_count="$(jq -r '.missing | length' <<<"$eval_json")"
    schema_supported="$(jq -r '.schemaSupported' <<<"$eval_json")"
    evidence_is_array="$(jq -r '.evidenceRefsIsArray' <<<"$eval_json")"

    if (( missing_count > 0 )); then
      file_invalid_count=$(( file_invalid_count + 1 ))
      file_contract_reason="contract_required_field_missing"
      continue
    fi
    if [[ "$schema_supported" != "true" ]]; then
      file_invalid_count=$(( file_invalid_count + 1 ))
      file_contract_reason="contract_schema_version_unsupported"
      continue
    fi
    if [[ "$evidence_is_array" != "true" ]]; then
      file_invalid_count=$(( file_invalid_count + 1 ))
      file_contract_reason="contract_evidence_refs_not_array"
      continue
    fi

    packet_id="$(jq -r '.normalized.packetId' <<<"$eval_json")"
    envelope_trace_id="$(jq -r '.normalized.traceId' <<<"$eval_json")"
    recipient_type="$(jq -r '.normalized.recipientType' <<<"$eval_json")"
    recipient_id="$(jq -r '.normalized.recipientId' <<<"$eval_json")"
    intent_value="$(jq -r '.normalized.intent' <<<"$eval_json")"
    evidence_refs_json="$(jq -c '.normalized.evidenceRefs' <<<"$eval_json")"

    dedupe_key="$packet_id::$envelope_trace_id"
    if [[ -n "${dedupe_seen["$dedupe_key"]+x}" || -n "${file_dedupe["$dedupe_key"]+x}" ]]; then
      file_duplicate_count=$(( file_duplicate_count + 1 ))
      continue
    fi

    file_dedupe["$dedupe_key"]=1
    file_queued_count=$(( file_queued_count + 1 ))
    intent_slug="$(jq -rn --arg v "$intent_value" '$v | ascii_downcase | gsub("[^a-z0-9._-]"; "-") | gsub("-+"; "-") | gsub("(^-)|(-$)"; "")')"
    if [[ -z "$intent_slug" ]]; then
      intent_slug="intent"
    fi
    intent_id="horizon-bridge:${packet_id}:${intent_slug}"

    file_intents+=("$(jq -cn \
      --arg intent_id "$intent_id" \
      --arg packet_id "$packet_id" \
      --arg trace_id "$envelope_trace_id" \
      --arg recipient_type "$recipient_type" \
      --arg recipient_id "$recipient_id" \
      --arg intent "$intent_value" \
      --arg ingested_at "$run_started_at" \
      --arg source_file "$rel_claim" \
      --arg source "horizon_outbox_contract_v1" \
      --argjson evidence_refs "$evidence_refs_json" \
      '{
        intentId: $intent_id,
        packetId: $packet_id,
        traceId: $trace_id,
        recipient: {type: $recipient_type, id: $recipient_id},
        intent: $intent,
        status: "pending_operator_confirmation",
        requiresOperatorConfirmation: true,
        autonomous: {
          eligible: false,
          manualOnly: true,
          reasons: ["horizon_bridge_manual_confirmation_required"]
        },
        source: $source,
        sourceFile: $source_file,
        evidenceRefs: $evidence_refs,
        createdAt: $ingested_at,
        updatedAt: $ingested_at
      }')")
  done < "$claim_file"

  target_root="$claims_processed_dir"
  file_status="processed"
  file_reason_codes_json='[]'
  if (( file_invalid_count > 0 )); then
    target_root="$claims_rejected_dir"
    file_status="rejected_contract"
    file_reason_codes_json="$(jq -cn --arg reason "$file_contract_reason" '[$reason]')"
    rejected_files=$(( rejected_files + 1 ))
    invalid_envelopes=$(( invalid_envelopes + file_invalid_count ))
  else
    processed_files=$(( processed_files + 1 ))
  fi

  target_file="$target_root/$rel_claim"
  mkdir -p "$(dirname "$target_file")"
  mv "$claim_file" "$target_file"

  if [[ "$file_status" == "rejected_contract" ]]; then
    rejected_rel_paths+=("${target_file#"$claims_rejected_dir"/}")
  else
    for file_key in "${!file_dedupe[@]}"; do
      dedupe_seen["$file_key"]=1
    done
    processed_rel_paths+=("${target_file#"$claims_processed_dir"/}")
    duplicate_envelopes=$(( duplicate_envelopes + file_duplicate_count ))
    queued_envelopes=$(( queued_envelopes + file_queued_count ))
    if (( ${#file_intents[@]} > 0 )); then
      newly_queued_intents+=("${file_intents[@]}")
    fi
  fi

  jq -cn \
    --arg timestamp "$run_started_at" \
    --arg trace_id "$trace_id" \
    --arg status "$file_status" \
    --arg source_file "$rel_claim" \
    --arg target_file "${target_file#"$claims_dir"/}" \
    --argjson line_count "$total_lines" \
    --argjson queued_count "$file_queued_count" \
    --argjson duplicate_count "$file_duplicate_count" \
    --argjson invalid_count "$file_invalid_count" \
    --argjson reason_codes "$file_reason_codes_json" \
    '{
      timestamp: $timestamp,
      category: "horizon_bridge_file",
      traceId: $trace_id,
      status: $status,
      sourceFile: $source_file,
      claimTarget: $target_file,
      summary: {
        lineCount: $line_count,
        queuedCount: $queued_count,
        duplicateCount: $duplicate_count,
        invalidCount: $invalid_count
      },
      reasonCodes: $reason_codes
    }' >> "$file_records_tmp"
done

new_intents_json='[]'
if (( ${#newly_queued_intents[@]} > 0 )); then
  new_intents_json="$(printf '%s\n' "${newly_queued_intents[@]}" | jq -Rsc 'split("\n") | map(select(length > 0) | fromjson)')"
fi

queue_intents_updated_json="$(jq -cn \
  --argjson prior "$queue_intents_json" \
  --argjson adds "$new_intents_json" '
  ($prior + $adds)
  | map(select((((.packetId // "") | length) > 0) and (((.traceId // "") | length) > 0)))
  | unique_by((.packetId + "::" + .traceId))
  | sort_by((.createdAt // ""), (.packetId // ""), (.traceId // ""))
  ')"

pending_count="$(jq -r '[ .[] | select((.status // "") == "pending_operator_confirmation") ] | length' <<<"$queue_intents_updated_json")"
intent_count="$(jq -r 'length' <<<"$queue_intents_updated_json")"

queue_json="$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$run_started_at" \
  --arg updated_at "$run_started_at" \
  --arg trace_id "$trace_id" \
  --arg outbox_dir "$outbox_dir" \
  --arg claims_dir "$claims_dir" \
  --arg contract "horizon-envelope-contract-v1" \
  --argjson intents "$queue_intents_updated_json" \
  --argjson intent_count "$intent_count" \
  --argjson pending_count "$pending_count" \
  '{
    schemaVersion: $schema_version,
    generatedAt: $generated_at,
    updatedAt: $updated_at,
    traceId: $trace_id,
    source: {
      outboxDir: $outbox_dir,
      claimsDir: $claims_dir,
      contract: $contract
    },
    intents: $intents,
    summary: {
      intentCount: $intent_count,
      pendingConfirmationCount: $pending_count
    },
    reasonCodes: (
      [
        (if $pending_count > 0 then "horizon_bridge_confirmation_pending" else "horizon_bridge_queue_empty" end)
      ] | unique
    )
  }')"

printf '%s\n' "$queue_json" > "$queue_file"

dedupe_keys_json="$(printf '%s\n' "${!dedupe_seen[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique | sort')"
dedupe_count="$(jq -r 'length' <<<"$dedupe_keys_json")"
claimed_count_total="${#claimed_files[@]}"
reason_codes_json="$(jq -cn \
  --argjson claimed "$claimed_count_total" \
  --argjson queued "$queued_envelopes" \
  --argjson dup "$duplicate_envelopes" \
  --argjson rejected "$rejected_files" \
  '
  [
    (if $claimed == 0 then "horizon_bridge_no_outbox_files" else "horizon_bridge_claimed_files" end),
    (if $queued > 0 then "horizon_bridge_queue_updated" else empty end),
    (if $dup > 0 then "horizon_bridge_duplicates_skipped" else empty end),
    (if $rejected > 0 then "horizon_bridge_contract_validation_failed" else empty end)
  ] | unique
  ')"

run_status="ok"
exit_code=0
if (( rejected_files > 0 )); then
  run_status="failed_contract_validation"
  exit_code=2
fi

state_json="$(jq -cn \
  --arg schema_version "v1" \
  --arg generated_at "$run_started_at" \
  --arg updated_at "$run_started_at" \
  --arg trace_id "$trace_id" \
  --arg status "$run_status" \
  --arg outbox_dir "$outbox_dir" \
  --arg claims_dir "$claims_dir" \
  --arg queue_file "$queue_file" \
  --arg state_file "$state_file" \
  --arg telemetry_file "$telemetry_file" \
  --arg contract "horizon-envelope-contract-v1" \
  --argjson claimed_count "$claimed_count_total" \
  --argjson processed_count "$processed_files" \
  --argjson rejected_count "$rejected_files" \
  --argjson queued_count "$queued_envelopes" \
  --argjson duplicate_count "$duplicate_envelopes" \
  --argjson invalid_count "$invalid_envelopes" \
  --argjson pending_count "$pending_count" \
  --argjson dedupe_count "$dedupe_count" \
  --argjson dedupe_keys "$dedupe_keys_json" \
  --argjson reason_codes "$reason_codes_json" \
  --argjson previous_state "$prior_state_json" \
  --argjson claimed_files "$(printf '%s\n' "${claimed_rel_paths[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  --argjson processed_files "$(printf '%s\n' "${processed_rel_paths[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  --argjson rejected_files "$(printf '%s\n' "${rejected_rel_paths[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  '{
    schemaVersion: $schema_version,
    generatedAt: $generated_at,
    updatedAt: $updated_at,
    traceId: $trace_id,
    status: $status,
    contract: $contract,
    source: {
      outboxDir: $outbox_dir,
      claimsDir: $claims_dir
    },
    files: {
      queueFile: $queue_file,
      stateFile: $state_file,
      telemetryFile: $telemetry_file,
      claimed: $claimed_files,
      processed: $processed_files,
      rejected: $rejected_files
    },
    summary: {
      claimedFileCount: $claimed_count,
      processedFileCount: $processed_count,
      rejectedFileCount: $rejected_count,
      queuedEnvelopeCount: $queued_count,
      duplicateEnvelopeCount: $duplicate_count,
      invalidEnvelopeCount: $invalid_count,
      pendingConfirmationCount: $pending_count
    },
    dedupe: {
      keyCount: $dedupe_count,
      keys: $dedupe_keys
    },
    reasonCodes: $reason_codes,
    observed: {
      hadPreviousState: ($previous_state != null),
      previousStatus: ($previous_state.status // null),
      previousUpdatedAt: ($previous_state.updatedAt // null)
    }
  }')"

printf '%s\n' "$state_json" > "$state_file"

cat "$file_records_tmp" >> "$telemetry_file"
jq -cn \
  --arg timestamp "$run_started_at" \
  --arg trace_id "$trace_id" \
  --arg status "$run_status" \
  --arg contract "horizon-envelope-contract-v1" \
  --arg state_file "$state_file" \
  --arg queue_file "$queue_file" \
  --arg telemetry_file "$telemetry_file" \
  --argjson summary "$(jq -c '.summary' <<<"$state_json")" \
  --argjson reason_codes "$reason_codes_json" \
  '{
    timestamp: $timestamp,
    category: "horizon_bridge_run",
    traceId: $trace_id,
    status: $status,
    contract: $contract,
    files: {
      stateFile: $state_file,
      queueFile: $queue_file,
      telemetryFile: $telemetry_file
    },
    summary: $summary,
    reasonCodes: $reason_codes
  }' >> "$telemetry_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$state_json"
else
  jq -c '.' <<<"$state_json"
fi

exit "$exit_code"
