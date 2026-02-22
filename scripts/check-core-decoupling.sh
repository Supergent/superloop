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

DENYLIST_FILE="${SUPERLOOP_DECOUPLING_DENYLIST_FILE:-scripts/decoupling-core-denylist.txt}"

if [[ ! -f "$DENYLIST_FILE" ]]; then
  echo "error: decoupling denylist file not found: $DENYLIST_FILE" >&2
  exit 2
fi

mapfile -t DENYLIST_PATTERNS < <(
  sed -E 's/[[:space:]]*#.*$//' "$DENYLIST_FILE" | sed -E '/^[[:space:]]*$/d'
)

if [[ ${#DENYLIST_PATTERNS[@]} -eq 0 ]]; then
  echo "error: decoupling denylist file has no patterns: $DENYLIST_FILE" >&2
  exit 2
fi

# Product-specific names/hosts must not appear in core paths.
PATTERN="$(IFS='|'; echo "${DENYLIST_PATTERNS[*]}")"

if command -v rg >/dev/null 2>&1; then
  SEARCH_TOOL="rg"
else
  SEARCH_TOOL="grep"
fi

cd "$ROOT_DIR"

search_path_for_pattern() {
  local path="$1"
  if [[ "$SEARCH_TOOL" == "rg" ]]; then
    rg -n -S -i -e "$PATTERN" "$path" || true
  else
    grep -n -R -E -i "$PATTERN" "$path" 2>/dev/null || true
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
  echo "Denylist source: $DENYLIST_FILE" >&2
  echo "Move target-specific names to adapter profiles/docs outside core paths." >&2
  exit 1
fi

echo "PASS: no product-specific coupling detected in core paths."
