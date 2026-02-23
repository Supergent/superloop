#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/validate-horizons.sh [--repo DIR] [--file PATH] [--schema PATH] [--strict]

Options:
  --repo DIR      Repository root (default: .)
  --file PATH     Horizon control-plane file (default: .superloop/horizons.json)
  --schema PATH   Horizon schema file (default: schema/horizons.schema.json)
  --strict        Run full JSON Schema validation via python jsonschema module
  -h, --help      Show this help

Notes:
  - Non-strict mode uses Superloop's built-in schema validator plus additional
    jq checks for horizon invariants.
  - Strict mode requires python3/python with the `jsonschema` module installed.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

repo="."
horizons_path=".superloop/horizons.json"
schema_path="schema/horizons.schema.json"
strict="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      repo="$2"
      shift 2
      ;;
    --file)
      [[ $# -ge 2 ]] || die "--file requires a value"
      horizons_path="$2"
      shift 2
      ;;
    --schema)
      [[ $# -ge 2 ]] || die "--schema requires a value"
      schema_path="$2"
      shift 2
      ;;
    --strict)
      strict="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

need_cmd jq

repo=$(cd "$repo" && pwd)
[[ -x "$repo/superloop.sh" ]] || die "missing executable: $repo/superloop.sh"

if [[ "$horizons_path" != /* ]]; then
  horizons_path="$repo/$horizons_path"
fi
if [[ "$schema_path" != /* ]]; then
  schema_path="$repo/$schema_path"
fi

[[ -f "$horizons_path" ]] || die "horizon file not found: $horizons_path"
[[ -f "$schema_path" ]] || die "schema file not found: $schema_path"

# JSON parse sanity.
jq -e '.' "$horizons_path" >/dev/null

# Reuse Superloop schema validation machinery (portable baseline).
"$repo/superloop.sh" validate --repo "$repo" --config "$horizons_path" --schema "$schema_path" >/dev/null

# Additional invariant checks to catch control-plane contract drift.
jq -e '
  .version == 1 and
  (.horizons | type == "array" and length > 0) and
  ([.horizons[].id] | length == (unique | length)) and
  ([.horizons[].level] | all(. == "H1" or . == "H2" or . == "H3")) and
  ([.horizons[].status] | all(. == "proposed" or . == "active" or . == "paused" or . == "completed" or . == "retired")) and
  ([.horizons[].cadence_domain] | all(. == "realtime" or . == "tactical" or . == "program" or . == "strategic")) and
  ([.horizons[] | .confidence? | select(. != null)] | all(type == "number" and . >= 0 and . <= 1)) and
  ([.horizons[] | (.execution_slices // [])[] | .status] | all(. == "planned" or . == "active" or . == "blocked" or . == "completed" or . == "cancelled")) and
  ([.horizons[] | (.transitions // [])[] | .from_level] | all(. == "H1" or . == "H2" or . == "H3")) and
  ([.horizons[] | (.transitions // [])[] | .to_level] | all(. == "H1" or . == "H2" or . == "H3"))
' "$horizons_path" >/dev/null

if [[ "$strict" == "1" ]]; then
  py_bin=""
  if command -v python3 >/dev/null 2>&1; then
    py_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    py_bin="python"
  else
    die "strict mode requires python3/python with jsonschema module"
  fi

  "$py_bin" - "$schema_path" "$horizons_path" <<'PY'
import json
import sys

schema_path = sys.argv[1]
horizons_path = sys.argv[2]

try:
    import jsonschema  # type: ignore
except Exception as exc:
    sys.stderr.write(f"error: strict mode requires python jsonschema module ({exc.__class__.__name__})\n")
    sys.exit(1)

with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)
with open(horizons_path, "r", encoding="utf-8") as f:
    data = json.load(f)

jsonschema.validate(instance=data, schema=schema)
PY
fi

echo "ok: horizons control-plane file is valid"
