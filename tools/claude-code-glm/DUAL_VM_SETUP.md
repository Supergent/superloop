# Dual VM Setup - Cerebras & Z.ai

**Architecture:** Two separate VMs, each optimized for its provider

## Overview

You now have **two independent VMs** for Claude Code with GLM-4.7:

| VM Name | Provider | Integration | Best For | Speed | Cost |
|---------|----------|-------------|----------|-------|------|
| **claude-code-glm-cerebras** | Cerebras | Router-based | Complex tasks, high-speed | 1000-1700 TPS | $2.25-2.75/1M |
| **claude-code-glm-zai** | Z.ai | Direct (official) | Daily coding, cost savings | TBD | ~$1-2/1M |

## Why Separate VMs?

**Z.ai API Compatibility Discovery:**
- Z.ai's API is designed for **direct integration** with Claude Code
- Using it through the router caused compatibility issues:
  - System message format errors
  - Tool schema validation failures
- **Solution:** Use Z.ai's official integration method (direct, no router)

**Architecture Benefits:**
- ✅ Each provider uses its optimal integration method
- ✅ No compatibility workarounds needed
- ✅ Easy switching between providers
- ✅ Both VMs fully isolated and independent

---

## Quick Start

### Cerebras VM (High-Speed)

```bash
# Start VM and router
orb shell claude-code-glm-cerebras

# Inside VM
source ~/.bashrc
ccr start &
sleep 3
eval "$(ccr activate)"
cd ~/superloop
claude
```

**What's running:**
- Claude Code Router (port 3456)
- Custom Anthropic ↔ OpenAI transformer
- Cerebras GLM-4.7 (zai-glm-4.7 model)

### Z.ai VM (Best Pricing)

```bash
# Start VM
orb shell claude-code-glm-zai

# Inside VM
cd ~/superloop
claude
```

**What's running:**
- Claude Code directly connected to Z.ai
- No router needed (direct integration)
- Z.ai GLM-4.7 model

**Note:** You'll need to replace `your-zai-api-key-here` in `~/.claude/settings.json` with your actual Z.ai API key.

---

## Configuration Details

### Cerebras VM Configuration

**Router Config:** `~/.claude-code-router/config.json`
```json
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 300000,
  "Providers": [{
    "name": "cerebras",
    "api_base_url": "https://api.cerebras.ai/v1/chat/completions",
    "api_key": "$CEREBRAS_API_KEY",
    "models": ["zai-glm-4.7", "zai-glm-4.6", "llama3.1-8b", "llama-3.3-70b"],
    "transformer": {
      "request": "/home/multiplicity/.claude-code-router/plugins/cerebras-transformer.js::transformRequest",
      "response": "/home/multiplicity/.claude-code-router/plugins/cerebras-transformer.js::transformResponse",
      "streamChunk": "/home/multiplicity/.claude-code-router/plugins/cerebras-transformer.js::transformStreamChunk"
    }
  }],
  "Router": {
    "default": "cerebras,zai-glm-4.7"
  }
}
```

**API Key:** Set in `~/.bashrc`
```bash
export CEREBRAS_API_KEY="your-cerebras-api-key"
```

### Z.ai VM Configuration

**Claude Code Settings:** `~/.claude/settings.json`
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-zai-api-key-here",
    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
    "API_TIMEOUT_MS": "3000000",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-4.5-air",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-4.7",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-4.7"
  }
}
```

**No router needed** - Claude Code connects directly to Z.ai.

---

## Setting Up API Keys

### Cerebras API Key

Already configured! Key is in the VM's `~/.bashrc`.

If you need to update it:
```bash
orb shell claude-code-glm-cerebras
nano ~/.bashrc
# Update CEREBRAS_API_KEY value
source ~/.bashrc
ccr restart
```

### Z.ai API Key

**Get your key:**
1. Visit https://z.ai/model-api
2. Register/Login
3. Create API Key at https://z.ai/manage-apikey/apikey-list
4. Copy your key

**Configure in VM:**
```bash
orb shell claude-code-glm-zai
nano ~/.claude/settings.json
# Replace "your-zai-api-key-here" with your actual key
# Save and exit
```

**Verify:**
```bash
cd ~/superloop
claude
# Should connect to Z.ai without errors
```

---

## Switching Between Providers

### Option 1: Terminal per Provider (Recommended)

Keep two terminals open:

**Terminal 1 - Cerebras (High-Speed):**
```bash
orb shell claude-code-glm-cerebras
source ~/.bashrc && ccr start &
sleep 3 && eval "$(ccr activate)"
cd ~/superloop && claude
```

**Terminal 2 - Z.ai (Best Pricing):**
```bash
orb shell claude-code-glm-zai
cd ~/superloop && claude
```

### Option 2: One-Liner Switching

```bash
# Use Cerebras
orb shell claude-code-glm-cerebras

# Exit and switch to Z.ai
exit
orb shell claude-code-glm-zai
```

### Option 3: Mac Aliases (Convenience)

Add to your `~/.zshrc` or `~/.bashrc` on Mac:

```bash
# Claude Code with Cerebras (high-speed)
alias claude-fast='orb shell claude-code-glm-cerebras'

# Claude Code with Z.ai (best pricing)
alias claude-cheap='orb shell claude-code-glm-zai'
```

Then just use:
```bash
claude-fast  # High-speed development
claude-cheap # Cost-effective coding
```

---

## Verification

### Check Cerebras VM

```bash
orb shell claude-code-glm-cerebras

# Check router
ccr status  # Should show: Running

# Check providers
grep "cerebras provider registered" ~/.claude-code-router/logs/ccr-*.log | tail -1
```

### Check Z.ai VM

```bash
orb shell claude-code-glm-zai

# Check Claude Code settings
cat ~/.claude/settings.json | grep ANTHROPIC_BASE_URL
# Should show: https://api.z.ai/api/anthropic

# Check router is NOT running
ccr status  # Should show: Not Running (this is correct!)
```

---

## Troubleshooting

### Cerebras VM Issues

**Router not starting:**
```bash
# Check logs
tail -50 ~/.claude-code-router/logs/ccr-*.log

# Restart router
pkill -f ccr
source ~/.bashrc
ccr start
```

**API key issues:**
```bash
# Verify key is set
echo $CEREBRAS_API_KEY

# If empty, reload bashrc
source ~/.bashrc
```

### Z.ai VM Issues

**"Insufficient balance" error:**
- Fund your Z.ai account at https://z.ai/manage-apikey/apikey-list
- Minimum recharge required to use the API

**API key not working:**
```bash
# Verify settings
cat ~/.claude/settings.json

# Make sure key is correct (no quotes issues)
nano ~/.claude/settings.json
```

**Want to use router anyway:**
- Not recommended - Z.ai designed for direct integration
- If needed, use Cerebras VM instead

---

## Performance Comparison

Based on actual usage:

### Cerebras VM
- **Speed:** 1000-1700 tokens/sec ⚡
- **Cost:** $2.25 input, $2.75 output per 1M tokens
- **Latency:** 30-200ms typical
- **Tool Calling:** #1 ranked (Berkeley leaderboard)
- **Best for:** Complex reasoning, large codebases, time-sensitive debugging

### Z.ai VM
- **Speed:** TBD (test after funding)
- **Cost:** ~$1-2 per 1M tokens (with promotions)
- **Latency:** TBD
- **Tool Calling:** GLM-4.7 (same model as Cerebras)
- **Best for:** Daily coding, learning, experimentation, cost optimization

### Cost Example (1M tokens)

**Cerebras:** ~$5.00
**Z.ai:** ~$1.50 (estimated with promos)
**Savings:** 70% cheaper with Z.ai!

---

## Recommended Workflow

### Daily Development (Z.ai VM)
```bash
# Morning: start Z.ai VM for routine work
claude-cheap  # or: orb shell claude-code-glm-zai
cd ~/superloop
claude

# All day coding, testing, small features
# Low cost, good performance
```

### Complex Tasks (Cerebras VM)
```bash
# When you need speed:
claude-fast  # or: orb shell claude-code-glm-cerebras
source ~/.bashrc && ccr start &
sleep 3 && eval "$(ccr activate)"
cd ~/superloop
claude

# Large refactors, debugging, performance-critical work
# Maximum speed, worth the higher cost
```

### Hybrid Approach
- Start day with Z.ai (cheap)
- Switch to Cerebras when hitting complex problems (fast)
- Return to Z.ai for routine follow-up work (cheap)

---

## VM Management

### List All VMs
```bash
orbctl list
```

### Start/Stop Specific VM
```bash
# Start Cerebras
orbctl start claude-code-glm-cerebras

# Stop Cerebras
orbctl stop claude-code-glm-cerebras

# Start Z.ai
orbctl start claude-code-glm-zai

# Stop Z.ai
orbctl stop claude-code-glm-zai
```

### Stop All VMs
```bash
orbctl stop --all
```

### Delete a VM (Careful!)
```bash
# Only if you want to remove completely
orbctl delete claude-code-glm-cerebras
# or
orbctl delete claude-code-glm-zai
```

---

## File Access

Both VMs have access to the same files:

```bash
# In either VM:
~/superloop → /Users/multiplicity/Work/superloop
~/work      → /Users/multiplicity/Work

# Changes in one VM are visible in the other
# (They're both accessing the same Mac filesystem)
```

---

## Summary

✅ **Two independent VMs ready to use**
✅ **Cerebras:** High-speed via router (working now)
✅ **Z.ai:** Best pricing via direct integration (needs API key funding)
✅ **Easy switching:** Just different `orb shell` commands
✅ **Fully isolated:** Each uses optimal integration method
✅ **Cost effective:** Use Z.ai for 70% savings on routine work

**Next Steps:**
1. Fund Z.ai account: https://z.ai/manage-apikey/apikey-list
2. Update Z.ai API key in `claude-code-glm-zai` VM
3. Test both VMs with your actual projects
4. Develop workflow that leverages both providers' strengths

---

**Status:** Both VMs configured and ready. Cerebras tested and working. Z.ai awaiting API key funding. 🚀
