#!/bin/bash
# plan-session.sh - Runner-agnostic wrapper for spec planning
#
# Usage: ./scripts/plan-session.sh [target-repo-path]
#
# Launches an interactive planning session using the spec-planning skill.
# The skill is read from ralph-codex (where this script lives), and the
# AI session runs in the target repo.
#
# Detects available AI runners (claude, codex) and uses the first found.

set -e

# Get the directory where this script lives (ralph-codex/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Target repo is the argument (or current directory)
TARGET_REPO="${1:-.}"
TARGET_REPO=$(cd "$TARGET_REPO" && pwd)

# Skill lives in ralph-codex, not target repo
SKILL_FILE="$RALPH_DIR/.superloop/skills/spec-planning.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
  echo -e "${GREEN}[plan]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[plan]${NC} $1"
}

error() {
  echo -e "${RED}[plan]${NC} $1" >&2
}

# Check that skill file exists (in ralph-codex)
if [[ ! -f "$SKILL_FILE" ]]; then
  error "Skill file not found: $SKILL_FILE"
  error "Is ralph-codex properly installed?"
  exit 1
fi

# Detect available runner
RUNNER=""

if command -v claude &>/dev/null; then
  RUNNER="claude"
  info "Detected runner: Claude Code"
elif command -v codex &>/dev/null; then
  RUNNER="codex"
  info "Detected runner: OpenAI Codex"
else
  error "No supported runner found"
  error "Install one of: claude (Claude Code), codex (OpenAI Codex)"
  exit 1
fi

info "Target repo: $TARGET_REPO"
info "Skill source: $SKILL_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SPEC PLANNING SESSION"
echo "  "
echo "  Commands: save, draft, validate, start over, skip [phase]"
echo "  "
echo "  The AI will guide you through creating a spec for your project."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Launch the appropriate runner with skill injected via CLI flags
case "$RUNNER" in
  claude)
    # --append-system-prompt adds skill to system prompt without modifying files
    cd "$TARGET_REPO" && claude --append-system-prompt "$(cat "$SKILL_FILE")"
    ;;

  codex)
    # --config developer_instructions adds skill as developer role message
    cd "$TARGET_REPO" && codex --config developer_instructions="$(cat "$SKILL_FILE")"
    ;;
esac

# Post-session message
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PLANNING SESSION ENDED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if spec was created in target repo
if [[ -f "$TARGET_REPO/.superloop/spec.md" ]]; then
  info "Spec file created: $TARGET_REPO/.superloop/spec.md"

  if [[ -f "$TARGET_REPO/.superloop/config.json" ]]; then
    info "Config file created: $TARGET_REPO/.superloop/config.json"
  fi

  if [[ -f "$TARGET_REPO/CHECKLIST.md" ]]; then
    info "Checklist created: $TARGET_REPO/CHECKLIST.md"
  fi

  echo ""
  info "To start the implementation loop, run:"
  echo "  $RALPH_DIR/superloop.sh run --repo $TARGET_REPO"
else
  warn "No spec.md found in $TARGET_REPO/.superloop/"
  warn "Planning may not have completed. Run this script again or use 'save' command."
fi
