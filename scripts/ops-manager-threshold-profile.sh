#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-threshold-profile.sh [options]

Options:
  --profiles-file <path>   Profile catalog JSON file.
  --profile <name>         Profile name. Defaults to catalog defaultProfile.
  --list                   List available profile names and exit.
  --pretty                 Pretty-print output JSON.
  --help                   Show this help message.
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

profiles_file=""
profile_name=""
list_only="0"
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profiles-file)
      profiles_file="${2:-}"
      shift 2
      ;;
    --profile)
      profile_name="${2:-}"
      shift 2
      ;;
    --list)
      list_only="1"
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

if [[ -z "$profiles_file" ]]; then
  profiles_file="${OPS_MANAGER_THRESHOLD_PROFILES_FILE:-$root_dir/config/ops-manager-threshold-profiles.v1.json}"
fi

if [[ ! -f "$profiles_file" ]]; then
  die "threshold profiles file not found: $profiles_file"
fi

profiles_json=$(jq -c '.' "$profiles_file" 2>/dev/null) || die "invalid threshold profiles JSON: $profiles_file"

if ! jq -e '.schemaVersion == "v1" and (.profiles | type == "object") and ((.profiles | keys | length) > 0)' <<<"$profiles_json" >/dev/null; then
  die "threshold profiles file has invalid shape"
fi

if [[ "$list_only" == "1" ]]; then
  jq -r '.profiles | keys[]' <<<"$profiles_json"
  exit 0
fi

if [[ -z "$profile_name" ]]; then
  profile_name=$(jq -r '.defaultProfile // empty' <<<"$profiles_json")
fi
if [[ -z "$profile_name" ]]; then
  die "profile name is required and defaultProfile is missing"
fi

if ! jq -e --arg profile "$profile_name" '.profiles[$profile] != null' <<<"$profiles_json" >/dev/null; then
  die "unknown threshold profile: $profile_name"
fi

if ! jq -e --arg profile "$profile_name" '
  .profiles[$profile] as $p
  | ($p.degradedIngestLagSeconds | type == "number")
    and ($p.criticalIngestLagSeconds | type == "number")
    and ($p.degradedTransportFailureStreak | type == "number")
    and ($p.criticalTransportFailureStreak | type == "number")
    and ($p.criticalIngestLagSeconds >= $p.degradedIngestLagSeconds)
    and ($p.criticalTransportFailureStreak >= $p.degradedTransportFailureStreak)
' <<<"$profiles_json" >/dev/null; then
  die "threshold profile values are invalid: $profile_name"
fi

resolved_json=$(jq -cn \
  --arg schema_version "v1" \
  --arg source_file "$profiles_file" \
  --arg profile "$profile_name" \
  --argjson root "$profiles_json" \
  '{
    schemaVersion: $schema_version,
    sourceFile: $source_file,
    profile: $profile,
    values: {
      degradedIngestLagSeconds: ($root.profiles[$profile].degradedIngestLagSeconds | tonumber),
      criticalIngestLagSeconds: ($root.profiles[$profile].criticalIngestLagSeconds | tonumber),
      degradedTransportFailureStreak: ($root.profiles[$profile].degradedTransportFailureStreak | tonumber),
      criticalTransportFailureStreak: ($root.profiles[$profile].criticalTransportFailureStreak | tonumber)
    },
    description: ($root.profiles[$profile].description // null)
  } | with_entries(select(.value != null))')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$resolved_json"
else
  jq -c '.' <<<"$resolved_json"
fi
