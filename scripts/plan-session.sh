#!/bin/bash
# plan-session.sh - Runner-agnostic wrapper for spec planning
#
# Usage: ./scripts/plan-session.sh [repo-path]
#
# Launches an interactive planning session using the spec-planning skill.
# Detects available AI runners (claude, codex) and uses the first found.

set -e

REPO="${1:-.}"
REPO=$(cd "$REPO" && pwd)

SKILL_FILE="$REPO/.superloop/skills/spec-planning.md"
SUPERLOOP_DIR="$REPO/.superloop"

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

# Check prerequisites
if [[ ! -d "$SUPERLOOP_DIR" ]]; then
  error ".superloop directory not found in $REPO"
  error "Run 'superloop.sh init --repo $REPO' first"
  exit 1
fi

if [[ ! -f "$SKILL_FILE" ]]; then
  error "Skill file not found: $SKILL_FILE"
  error "Ensure .superloop/skills/spec-planning.md exists"
  exit 1
fi

# Detect available runner
RUNNER=""
RUNNER_CMD=""

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

info "Starting planning session in: $REPO"
info "Skill: $SKILL_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SPEC PLANNING SESSION"
echo "  "
echo "  Commands: save, draft, validate, start over, skip [phase]"
echo "  "
echo "  When done, run: ./superloop.sh run --repo $REPO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Launch the appropriate runner
case "$RUNNER" in
  claude)
    # Claude Code: launch in repo directory
    # The skill file path will be provided as context
    info "Launching Claude Code..."
    info "Skill prompt: $SKILL_FILE"
    info ""
    info "Tip: Start by saying 'Read the spec-planning skill at .superloop/skills/spec-planning.md and help me create a spec'"
    cd "$REPO" && claude
    ;;

  codex)
    # OpenAI Codex: use -C for directory and -p for prompt
    # --full-auto false for interactive mode
    if codex --help 2>&1 | grep -q -- '--full-auto'; then
      codex -C "$REPO" --full-auto false -p "$(cat "$SKILL_FILE")"
    else
      # Fallback
      warn "Launching Codex in repo (skill prompt may need manual loading)"
      cd "$REPO" && codex -p "$(cat "$SKILL_FILE")"
    fi
    ;;
esac

# Post-session message
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PLANNING SESSION ENDED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if spec was created
if [[ -f "$REPO/.superloop/spec.md" ]]; then
  info "Spec file exists: .superloop/spec.md"

  if [[ -f "$REPO/.superloop/config.json" ]]; then
    info "Config file exists: .superloop/config.json"
  fi

  if [[ -f "$REPO/CHECKLIST.md" ]]; then
    info "Checklist exists: CHECKLIST.md"
  fi

  echo ""
  info "To start the implementation loop, run:"
  echo "  ./superloop.sh run --repo $REPO"
else
  warn "No spec.md found - planning may not have completed"
  warn "You can run this script again or create spec.md manually"
fi
