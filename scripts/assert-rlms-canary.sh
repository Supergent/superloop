#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/assert-rlms-canary.sh \
  --status-file <path> \
  [--result-file <path>] \
  [--require-should-run <true|false>] \
  [--min-citations <n>] \
  [--min-non-fallback-citations <n>] \
  [--fallback-signals <comma-separated>] \
  [--require-highlight-pattern <regex>]

Environment variable defaults:
  RLMS_CANARY_REQUIRE_SHOULD_RUN=true
  RLMS_CANARY_MIN_CITATIONS=1
  RLMS_CANARY_MIN_NON_FALLBACK_CITATIONS=1
  RLMS_CANARY_FALLBACK_SIGNALS=file_reference
  RLMS_CANARY_REQUIRE_HIGHLIGHT_PATTERN=
USAGE
}

fail() {
  local message="$1"
  echo "RLMS canary assertion failed: $message" >&2
  echo "::error::$message" >&2
  exit 1
}

need_file() {
  local path="$1"
  local label="$2"
  if [[ -z "$path" ]]; then
    fail "missing required $label"
  fi
  if [[ ! -f "$path" ]]; then
    fail "$label not found: $path"
  fi
}

need_int() {
  local value="$1"
  local label="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    fail "$label must be a non-negative integer (got: $value)"
  fi
}

status_file=""
result_file=""
require_should_run="${RLMS_CANARY_REQUIRE_SHOULD_RUN:-true}"
min_citations="${RLMS_CANARY_MIN_CITATIONS:-1}"
min_non_fallback_citations="${RLMS_CANARY_MIN_NON_FALLBACK_CITATIONS:-1}"
fallback_signals="${RLMS_CANARY_FALLBACK_SIGNALS:-file_reference}"
require_highlight_pattern="${RLMS_CANARY_REQUIRE_HIGHLIGHT_PATTERN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status-file)
      status_file="${2:-}"
      shift 2
      ;;
    --result-file)
      result_file="${2:-}"
      shift 2
      ;;
    --require-should-run)
      require_should_run="${2:-}"
      shift 2
      ;;
    --min-citations)
      min_citations="${2:-}"
      shift 2
      ;;
    --min-non-fallback-citations)
      min_non_fallback_citations="${2:-}"
      shift 2
      ;;
    --fallback-signals)
      fallback_signals="${2:-}"
      shift 2
      ;;
    --require-highlight-pattern)
      require_highlight_pattern="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
done

need_file "$status_file" "status file"
if [[ -z "$result_file" ]]; then
  result_file="${status_file%.status.json}.json"
fi
need_file "$result_file" "result file"

if [[ "$require_should_run" != "true" && "$require_should_run" != "false" ]]; then
  fail "--require-should-run must be true or false (got: $require_should_run)"
fi

need_int "$min_citations" "--min-citations"
need_int "$min_non_fallback_citations" "--min-non-fallback-citations"

local_status=$(jq -r '.status // ""' "$status_file")
if [[ "$local_status" != "ok" ]]; then
  fail "expected status=ok, got '$local_status' in $status_file"
fi

local_should_run=$(jq -r '.should_run // false' "$status_file")
if [[ "$require_should_run" == "true" && "$local_should_run" != "true" ]]; then
  fail "expected should_run=true in $status_file"
fi

local_ok=$(jq -r '.ok // false' "$result_file")
if [[ "$local_ok" != "true" ]]; then
  fail "expected ok=true in $result_file"
fi

citation_count=$(jq -r '(.citations // []) | length' "$result_file")
if (( citation_count < min_citations )); then
  fail "citation threshold failed: expected >= $min_citations, got $citation_count"
fi

fallback_signals_json=$(jq -Rn --arg csv "$fallback_signals" '
  ($csv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
')

non_fallback_count=$(jq -r --argjson fallback "$fallback_signals_json" '
  (.citations // [])
  | map((.signal // "") as $signal | select(($fallback | index($signal)) == null))
  | length
' "$result_file")

if (( non_fallback_count < min_non_fallback_citations )); then
  fail "non-fallback citation threshold failed: expected >= $min_non_fallback_citations, got $non_fallback_count (fallback signals: $fallback_signals)"
fi

if [[ -n "$require_highlight_pattern" ]]; then
  highlight_matches=$(jq -r --arg pattern "$require_highlight_pattern" '
    (.highlights // [])
    | map(tostring)
    | map(select(test($pattern)))
    | length
  ' "$result_file")
  if (( highlight_matches < 1 )); then
    fail "required highlight pattern not found: $require_highlight_pattern"
  fi
fi

echo "RLMS canary assertions passed: status=ok, should_run=$local_should_run, citations=$citation_count, non_fallback_citations=$non_fallback_count"
