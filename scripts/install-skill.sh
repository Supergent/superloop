#!/usr/bin/env bash
#
# Install/sync construct-superloop skill for Claude Code and Codex.
#
# Copies the repository skill source to:
# - ~/.claude/skills/construct-superloop
# - ~/.codex/skills/construct-superloop
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPERLOOP_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_NAME="construct-superloop"
SKILL_SOURCE="$SUPERLOOP_DIR/.claude/skills/$SKILL_NAME"
FORCE="${1:-}"

confirm_overwrite() {
    local target="$1"
    if [[ "$FORCE" == "--force" ]]; then
        return 0
    fi

    echo "Skill already exists at $target"
    read -r -p "Overwrite? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        echo "Skipping $target"
        return 1
    fi
    return 0
}

sync_target() {
    local parent_dir="$1"
    local target="$2"
    local label="$3"

    mkdir -p "$parent_dir"
    if [[ -d "$target" ]]; then
        if ! confirm_overwrite "$target"; then
            return 0
        fi
        rm -rf "$target"
    fi

    cp -R "$SKILL_SOURCE" "$target"
    echo "Synced to $label: $target"
}

echo "Installing $SKILL_NAME skill from $SKILL_SOURCE"

if [[ ! -d "$SKILL_SOURCE" ]]; then
    echo "ERROR: Skill source not found at $SKILL_SOURCE"
    exit 1
fi

CLAUDE_PARENT="$HOME/.claude/skills"
CLAUDE_DEST="$CLAUDE_PARENT/$SKILL_NAME"
CODEX_PARENT="$HOME/.codex/skills"
CODEX_DEST="$CODEX_PARENT/$SKILL_NAME"

sync_target "$CLAUDE_PARENT" "$CLAUDE_DEST" "Claude Code"
sync_target "$CODEX_PARENT" "$CODEX_DEST" "Codex"

echo
echo "Skill sync complete."
echo "Claude usage: /construct-superloop \"Your feature description\""
echo "Codex note: restart Codex to pick up newly installed skills."
