#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

runner=""
if command -v node >/dev/null 2>&1; then
  runner="node"
elif command -v bun >/dev/null 2>&1; then
  runner="bun"
else
  echo "error: missing node or bun" >&2
  exit 1
fi

run_preflight() {
  "$runner" "$ROOT_DIR/scripts/validation/bundle-preflight.js" --repo "$ROOT_DIR" --config \
    '{"entry":"feat/validation/fixtures/web/index.html","web_root":"feat/validation/fixtures/web","required_selectors":["#root"],"required_text":["Validation Fixture"]}'
}

run_negative() {
  set +e
  "$runner" "$ROOT_DIR/scripts/validation/bundle-preflight.js" --repo "$ROOT_DIR" --config \
    '{"entry":"feat/validation/fixtures/web/missing.html","web_root":"feat/validation/fixtures/web","required_selectors":["#root"]}' >/dev/null
  local status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    echo "error: negative preflight unexpectedly succeeded" >&2
    exit 1
  fi
}

case "${1:-}" in
  --negative)
    run_preflight
    run_negative
    ;;
  "")
    run_preflight
    ;;
  *)
    echo "usage: $(basename "$0") [--negative]" >&2
    exit 2
    ;;
esac
