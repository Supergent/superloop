#!/bin/bash
#
# Install construct-superloop skill for Claude Code
#
# This script copies the construct-superloop skill to the user's
# Claude Code skills directory, making /construct-superloop available.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPERLOOP_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_SOURCE="$SUPERLOOP_DIR/.claude/skills/construct-superloop"
SKILL_DEST="$HOME/.claude/skills/construct-superloop"

echo "Installing construct-superloop skill..."

# Check source exists
if [[ ! -d "$SKILL_SOURCE" ]]; then
    echo "ERROR: Skill source not found at $SKILL_SOURCE"
    exit 1
fi

# Create destination directory
mkdir -p "$HOME/.claude/skills"

# Check if already installed
if [[ -d "$SKILL_DEST" ]]; then
    echo "Skill already installed at $SKILL_DEST"
    read -p "Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    rm -rf "$SKILL_DEST"
fi

# Copy skill directory
cp -r "$SKILL_SOURCE" "$SKILL_DEST"

echo ""
echo "Skill installed successfully!"
echo ""
echo "Location: $SKILL_DEST"
echo ""
echo "Usage: In Claude Code, run:"
echo "  /construct-superloop \"Your feature description\""
echo ""
echo "Or just describe a feature and Claude will suggest using the skill."
