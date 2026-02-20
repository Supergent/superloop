#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/run-local-canary.sh [--repo <path>]

Runs a deterministic local RLMS canary pass by:
1. Temporarily switching the canary reviewer runner to a local shell runner.
2. Forcing RLMS root/subcall commands to local mock scripts.
3. Executing the rlms-canary loop.
4. Asserting canary artifacts and restoring config.
USAGE
}

repo="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$repo" ]]; then
  echo "--repo requires a value" >&2
  exit 1
fi

repo="$(cd "$repo" && pwd)"
config_file="$repo/.superloop/config.json"
if [[ ! -f "$config_file" ]]; then
  echo "Config not found: $config_file" >&2
  exit 1
fi

backup_file="$(mktemp)"
cp "$config_file" "$backup_file"

cleanup() {
  if [[ -f "$backup_file" ]]; then
    cp "$backup_file" "$config_file"
    rm -f "$backup_file"
  fi
}
trap cleanup EXIT

tmp_cfg="$(mktemp)"
jq '
  .runners["local-shell"] = {
    command: ["bash"],
    args: ["-lc", "echo \"<promise>SUPERLOOP_COMPLETE</promise>\" > \"{last_message_file}\""],
    prompt_mode: "stdin"
  }
  | (.loops[] | select(.id == "rlms-canary") | .roles.reviewer.runner) = "local-shell"
  | del(
      (.loops[] | select(.id == "rlms-canary") | .roles.reviewer.model),
      (.loops[] | select(.id == "rlms-canary") | .roles.reviewer.thinking)
    )
' "$config_file" > "$tmp_cfg"
mv "$tmp_cfg" "$config_file"

"$repo/superloop.sh" validate --repo "$repo"

root_command_json="$(jq -cn --arg cmd "$repo/scripts/rlms-mock-root.sh" '[$cmd]')"
subcall_command_json="$(jq -cn --arg cmd "$repo/scripts/rlms-mock-subcall.sh" '[$cmd]')"

SUPERLOOP_RLMS_ROOT_COMMAND_JSON="$root_command_json" \
SUPERLOOP_RLMS_ROOT_ARGS_JSON='[]' \
SUPERLOOP_RLMS_ROOT_PROMPT_MODE='stdin' \
SUPERLOOP_RLMS_SUBCALL_COMMAND_JSON="$subcall_command_json" \
SUPERLOOP_RLMS_SUBCALL_ARGS_JSON='[]' \
SUPERLOOP_RLMS_SUBCALL_PROMPT_MODE='stdin' \
"$repo/superloop.sh" run --repo "$repo" --loop rlms-canary

"$repo/scripts/assert-rlms-canary.sh" \
  --status-file "$repo/.superloop/loops/rlms-canary/rlms/latest/reviewer.status.json" \
  --result-file "$repo/.superloop/loops/rlms-canary/rlms/latest/reviewer.json" \
  --require-should-run true \
  --min-citations "${RLMS_CANARY_MIN_CITATIONS:-1}" \
  --min-non-fallback-citations "${RLMS_CANARY_MIN_NON_FALLBACK_CITATIONS:-1}" \
  --fallback-signals "${RLMS_CANARY_FALLBACK_SIGNALS:-file_reference}" \
  --require-highlight-pattern "${RLMS_CANARY_REQUIRE_HIGHLIGHT_PATTERN:-mock_root_complete}"

echo "Local deterministic rlms-canary run passed."
