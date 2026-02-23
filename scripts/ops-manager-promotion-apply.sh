#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-promotion-apply.sh --repo <path> --intent <expand|resume|rollback> --by <actor> --approval-ref <id> --rationale <text> --review-by <iso8601> [options]

Options:
  --registry-file <path>          Fleet registry JSON path. Default: <repo>/.superloop/ops-manager/fleet/registry.v1.json
  --promotion-state-file <path>   Promotion decision JSON path. Default: <repo>/.superloop/ops-manager/fleet/promotion-state.json
  --apply-state-file <path>       Apply state JSON output path. Default: <repo>/.superloop/ops-manager/fleet/promotion-apply-state.json
  --apply-telemetry-file <path>   Apply telemetry JSONL path. Default: <repo>/.superloop/ops-manager/fleet/telemetry/promotion-apply.jsonl
  --intent <expand|resume|rollback> Mutation intent.
  --expand-step <n>               Expand step percentage for intent=expand (default: 25)
  --idempotency-key <key>         Optional idempotency key. Replay returns prior result without mutation.
  --trace-id <id>                 Apply trace id override.
  --by <actor>                    Governance actor identity for mutation.
  --approval-ref <id>             Governance approval/change reference.
  --rationale <text>              Governance rationale.
  --review-by <iso8601>           Governance review deadline (must be in future).
  --pretty                        Pretty-print output JSON.
  --help                          Show this help message.
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

is_non_empty() {
  local value="$1"
  [[ -n "$value" ]]
}

repo=""
registry_file=""
promotion_state_file=""
apply_state_file=""
apply_telemetry_file=""
intent=""
expand_step="25"
idempotency_key=""
trace_id=""
actor=""
approval_ref=""
rationale=""
review_by=""
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --registry-file)
      registry_file="${2:-}"
      shift 2
      ;;
    --promotion-state-file)
      promotion_state_file="${2:-}"
      shift 2
      ;;
    --apply-state-file)
      apply_state_file="${2:-}"
      shift 2
      ;;
    --apply-telemetry-file)
      apply_telemetry_file="${2:-}"
      shift 2
      ;;
    --intent)
      intent="${2:-}"
      shift 2
      ;;
    --expand-step)
      expand_step="${2:-}"
      shift 2
      ;;
    --idempotency-key)
      idempotency_key="${2:-}"
      shift 2
      ;;
    --trace-id)
      trace_id="${2:-}"
      shift 2
      ;;
    --by)
      actor="${2:-}"
      shift 2
      ;;
    --approval-ref)
      approval_ref="${2:-}"
      shift 2
      ;;
    --rationale)
      rationale="${2:-}"
      shift 2
      ;;
    --review-by)
      review_by="${2:-}"
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
if [[ "$intent" != "expand" && "$intent" != "resume" && "$intent" != "rollback" ]]; then
  die "--intent must be one of expand, resume, rollback"
fi
if ! [[ "$expand_step" =~ ^[0-9]+$ ]] || (( expand_step < 1 )) || (( expand_step > 100 )); then
  die "--expand-step must be an integer between 1 and 100"
fi
if ! is_non_empty "$actor"; then
  die "--by is required"
fi
if ! is_non_empty "$approval_ref"; then
  die "--approval-ref is required"
fi
if ! is_non_empty "$rationale"; then
  die "--rationale is required"
fi
if ! is_non_empty "$review_by"; then
  die "--review-by is required"
fi

repo="$(cd "$repo" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
registry_script="${OPS_MANAGER_FLEET_REGISTRY_SCRIPT:-$script_dir/ops-manager-fleet-registry.sh}"

if [[ -z "$registry_file" ]]; then
  registry_file="$repo/.superloop/ops-manager/fleet/registry.v1.json"
fi
if [[ -z "$promotion_state_file" ]]; then
  promotion_state_file="$repo/.superloop/ops-manager/fleet/promotion-state.json"
fi
if [[ -z "$apply_state_file" ]]; then
  apply_state_file="$repo/.superloop/ops-manager/fleet/promotion-apply-state.json"
fi
if [[ -z "$apply_telemetry_file" ]]; then
  apply_telemetry_file="$repo/.superloop/ops-manager/fleet/telemetry/promotion-apply.jsonl"
fi

if [[ -z "$trace_id" && -n "${OPS_MANAGER_TRACE_ID:-}" ]]; then
  trace_id="$OPS_MANAGER_TRACE_ID"
fi
if [[ -z "$trace_id" ]]; then
  trace_id="$(generate_trace_id)"
fi

mkdir -p "$(dirname "$apply_state_file")"
mkdir -p "$(dirname "$apply_telemetry_file")"

[[ -f "$promotion_state_file" ]] || die "promotion state file not found: $promotion_state_file"
promotion_state_json="$(jq -c '.' "$promotion_state_file" 2>/dev/null)" || die "invalid promotion state JSON: $promotion_state_file"

promotion_decision="$(jq -r '.summary.decision // empty' <<<"$promotion_state_json")"
if [[ -z "$promotion_decision" ]]; then
  die "promotion state missing summary.decision"
fi

if [[ "$intent" != "rollback" && "$promotion_decision" != "promote" ]]; then
  die "intent $intent requires promotion decision promote (found: $promotion_decision)"
fi

# validate review-by upfront for better operator feedback before mutation
if ! jq -en --arg review_by "$review_by" '($review_by | fromdateiso8601?) != null' >/dev/null 2>&1; then
  die "--review-by must be an ISO-8601 timestamp"
fi
if ! jq -en --arg review_by "$review_by" --arg now "$(timestamp)" '($review_by | fromdateiso8601) > ($now | fromdateiso8601)' >/dev/null 2>&1; then
  die "--review-by must be in the future"
fi

if [[ -n "$idempotency_key" && -f "$apply_telemetry_file" ]]; then
  prior_record="$(jq -cs --arg key "$idempotency_key" '[.[] | select((.idempotencyKey // "") == $key)] | last // empty' "$apply_telemetry_file" 2>/dev/null || true)"
  if [[ -n "$prior_record" ]]; then
    replay_json="$(jq -c '. + {replayed: true}' <<<"$prior_record")"
    jq -c '.' <<<"$replay_json" > "$apply_state_file"
    if [[ "$pretty" == "1" ]]; then
      jq '.' <<<"$replay_json"
    else
      jq -c '.' <<<"$replay_json"
    fi
    exit 0
  fi
fi

registry_json="$($registry_script --repo "$repo" --registry-file "$registry_file")" || die "failed to read/validate fleet registry"

mode="$(jq -r '.policy.mode // "advisory"' <<<"$registry_json")"
if [[ "$mode" != "guarded_auto" ]]; then
  die "promotion apply requires policy.mode guarded_auto"
fi

changed_at="$(timestamp)"

mutated_registry_json=$(jq -cn \
  --argjson registry "$registry_json" \
  --arg intent "$intent" \
  --argjson expand_step "$expand_step" \
  --arg actor "$actor" \
  --arg approval_ref "$approval_ref" \
  --arg rationale "$rationale" \
  --arg changed_at "$changed_at" \
  --arg review_by "$review_by" \
  '
  ($registry.policy.autonomous.rollout.canaryPercent // 100) as $canary_before
  | ($registry.policy.autonomous.rollout.pause.manual // false) as $manual_before
  | (
      if $intent == "expand" then
        ($canary_before + $expand_step | if . > 100 then 100 else . end)
      else
        $canary_before
      end
    ) as $canary_after
  | (
      if $intent == "rollback" then true else false end
    ) as $manual_after
  | ($registry
      | .policy.autonomous.rollout.canaryPercent = $canary_after
      | .policy.autonomous.rollout.pause.manual = $manual_after
      | .policy.autonomous.governance.actor = $actor
      | .policy.autonomous.governance.approvalRef = $approval_ref
      | .policy.autonomous.governance.rationale = $rationale
      | .policy.autonomous.governance.changedAt = $changed_at
      | .policy.autonomous.governance.reviewBy = $review_by
    )
  ')

# Validate mutated registry through canonical registry script, then persist normalized output.
tmp_registry="$(mktemp)"
trap 'rm -f "$tmp_registry"' EXIT
jq -c '.' <<<"$mutated_registry_json" > "$tmp_registry"
normalized_registry_json="$($registry_script --repo "$repo" --registry-file "$tmp_registry")" || die "mutated registry failed validation"

before_canary="$(jq -r '.policy.autonomous.rollout.canaryPercent // 100' <<<"$registry_json")"
after_canary="$(jq -r '.policy.autonomous.rollout.canaryPercent // 100' <<<"$normalized_registry_json")"
before_manual="$(jq -r '.policy.autonomous.rollout.pause.manual // false' <<<"$registry_json")"
after_manual="$(jq -r '.policy.autonomous.rollout.pause.manual // false' <<<"$normalized_registry_json")"
fleet_id="$(jq -r '.fleetId // "default"' <<<"$normalized_registry_json")"

printf '%s\n' "$normalized_registry_json" > "$registry_file"

apply_record_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg timestamp "$changed_at" \
  --arg fleet_id "$fleet_id" \
  --arg trace_id "$trace_id" \
  --arg idempotency_key "$idempotency_key" \
  --arg intent "$intent" \
  --arg decision "$promotion_decision" \
  --arg actor "$actor" \
  --arg approval_ref "$approval_ref" \
  --arg rationale "$rationale" \
  --arg review_by "$review_by" \
  --arg changed_at "$changed_at" \
  --arg registry_file "$registry_file" \
  --arg promotion_state_file "$promotion_state_file" \
  --arg apply_state_file "$apply_state_file" \
  --arg apply_telemetry_file "$apply_telemetry_file" \
  --argjson before_canary "$before_canary" \
  --argjson after_canary "$after_canary" \
  --argjson before_manual "$before_manual" \
  --argjson after_manual "$after_manual" \
  '{
    schemaVersion: $schema_version,
    timestamp: $timestamp,
    category: "promotion_apply",
    fleetId: $fleet_id,
    traceId: $trace_id,
    idempotencyKey: (if ($idempotency_key | length) > 0 then $idempotency_key else null end),
    status: "applied",
    intent: $intent,
    decision: $decision,
    governance: {
      actor: $actor,
      approvalRef: $approval_ref,
      rationale: $rationale,
      changedAt: $changed_at,
      reviewBy: $review_by
    },
    rollout: {
      before: {
        canaryPercent: $before_canary,
        manualPause: $before_manual
      },
      after: {
        canaryPercent: $after_canary,
        manualPause: $after_manual
      },
      changed: {
        canaryPercent: ($before_canary != $after_canary),
        manualPause: ($before_manual != $after_manual)
      }
    },
    files: {
      registryFile: $registry_file,
      promotionStateFile: $promotion_state_file,
      applyStateFile: $apply_state_file,
      applyTelemetryFile: $apply_telemetry_file
    },
    reasonCodes: []
  }')

jq -c '.' <<<"$apply_record_json" > "$apply_state_file"
jq -c '.' <<<"$apply_record_json" >> "$apply_telemetry_file"

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$apply_record_json"
else
  jq -c '.' <<<"$apply_record_json"
fi
