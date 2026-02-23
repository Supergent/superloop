#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/validate-horizon-directory.sh [--repo DIR] [--file PATH] [--schema PATH] [--strict]

Options:
  --repo DIR      Repository root (default: .)
  --file PATH     Directory file path (default: .superloop/horizon-directory.json)
  --schema PATH   Schema path (default: schema/horizon-directory.schema.json)
  --strict        Run full JSON Schema validation via python jsonschema module
  -h, --help      Show this help

Notes:
  - Non-strict mode uses Superloop's built-in schema validator plus additional
    jq checks for recipient uniqueness and policy invariants.
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
directory_path=".superloop/horizon-directory.json"
schema_path="schema/horizon-directory.schema.json"
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
      directory_path="$2"
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

if [[ "$directory_path" != /* ]]; then
  directory_path="$repo/$directory_path"
fi
if [[ "$schema_path" != /* ]]; then
  schema_path="$repo/$schema_path"
fi

[[ -f "$directory_path" ]] || die "directory file not found: $directory_path"
[[ -f "$schema_path" ]] || die "schema file not found: $schema_path"

jq -e '.' "$directory_path" >/dev/null
"$repo/superloop.sh" validate --repo "$repo" --config "$directory_path" --schema "$schema_path" >/dev/null

jq -e '
  .version == 1 and
  (.contacts | type == "array" and length > 0) and
  ([.contacts[] | .recipient.type + "|" + .recipient.id] | length == (unique | length)) and
  ([.contacts[].dispatch.adapter] | all(. == "filesystem_outbox" or . == "stdout")) and
  ([.contacts[] | .dispatch.target? | select(. != null)] | all(type == "string" and length > 0)) and
  ([.contacts[] | .ack.timeout_seconds? | select(. != null)] | all(type == "number" and . >= 0 and . == floor)) and
  ([.contacts[] | .ack.max_retries? | select(. != null)] | all(type == "number" and . >= 0 and . == floor)) and
  ([.contacts[] | .ack.retry_backoff_seconds? | select(. != null)] | all(type == "number" and . >= 0 and . == floor))
' "$directory_path" >/dev/null

if [[ "$strict" == "1" ]]; then
  py_bin=""
  if command -v python3 >/dev/null 2>&1; then
    py_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    py_bin="python"
  else
    die "strict mode requires python3/python with jsonschema module"
  fi

  "$py_bin" - "$schema_path" "$directory_path" <<'PY'
import json
import sys

schema_path = sys.argv[1]
directory_path = sys.argv[2]

try:
    import jsonschema  # type: ignore
except Exception as exc:
    sys.stderr.write(f"error: strict mode requires python jsonschema module ({exc.__class__.__name__})\n")
    sys.exit(1)

with open(schema_path, "r", encoding="utf-8") as f:
    schema = json.load(f)
with open(directory_path, "r", encoding="utf-8") as f:
    data = json.load(f)

jsonschema.validate(instance=data, schema=schema)
PY
fi

echo "ok: horizon directory file is valid"
