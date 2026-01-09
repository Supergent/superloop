# Relace Instant Apply Integration for Claude Code GLM

## Executive Summary

This document describes how to integrate Relace's "instant apply" approach into Claude Code's Edit tool, enabling Claude to output abbreviated edit snippets with `// ... rest of code ...` markers that are then merged at >10k tokens/sec using the `relace-apply-3` model.

**Benefits:**
- **3x faster and cheaper** than rewriting full files
- Uses frontier models (GLM-4.7 via Cerebras) for **new code sections only**
- Uses lightweight Relace model at 10k+ tok/s for **merging**
- Separation of concerns: heavyweight model for changes, lightweight for merge

**Integration Points:**
1. System prompt modification (instruct Claude to output abbreviated snippets)
2. PreToolUse hook (intercept Edit tool, call Relace API, modify tool input)
3. Optional: Custom transformer modification for router-level integration

---

## Architecture Overview

```
User Request
    ↓
Claude Code CLI (with modified system prompt)
    ↓
GLM-4.7 generates abbreviated edit snippet
    ↓ (Edit tool call with snippet)
PreToolUse Hook intercepts
    ↓
Hook Script:
  1. Read original file
  2. Extract edit snippet from tool input
  3. Call Relace API (initial_code + edit_snippet)
  4. Receive merged code
  5. Modify tool input: replace snippet with merged result
    ↓
Edit tool executes with merged code
    ↓
File updated successfully
```

---

## Implementation Plan

### Phase 1: System Prompt Modification

**Goal:** Instruct Claude to output abbreviated edit snippets instead of full code blocks.

**Location:** `~/.claude/settings.json` in your VM (both Cerebras and Z.ai VMs)

**Configuration:**

```json
{
  "systemPrompt": {
    "append": "# Relace Instant Apply - Edit Formatting\n\nWhen using the Edit tool, format your edits as abbreviated snippets to optimize for speed and cost:\n\n**Rules for Edit Snippets:**\n- Abbreviate sections that remain unchanged with comments like `// ... rest of code ...`, `// ... keep existing code ...`, `// ... code remains the same`\n- Be precise with comment placement - a lightweight model will use your context clues to merge accurately\n- Include concise hints in comments about retained code: `// ... keep calculateTotalFunction ...`\n- For deletions, provide context:\n  - Option 1: Show adjacent blocks without the deleted section\n  - Option 2: Use explicit removal comment: `// ... remove BlockName ...`\n- Use language-appropriate comment syntax (// for JS/TS, # for Python, etc.)\n- Preserve exact indentation showing final code structure\n- Include only lines that will appear in final merged code\n- Be length-efficient without omitting key context\n\n**Example (TypeScript):**\n```typescript\n// Original file has 100 lines\n// You only need to change lines 45-50\n\n// ... keep existing imports and setup ...\n\nfunction processData(data: any) {\n  // NEW: Add validation\n  if (!data || !data.id) {\n    throw new Error('Invalid data');\n  }\n  \n  // ... keep existing processing logic ...\n  \n  return result;\n}\n\n// ... rest of file remains the same ...\n```\n\nThe Edit tool will automatically merge your snippet with the original file."
  }
}
```

**Alternative Location:** Create `~/.claude/commands/relace-mode.md`:

```markdown
# Relace Edit Mode

Enable abbreviated edit snippet mode for faster, cheaper edits.

When this mode is active, format all Edit tool calls as abbreviated snippets:

- Use `// ... rest of code ...` to abbreviate unchanged sections
- Be precise with comment placement for accurate merging
- Include hints: `// ... keep existingFunction ...`
- Preserve indentation of final code
- Use language-appropriate comments

This enables 3x faster edits via Relace instant apply.
```

Then activate with: `/relace-mode` in Claude Code CLI.

---

### Phase 2: Relace API Hook Script

**Goal:** Intercept Edit tool calls, process through Relace API, and modify tool input.

**Location:** `~/claude-code-relace-hook.sh` (in your VM)

**Script:**

```bash
#!/bin/bash
#
# Claude Code PreToolUse Hook for Relace Instant Apply
#
# This hook intercepts Edit tool calls and processes them through Relace API
# for fast, efficient code merging.
#
# Requirements:
# - curl or wget
# - jq for JSON processing
# - RELACE_API_KEY environment variable
#
# Exit codes:
# 0 = Success (allow tool execution with modified input)
# 2 = Block (with error message to stderr for Claude)
# Other = Non-blocking error shown to user

set -euo pipefail

# Configuration
RELACE_API_KEY="${RELACE_API_KEY:-}"
RELACE_ENDPOINT="https://instantapply.endpoint.relace.run/v1/code/apply"
TIMEOUT_SECONDS=30
DEBUG="${CLAUDE_CODE_RELACE_DEBUG:-false}"

# Logging helper
log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[RELACE-HOOK DEBUG] $*" >&2
    fi
}

log_error() {
    echo "[RELACE-HOOK ERROR] $*" >&2
}

# Check prerequisites
if [[ -z "$RELACE_API_KEY" ]]; then
    log_error "RELACE_API_KEY not set. Falling back to standard Edit tool."
    exit 0  # Don't block, just pass through
fi

if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install with: apt-get install jq"
    exit 0  # Don't block
fi

# Read tool call data from stdin
TOOL_DATA=$(cat)
log_debug "Received tool data: $TOOL_DATA"

# Extract tool input
TOOL_INPUT=$(echo "$TOOL_DATA" | jq -r '.tool_input')
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path')
OLD_STRING=$(echo "$TOOL_INPUT" | jq -r '.old_string')
NEW_STRING=$(echo "$TOOL_INPUT" | jq -r '.new_string')

log_debug "File: $FILE_PATH"
log_debug "Edit type: old_string -> new_string"

# Check if this looks like an abbreviated snippet
# Heuristic: contains "... rest of code" or similar markers
if ! echo "$NEW_STRING" | grep -qE "\.\.\.|keep.*code|rest.*file|existing.*code"; then
    log_debug "No abbreviation markers detected. Using standard Edit tool."
    exit 0  # Pass through to normal Edit
fi

log_debug "Abbreviated snippet detected. Processing through Relace..."

# Read original file content
if [[ ! -f "$FILE_PATH" ]]; then
    log_error "File not found: $FILE_PATH"
    echo '{"block": true, "message": "File not found for Relace processing"}' >&2
    exit 2
fi

INITIAL_CODE=$(cat "$FILE_PATH")
EDIT_SNIPPET="$NEW_STRING"

# Build Relace API request
REQUEST_JSON=$(jq -n \
    --arg initial_code "$INITIAL_CODE" \
    --arg edit_snippet "$EDIT_SNIPPET" \
    '{
        initial_code: $initial_code,
        edit_snippet: $edit_snippet
    }')

log_debug "Calling Relace API..."

# Call Relace API
RESPONSE=$(curl -s -X POST "$RELACE_ENDPOINT" \
    -H "Authorization: Bearer $RELACE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_JSON" \
    --max-time "$TIMEOUT_SECONDS" 2>&1) || {
    log_error "Relace API call failed: $RESPONSE"
    exit 0  # Fall back to standard Edit
}

log_debug "Relace API response received"

# Extract merged code
MERGED_CODE=$(echo "$RESPONSE" | jq -r '.mergedCode')

if [[ -z "$MERGED_CODE" || "$MERGED_CODE" == "null" ]]; then
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // "Unknown error"')
    log_error "Relace API error: $ERROR_MSG"
    exit 0  # Fall back to standard Edit
fi

log_debug "Successfully merged code (${#MERGED_CODE} chars)"

# Modify tool input to use merged code
# Strategy: Replace new_string with merged code, and old_string with original file content
MODIFIED_INPUT=$(echo "$TOOL_INPUT" | jq \
    --arg merged "$MERGED_CODE" \
    --arg original "$INITIAL_CODE" \
    '.old_string = $original | .new_string = $merged')

# Output modified tool data
echo "$TOOL_DATA" | jq \
    --argjson modified_input "$MODIFIED_INPUT" \
    '.tool_input = $modified_input'

log_debug "Tool input modified successfully"

# Log usage stats if available
if echo "$RESPONSE" | jq -e '.usage' > /dev/null 2>&1; then
    PROMPT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens')
    COMPLETION_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
    log_debug "Relace usage: ${PROMPT_TOKENS} prompt + ${COMPLETION_TOKENS} completion tokens"
fi

exit 0  # Success, allow modified tool execution
```

**Make executable:**

```bash
chmod +x ~/claude-code-relace-hook.sh
```

---

### Phase 3: Hook Configuration

**Goal:** Register the hook to intercept Edit tool calls.

**Location:** `~/.claude/settings.json` in your VM

**Configuration:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "~/claude-code-relace-hook.sh",
            "timeout": 60
          }
        ]
      }
    ]
  },
  "systemPrompt": {
    "append": "# Relace Instant Apply - Edit Formatting\n\nWhen using the Edit tool, format your edits as abbreviated snippets...\n[Full prompt from Phase 1]"
  }
}
```

**Combined with existing settings:**

If you already have hooks or system prompt modifications, merge them:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "~/claude-code-relace-hook.sh",
            "timeout": 60
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          // Your existing Bash hooks
        ]
      }
    ]
  },
  "systemPrompt": {
    "append": "# Existing system prompt modifications\n\n...\n\n# Relace Instant Apply\n\n..."
  }
}
```

---

### Phase 4: Environment Setup

**Goal:** Configure API keys and dependencies.

**In your VM (Cerebras or Z.ai):**

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y jq curl

# Set Relace API key
echo 'export RELACE_API_KEY="your-relace-api-key-here"' >> ~/.bashrc
source ~/.bashrc

# Optional: Enable debug logging
echo 'export CLAUDE_CODE_RELACE_DEBUG=true' >> ~/.bashrc  # Remove for production

# Test the hook script
echo '{"tool_input": {"file_path": "/tmp/test.txt", "old_string": "old", "new_string": "// ... new code ..."}}' | ~/claude-code-relace-hook.sh
```

**Obtain Relace API Key:**

1. Sign up at https://app.relace.ai
2. Create API key at https://app.relace.ai/settings/api-keys
3. Set in environment variable (see above)

---

### Phase 5: Testing

**Test 1: Verify Hook Registration**

```bash
# In VM
cat ~/.claude/settings.json | jq '.hooks.PreToolUse'

# Should show Edit matcher with your hook script
```

**Test 2: Simple Edit with Abbreviated Snippet**

```bash
# Start Claude Code
claude

# In Claude Code session:
# "Create a test file with a simple function, then ask me to edit it"

# Claude creates: /tmp/test.js
function hello() {
  console.log("Hello");
  console.log("World");
  console.log("From Claude");
}

# You: "Change the console.log messages to use template literals, but keep the function structure"

# Claude should output abbreviated snippet:
function hello() {
  console.log(`Hello from ${new Date().toISOString()}`);
  // ... keep remaining logs ...
}
```

**Expected behavior:**
1. Hook intercepts Edit call
2. Detects abbreviation markers (`... keep`)
3. Calls Relace API
4. Merges code
5. Edit tool applies merged result

**Test 3: Verify Debug Logs**

```bash
# With CLAUDE_CODE_RELACE_DEBUG=true
# Check Claude Code output for hook messages:

# Should see:
# [RELACE-HOOK DEBUG] Abbreviated snippet detected. Processing through Relace...
# [RELACE-HOOK DEBUG] Successfully merged code (XXX chars)
# [RELACE-HOOK DEBUG] Tool input modified successfully
```

**Test 4: Fallback Behavior**

Test that hook doesn't break normal edits:

```bash
# In Claude Code:
# "Make a simple typo fix in test.js - change 'Wrold' to 'World'"

# Claude uses exact string replacement (no abbreviation)
# Hook should detect no markers and pass through (exit 0)
```

---

## Advanced Configuration

### Option A: OpenAI-Compatible Endpoint

Relace also provides an OpenAI-compatible endpoint for easier integration:

**Modified Hook Script (OpenAI endpoint):**

```bash
# Use OpenAI-compatible endpoint
RELACE_ENDPOINT="https://instantapply.endpoint.relace.run/v1/apply"

# Build request in OpenAI format
REQUEST_JSON=$(jq -n \
    --arg initial "$INITIAL_CODE" \
    --arg snippet "$EDIT_SNIPPET" \
    '{
        model: "auto",
        messages: [
            {
                role: "user",
                content: ("<code>" + $initial + "</code>\n<update>" + $snippet + "</update>")
            }
        ]
    }')

# Parse response
MERGED_CODE=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
```

### Option B: Router-Level Integration

For more advanced setups, integrate Relace into the Claude Code Router transformer.

**Location:** `~/.claude-code-router/plugins/cerebras-transformer.js`

**Add Edit Tool Interception:**

```javascript
// In transformRequest function, detect Edit tool calls

module.exports.transformRequest = async function(req) {
  const anthropic = req.body;

  // Check if this is an Edit tool call with abbreviated snippet
  if (anthropic.tools && hasEditToolWithSnippet(anthropic)) {
    // Intercept and process through Relace
    const modifiedBody = await processEditWithRelace(anthropic);
    return buildOpenAIRequest(modifiedBody);
  }

  // Normal transformation
  return buildOpenAIRequest(anthropic);
};

async function processEditWithRelace(anthropic) {
  // Extract edit tool call
  // Call Relace API
  // Modify tool parameters
  // Return modified request
}
```

**Benefits:**
- Centralized processing in router
- No per-VM hook configuration
- Can batch multiple edits
- Easier debugging

**Drawbacks:**
- More complex implementation
- Router becomes stateful (needs file access)
- Tighter coupling

### Option C: Custom Edit Tool Definition

Create a new tool `RelaceEdit` alongside standard `Edit`:

**Location:** `~/.claude/plugins/relace-edit/plugin.json`

```json
{
  "name": "relace-edit",
  "version": "1.0.0",
  "tools": [
    {
      "name": "RelaceEdit",
      "description": "Performs fast file edits using abbreviated snippets processed by Relace instant apply. Use this for large files or multi-section edits. Format edits with '// ... rest of code ...' markers.",
      "input_schema": {
        "type": "object",
        "properties": {
          "file_path": {
            "type": "string",
            "description": "Absolute path to file"
          },
          "edit_snippet": {
            "type": "string",
            "description": "Abbreviated code with '// ...' markers"
          }
        },
        "required": ["file_path", "edit_snippet"]
      },
      "implementation": {
        "type": "command",
        "command": "~/claude-code-relace-edit-tool.sh"
      }
    }
  ]
}
```

**Benefits:**
- Clean separation: use `Edit` for small changes, `RelaceEdit` for large files
- No hook interception needed
- Explicit intent

**Drawbacks:**
- Requires Claude to choose between tools
- More complex tool landscape

---

## Monitoring and Optimization

### Performance Metrics

Track Relace API performance:

```bash
# Add to hook script
log_performance() {
    local start_time=$1
    local end_time=$2
    local tokens=$3
    local duration=$((end_time - start_time))
    local tps=$((tokens / duration))

    echo "[RELACE-HOOK] Duration: ${duration}s, Tokens: $tokens, Speed: ${tps} tok/s" >&2
}

# Usage:
START=$(date +%s)
# ... call Relace API ...
END=$(date +%s)
TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens')
log_performance $START $END $TOKENS
```

### Cost Tracking

```bash
# Log costs to file
COST_LOG="$HOME/.claude/relace-costs.log"

log_cost() {
    local prompt_tokens=$1
    local completion_tokens=$2

    # Relace pricing (example, check current rates)
    local cost=$(echo "scale=6; ($prompt_tokens * 0.000001) + ($completion_tokens * 0.000001)" | bc)

    echo "$(date -Iseconds),$prompt_tokens,$completion_tokens,$cost" >> "$COST_LOG"
}
```

### Error Handling

Monitor Relace API failures:

```bash
# In hook script
ERROR_LOG="$HOME/.claude/relace-errors.log"

log_api_error() {
    local error_msg=$1
    echo "$(date -Iseconds): $error_msg" >> "$ERROR_LOG"

    # Alert if error rate is high
    local recent_errors=$(tail -100 "$ERROR_LOG" | wc -l)
    if [[ $recent_errors -gt 50 ]]; then
        log_error "High error rate detected: $recent_errors errors in last 100 calls"
    fi
}
```

---

## Troubleshooting

### Issue: Hook Not Triggering

**Symptoms:**
- Edits work but don't use Relace
- No debug logs appear

**Solutions:**

1. **Check hook registration:**
   ```bash
   cat ~/.claude/settings.json | jq '.hooks.PreToolUse'
   ```

2. **Verify hook script is executable:**
   ```bash
   ls -la ~/claude-code-relace-hook.sh
   chmod +x ~/claude-code-relace-hook.sh
   ```

3. **Test hook manually:**
   ```bash
   echo '{"tool_input": {"file_path": "/tmp/test.txt", "old_string": "old", "new_string": "// ... new code ..."}}' | ~/claude-code-relace-hook.sh
   ```

4. **Check Claude Code logs:**
   ```bash
   # Look for hook execution logs
   claude --verbose
   ```

### Issue: Relace API Errors

**Symptoms:**
- Hook logs show API errors
- Edits fall back to standard Edit tool

**Solutions:**

1. **Verify API key:**
   ```bash
   echo $RELACE_API_KEY
   ```

2. **Test API directly:**
   ```bash
   curl -X POST https://instantapply.endpoint.relace.run/v1/code/apply \
     -H "Authorization: Bearer $RELACE_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"initial_code": "test", "edit_snippet": "// ... updated ..."}'
   ```

3. **Check rate limits:**
   - Monitor response headers for rate limit info
   - Implement exponential backoff in hook script

4. **Increase timeout:**
   ```json
   {
     "hooks": {
       "PreToolUse": [{
         "matcher": "Edit",
         "hooks": [{
           "timeout": 120  // Increase from 60
         }]
       }]
     }
   }
   ```

### Issue: Merge Quality Problems

**Symptoms:**
- Merged code has errors
- Context is lost or misplaced

**Solutions:**

1. **Improve system prompt specificity:**
   - Add more examples
   - Emphasize context preservation
   - Include language-specific patterns

2. **Adjust snippet format:**
   - Use more specific comment markers
   - Include more surrounding context
   - Add line number hints

3. **Provide feedback to Claude:**
   - "The merge lost the function signature, please include more context"
   - Claude will adjust future snippets

4. **Fall back to standard Edit for critical files:**
   ```json
   {
     "hooks": {
       "PreToolUse": [{
         "matcher": "Edit",
         "hooks": [{
           "command": "if echo \"$TOOL_INPUT\" | jq -r '.file_path' | grep -qE 'critical|production'; then exit 0; fi; ~/claude-code-relace-hook.sh"
         }]
       }]
     }
   }
   ```

### Issue: Performance Not as Expected

**Symptoms:**
- Edits are slow
- Not seeing 3x speedup

**Solutions:**

1. **Profile the pipeline:**
   ```bash
   # Add timing to hook script
   time ~/claude-code-relace-hook.sh < test_input.json
   ```

2. **Check network latency:**
   ```bash
   curl -w "@curl-format.txt" -o /dev/null -s https://instantapply.endpoint.relace.run/v1/code/apply
   ```

3. **Optimize for file size:**
   - Relace excels with large files (>500 lines)
   - Small files may not benefit
   - Add size check to hook:
   ```bash
   FILE_SIZE=$(wc -l < "$FILE_PATH")
   if [[ $FILE_SIZE -lt 100 ]]; then
       log_debug "File too small for Relace, using standard Edit"
       exit 0
   fi
   ```

---

## Integration with Existing Setup

### Cerebras VM Setup

Your Cerebras VM already has:
- Router on port 3456
- Custom transformer
- Isolated or shared filesystem modes

**Add Relace hook:**

```bash
# SSH into Cerebras VM
orb -m claude-code-glm-cerebras

# Install dependencies
sudo apt-get install -y jq curl

# Create hook script
nano ~/claude-code-relace-hook.sh
# [Paste script from Phase 2]

chmod +x ~/claude-code-relace-hook.sh

# Configure API key
echo 'export RELACE_API_KEY="your-key"' >> ~/.bashrc
source ~/.bashrc

# Update settings
nano ~/.claude/settings.json
# [Add hooks configuration from Phase 3]

# Test
~/start-claude-isolated.sh
# Try an edit with abbreviated snippet
```

### Z.ai VM Setup

Similar process for Z.ai VM:

```bash
orb -m claude-code-glm-zai
# Same steps as Cerebras VM
```

### Coordination with Router

The Relace hook works **alongside** your existing router setup:

```
User → Claude Code → Anthropic format → Router (port 3456) → Transformer → Cerebras/Z.ai
                                                  ↓
                                            PreToolUse Hook
                                                  ↓
                                            Relace API
```

**No router changes needed!** The hook intercepts at the Claude Code level, before the router sees the API call.

---

## Performance Comparison

### Scenario: Edit 50-line function in 1000-line file

**Traditional Edit (full file rewrite):**
- GLM-4.7 processes: 1000 lines
- Output: 1000 lines
- Speed: 1500 tok/s (Cerebras)
- Time: ~0.67s
- Cost: $2.50/1M tokens × 1000 tokens = $0.0025

**Relace Instant Apply:**
- GLM-4.7 processes: 50 lines (abbreviated snippet)
- Relace processes: 1050 lines (1000 + 50)
- Speed: 1500 tok/s (GLM) + 10,000 tok/s (Relace)
- Time: ~0.03s (GLM) + ~0.11s (Relace) = ~0.14s
- Cost: $2.50/1M × 50 + Relace cost = ~$0.0001 + $0.0010 = $0.0011

**Speedup: 4.8x faster**
**Cost savings: 56% cheaper**

### Real-World Benefits

- **Large files (2000+ lines):** 10x+ speedup
- **Multiple edits in session:** Cumulative savings
- **Complex refactors:** Better context preservation with abbreviated snippets

---

## Next Steps

1. **Phase 1:** Modify system prompt in one VM (start with Cerebras)
2. **Phase 2:** Create and test hook script
3. **Phase 3:** Register hook in settings.json
4. **Phase 4:** Set up Relace API key
5. **Phase 5:** Test with simple edits
6. **Phase 6:** Monitor performance and iterate
7. **Phase 7:** Deploy to both VMs

**Estimated setup time:** 30-60 minutes

**Documentation:**
- Claude Code Hooks: https://code.claude.com/docs/en/hooks
- Relace API: https://docs.relace.ai/
- This guide: `tools/claude-code-glm/RELACE_INTEGRATION.md`

---

## Appendix A: Complete Hook Script (Production-Ready)

See `tools/claude-code-glm/scripts/relace-hook.sh` for a production-ready version with:
- Comprehensive error handling
- Performance logging
- Cost tracking
- Retry logic
- Rate limit handling
- Multi-language support
- Configuration file support

---

## Appendix B: System Prompt Templates

### Minimal (Lightweight)

```
When using Edit tool, abbreviate unchanged code with `// ... rest of code ...` comments for faster processing.
```

### Standard (Recommended)

[See Phase 1 for full text]

### Comprehensive (Maximum guidance)

Includes:
- Language-specific examples (Python, TypeScript, Rust, Go)
- Edge case handling (deletions, insertions, renames)
- Best practices for context preservation
- Common pitfalls to avoid

Available at: `tools/claude-code-glm/prompts/relace-comprehensive.md`

---

## Appendix C: Alternative Approaches

### 1. Aider-style Diff Format

Instead of abbreviated snippets, use unified diff format:

```diff
--- original.ts
+++ modified.ts
@@ -45,3 +45,5 @@
 function processData(data: any) {
+  if (!data) throw new Error('Invalid');
   return result;
 }
```

**Pros:** Standard format, precise
**Cons:** More verbose, requires diff generation

### 2. Line Number Targeting

Specify line ranges:

```json
{
  "file_path": "/path/to/file.ts",
  "line_start": 45,
  "line_end": 50,
  "replacement": "// new code"
}
```

**Pros:** Precise, simple
**Cons:** Fragile (line numbers change), no context

### 3. AST-Based Edits

Use syntax tree manipulation:

```json
{
  "file_path": "/path/to/file.ts",
  "selector": "function[name='processData']",
  "operation": "insert_before",
  "code": "// validation code"
}
```

**Pros:** Robust to whitespace changes
**Cons:** Complex, language-specific

**Recommendation:** Stick with Relace abbreviated snippets for best balance of simplicity, robustness, and performance.

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Status:** Ready for Implementation
**Next Review:** After initial testing phase
