#!/bin/bash
#
# Quick Fix Script for Hook Format Update
# Converts old string-based hook format to new matcher-based array format
#

set -euo pipefail

CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "Mantic Hook Format Updater"
echo "=========================="
echo ""

# Check if settings file exists
if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "Error: $CLAUDE_SETTINGS not found"
    exit 1
fi

# Backup
BACKUP_FILE="${CLAUDE_SETTINGS}.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: $BACKUP_FILE"
cp "$CLAUDE_SETTINGS" "$BACKUP_FILE"

# Check current format
if jq -e '.hooks.PreToolUse | type' "$CLAUDE_SETTINGS" 2>/dev/null | grep -q "string"; then
    echo "Old format detected - converting to new format..."

    # Get current hook path
    HOOK_PATH=$(jq -r '.hooks.PreToolUse' "$CLAUDE_SETTINGS")
    echo "Current hook: $HOOK_PATH"

    # Update to new format
    TEMP=$(mktemp)
    jq --arg hook "$HOOK_PATH" \
       '.hooks.PreToolUse = [
          {
            "matcher": {"tools": ["Grep"]},
            "hooks": [
              {
                "type": "command",
                "command": $hook
              }
            ]
          }
        ]' "$CLAUDE_SETTINGS" > "$TEMP"

    mv "$TEMP" "$CLAUDE_SETTINGS"
    echo "✓ Converted to new format!"

elif jq -e '.hooks.PreToolUse | type' "$CLAUDE_SETTINGS" 2>/dev/null | grep -q "array"; then
    echo "✓ Already using new format - no changes needed"
else
    echo "Warning: Unexpected hook format"
    jq '.hooks' "$CLAUDE_SETTINGS"
fi

echo ""
echo "Verification:"
jq '.hooks.PreToolUse' "$CLAUDE_SETTINGS"

echo ""
echo "Done! Backup saved to: $BACKUP_FILE"
