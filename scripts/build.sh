#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC_DIR="$ROOT_DIR/src"
OUT_FILE="$ROOT_DIR/superloop.sh"

PARTS=(
  "00-header.sh"
  "10-evidence.sh"
  "20-prompts.sh"
  "30-runner.sh"
  "40-gates.sh"
  "50-events.sh"
  "60-commands.sh"
  "70-report.sh"
  "99-main.sh"
)

: > "$OUT_FILE"
for part in "${PARTS[@]}"; do
  src_file="$SRC_DIR/$part"
  if [[ ! -f "$src_file" ]]; then
    echo "error: missing $src_file" >&2
    exit 1
  fi
  cat "$src_file" >> "$OUT_FILE"
  echo "" >> "$OUT_FILE"
done

chmod +x "$OUT_FILE"
