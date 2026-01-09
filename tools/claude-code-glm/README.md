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

## ⚡ NEW: Relace Instant Apply Integration

Make edits **3-5x faster and 50% cheaper** with abbreviated code snippets!

**What it does:** Instead of rewriting entire files, Claude outputs abbreviated snippets with `// ... rest of code ...` markers. Relace merges them at 10k+ tok/s.

**Quick Setup (5 minutes):**

```bash
# SSH into your VM
orb -m claude-code-glm-cerebras  # or -zai

# Run one command
cd /Users/multiplicity/Work/superloop/tools/claude-code-glm/scripts
./quick-setup.sh

# Done! Start using Claude Code
~/start-claude-isolated.sh
```

**Features:**
- ✅ Automatic detection - uses Relace for large files (>100 lines)
- ✅ Multiple toggle options - disable globally, per-project, or per-session
- ✅ Performance logging - track speed and cost savings
- ✅ Graceful fallback - never breaks your workflow

**Documentation:**
- 📘 [START_HERE.md](START_HERE.md) - Super simple setup
- 📖 [RELACE_QUICKSTART.md](RELACE_QUICKSTART.md) - 5-minute guide
- 📚 [RELACE_INTEGRATION.md](RELACE_INTEGRATION.md) - Complete documentation

**Toggle Commands:**
```bash
claude-relace-off      # Disable
claude-relace-on       # Enable
claude-relace-status   # Check status
claude-relace-logs     # View logs
claude-relace-costs    # See savings
```

**Performance:** 107-line file edited in 1s (1,648 tok/s) for $0.0016 ✨

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

## Common Issues

### API Error 422: "body.reasoning: property 'body.reasoning' is unsupported"

**Solution:** This is fixed by the local proxy that ships with the Cerebras VM setup. The proxy automatically strips the unsupported reasoning parameter before forwarding to Cerebras.

**Already configured:**
- Proxy: `~/cerebras-proxy.js` (runs on port 8080)
- Startup script: `~/start-claude-isolated.sh` (launches proxy automatically)
- No manual configuration needed!

**If proxy fails:**
```bash
# Check logs
tail /tmp/cerebras-proxy.log

# Restart everything
pkill -f cerebras-proxy && pkill -f ccr
~/start-claude-isolated.sh
```

**Technical details:** See [REASONING_PARAMETER_FIX.md](REASONING_PARAMETER_FIX.md) for architecture and troubleshooting.

### Other Issues

- Router not starting → Check logs: `tail ~/.claude-code-router/logs/ccr-*.log`
- Files being modified on Mac → Switch to isolated mode: `~/start-claude-isolated.sh`
- Z.ai balance error → Fund account at https://z.ai/manage-apikey/apikey-list

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
- `FILESYSTEM_ISOLATION.md` - **CRITICAL: Read this first!** ⭐
- `REASONING_PARAMETER_FIX.md` - **Proxy solution for API 422 errors** ⭐
- `DUAL_VM_SETUP.md` - Complete dual-VM setup guide
- `SETUP_GUIDE.md` - Original single-VM setup (Cerebras)
- `MULTI_PROVIDER_SETUP.md` - Router-based multi-provider config
- `TECHNICAL_DOCS.md` - Full technical documentation
- `TEST_RESULTS.md` - API test results
- `SETUP_STATUS.md` - Current status and troubleshooting
- `SECURITY_NOTE.md` - API key security best practices
- `test-cerebras-api.sh` - API testing script
- `archive/` - Failed troubleshooting attempts (reference only)
- **Relace Integration:** ⭐ NEW
  - `START_HERE.md` - **Super simple setup guide**
  - `RELACE_QUICKSTART.md` - 5-minute quickstart
  - `RELACE_INTEGRATION.md` - Comprehensive documentation
  - `IMPLEMENTATION_COMPLETE.md` - Implementation summary
  - `TROUBLESHOOT_VM_STARTUP.md` - VM startup troubleshooting
  - `scripts/` - Installation and hook scripts

## Status: ✅ COMPLETE & PRODUCTION-READY

**Ready to Use:**
- ✅ Cerebras VM: Configured and tested
- ✅ Relace Integration: Installed and working (3-5x faster edits!)
- ⏳ Z.ai VM: Configured, needs API key funding

**Next Steps:**
1. **READ [FILESYSTEM_ISOLATION.md](FILESYSTEM_ISOLATION.md)** - Critical for safe usage! ⭐
2. **Optional: Install Relace** - Run `scripts/quick-setup.sh` in VM for 3-5x faster edits
3. Fund Z.ai account: https://z.ai/manage-apikey/apikey-list
4. Add Z.ai API key to `claude-code-glm-zai` VM
5. Test both VMs with isolated mode: `~/start-claude-isolated.sh`
6. Develop workflow leveraging both providers!
