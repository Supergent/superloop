#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CORE_PATHS=(
  "README.md"
  "docs/dev-env-contract-v1.md"
  "docs/dev-env-stack.md"
  ".claude/skills/construct-superloop/SKILL.md"
  ".claude/skills/local-dev-stack/SKILL.md"
  "scripts/bootstrap-target-dev-env.sh"
  "src"
)

# Product-specific env names or lab-specific canonical keys are not allowed in core paths.
PATTERN='SUPERGENT_|SUPERLOOP_LAB_BASE_URL|supergent\.localhost|lab\.supergent'

if command -v rg >/dev/null 2>&1; then
  SEARCH_TOOL="rg"
else
  SEARCH_TOOL="grep"
fi

cd "$ROOT_DIR"

search_path_for_pattern() {
  local path="$1"
  if [[ "$SEARCH_TOOL" == "rg" ]]; then
    rg -n -S -e "$PATTERN" "$path" || true
  else
    grep -n -R -E "$PATTERN" "$path" 2>/dev/null || true
  fi
}

FOUND=0
for path in "${CORE_PATHS[@]}"; do
  if [[ ! -e "$path" ]]; then
    continue
  fi
  matches="$(search_path_for_pattern "$path")"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches"
    FOUND=1
  fi
done

if [[ "$FOUND" -ne 0 ]]; then
  echo >&2
  echo "FAIL: product-specific coupling found in Superloop core paths." >&2
  echo "Move target-specific names to adapter profiles/docs outside core paths." >&2
  exit 1
fi

echo "PASS: no product-specific coupling detected in core paths."
