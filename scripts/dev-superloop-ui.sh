#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_raw() {
  bash -lc 'cd "$1" && bun run --cwd packages/superloop-ui dev -- --port "${PORT:-5173}"' _ "$ROOT_DIR"
}

if [[ "${PORTLESS:-1}" == "0" ]]; then
  echo "[dev-superloop-ui] PORTLESS=0 -> running without proxy"
  run_raw
  exit 0
fi

if ! command -v portless >/dev/null 2>&1; then
  echo "[dev-superloop-ui] portless not found -> running without proxy"
  run_raw
  exit 0
fi

export SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-http://superloop-ui.localhost:1355}"
echo "[dev-superloop-ui] Starting at ${SUPERLOOP_UI_BASE_URL}/liquid"

portless superloop-ui bash -lc 'cd "$1" && bun run --cwd packages/superloop-ui dev -- --port "${PORT:-5173}"' _ "$ROOT_DIR"
