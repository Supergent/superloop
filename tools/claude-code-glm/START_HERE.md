# 🚀 Relace Quick Start - Super Simple Setup

## One Command Setup

SSH into your VM and run:

```bash
cd ~/superloop/tools/claude-code-glm/scripts
./quick-setup.sh
```

**That's it!** The script will:
- ✅ Install everything automatically
- ✅ Configure Claude Code with your API key
- ✅ Run all tests
- ✅ Create a demo file for you to try

**Time:** ~2 minutes

---

## Try It Out

After setup completes:

### 1. Start Claude Code

```bash
claude
```

### 2. Try This Prompt

```
Edit /tmp/relace-demo.js and add input validation to all functions
```

Claude will automatically use Relace to merge the changes super fast!

### 3. Watch It Work (Optional)

Open a new terminal and run:

```bash
claude-relace-logs
```

You'll see real-time logs showing Relace processing your edits at 10k+ tok/s.

---

## Quick Commands

### Toggle On/Off

```bash
claude-relace-off     # Disable Relace
claude-relace-on      # Enable Relace
claude-relace-status  # Check if enabled
```

### Monitor Performance

```bash
claude-relace-logs    # Watch real-time logs
claude-relace-costs   # View cost savings
```

### Debug Mode

```bash
claude-relace-debug-on   # See detailed logs
claude-relace-debug-off  # Turn off debug
```

---

## What's Happening?

When you ask Claude to edit a file, Relace:

1. **Detects** large files (>100 lines)
2. **Claude outputs** abbreviated snippet with `// ... rest of code ...` markers
3. **Relace merges** at 10k+ tok/s (3-5x faster than rewriting)
4. **Saves 50%+** on costs

For small files, it automatically uses standard Edit (no overhead).

---

## Disable Per-Project

```bash
cd /path/to/sensitive/project
touch .no-relace
```

Relace will be disabled for that project only.

---

## That's All!

You're ready to go. Just run:

```bash
cd ~/superloop/tools/claude-code-glm/scripts
./quick-setup.sh
```

Then start coding with `claude`!

---

**Need Help?**
- Full docs: `RELACE_INTEGRATION.md`
- Quick guide: `RELACE_QUICKSTART.md`
- Scripts help: `scripts/README.md`
