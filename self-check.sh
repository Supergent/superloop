#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'USAGE'
Supergent Wrapper Self-Check

Usage:
  self-check.sh --repo DIR --loop ID [--fast]

Checks:
  - Runs the loop twice.
  - Fails if plan/report files change between runs.

Options:
  --repo DIR   Repository root to test.
  --loop ID    Loop id to run (required).
  --fast       Use runner.fast_args if configured.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

file_hash() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "missing"
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi

  cksum "$file" | awk '{print $1}'
}

snapshot_hashes() {
  local repo="$1"
  local out="$2"
  shift 2
  local -a files=("$@")

  : > "$out"
  for f in "${files[@]}"; do
    printf '%s\t%s\n' "$(file_hash "$repo/$f")" "$f" >> "$out"
  done
}

REPO="."
LOOP_ID=""
FAST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --loop)
      LOOP_ID="$2"
      shift 2
      ;;
    --fast)
      FAST=1
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

if [[ -z "$LOOP_ID" ]]; then
  die "--loop is required"
fi

REPO=$(cd "$REPO" && pwd)

FILES=(
  ".ralph/loops/$LOOP_ID/plan.md"
  ".ralph/loops/$LOOP_ID/implementer.md"
  ".ralph/loops/$LOOP_ID/test-report.md"
  ".ralph/loops/$LOOP_ID/review.md"
)

tmp1=$(mktemp)
tmp2=$(mktemp)
trap 'rm -f "$tmp1" "$tmp2"' EXIT

run_args=(run --repo "$REPO" --loop "$LOOP_ID")
if [[ $FAST -eq 1 ]]; then
  run_args+=(--fast)
fi

echo "Running loop (1/2)..."
"$ROOT_DIR/ralph-codex.sh" "${run_args[@]}"
snapshot_hashes "$REPO" "$tmp1" "${FILES[@]}"

echo "Running loop (2/2)..."
"$ROOT_DIR/ralph-codex.sh" "${run_args[@]}"
snapshot_hashes "$REPO" "$tmp2" "${FILES[@]}"

if diff -u "$tmp1" "$tmp2" >/dev/null; then
  echo "ok: no churn detected in plan/report files"
  exit 0
fi

echo "churn detected in plan/report files"
diff -u "$tmp1" "$tmp2" || true
exit 1
