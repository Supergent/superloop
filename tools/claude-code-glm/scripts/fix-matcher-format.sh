#!/bin/bash
# Fix matcher format - should be string not object

SETTINGS=~/.claude/settings.json
BACKUP="${SETTINGS}.backup.$(date +%Y%m%d_%H%M%S)"

echo "Fixing matcher format in $SETTINGS"

# Backup
cp "$SETTINGS" "$BACKUP"
echo "✓ Backup: $BACKUP"

# Fix: Change matcher from object to string
jq '.hooks.PreToolUse[0].matcher = "Grep"' "$SETTINGS" > /tmp/settings.json
mv /tmp/settings.json "$SETTINGS"

echo "✓ Fixed: matcher is now a string"
echo ""
echo "Verification:"
jq '.hooks.PreToolUse[0].matcher' "$SETTINGS"
