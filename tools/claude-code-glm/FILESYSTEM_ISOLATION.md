# OrbStack VM Filesystem Isolation Guide

**CRITICAL**: OrbStack VMs share your Mac filesystem by default. Claude Code running in a VM can modify your actual Mac files!

This guide explains how to set up **isolated filesystems** to protect your Mac files from accidental changes.

---

## Table of Contents

- [The Problem: Default Shared Filesystem](#the-problem-default-shared-filesystem)
- [The Solution: Isolated VM Filesystem](#the-solution-isolated-vm-filesystem)
- [Implementation Guide](#implementation-guide)
- [Usage Patterns](#usage-patterns)
- [Syncing Between VM and Mac](#syncing-between-vm-and-mac)
- [When to Use Which Approach](#when-to-use-which-approach)

---

## The Problem: Default Shared Filesystem

### How OrbStack Works

OrbStack automatically mounts your Mac's filesystem into Linux VMs:

```
Your Mac:  /Users/yourname/Work/project
              ↕ (SAME FILESYSTEM)
In VM:     /Users/yourname/Work/project
```

**This means:**
- ❌ VM file changes immediately affect your Mac
- ❌ Claude Code can modify/delete your actual project files
- ❌ No rollback if Claude makes mistakes
- ❌ No isolation for experimentation

### Example of the Danger

```bash
# Inside VM
rm -rf ~/Work/important-project

# Result: Your Mac files are DELETED! 💀
```

---

## The Solution: Isolated VM Filesystem

Create a **separate copy** of your project inside the VM:

```
Your Mac:  /Users/yourname/Work/project (ORIGINAL - SAFE)
              ✗ (NO CONNECTION)
In VM:     /home/yourname/vm-projects/project (ISOLATED COPY)
```

**Benefits:**
- ✅ VM changes only affect VM copy
- ✅ Your Mac files remain untouched
- ✅ Safe experimentation with Claude Code
- ✅ Manual sync when you're ready
- ✅ Easy rollback (just delete VM copy)

---

## Implementation Guide

### Step 1: Remove Default Symlinks

The VM setup may create symlinks to your Mac filesystem. Remove them:

```bash
# Inside the VM
rm ~/superloop
rm ~/work
```

**Why?** These symlinks create direct paths to your Mac files.

### Step 2: Create Isolated Project Directory

```bash
# Inside the VM
mkdir -p ~/vm-projects
```

### Step 3: Copy Your Project

```bash
# Inside the VM
cp -r /Users/yourname/Work/superloop ~/vm-projects/
```

**Note:** This creates a one-time copy. Future Mac changes won't appear in the VM unless you manually sync.

### Step 4: Create Isolated Startup Script

Create `~/start-claude-isolated.sh`:

```bash
#!/bin/bash
#
# Start Claude Code with Isolated Filesystem
# Project location: ~/vm-projects/superloop (VM only, does NOT affect Mac)
#

echo "================================================="
echo "Claude Code - Isolated VM Mode"
echo "================================================="
echo ""
echo "✓ Working directory: ~/vm-projects/superloop"
echo "✓ Filesystem: ISOLATED (Mac files are safe)"
echo ""

# Load environment variables
source ~/.bashrc

# Start router if not already running
if ! pgrep -f "ccr" > /dev/null; then
    echo "Starting Claude Code Router..."
    ccr start &
    sleep 3
fi

# Activate router environment
eval "$(ccr activate)"

# Navigate to isolated project
cd ~/vm-projects/superloop

echo ""
echo "================================================="
echo "Ready! Starting Claude Code..."
echo "================================================="
echo ""

# Start Claude Code
claude
```

Make it executable:
```bash
chmod +x ~/start-claude-isolated.sh
```

### Step 5: Verify Isolation

Test that changes don't affect your Mac:

```bash
# Inside VM
touch ~/vm-projects/superloop/TEST_FILE.txt

# On Mac - should NOT exist
ls /Users/yourname/Work/superloop/TEST_FILE.txt
# Error: No such file or directory ✓
```

---

## Usage Patterns

### Starting Claude Code (Isolated Mode)

```bash
# From Mac
orb -m claude-code-glm-cerebras

# Inside VM
~/start-claude-isolated.sh
```

### Checking Your Current Directory

Always verify you're in the isolated directory:

```bash
pwd
# Should show: /home/yourname/vm-projects/superloop
```

### Directory Structure

```
/home/yourname/
├── .bashrc                      # API keys
├── .claude-code-router/         # Router config
├── start-claude-isolated.sh     # Startup script
└── vm-projects/                 # ISOLATED PROJECTS
    └── superloop/               # Your project copy
        ├── packages/
        ├── src/
        └── ...
```

---

## Syncing Between VM and Mac

### When to Sync

Only sync when you've verified the VM changes are safe and want to apply them to your Mac.

### VM → Mac (Apply VM Changes to Mac)

**Option 1: Rsync (Recommended)**
```bash
# Inside VM - Preview changes first
rsync -av --dry-run ~/vm-projects/superloop/ /Users/yourname/Work/superloop/

# If happy with changes, run without --dry-run
rsync -av ~/vm-projects/superloop/ /Users/yourname/Work/superloop/
```

**Option 2: Git (Safest)**
```bash
# Inside VM - Commit your changes
cd ~/vm-projects/superloop
git add .
git commit -m "Changes made by Claude Code in VM"
git push

# On Mac - Pull the changes
cd /Users/yourname/Work/superloop
git pull
```

### Mac → VM (Update VM with Mac Changes)

```bash
# Inside VM
rsync -av /Users/yourname/Work/superloop/ ~/vm-projects/superloop/
```

### Selective File Sync

```bash
# Copy specific file from VM to Mac
rsync -av ~/vm-projects/superloop/src/specific-file.ts /Users/yourname/Work/superloop/src/

# Copy specific directory
rsync -av ~/vm-projects/superloop/packages/ui/ /Users/yourname/Work/superloop/packages/ui/
```

---

## When to Use Which Approach

### Use Isolated Filesystem (Recommended)

**Best for:**
- ✅ Experimenting with Claude Code
- ✅ Trying risky refactors
- ✅ Testing new features
- ✅ Learning/exploring the tool
- ✅ Working on non-critical projects
- ✅ Batch processing many files

**Advantages:**
- Mac files always safe
- Easy rollback (delete VM copy)
- No accidental damage
- Freedom to experiment

**Disadvantages:**
- Manual sync required
- Extra disk space (usually minimal)
- Two copies to track

### Use Shared Filesystem (Advanced Users Only)

**Only use when:**
- ⚠️ You fully trust Claude Code's changes
- ⚠️ You have git commits for rollback
- ⚠️ You're doing simple, low-risk tasks
- ⚠️ You want immediate Mac file updates

**Setup:**
```bash
# Inside VM - Create symlinks (DANGEROUS!)
ln -s /Users/yourname/Work/superloop ~/superloop
```

**ALWAYS:**
- Have recent git commits
- Review changes carefully
- Use on branches, not main
- Keep backups

---

## Best Practices

### 1. Default to Isolated Mode

Start with isolation. Only use shared filesystem when you have a specific reason.

### 2. Use Git for Safe Syncing

```bash
# VM workflow
cd ~/vm-projects/superloop
# Make changes with Claude Code
git status
git diff
git add .
git commit -m "Descriptive message"
git push

# Mac workflow
git pull  # Review changes, then apply
```

### 3. Regular Backups

```bash
# Backup VM project before major changes
tar -czf ~/vm-projects/superloop-backup-$(date +%Y%m%d).tar.gz ~/vm-projects/superloop
```

### 4. Document Your Sync Strategy

Add to your project README:
```markdown
## VM Development

This project has a VM copy at `~/vm-projects/superloop` (isolated).

To sync VM → Mac: [instructions]
To sync Mac → VM: [instructions]
```

### 5. Verify Isolation Regularly

```bash
# Test script
touch ~/vm-projects/superloop/.isolation-test
sleep 1
if [ -f /Users/yourname/Work/superloop/.isolation-test ]; then
    echo "❌ WARNING: Filesystem is NOT isolated!"
else
    echo "✅ Filesystem is properly isolated"
fi
rm ~/vm-projects/superloop/.isolation-test
```

---

## Troubleshooting

### "My VM changes appeared on Mac!"

You likely have symlinks. Check:
```bash
ls -la ~ | grep -E "superloop|work"
```

If you see `superloop ->`, delete it:
```bash
rm ~/superloop ~/work
```

### "I can't find my project in the VM"

Check the isolated directory:
```bash
ls -la ~/vm-projects/
```

If empty, copy your project again:
```bash
cp -r /Users/yourname/Work/superloop ~/vm-projects/
```

### "Rsync is copying too many files"

Use `--exclude` for node_modules, etc.:
```bash
rsync -av --exclude='node_modules' --exclude='.git' ~/vm-projects/superloop/ /Users/yourname/Work/superloop/
```

### "I want to reset the VM copy"

```bash
# Delete and recopy
rm -rf ~/vm-projects/superloop
cp -r /Users/yourname/Work/superloop ~/vm-projects/
```

---

## Security Considerations

### API Keys

API keys in `~/.bashrc` are VM-only and won't sync to Mac. This is good!

```bash
# ~/.bashrc in VM
export CEREBRAS_API_KEY="your-key"  # VM only, not on Mac
```

### Sensitive Files

If your project has secrets (`.env`, credentials):
```bash
# Exclude from sync
rsync -av --exclude='.env' --exclude='*.key' ~/vm-projects/superloop/ /Users/yourname/Work/superloop/
```

### Git Credentials

The VM can access Mac's git credentials if the path is shared. Use git credential helpers in the VM:
```bash
# Inside VM
git config --global credential.helper store
```

---

## Summary

### Quick Reference

| Action | Command |
|--------|---------|
| Enter VM | `orb -m claude-code-glm-cerebras` |
| Start Claude (isolated) | `~/start-claude-isolated.sh` |
| Verify isolation | `pwd` (should be `~/vm-projects/...`) |
| Sync VM → Mac | `rsync -av ~/vm-projects/superloop/ /Users/yourname/Work/superloop/` |
| Sync Mac → VM | `rsync -av /Users/yourname/Work/superloop/ ~/vm-projects/superloop/` |
| Reset VM copy | `rm -rf ~/vm-projects/superloop && cp -r /Users/yourname/Work/superloop ~/vm-projects/` |

### Key Takeaways

1. **OrbStack shares your Mac filesystem by default** - this is dangerous for Claude Code
2. **Isolated filesystem** = VM copy that doesn't affect Mac
3. **Sync manually** when you're ready to apply changes
4. **Use git** for the safest sync method
5. **Default to isolated mode** - only use shared filesystem if you have a specific reason

---

## Related Documentation

- [README.md](README.md) - Quick start guide
- [DUAL_VM_SETUP.md](DUAL_VM_SETUP.md) - Complete VM setup
- [SECURITY_NOTE.md](SECURITY_NOTE.md) - API key security
- [TECHNICAL_DOCS.md](TECHNICAL_DOCS.md) - Full technical details

---

**Last Updated**: 2026-01-08
**Status**: Production-ready pattern for safe Claude Code usage in OrbStack VMs
