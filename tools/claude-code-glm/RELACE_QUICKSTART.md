# Relace Integration Quick Start

> Make Claude Code edits 3-5x faster and cheaper with abbreviated snippets

## What is This?

Relace instant apply allows Claude to output abbreviated code snippets with `// ... rest of code ...` markers instead of rewriting entire files. A lightweight model (10k+ tok/s) merges the snippet with your original file automatically.

**Result:** 3-5x faster edits, 50%+ cost savings.

## Installation (5 minutes)

### Step 1: Get Relace API Key

1. Sign up at https://app.relace.ai
2. Create API key at https://app.relace.ai/settings/api-keys
3. Copy the key

### Step 2: Install in Your VM

```bash
# SSH into your Cerebras or Z.ai VM
orb -m claude-code-glm-cerebras  # or claude-code-glm-zai

# Navigate to the scripts directory
cd ~/superloop/tools/claude-code-glm/scripts

# Run the installer
./install-relace.sh --api-key "your-relace-api-key-here"

# Reload your shell
source ~/.bashrc
```

That's it! The installer handles everything:
- Installs dependencies (jq, curl)
- Copies hook script
- Configures Claude Code settings
- Sets up environment variables
- Creates helper aliases

### Step 3: Test It

```bash
# Start Claude Code
claude

# Ask Claude to edit a file
# Example: "Create a test.js file with a hello function, then modify it to add logging"

# Claude will now use abbreviated snippets automatically!
```

## Quick Reference

### Toggle Commands

```bash
claude-relace-on          # Enable Relace (default)
claude-relace-off         # Disable Relace
claude-relace-status      # Check current status
claude-relace-debug-on    # Enable debug logging
claude-relace-debug-off   # Disable debug logging
```

### View Logs & Costs

```bash
claude-relace-logs        # Watch logs in real-time
claude-relace-costs       # View cost tracking (last 20)
```

### Per-Project Disable

```bash
cd /path/to/sensitive/project
touch .no-relace          # Disable Relace for this project
```

### Manual Toggle

```bash
export RELACE_ENABLED=false   # Disable
export RELACE_ENABLED=true    # Enable
```

## How It Works

### Traditional Edit (Slow)

```
Claude → Rewrites entire file (1000 lines)
      → GLM-4.7 processes 1000 lines @ 1500 tok/s
      → Takes ~0.67s, costs $0.0025
```

### With Relace (Fast)

```
Claude → Outputs abbreviated snippet (50 lines with "..." markers)
      → GLM-4.7 processes 50 lines @ 1500 tok/s (~0.03s)
      → Relace merges with original @ 10k+ tok/s (~0.11s)
      → Total: ~0.14s, costs $0.0011
      → 4.8x faster, 56% cheaper!
```

### Example Snippet

**Claude outputs:**

```typescript
// ... keep existing imports ...

function processData(data: any) {
  // NEW: Add validation
  if (!data || !data.id) {
    throw new Error('Invalid data');
  }

  // ... keep existing processing logic ...

  return result;
}

// ... rest of file remains the same ...
```

**Relace merges it with the original file automatically.**

## When Relace Activates

Relace automatically activates when:
- ✅ File is >100 lines (configurable via `RELACE_MIN_FILE_SIZE`)
- ✅ Edit contains abbreviation markers (`...`, `keep existing`, etc.)
- ✅ `RELACE_ENABLED=true` (default)
- ✅ No `.no-relace` file in project

Otherwise, it falls back to standard Edit tool.

## Configuration

All settings in `~/.bashrc`:

```bash
export RELACE_API_KEY="..."           # Your API key (required)
export RELACE_ENABLED=true            # Enable/disable
export RELACE_MIN_FILE_SIZE=100       # Min file size in lines
export RELACE_TIMEOUT=30              # API timeout in seconds
export RELACE_DEBUG=false             # Debug logging
export RELACE_COST_TRACKING=true      # Cost tracking
```

## Troubleshooting

### Problem: Hook not triggering

**Check:**

```bash
# 1. Verify hook is installed
ls -la ~/claude-code-relace-hook.sh

# 2. Check it's executable
chmod +x ~/claude-code-relace-hook.sh

# 3. Verify settings
cat ~/.claude/settings.json | jq '.hooks.PreToolUse'

# 4. Enable debug mode
export RELACE_DEBUG=true
claude
```

### Problem: API errors

**Check:**

```bash
# 1. Verify API key
echo $RELACE_API_KEY

# 2. Test API directly
curl -X POST https://instantapply.endpoint.relace.run/v1/code/apply \
  -H "Authorization: Bearer $RELACE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"initial_code": "test", "edit_snippet": "// ... updated ..."}'

# 3. Check error logs
tail -20 ~/.claude/relace-logs/errors.log
```

### Problem: Edits not working as expected

**Solution:**

The hook gracefully falls back to standard Edit on any error. Check:

```bash
# View debug logs
tail -f ~/.claude/relace-logs/*.log

# Temporarily disable Relace
claude-relace-off
claude  # Use standard Edit tool
```

## Advanced Usage

### Different Settings per VM

You can have different `RELACE_MIN_FILE_SIZE` settings:

```bash
# Cerebras VM (high-speed, use Relace less)
export RELACE_MIN_FILE_SIZE=200

# Z.ai VM (cost-sensitive, use Relace more)
export RELACE_MIN_FILE_SIZE=50
```

### Disable for Specific File Types

Edit `~/claude-code-relace-hook.sh`:

```bash
# Around line 200, add:
FILE_EXT="${FILE_PATH##*.}"
case "$FILE_EXT" in
    md|txt|json)
        log_debug "Relace disabled for .$FILE_EXT files"
        exit 0
        ;;
esac
```

### Custom API Endpoint

If using a custom Relace deployment:

```bash
export RELACE_ENDPOINT="https://your-custom-endpoint.com/v1/code/apply"
```

## Performance Monitoring

### View Performance Stats

```bash
cat ~/.claude/relace-logs/performance.log
# Shows: timestamp, duration, prompt_tokens, completion_tokens, file_size, tok/s
```

### Calculate Savings

```bash
# View recent costs
cat ~/.claude/relace-logs/costs.csv | tail -20

# Calculate total costs this month
awk -F, 'NR>1 {sum += $5} END {printf "Total: $%.4f\n", sum}' ~/.claude/relace-logs/costs.csv
```

## Testing

Run the test suite:

```bash
cd ~/superloop/tools/claude-code-glm/scripts
./test-relace-hook.sh

# With debug output
./test-relace-hook.sh --debug
```

## Uninstall

```bash
# Remove hook script
rm ~/claude-code-relace-hook.sh

# Remove configuration from ~/.bashrc
nano ~/.bashrc
# Delete the "Relace Instant Apply Configuration" section

# Remove hooks from settings
nano ~/.claude/settings.json
# Delete the Edit hook under PreToolUse

# Remove logs
rm -rf ~/.claude/relace-logs
```

## FAQ

**Q: Does this modify Claude Code itself?**
A: No. It uses Claude Code's built-in hooks system. No modification to Claude Code.

**Q: What if Relace API is down?**
A: The hook automatically falls back to standard Edit tool. No disruption.

**Q: Can I use this with other providers (not Cerebras/Z.ai)?**
A: Yes! Works with any Claude Code setup. The hook is provider-agnostic.

**Q: Does this work with Write tool?**
A: Currently only Edit tool. Write tool creates new files (no merging needed).

**Q: How do I know if Relace was used?**
A: Enable debug mode: `claude-relace-debug-on` and watch logs: `claude-relace-logs`

**Q: Can I use both VMs with Relace?**
A: Yes! Install in both VMs independently with `./install-relace.sh`

## Support

- **Documentation:** `RELACE_INTEGRATION.md` (comprehensive guide)
- **Relace Docs:** https://docs.relace.ai/
- **Claude Code Hooks:** https://code.claude.com/docs/en/hooks
- **Issues:** Report in your project issue tracker

## Quick Tips

1. **Start small:** Test with a single VM first (Cerebras recommended)
2. **Monitor logs:** Use `claude-relace-debug-on` for the first few edits
3. **Adjust threshold:** Lower `RELACE_MIN_FILE_SIZE` for more aggressive usage
4. **Per-project control:** Use `.no-relace` for sensitive projects
5. **Cost tracking:** Check `claude-relace-costs` weekly to see savings

---

**Version:** 1.0.0
**Last Updated:** 2026-01-08
**Estimated Setup Time:** 5 minutes
**Difficulty:** Easy
