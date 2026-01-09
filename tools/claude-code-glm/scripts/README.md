# Relace Integration Scripts

This directory contains all scripts needed to integrate Relace instant apply with Claude Code GLM.

## Files

### Core Scripts

| File | Description | Usage |
|------|-------------|-------|
| `relace-hook.sh` | Production-ready hook script that intercepts Edit tool calls | Auto-executed by Claude Code |
| `install-relace.sh` | One-command installer for VM setup | `./install-relace.sh --api-key "your-key"` |
| `test-relace-hook.sh` | Test suite for validation | `./test-relace-hook.sh` |

### Configuration

| File | Description |
|------|-------------|
| `relace-config-template.json` | Claude Code settings template |

## Quick Start

### 1. Install

```bash
# In your VM (Cerebras or Z.ai)
cd ~/superloop/tools/claude-code-glm/scripts
./install-relace.sh --api-key "your-relace-api-key"
source ~/.bashrc
```

### 2. Test

```bash
./test-relace-hook.sh
```

### 3. Use

```bash
claude
# Claude will now use Relace for abbreviated snippets automatically
```

## Script Details

### relace-hook.sh

**Purpose:** PreToolUse hook that intercepts Edit tool calls, detects abbreviated snippets, calls Relace API, and modifies tool input.

**Features:**
- Multiple toggle mechanisms (env var, project-level, file-size)
- Automatic fallback on errors
- Performance logging
- Cost tracking
- Comprehensive error handling
- Debug mode

**Environment Variables:**

```bash
RELACE_API_KEY              # Your API key (required)
RELACE_ENABLED=true         # Enable/disable (default: true)
RELACE_MIN_FILE_SIZE=100    # Min file size (default: 100 lines)
RELACE_TIMEOUT=30           # API timeout (default: 30s)
RELACE_DEBUG=false          # Debug logging (default: false)
RELACE_COST_TRACKING=true   # Cost tracking (default: true)
```

**Exit Codes:**
- `0` - Success or fallback (allow tool execution)
- `2` - Block tool execution (with error message)

**Logs:**
- Performance: `~/.claude/relace-logs/performance.log`
- Costs: `~/.claude/relace-logs/costs.csv`
- Errors: `~/.claude/relace-logs/errors.log`

### install-relace.sh

**Purpose:** Automated installer that sets up everything needed for Relace integration.

**What It Does:**
1. Installs dependencies (jq, curl)
2. Copies hook script to `~/claude-code-relace-hook.sh`
3. Configures `~/.claude/settings.json` with hooks
4. Sets up environment variables in `~/.bashrc`
5. Creates helper aliases
6. Runs validation tests

**Options:**

```bash
./install-relace.sh [options]

Options:
  --api-key KEY       Set Relace API key
  --vm cerebras|zai   Install for specific VM (default: current)
  --no-backup         Skip backup of existing settings
  --debug             Enable debug mode
  --help              Show help message
```

**Examples:**

```bash
# Basic install
./install-relace.sh --api-key "sk-..."

# Install without backups
./install-relace.sh --api-key "sk-..." --no-backup

# Get help
./install-relace.sh --help
```

### test-relace-hook.sh

**Purpose:** Comprehensive test suite to validate hook installation and functionality.

**Tests:**
1. Hook script exists
2. Hook script is executable
3. Dependencies installed (jq, curl)
4. API key configured
5. Abbreviated snippet processing
6. Full replacement pass-through
7. Disabled hook behavior
8. Small file threshold
9. `.no-relace` file detection

**Options:**

```bash
./test-relace-hook.sh [options]

Options:
  --file PATH         Test file path (default: /tmp/test-relace.js)
  --snippet           Use abbreviated snippet (default)
  --full              Use full replacement (no abbreviation)
  --debug             Enable debug output
  --help              Show help
```

**Examples:**

```bash
# Run all tests
./test-relace-hook.sh

# Run with debug output
./test-relace-hook.sh --debug

# Test specific file
./test-relace-hook.sh --file /path/to/my-file.js
```

## Helper Aliases

After installation, these aliases are available:

```bash
# Toggle
claude-relace-on          # Enable Relace
claude-relace-off         # Disable Relace
claude-relace-status      # Check status

# Debug
claude-relace-debug-on    # Enable debug logging
claude-relace-debug-off   # Disable debug logging

# Monitoring
claude-relace-logs        # Watch logs in real-time
claude-relace-costs       # View cost tracking
```

## Configuration File

### relace-config-template.json

Complete Claude Code settings configuration with:
- PreToolUse hook for Edit tool
- System prompt with abbreviation instructions
- Examples for TypeScript and Python

Can be used to manually configure or as reference.

## Workflow

### Installation Workflow

```
1. Get Relace API key from https://app.relace.ai
2. SSH into VM: orb -m claude-code-glm-cerebras
3. cd ~/superloop/tools/claude-code-glm/scripts
4. ./install-relace.sh --api-key "your-key"
5. source ~/.bashrc
6. ./test-relace-hook.sh
7. claude  # Start using!
```

### Daily Usage

```
# Normal usage (Relace enabled by default)
claude

# Disable for specific session
claude-relace-off
claude

# Re-enable
claude-relace-on
claude

# Monitor performance
claude-relace-logs  # In another terminal
```

### Debugging Workflow

```
# Enable debug mode
claude-relace-debug-on

# Start Claude Code
claude

# Watch logs in another terminal
claude-relace-logs

# Try an edit
# (In Claude Code, ask to edit a large file)

# Check for issues
tail -20 ~/.claude/relace-logs/errors.log

# Disable debug when done
claude-relace-debug-off
```

## Troubleshooting

### Hook not executing

```bash
# Check hook exists and is executable
ls -la ~/claude-code-relace-hook.sh
chmod +x ~/claude-code-relace-hook.sh

# Verify settings.json
cat ~/.claude/settings.json | jq '.hooks.PreToolUse'

# Run test suite
./test-relace-hook.sh
```

### API errors

```bash
# Check API key
echo $RELACE_API_KEY

# Test API directly
curl -X POST https://instantapply.endpoint.relace.run/v1/code/apply \
  -H "Authorization: Bearer $RELACE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"initial_code": "test", "edit_snippet": "// ... test ..."}'

# Check error logs
cat ~/.claude/relace-logs/errors.log
```

### Settings conflicts

```bash
# Backup current settings
cp ~/.claude/settings.json ~/.claude/settings.json.backup

# Reinstall (will merge with existing)
./install-relace.sh --api-key "$RELACE_API_KEY"

# Or manually edit
nano ~/.claude/settings.json
```

## Advanced Usage

### Custom Hook Modifications

Edit `~/claude-code-relace-hook.sh` to customize:

**Disable for specific file types:**

```bash
# Around line 200
FILE_EXT="${FILE_PATH##*.}"
case "$FILE_EXT" in
    md|txt|json)
        exit 0  # Skip Relace
        ;;
esac
```

**Different thresholds by project:**

```bash
# Check project path
if [[ "$FILE_PATH" == *"/my-project/"* ]]; then
    RELACE_MIN_FILE_SIZE=50  # Lower threshold
fi
```

**Custom abbreviation markers:**

```bash
# Change ABBREVIATION_MARKERS regex
ABBREVIATION_MARKERS='(TODO|FIXME|...|your-custom-marker)'
```

### Performance Tuning

```bash
# Aggressive mode (use Relace more often)
export RELACE_MIN_FILE_SIZE=50

# Conservative mode (use Relace less often)
export RELACE_MIN_FILE_SIZE=200

# Faster timeout (risky for large files)
export RELACE_TIMEOUT=15

# Slower timeout (safer for large files)
export RELACE_TIMEOUT=60
```

### Multi-VM Setup

```bash
# Install in Cerebras VM
orb -m claude-code-glm-cerebras
cd ~/superloop/tools/claude-code-glm/scripts
./install-relace.sh --api-key "your-key"
exit

# Install in Z.ai VM
orb -m claude-code-glm-zai
cd ~/superloop/tools/claude-code-glm/scripts
./install-relace.sh --api-key "your-key"
exit

# Both VMs now have independent Relace integration
```

## Files Created by Installation

```
~/claude-code-relace-hook.sh           # Hook script
~/.claude/settings.json                # Updated with hooks
~/.bashrc                              # Updated with env vars and aliases
~/.claude/relace-logs/                 # Log directory
~/.claude/relace-logs/performance.log  # Performance metrics
~/.claude/relace-logs/costs.csv        # Cost tracking
~/.claude/relace-logs/errors.log       # Error log
```

## Uninstall

```bash
# Remove hook script
rm ~/claude-code-relace-hook.sh

# Remove configuration from ~/.bashrc
nano ~/.bashrc
# Delete "Relace Instant Apply Configuration" section

# Remove hooks from settings.json
nano ~/.claude/settings.json
# Delete Edit hook from PreToolUse array

# Remove logs
rm -rf ~/.claude/relace-logs

# Reload shell
source ~/.bashrc
```

## Documentation

- **Quick Start:** `../RELACE_QUICKSTART.md` - 5-minute setup guide
- **Complete Guide:** `../RELACE_INTEGRATION.md` - Comprehensive documentation
- **Main README:** `../README.md` - Claude Code GLM overview

## Support & Resources

- **Relace Docs:** https://docs.relace.ai/
- **Claude Code Hooks:** https://code.claude.com/docs/en/hooks
- **Issue Tracker:** Report issues in your project tracker

---

**Version:** 1.0.0
**Last Updated:** 2026-01-08
