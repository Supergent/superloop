# Quick Start - Claude Code GLM Dual-VM Setup

Run Claude Code CLI with **GLM-4.7** via **two specialized VMs**:
- 🚀 **Cerebras** (high-speed: 1000-1700 TPS)
- 💰 **Z.ai** (best pricing: ~$1-2/1M tokens)

⚠️ **Security**: All API keys in this documentation are placeholders. See [SECURITY_NOTE.md](SECURITY_NOTE.md) for key management.

🚨 **CRITICAL - Filesystem Isolation**: OrbStack VMs share your Mac filesystem by default! Claude Code can modify your actual Mac files. **READ [FILESYSTEM_ISOLATION.md](FILESYSTEM_ISOLATION.md) before using** to protect your files.

📖 **Complete Guide**: See [DUAL_VM_SETUP.md](DUAL_VM_SETUP.md) for detailed dual-VM documentation.

## Quick Launch

### Cerebras VM (High-Speed Development)

**Isolated Mode (Recommended - Safe):**
```bash
# From Mac
orb -m claude-code-glm-cerebras

# Inside VM
~/start-claude-isolated.sh
```

**Shared Mode (Advanced - Mac files at risk):**
```bash
# From Mac
orb -m claude-code-glm-cerebras

# Inside VM
source ~/.bashrc && ccr start &
sleep 3 && eval "$(ccr activate)"
cd ~/superloop && claude
```

**Best for:** Complex tasks, large refactors, debugging
**See:** [FILESYSTEM_ISOLATION.md](FILESYSTEM_ISOLATION.md) for details on isolated vs shared modes

### Z.ai VM (Cost-Effective Coding)

```bash
# From Mac
orb -m claude-code-glm-zai

# Inside VM (isolated mode recommended)
~/start-claude-isolated.sh
```

**Best for:** Daily coding, learning, routine development
**Note:** Requires Z.ai API key configuration (see [DUAL_VM_SETUP.md](DUAL_VM_SETUP.md))

## Architecture Overview

**Two Independent VMs:**

| VM | Provider | Method | Speed | Cost |
|----|----------|--------|-------|------|
| `claude-code-glm-cerebras` | Cerebras | Router + Transformer | 1000-1700 TPS | $2.25-2.75/1M |
| `claude-code-glm-zai` | Z.ai | Direct (official) | TBD | ~$1-2/1M |

**Why Separate VMs?**
- Z.ai uses direct integration (no router) per official docs
- Cerebras requires custom transformer via router
- Each VM optimized for its provider's integration method
- Easy switching, no compatibility issues

## Useful Commands

```bash
# VM management
orbctl list                           # List all VMs
orbctl start claude-code-glm-cerebras # Start Cerebras VM
orbctl start claude-code-glm-zai      # Start Z.ai VM
orbctl stop --all                     # Stop all VMs

# Inside Cerebras VM
ccr status                            # Router status
ccr restart                           # Restart router
tail -f ~/.claude-code-router/logs/ccr-*.log  # View logs

# Inside Z.ai VM
cat ~/.claude/settings.json           # View Claude Code config
# No router needed for Z.ai!

# Access your code (both VMs)
cd ~/vm-projects/superloop  # Isolated project (safe)
# Avoid: cd ~/superloop or ~/work (deprecated, shared with Mac)
```

## What's Running

### Cerebras VM
- **Router**: Port 3456 (Claude Code Router)
- **Transformer**: Custom Anthropic ↔ OpenAI converter
- **Model**: Cerebras GLM-4.7 (zai-glm-4.7)
- **Speed**: 1000-1700 TPS
- **Tool Calling**: #1 ranked

### Z.ai VM
- **Direct Integration**: No router, Claude Code → Z.ai API
- **Models**: GLM-4.7 (Sonnet/Opus), GLM-4.5-Air (Haiku)
- **Config**: `~/.claude/settings.json`
- **Method**: Official Z.ai integration per their docs

**Both VMs:**
- **Code Access**: Isolated copy in `~/vm-projects/superloop` (recommended)
- **Filesystem**: Can access Mac files at `/Users/multiplicity/Work` (use with caution)
- **Ubuntu**: ARM64, OrbStack VMs
- **Isolated**: Independent configurations
- **Safety**: See [FILESYSTEM_ISOLATION.md](FILESYSTEM_ISOLATION.md) for safe usage

## Switching Between VMs

**Method 1: Different Terminals**
```bash
# Terminal 1 - Cerebras
orb -m claude-code-glm-cerebras

# Terminal 2 - Z.ai
orb -m claude-code-glm-zai
```

**Method 2: Exit and Switch**
```bash
# In VM
exit

# Switch to other VM
orb -m claude-code-glm-cerebras
# or
orb -m claude-code-glm-zai
```

**Method 3: Mac Aliases (add to ~/.zshrc)**
```bash
alias claude-fast='orb -m claude-code-glm-cerebras'
alias claude-cheap='orb -m claude-code-glm-zai'
```

## Setting Up Z.ai (Required for Z.ai VM)

1. Get API key from https://z.ai/model-api
2. Fund account at https://z.ai/manage-apikey/apikey-list
3. Configure in VM:
   ```bash
   orb -m claude-code-glm-zai
   nano ~/.claude/settings.json
   # Replace "your-zai-api-key-here" with actual key
   ```
4. Test:
   ```bash
   ~/start-claude-isolated.sh
   ```

**Status**: Cerebras VM ready. Z.ai VM needs API key funding.

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
- `~/start-claude-router.sh` - Helper script (shared mode)
- `~/start-claude-isolated.sh` - Isolated mode startup ⭐ RECOMMENDED
- `~/vm-projects/superloop/` - Isolated project copy (safe)
- `~/setup-workspace.sh` - Workspace setup (deprecated)

**On Mac (in `tools/claude-code-glm/`):**
- `README.md` - This quick start file
- `FILESYSTEM_ISOLATION.md` - **CRITICAL: Read this first!** ⭐ NEW
- `DUAL_VM_SETUP.md` - Complete dual-VM setup guide
- `SETUP_GUIDE.md` - Original single-VM setup (Cerebras)
- `MULTI_PROVIDER_SETUP.md` - Router-based multi-provider config
- `TECHNICAL_DOCS.md` - Full technical documentation
- `TEST_RESULTS.md` - API test results
- `SETUP_STATUS.md` - Current status and troubleshooting
- `SECURITY_NOTE.md` - API key security best practices
- `test-cerebras-api.sh` - API testing script

## Status: ✅ DUAL-VM SETUP COMPLETE

**Ready to Use:**
- ✅ Cerebras VM: Configured and tested
- ⏳ Z.ai VM: Configured, needs API key funding

**Next Steps:**
1. **READ [FILESYSTEM_ISOLATION.md](FILESYSTEM_ISOLATION.md)** - Critical for safe usage! ⭐
2. Fund Z.ai account: https://z.ai/manage-apikey/apikey-list
3. Add Z.ai API key to `claude-code-glm-zai` VM
4. Test both VMs with isolated mode: `~/start-claude-isolated.sh`
5. Develop workflow leveraging both providers!
