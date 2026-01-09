# VM Startup Troubleshooting

## Problem: "Invalid API key" in Cerebras VM

This happens because Claude Code needs to connect to your router first.

## Quick Fix

Exit Claude Code (Ctrl+C or type `exit`) and run:

```bash
# Start the router and set up environment
ccr start
sleep 3
eval "$(ccr activate)"

# Now start Claude Code
claude
```

## Or Use the Startup Script

```bash
# Exit Claude Code first, then:
~/start-claude-isolated.sh
```

This script automatically:
- Starts the router
- Activates the environment
- Starts Claude Code in isolated mode

## What's Happening?

Your Cerebras VM setup routes Claude Code through a local router on port 3456:

```
Claude Code → Router (localhost:3456) → Cerebras API
```

The router needs to be running and the environment variables set before Claude Code starts.

## Verify Router is Running

```bash
ccr status
```

Should show: "Router is running on http://127.0.0.1:3456"

## Manual Setup (If Needed)

```bash
# 1. Start router
ccr start

# 2. Wait for it to start
sleep 3

# 3. Set environment variables
eval "$(ccr activate)"

# This sets:
# - ANTHROPIC_BASE_URL=http://127.0.0.1:3456
# - ANTHROPIC_AUTH_TOKEN=<from config>
# - NO_PROXY=127.0.0.1

# 4. Start Claude Code
claude
```

## For Relace Setup

After you get Claude Code working:

```bash
cd ~/superloop/tools/claude-code-glm/scripts
./quick-setup.sh
```

The Relace hook will work alongside your existing router setup!

## Quick Reference

```bash
# Check router status
ccr status

# Restart router if needed
ccr restart

# View router logs
tail -f ~/.claude-code-router/logs/ccr-*.log

# Start everything (easiest)
~/start-claude-isolated.sh
```
