#!/bin/bash
# plan-session.sh - Runner-agnostic wrapper for spec planning
#
# Usage: ./scripts/plan-session.sh [--runner claude|codex] [target-repo-path]
#
# Launches an interactive planning session using the spec-planning skill.
# The skill is read from superloop (where this script lives), and the
# AI session runs in the target repo.
#
# Options:
#   --runner claude|codex  Force a specific runner (default: auto-detect)
#
# If no runner is specified, detects available AI runners and uses the first found.

set -e

# Get the directory where this script lives (superloop/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPERLOOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
FORCED_RUNNER=""
TARGET_REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner)
      FORCED_RUNNER="$2"
      shift 2
      ;;
    --runner=*)
      FORCED_RUNNER="${1#*=}"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--runner claude|codex] [target-repo-path]"
      echo ""
      echo "Options:"
      echo "  --runner claude|codex  Force a specific runner (default: auto-detect)"
      echo "  -h, --help             Show this help message"
      exit 0
      ;;
    *)
      TARGET_REPO="$1"
      shift
      ;;
  esac
done

# Default to current directory if no target specified
TARGET_REPO="${TARGET_REPO:-.}"
TARGET_REPO=$(cd "$TARGET_REPO" && pwd)

# Skill lives in superloop, not target repo
SKILL_FILE="$SUPERLOOP_DIR/.superloop/skills/spec-planning.md"

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

# Check that skill file exists (in superloop)
if [[ ! -f "$SKILL_FILE" ]]; then
  error "Skill file not found: $SKILL_FILE"
  error "Is superloop properly installed?"
  exit 1
fi

# Determine runner (forced or auto-detect)
RUNNER=""

if [[ -n "$FORCED_RUNNER" ]]; then
  # Validate forced runner
  case "$FORCED_RUNNER" in
    claude)
      if ! command -v claude &>/dev/null; then
        error "Claude Code (claude) is not installed"
        exit 1
      fi
      RUNNER="claude"
      info "Using runner: Claude Code (forced)"
      ;;
    codex)
      if ! command -v codex &>/dev/null; then
        error "OpenAI Codex (codex) is not installed"
        exit 1
      fi
      RUNNER="codex"
      info "Using runner: OpenAI Codex (forced)"
      ;;
    *)
      error "Unknown runner: $FORCED_RUNNER"
      error "Supported runners: claude, codex"
      exit 1
      ;;
  esac
else
  # Auto-detect runner
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
  echo "  $SUPERLOOP_DIR/superloop.sh run --repo $TARGET_REPO"
else
  warn "No spec.md found in $TARGET_REPO/.superloop/"
  warn "Planning may not have completed. Run this script again or use 'save' command."
fi
