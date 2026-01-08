# Multi-Provider Setup Status

**Last Updated**: 2026-01-08
**VM**: claude-code-glm (OrbStack Ubuntu ARM64)
**Router Version**: @musistudio/claude-code-router
**Status**: ✅ OPERATIONAL (Cerebras only)

---

## Current Configuration

### Active Providers

| Provider | Status | API Key | Model | Notes |
|----------|--------|---------|-------|-------|
| **Cerebras** | ✅ Operational | Configured | zai-glm-4.7 | Primary provider, fully tested |
| **Z.ai** | ⚠️ Configured but inactive | Configured | glm-4.7 | Two blockers (see below) |

### Router Settings

All task types currently route to Cerebras:

```json
{
  "default": "cerebras,zai-glm-4.7",
  "background": "cerebras,zai-glm-4.7",
  "think": "cerebras,zai-glm-4.7",
  "longContext": "cerebras,zai-glm-4.7"
}
```

---

## Provider Details

### Cerebras Provider ✅

**Configuration:**
- API Endpoint: `https://api.cerebras.ai/v1/chat/completions`
- API Key: Set in `$CEREBRAS_API_KEY` (VM bashrc)
- Models Available: `zai-glm-4.7`, `zai-glm-4.6`, `llama3.1-8b`, `llama-3.3-70b`
- Transformer: Custom Anthropic ↔ OpenAI format converter

**Performance:**
- Speed: 1000-1700 tokens/sec
- Cost: $2.25-2.75 per 1M tokens
- Tool Calling: #1 ranked on Berkeley Function Calling Leaderboard
- Context Window: 131k tokens

**Status:** Fully operational and tested.

### Z.ai Provider ⚠️

**Configuration:**
- API Endpoint: `https://api.z.ai/api/anthropic/v1/messages`
- API Key: Set in `$ZAI_API_KEY` (VM bashrc)
- Models Available: `glm-4.7`, `glm-4.5-air`
- Transformer: None (claimed Anthropic-native)

**Blockers (2):**

1. **Insufficient Balance** ❌
   ```json
   {
     "error": {
       "code": "1113",
       "message": "Insufficient balance or no resource package. Please recharge."
     }
   }
   ```
   **Resolution Required:** Fund Z.ai account at https://z.ai/manage-apikey/apikey-list

2. **API Compatibility Issues** ❌
   - Rejects `role: "system"` messages (expects only "user" or "assistant")
   - Tool schema validation failures (expects `name` at top level, not nested in `function`)
   - May not be fully Anthropic-compatible despite documentation claims

   **Example Error:**
   ```json
   {
     "detail": [
       {
         "type": "literal_error",
         "loc": ["body", "messages", 0, "role"],
         "msg": "Input should be 'user' or 'assistant'",
         "input": "system"
       },
       {
         "type": "missing",
         "loc": ["body", "tools", 0, "name"],
         "msg": "Field required"
       }
     ]
   }
   ```

**Status:** Configured but not usable until both blockers resolved.

---

## Files Created/Modified

### In VM (`claude-code-glm`)

| File | Size | Purpose |
|------|------|---------|
| `~/.claude-code-router/config.json` | 2.4KB | Multi-provider router configuration |
| `~/.claude-code-router/plugins/cerebras-transformer.js` | 10KB | Anthropic ↔ OpenAI format transformer |
| `~/.bashrc` | Updated | API keys: `CEREBRAS_API_KEY`, `ZAI_API_KEY` |
| `~/start-claude-router.sh` | 1.5KB | Router startup script with provider checks |
| `~/setup-workspace.sh` | 185B | Workspace symlink creation |

### On Mac (`tools/claude-code-glm/`)

| File | Size | Purpose |
|------|------|---------|
| `README.md` | 3.1KB | Quick start guide |
| `SETUP_GUIDE.md` | 8.5KB | Complete VM setup walkthrough |
| `TECHNICAL_DOCS.md` | 33KB | Full technical specification |
| `TEST_RESULTS.md` | 7.6KB | API validation results |
| `MULTI_PROVIDER_SETUP.md` | 7.8KB | Multi-provider configuration guide |
| `SETUP_STATUS.md` | This file | Current setup status |
| `test-cerebras-api.sh` | 3.2KB | API testing script |

---

## Git Commits

Two commits created documenting this work:

1. **687613f** - Initial Cerebras integration
   - VM setup with OrbStack
   - Transformer implementation
   - Complete documentation

2. **e21b863** - Multi-provider support
   - Added Z.ai provider configuration
   - Smart task-based routing
   - Updated documentation for dual-provider setup

**Status:** Ready to push (not yet pushed to remote)

---

## How to Use

### Start the Environment

From Mac:
```bash
orb shell claude-code-glm
```

Inside VM:
```bash
export CEREBRAS_API_KEY="csk-your-cerebras-api-key-here"
export ZAI_API_KEY="your-zai-api-key-here"
ccr start &
sleep 3
eval "$(ccr activate)"
cd ~/superloop
claude
```

### Check Status

```bash
# Router status
ccr status

# View logs
tail -f ~/.claude-code-router/logs/ccr-*.log

# Check providers
grep "provider registered" ~/.claude-code-router/logs/ccr-*.log
```

### Switch Models (when Z.ai is active)

Inside Claude Code session:
```bash
# Use Cerebras (current default)
/model cerebras,zai-glm-4.7

# Use Z.ai (when available)
/model zai,glm-4.7

# Check current model
/status
```

---

## Next Steps

### To Activate Z.ai Provider:

1. **Fund Z.ai Account**
   - Visit: https://z.ai/manage-apikey/apikey-list
   - Add balance or purchase resource package
   - Use your Z.ai API key

2. **Investigate API Compatibility**
   - Test direct API calls after funding
   - May require custom transformer similar to Cerebras
   - Contact Z.ai support if issues persist

3. **Update Router Config**
   - Once Z.ai works, update `Router` section in config.json
   - Set Z.ai as default for cost savings
   - Keep Cerebras for high-speed tasks

### Optional:

- **Push Git Commits**: `git push origin main`
- **Rotate API Keys**: Before public sharing, rotate keys in TEST_RESULTS.md
- **Add to .gitignore**: Consider excluding `*TEST_RESULTS.md` with sensitive keys

---

## Performance Comparison

When both providers are operational:

| Metric | Cerebras | Z.ai (Estimated) |
|--------|----------|------------------|
| Speed | 1000-1700 TPS | Unknown |
| Cost (1M tokens) | $2.25-2.75 | ~$1-2 (claimed) |
| Context Window | 131k | Unknown |
| Tool Calling | #1 ranked | Unknown |
| API Format | OpenAI (needs transformer) | Anthropic (claimed) |
| Current Status | ✅ Working | ⚠️ Blocked |

---

## Troubleshooting

### Router Not Starting

```bash
# Check if already running
ccr status

# Kill existing instance
pkill -f ccr

# Restart
~/start-claude-router.sh
```

### Provider Not Working

```bash
# Check API keys are set
echo $CEREBRAS_API_KEY
echo $ZAI_API_KEY

# View recent errors
tail -50 ~/.claude-code-router/logs/ccr-*.log | grep error

# Test API directly
curl -X POST https://api.cerebras.ai/v1/chat/completions \
  -H "Authorization: Bearer $CEREBRAS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"zai-glm-4.7","messages":[{"role":"user","content":"test"}],"max_tokens":10}'
```

### Claude Code Not Connecting

```bash
# Verify router is active
ccr status

# Check activation
eval "$(ccr activate)"
echo $ANTHROPIC_API_KEY  # Should show router endpoint

# Restart Claude Code
exit  # Exit current session
claude  # Start new session
```

---

## Summary

**What's Working:**
- ✅ OrbStack VM fully configured and isolated
- ✅ Cerebras provider operational (1000-1700 TPS)
- ✅ Custom transformer handling API format conversion
- ✅ Tool calling verified and working
- ✅ Multi-provider architecture ready
- ✅ Complete documentation suite

**What Needs Attention:**
- ⚠️ Z.ai account needs funding ($1-2 estimated)
- ⚠️ Z.ai API compatibility issues to resolve
- 📋 Optional: Git commits ready to push

**Current Recommendation:**
Use Cerebras provider for all Claude Code work. Fast, reliable, and significantly cheaper than Anthropic's Claude Sonnet ($2.25-2.75/1M vs ~$15/1M for Claude).

When Z.ai becomes operational, it may offer even better pricing (~$1-2/1M), making it ideal for routine development work while keeping Cerebras for complex reasoning tasks.

---

**Status**: Ready for production use with Cerebras provider. 🚀
