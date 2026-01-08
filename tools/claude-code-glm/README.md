# Quick Start - Claude Code GLM Multi-Provider Setup

Run Claude Code CLI with **GLM-4.7** via **Cerebras** (high-speed) or **Z.ai** (best pricing)!

⚠️ **Security**: All API keys in this documentation are placeholders. See [SECURITY_NOTE.md](SECURITY_NOTE.md) for key management.

## One-Liner Launch (From Mac)

```bash
orb shell claude-code-glm
```

Then inside VM:
```bash
export CEREBRAS_API_KEY="csk-your-cerebras-api-key-here"
ccr start &
sleep 3
eval "$(ccr activate)"
cd ~/superloop
claude
```

## Super Quick Version

```bash
# From Mac - all in one:
orb -m claude-code-glm -s '
  export CEREBRAS_API_KEY="csk-your-cerebras-api-key-here"
  ccr start &
  sleep 3
  eval "$(ccr activate)"
  cd ~/superloop
  claude
'
```

## Useful Commands

```bash
# VM management
orbctl list                  # Check VM status
orbctl stop claude-code-glm  # Stop VM
orbctl start claude-code-glm # Start VM

# Inside VM
ccr status                   # Router status
ccr restart                  # Restart router
tail -f ~/.claude-code-router/logs/ccr-*.log  # View logs

# Access your code
cd ~/superloop  # Your project
cd ~/work       # All projects
```

## What's Running

- **VM**: `claude-code-glm` (Ubuntu ARM64)
- **Router**: Port 3456 (localhost)
- **Providers**:
  - Cerebras GLM-4.7 (high-speed: 1000-1700 TPS)
  - Z.ai GLM-4.7 (best pricing: ~$1-2/1M tokens)
- **Code Access**: Direct mount of `/Users/multiplicity/Work`

## Switching Providers

Inside Claude Code session:
```bash
# Check current model
/status

# Use Z.ai (cheaper, recommended for daily work)
/model zai,glm-4.7

# Use Cerebras (faster, for complex tasks)
/model cerebras,zai-glm-4.7

# Use Z.ai's lighter model
/model zai,glm-4.5-air
```

**Default routing**:
- Most tasks → Z.ai (best pricing)
- Thinking/long context → Cerebras (high speed)

## Setting Up Z.ai Provider

To enable Z.ai provider (optional but recommended):

1. Get API key from https://z.ai/model-api
2. In VM, edit `~/.bashrc`:
   ```bash
   export ZAI_API_KEY="your-zai-api-key-here"
   ```
3. Reload: `source ~/.bashrc`
4. Restart router: `pkill -f ccr && ~/start-claude-router.sh`

**Current setup**: Cerebras only (Z.ai key not configured yet)

## Quick Tests

```bash
# Simple query
echo "What is 2+2?" | claude

# List files (tests tool calling)
echo "List the .md files in current directory" | claude

# Git status (tests bash tools)
echo "What is the git status?" | claude
```

## Files Modified/Created

**In VM:**
- `~/.claude-code-router/config.json` - Router config
- `~/.claude-code-router/plugins/cerebras-transformer.js` - Transformer
- `~/.bashrc` - Contains API key
- `~/start-claude-router.sh` - Helper script
- `~/setup-workspace.sh` - Workspace setup

**On Mac (in `tools/claude-code-glm/`):**
- `README.md` - This quick start file
- `SETUP_GUIDE.md` - Complete setup guide
- `MULTI_PROVIDER_SETUP.md` - Multi-provider configuration guide
- `TECHNICAL_DOCS.md` - Full technical documentation
- `TEST_RESULTS.md` - API test results
- `SETUP_STATUS.md` - Current status and troubleshooting
- `SECURITY_NOTE.md` - API key security best practices

## Status: ✅ DOCUMENTATION READY

**Next Steps:**
1. Get API keys (Cerebras and/or Z.ai)
2. Create VM with setup instructions
3. Replace placeholder keys with your own
4. Start coding with Claude Code + GLM-4.7!
