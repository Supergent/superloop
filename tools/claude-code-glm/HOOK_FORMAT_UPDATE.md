# Hook Format Update - January 2026

## What Changed

Claude Code updated their hook format from a simple string to a **matcher-based array structure**.

### Old Format (No Longer Works)

```json
{
  "hooks": {
    "PreToolUse": "~/mantic-grep-hook.sh"
  }
}
```

### New Format (Required)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": {"tools": ["Grep"]},
        "hooks": [
          {
            "type": "command",
            "command": "~/mantic-grep-hook.sh"
          }
        ]
      }
    ]
  }
}
```

## Why the Change

The new format allows:
- **Tool-specific hooks**: Hook only triggers for specific tools (e.g., just "Grep")
- **Multiple hooks**: Can have different hooks for different tools
- **Better control**: More granular matching and hook chaining

## How to Fix

### Option 1: Quick Fix Script (Recommended)

```bash
cd /Users/multiplicity/Work/superloop/tools/claude-code-glm/scripts
./fix-hook-format.sh
```

This script:
1. Backs up your current settings.json
2. Detects old format
3. Converts to new format automatically
4. Verifies the update

### Option 2: Re-run Installation

```bash
cd /Users/multiplicity/Work/superloop/tools/claude-code-glm/scripts
./install-mantic.sh
```

The installation script has been updated with the new format.

### Option 3: Manual Fix

Edit `~/.claude/settings.json`:

**Before:**
```json
{
  "hooks": {
    "PreToolUse": "~/mantic-grep-hook.sh"
  }
}
```

**After:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": {"tools": ["Grep"]},
        "hooks": [
          {
            "type": "command",
            "command": "~/mantic-grep-hook.sh"
          }
        ]
      }
    ]
  }
}
```

## Verification

After fixing, verify the format:

```bash
# Check settings
cat ~/.claude/settings.json | jq '.hooks.PreToolUse'

# Should output:
[
  {
    "matcher": {
      "tools": [
        "Grep"
      ]
    },
    "hooks": [
      {
        "type": "command",
        "command": "/home/user/mantic-grep-hook.sh"
      }
    ]
  }
]

# Start Claude Code - should work without errors
claude
```

## Error Messages

If you see this error:

```
Settings Error
 ~/.claude/settings.json
  └ hooks
    └ PreToolUse: Expected array, but received string
```

**Solution:** Use one of the fix options above.

## Benefits of New Format

### Tool-Specific Matching

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": {"tools": ["Grep"]},
        "hooks": [{"type": "command", "command": "~/mantic-grep-hook.sh"}]
      },
      {
        "matcher": {"tools": ["Edit"]},
        "hooks": [{"type": "command", "command": "~/relace-hook.sh"}]
      }
    ]
  }
}
```

Now you can have:
- **Mantic hook** for Grep tool only
- **Relace hook** for Edit tool only
- Both work independently!

### Multiple Hooks per Tool

```json
{
  "matcher": {"tools": ["Grep"]},
  "hooks": [
    {"type": "command", "command": "~/pre-grep-logger.sh"},
    {"type": "command", "command": "~/mantic-grep-hook.sh"},
    {"type": "command", "command": "~/post-grep-logger.sh"}
  ]
}
```

Hooks run in sequence for the matched tool.

## Integration with Relace

If you have both Mantic and Relace installed:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": {"tools": ["Grep"]},
        "hooks": [
          {
            "type": "command",
            "command": "~/mantic-grep-hook.sh"
          }
        ]
      },
      {
        "matcher": {"tools": ["Edit"]},
        "hooks": [
          {
            "type": "command",
            "command": "~/claude-code-relace-hook.sh"
          }
        ]
      }
    ]
  }
}
```

Both hooks coexist cleanly!

## Troubleshooting

### Issue: Settings file has syntax errors

```bash
# Validate JSON
jq empty ~/.claude/settings.json

# If error, restore from backup
cp ~/.claude/settings.json.backup.YYYYMMDD_HHMMSS ~/.claude/settings.json
```

### Issue: Hook not triggering after update

```bash
# Check hook is executable
chmod +x ~/mantic-grep-hook.sh

# Verify matcher
cat ~/.claude/settings.json | jq '.hooks.PreToolUse[0].matcher'

# Should show: {"tools": ["Grep"]}
```

### Issue: Claude Code won't start

```bash
# Check settings validity
jq empty ~/.claude/settings.json

# If invalid, recreate from scratch
./install-mantic.sh
```

## Learn More

Official Claude Code hooks documentation:
https://code.claude.com/docs/en/hooks

## Summary

**What to do:**
1. Run `./fix-hook-format.sh` in scripts directory
2. Verify with `jq '.hooks.PreToolUse' ~/.claude/settings.json`
3. Start Claude Code - should work!

**If you see errors:**
- Check the JSON is valid
- Verify the hook path is correct
- Ensure hook is executable
- Restore from backup if needed

**All scripts have been updated** - fresh installations will use the new format automatically.
