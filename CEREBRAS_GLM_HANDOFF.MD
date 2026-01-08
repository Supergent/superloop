# Cerebras GLM 4.7 Integration via Claude Code Router

## Executive Summary

This document describes the implementation of a custom transformer for Claude Code Router to enable use of Cerebras AI's GLM 4.7 model through Claude Code CLI.

**Goal:** Route Claude Code requests from Anthropic format to Cerebras's OpenAI-compatible API endpoint, enabling Claude Code functionality without an Anthropic account.

**Approach:** Custom transformer plugin for Claude Code Router (@musistudio/claude-code-router) that handles bidirectional format translation.

---

## Business Context

### Requirements
- Use Claude Code CLI interface as primary development tool
- Route requests to Cerebras GLM 4.7 model for cost efficiency
- Maintain complete isolation from vanilla Anthropic account
- Enable model switching via `/model` command within Claude Code
- Support all Claude Code features (chat, file editing, tool calling where available)

### Constraints
- Cerebras provides OpenAI-compatible API, not Anthropic-compatible
- Must preserve Claude Code's expected response format for UI compatibility
- Transformer must handle both request and response transformations
- Streaming support is critical for real-time response experience

---

## Technical Architecture

### Component Overview

```
Claude Code CLI
    ↓ (Anthropic API format)
Claude Code Router (localhost:3456)
    ↓ Route matching
Custom Cerebras Transformer Plugin
    ↓ Format translation
Cerebras API (https://inference.cerebras.ai/v1)
    ↓ OpenAI-compatible format
Custom Cerebras Transformer Plugin
    ↓ Format translation
Claude Code CLI (Anthropic API format)
```

### Data Flow

1. **Request Path:**
   - User types in Claude Code
   - Claude Code sends HTTP POST to `ANTHROPIC_BASE_URL` (router)
   - Router matches request to "cerebras" provider
   - Custom transformer converts Anthropic format → OpenAI format
   - Router forwards to Cerebras API
   - Cerebras processes with GLM 4.7

2. **Response Path:**
   - Cerebras returns OpenAI format response
   - Custom transformer converts OpenAI format → Anthropic format
   - Router returns to Claude Code
   - Claude Code displays response to user

### Format Mappings

#### Anthropic Request → OpenAI Request

| Anthropic Field | OpenAI Field | Notes |
|----------------|----------------|--------|
| `model` | `model` | Map Claude model names to `zai-glm-4.7` |
| `messages[].role` | `messages[].role` | Same values (`user`, `assistant`, `system`) |
| `messages[].content` (string) | `messages[].content` (string) | Direct mapping |
| `messages[].content` (array of objects) | `messages[].content` (string) | Flatten blocks to string |
| `messages[].content[].type="text"` | `messages[].content` | Extract text value |
| `messages[].content[].type="image"` | Not supported | Cerebras GLM 4.7 is text-only |
| `messages[].content[].type="tool_use"` | `messages[].tool_calls` | Format differs significantly |
| `messages[].content[].type="tool_result"` | `messages[].tool_call_id` | Separate message structure |
| `system` (top-level) | `messages[0].role="system"` | Move to first message |
| `max_tokens` | `max_tokens` | Direct mapping |
| `temperature` | `temperature` | Direct mapping |
| `top_p` | `top_p` | Direct mapping |
| `stream` | `stream` | Direct mapping |

#### OpenAI Response → Anthropic Response

| OpenAI Field | Anthropic Field | Notes |
|--------------|-----------------|--------|
| `choices[0].message.content` | `content[0].text` | Wrap in array with type indicator |
| `choices[0].finish_reason` | `stop_reason` | Map values: `"stop"` → `"end_turn"` |
| `choices[0].message.tool_calls` | `content[].tool_use` | Complex structure transformation |
| `usage.prompt_tokens` | `usage.input_tokens` | Direct mapping |
| `usage.completion_tokens` | `usage.output_tokens` | Direct mapping |

---

## Implementation Steps

### Phase 1: Environment Setup

#### 1.1 Prerequisites

- Node.js 18+ installed
- npm installed
- Cerebras API key obtained from https://www.cerebras.ai/developers
- Claude Code installed: `npm install -g @anthropic-ai/claude-code`

#### 1.2 Install Claude Code Router

```bash
npm install -g @musistudio/claude-code-router
```

Verify installation:
```bash
ccr --version
# Should output version number
```

#### 1.3 Create Directory Structure

```bash
# Create plugin directory
mkdir -p ~/.claude-code-router/plugins

# Create logs directory (for debugging)
mkdir -p ~/.claude-code-router/logs
```

---

### Phase 2: Custom Transformer Implementation

#### 2.1 Create Transformer File

Create file: `~/.claude-code-router/plugins/cerebras-transformer.js`

```javascript
/**
 * Cerebras Transformer for Claude Code Router
 *
 * Purpose: Translate between Anthropic API format and Cerebras OpenAI-compatible API format
 * Model: GLM 4.7 (zai-glm-4.7)
 * Endpoint: https://inference.cerebras.ai/v1
 *
 * Architecture:
 * - transformRequest(): Anthropic → OpenAI
 * - transformResponse(): OpenAI → Anthropic
 * - transformStreamChunk(): Handle SSE streaming events
 */

'use strict';

/**
 * Transform Anthropic request to OpenAI format for Cerebras
 *
 * @param {Object} req - Request object containing body and headers
 * @returns {Object} Modified request with OpenAI format
 */
module.exports.transformRequest = async function(req) {
  const anthropic = req.body;

  // Extract model name, default to GLM 4.7
  const model = anthropic.model || 'zai-glm-4.7';

  // Transform messages from Anthropic to OpenAI format
  const openaiMessages = transformMessages(anthropic.messages, anthropic.system);

  // Build OpenAI request body
  const openaiReq = {
    model: model,
    messages: openaiMessages,
    max_tokens: anthropic.max_tokens || 4096,
    temperature: anthropic.temperature || 0.7,
    top_p: anthropic.top_p,
    stream: anthropic.stream !== false, // Default to true
  };

  // Add tool use if present
  if (anthropic.tools && anthropic.tools.length > 0) {
    openaiReq.tools = transformTools(anthropic.tools);
  }

  if (anthropic.tool_choice) {
    openaiReq.tool_choice = transformToolChoice(anthropic.tool_choice);
  }

  // Handle stop sequences
  if (anthropic.stop_sequences && anthropic.stop_sequences.length > 0) {
    openaiReq.stop = anthropic.stop_sequences;
  }

  // Log transformation for debugging
  console.error('[CEREBRAS-TRANSFORMER] Request transformed:', {
    anthropicModel: anthropic.model,
    openaiModel: openaiReq.model,
    messageCount: openaiMessages.length,
    hasTools: !!openaiReq.tools,
    stream: openaiReq.stream
  });

  return {
    ...req,
    body: openaiReq,
    headers: {
      ...req.headers,
      'Content-Type': 'application/json'
    }
  };
};

/**
 * Transform OpenAI response to Anthropic format
 *
 * @param {Object} resp - Response object containing body and status
 * @returns {Object} Modified response with Anthropic format
 */
module.exports.transformResponse = async function(resp) {
  const openai = resp.body;

  // Validate response structure
  if (!openai || typeof openai !== 'object') {
    console.error('[CEREBRAS-TRANSFORMER] Invalid response structure:', openai);
    return resp;
  }

  // Check for errors
  if (openai.error) {
    console.error('[CEREBRAS-TRANSFORMER] API Error:', openai.error);
    // Convert error to Anthropic format
    return {
      ...resp,
      body: {
        type: 'error',
        error: {
          type: 'api_error',
          message: openai.error.message || 'Unknown error from Cerebras API'
        }
      }
    };
  }

  // Extract choice
  const choice = openai.choices && openai.choices[0];
  if (!choice) {
    console.error('[CEREBRAS-TRANSFORMER] No choices in response:', openai);
    return resp;
  }

  const message = choice.message;
  const finishReason = choice.finish_reason || 'stop';

  // Transform content
  const content = transformResponseContent(message.content);

  // Build usage object
  const usage = {
    input_tokens: openai.usage?.prompt_tokens || 0,
    output_tokens: openai.usage?.completion_tokens || 0
  };

  // Build Anthropic format response
  const anthropicResp = {
    type: 'message',
    role: 'assistant',
    content: content,
    stop_reason: mapStopReason(finishReason),
    usage: usage
  };

  // Add stop sequence if present
  if (choice.stop) {
    anthropicResp.stop_reason = 'stop_sequence';
    anthropicResp.stop_sequence = choice.stop;
  }

  // Log transformation for debugging
  console.error('[CEREBRAS-TRANSFORMER] Response transformed:', {
    openaiModel: openai.model,
    finishReason,
    hasContent: !!message.content,
    usage
  });

  return {
    ...resp,
    body: anthropicResp,
    headers: {
      ...resp.headers,
      'Content-Type': 'application/json'
    }
  };
};

/**
 * Transform streaming chunk from OpenAI SSE to Anthropic format
 *
 * @param {Object} chunk - SSE chunk from OpenAI
 * @returns {Object} Anthropic-formatted chunk
 */
module.exports.transformStreamChunk = async function(chunk) {
  try {
    const data = JSON.parse(chunk);

    // Handle delta content
    if (data.choices && data.choices[0]?.delta?.content) {
      return {
        type: 'content_block_delta',
        index: 0,
        delta: {
          type: 'text',
          text: data.choices[0].delta.content
        }
      };
    }

    // Handle tool calls in streaming
    if (data.choices && data.choices[0]?.delta?.tool_calls) {
      const toolCalls = data.choices[0].delta.tool_calls;
      return {
        type: 'content_block_delta',
        index: 0,
        delta: {
          type: 'tool_use',
          tool_calls: toolCalls.map(tc => ({
            id: tc.id,
            name: tc.function?.name,
            input: JSON.parse(tc.function?.arguments || '{}')
          }))
        }
      };
    }

    // Handle finish reason
    if (data.choices && data.choices[0]?.finish_reason) {
      return {
        type: 'message_stop',
        stop_reason: mapStopReason(data.choices[0].finish_reason)
      };
    }

    return null;
  } catch (error) {
    console.error('[CEREBRAS-TRANSFORMER] Stream chunk error:', error);
    return null;
  }
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Transform messages array from Anthropic to OpenAI format
 *
 * Anthropic format:
 * - system prompt at top level
 * - messages with role + content (string or array of blocks)
 * - content blocks: {type: 'text'|'image'|'tool_use'|'tool_result'}
 *
 * OpenAI format:
 * - system message at start of array
 * - messages with role + content (string)
 * - Tool calls in separate field
 */
function transformMessages(messages, systemPrompt) {
  const openaiMessages = [];

  // Add system prompt first if present
  if (systemPrompt) {
    openaiMessages.push({
      role: 'system',
      content: systemPrompt
    });
  }

  // Transform each message
  if (Array.isArray(messages)) {
    for (const msg of messages) {
      const openaiMsg = {
        role: msg.role,
        content: null
      };

      // Handle content as string or array of blocks
      if (typeof msg.content === 'string') {
        openaiMsg.content = msg.content;
      } else if (Array.isArray(msg.content)) {
        // Flatten content blocks to string
        openaiMsg.content = flattenContentBlocks(msg.content);

        // Handle tool use blocks - append as tool_calls
        const toolUseBlock = msg.content.find(
          block => block.type === 'tool_use'
        );
        if (toolUseBlock) {
          openaiMsg.tool_calls = [{
            id: toolUseBlock.id,
            type: 'function',
            function: {
              name: toolUseBlock.name,
              arguments: JSON.stringify(toolUseBlock.input)
            }
          }];
        }

        // Handle tool result blocks - these should be separate messages
        const toolResultBlock = msg.content.find(
          block => block.type === 'tool_result'
        );
        if (toolResultBlock) {
          // Create separate message for tool result
          openaiMessages.push({
            role: 'tool',
            tool_call_id: toolResultBlock.tool_use_id,
            content: typeof toolResultBlock.content === 'string'
              ? toolResultBlock.content
              : JSON.stringify(toolResultBlock.content)
          });
        }
      }

      if (openaiMsg.content !== null) {
        openaiMessages.push(openaiMsg);
      }
    }
  }

  return openaiMessages;
}

/**
 * Flatten Anthropic content blocks to OpenAI string format
 *
 * Anthropic blocks can be text, image, tool_use, tool_result
 * OpenAI expects simple string content
 */
function flattenContentBlocks(blocks) {
  const textBlocks = blocks.filter(block => block.type === 'text');

  if (textBlocks.length === 0) {
    return '';
  }

  // Join text blocks with newlines
  return textBlocks
    .map(block => block.text)
    .join('\n\n');
}

/**
 * Transform Anthropic tools format to OpenAI format
 *
 * Anthropic: Array of {name, description, input_schema}
 * OpenAI: Array of {type, function: {name, description, parameters}}
 */
function transformTools(tools) {
  if (!Array.isArray(tools)) {
    return [];
  }

  return tools.map(tool => ({
    type: 'function',
    function: {
      name: tool.name,
      description: tool.description,
      parameters: tool.input_schema
    }
  }));
}

/**
 * Transform Anthropic tool_choice to OpenAI format
 *
 * Anthropic: {type: 'auto'|'any'|'tool', name: 'tool_name'}
 * OpenAI: 'auto'|'none'|'required'|{type: 'function', name: 'tool_name'}
 */
function transformToolChoice(toolChoice) {
  if (!toolChoice) {
    return 'auto';
  }

  if (toolChoice.type === 'any') {
    return 'auto';
  }

  if (toolChoice.type === 'auto') {
    return 'auto';
  }

  if (toolChoice.type === 'tool' && toolChoice.name) {
    return {
      type: 'function',
      function: { name: toolChoice.name }
    };
  }

  return 'auto';
}

/**
 * Transform OpenAI response content to Anthropic format
 *
 * OpenAI: string or null
 * Anthropic: Array of [{type: 'text', text: '...'}]
 */
function transformResponseContent(content) {
  if (!content) {
    return [];
  }

  return [{
    type: 'text',
    text: content
  }];
}

/**
 * Map OpenAI finish reason to Anthropic stop reason
 *
 * OpenAI: 'stop', 'length', 'content_filter', 'tool_calls'
 * Anthropic: 'end_turn', 'max_tokens', 'stop_sequence', 'tool_use'
 */
function mapStopReason(finishReason) {
  const mapping = {
    'stop': 'end_turn',
    'length': 'max_tokens',
    'content_filter': 'end_turn',
    'tool_calls': 'tool_use'
  };

  return mapping[finishReason] || 'end_turn';
}
```

#### 2.2 Transformer File Details

**Location:** `~/.claude-code-router/plugins/cerebras-transformer.js`

**Key Functions:**
- `transformRequest(req)` - Converts Anthropic → OpenAI
- `transformResponse(resp)` - Converts OpenAI → Anthropic
- `transformStreamChunk(chunk)` - Handles streaming responses
- Helper functions for nested transformations

**Logging:**
- All transformations log to stderr with `[CEREBRAS-TRANSFORMER]` prefix
- Enables debugging via `~/.claude-code-router/logs/ccr-*.log`

---

### Phase 3: Configuration

#### 3.1 Create Configuration File

Create file: `~/.claude-code-router/config.json`

```json
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 300000,
  "Providers": [
    {
      "name": "cerebras",
      "api_base_url": "https://inference.cerebras.ai/v1/chat/completions",
      "api_key": "$CEREBRAS_API_KEY",
      "models": [
        "zai-glm-4.7",
        "glm-4.7"
      ],
      "transformer": {
        "request": "~/.claude-code-router/plugins/cerebras-transformer.js::transformRequest",
        "response": "~/.claude-code-router/plugins/cerebras-transformer.js::transformResponse",
        "streamChunk": "~/.claude-code-router/plugins/cerebras-transformer.js::transformStreamChunk"
      }
    }
  ],
  "Router": {
    "default": "cerebras,zai-glm-4.7"
  }
}
```

**Configuration Options Explained:**

| Field | Value | Purpose |
|-------|--------|---------|
| `LOG` | `true` | Enable logging for debugging |
| `LOG_LEVEL` | `"info"` | Log verbosity: fatal, error, warn, info, debug, trace |
| `API_TIMEOUT_MS` | `300000` | API request timeout in milliseconds (5 minutes) |
| `Providers[].name` | `"cerebras"` | Provider identifier for routing |
| `Providers[].api_base_url` | Cerebras endpoint | Full API URL for chat completions |
| `Providers[].api_key` | `"$CEREBRAS_API_KEY"` | Environment variable interpolation (secure) |
| `Providers[].models` | `["zai-glm-4.7"]` | Available model names from Cerebras |
| `Providers[].transformer.request` | Path to transform function | Module::functionName syntax |
| `Providers[].transformer.response` | Path to transform function | Module::functionName syntax |
| `Providers[].transformer.streamChunk` | Path to transform function | For streaming support |
| `Router.default` | `"cerebras,zai-glm-4.7"` | Default provider,model for all requests |

#### 3.2 Environment Variables

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Cerebras API Key
export CEREBRAS_API_KEY="your-cerebras-api-key-here"
```

Reload shell:
```bash
source ~/.zshrc  # or ~/.bashrc
```

**Security Note:**
- Using `$VAR_NAME` syntax interpolates environment variables at runtime
- Never hardcode API keys in config.json
- Config file can be shared without exposing secrets

---

### Phase 4: Startup and Testing

#### 4.1 Start Claude Code Router

```bash
# Start the router service
ccr start
```

**Expected Output:**
```
[Claude Code Router] Starting on http://127.0.0.1:3456
[Claude Code Router] Config loaded from /Users/username/.claude-code-router/config.json
[Claude Code Router] Providers configured: cerebras
[Claude Code Router] Router default: cerebras,zai-glm-4.7
```

**Troubleshooting:**
- If port 3456 is in use: Edit config.json to add `"HOST": "127.0.0.1"` and specify different port
- Check logs: `tail -f ~/.claude-code-router/logs/ccr-$(date +%Y%m%d).log`

#### 4.2 Activate Router Environment

```bash
# Set environment variables for Claude Code
eval "$(ccr activate)"
```

**What This Sets:**
```bash
ANTHROPIC_AUTH_TOKEN=<from-config>
ANTHROPIC_BASE_URL=http://127.0.0.1:3456
NO_PROXY=127.0.0.1
DISABLE_TELEMETRY=true
DISABLE_COST_WARNINGS=true
API_TIMEOUT_MS=<from-config>
```

#### 4.3 Test Claude Code

```bash
# Start Claude Code with router
claude
```

**Verify Integration:**

1. In Claude Code, type: `/model`
2. Should show available models including `zai-glm-4.7`
3. Type a simple test: "Hello, what is 2+2?"
4. Check router logs for transformation:
   ```bash
   tail -f ~/.claude-code-router/logs/ccr-*.log | grep CEREBRAS-TRANSFORMER
   ```

**Expected Log Output:**
```
[CEREBRAS-TRANSFORMER] Request transformed: {
  anthropicModel: undefined,
  openaiModel: 'zai-glm-4.7',
  messageCount: 2,
  hasTools: false,
  stream: true
}
[CEREBRAS-TRANSFORMER] Response transformed: {
  openaiModel: 'zai-glm-4.7',
  finishReason: 'stop',
  hasContent: true,
  usage: { input_tokens: 12, output_tokens: 8 }
}
```

---

### Phase 5: OrbStack Isolation (Optional)

For complete isolation from host Claude Code:

#### 5.1 Create OrbStack VM

```bash
# Create new Ubuntu VM
orb create ubuntu --name claude-cerebras

# SSH into VM
orb ssh claude-cerebras
```

#### 5.2 Install Dependencies in VM

```bash
# Update packages
sudo apt update && sudo apt install -y curl nodejs npm

# Install Claude Code Router
npm install -g @musistudio/claude-code-router

# Create directories
mkdir -p ~/.claude-code-router/plugins
mkdir -p ~/.claude-code-router/logs
```

#### 5.3 Copy Transformer to VM

From host:
```bash
# Copy transformer file to VM
scp ~/.claude-code-router/plugins/cerebras-transformer.js claude-cerebras:~/.claude-code-router/plugins/
```

Or create directly in VM using your favorite editor (nano, vim, etc.)

#### 5.4 Configure in VM

```bash
# Create config with environment variable interpolation
cat > ~/.claude-code-router/config.json << 'EOF'
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 300000,
  "Providers": [
    {
      "name": "cerebras",
      "api_base_url": "https://inference.cerebras.ai/v1/chat/completions",
      "api_key": "$CEREBRAS_API_KEY",
      "models": ["zai-glm-4.7"],
      "transformer": {
        "request": "/root/.claude-code-router/plugins/cerebras-transformer.js::transformRequest",
        "response": "/root/.claude-code-router/plugins/cerebras-transformer.js::transformResponse",
        "streamChunk": "/root/.claude-code-router/plugins/cerebras-transformer.js::transformStreamChunk"
      }
    }
  ],
  "Router": {
    "default": "cerebras,zai-glm-4.7"
  }
}
EOF

# Set API key
echo 'export CEREBRAS_API_KEY="your-cerebras-api-key"' >> ~/.bashrc
source ~/.bashrc
```

#### 5.5 Access Codebase from VM

OrbStack provides automatic file sharing at `/mnt/my-mac`:

```bash
# Navigate to shared codebase
cd /mnt/my-mac/Users/yourname/Work/your-project

# Or create symbolic link
ln -s /mnt/my-mac/Users/yourname/Work ~/work
cd ~/work/your-project
```

#### 5.6 Start Router and Claude Code in VM

```bash
# Start router in background
nohup ccr start > /tmp/ccr.log 2>&1 &

# Wait a few seconds for startup
sleep 3

# Verify it's running
curl http://127.0.0.1:3456/health

# Activate environment
eval "$(ccr activate)"

# Start Claude Code
claude
```

#### 5.7 VM Autostart (Optional)

Create `~/.config/autostart.sh`:
```bash
#!/bin/bash
# Autostart Claude Code Router

sleep 5  # Wait for network to be ready

# Start router
nohup ccr start > /tmp/ccr.log 2>&1 &

echo "Claude Code Router started on $(date)"
```

Make executable and add to systemd or init system:
```bash
chmod +x ~/.config/autostart.sh
# Add to your startup script location
```

---

## Advanced Configuration

### Model Switching

Claude Code Router supports dynamic model switching within Claude Code:

```text
/model cerebras,zai-glm-4.7
```

**Pre-configured Routes in config.json:**
```json
{
  "Router": {
    "default": "cerebras,zai-glm-4.7",
    "background": "cerebras,zai-glm-4.7",
    "think": "cerebras,zai-glm-4.7",
    "longContext": "cerebras,zai-glm-4.7"
  }
}
```

### Multiple Providers

Add other providers alongside Cerebras:

```json
{
  "Providers": [
    {
      "name": "cerebras",
      "api_base_url": "https://inference.cerebras.ai/v1/chat/completions",
      "api_key": "$CEREBRAS_API_KEY",
      "models": ["zai-glm-4.7"],
      "transformer": {
        "request": "~/.claude-code-router/plugins/cerebras-transformer.js::transformRequest",
        "response": "~/.claude-code-router/plugins/cerebras-transformer.js::transformResponse"
      }
    },
    {
      "name": "anthropic-fallback",
      "api_base_url": "https://api.anthropic.com/v1/messages",
      "api_key": "$ANTHROPIC_API_KEY",
      "models": ["claude-sonnet-4-20250514"],
      "transformer": {
        "use": ["anthropic"]
      }
    }
  ]
}
```

### Custom Router Logic

For advanced routing, create `custom-router.js`:

```javascript
// ~/.claude-code-router/custom-router.js

module.exports = async function router(req, config) {
  const userMessage = req.body.messages.find(m => m.role === 'user')?.content;

  // Route simple queries to Cerebras
  if (userMessage && userMessage.length < 1000) {
    return "cerebras,zai-glm-4.7";
  }

  // Route complex reasoning tasks to Anthropic
  if (userMessage && userMessage.includes('reason') || userMessage.includes('think')) {
    return "anthropic-fallback,claude-sonnet-4-20250514";
  }

  // Default to Cerebras
  return null; // Uses Router.default
};
```

Update config.json:
```json
{
  "CUSTOM_ROUTER_PATH": "/root/.claude-code-router/custom-router.js"
}
```

---

## Troubleshooting

### Common Issues

#### Issue: "Transformer not found"

**Symptoms:**
```
Error: Cannot find module for transform: ~/.claude-code-router/plugins/cerebras-transformer.js::transformRequest
```

**Solutions:**
1. Verify file exists: `ls -la ~/.claude-code-router/plugins/cerebras-transformer.js`
2. Check module exports: Ensure functions are exported as `module.exports.transformRequest = ...`
3. Verify path is absolute or relative to home directory
4. Restart router: `ccr restart`

#### Issue: "API authentication failed"

**Symptoms:**
```
[CEREBRAS-TRANSFORMER] API Error: { type: 'authentication_error', ... }
```

**Solutions:**
1. Verify environment variable is set: `echo $CEREBRAS_API_KEY`
2. Check API key validity at https://www.cerebras.ai/developers
3. Ensure config.json uses `$CEREBRAS_API_KEY` (not hardcoded key)
4. Restart shell: `source ~/.zshrc` and `ccr restart`

#### Issue: "Streaming not working"

**Symptoms:**
- Responses appear all at once instead of streaming
- No incremental text updates

**Solutions:**
1. Check if `transformStreamChunk` is implemented in transformer
2. Verify streaming is enabled in config: `"stream": true` (default)
3. Check logs for stream errors: `grep -i stream ~/.claude-code-router/logs/ccr-*.log`
4. Test without streaming: Add `"stream": false` to OpenAI request in transformRequest()

#### Issue: "Tool calling failures"

**Symptoms:**
- Claude Code tools don't work
- "Tool not found" errors

**Solutions:**
1. Check if `transformTools()` in transformer handles all tool fields
2. Verify `tool_choice` transformation matches OpenAI format
3. Test simple tool call: "Use the read_file tool to read README.md"
4. Check Cerebras documentation for tool calling support
5. May need to disable tool use for GLM 4.7 if not fully supported

#### Issue: "Port already in use"

**Symptoms:**
```
Error: listen EADDRINUSE: address already in use :::3456
```

**Solutions:**
1. Find process using port: `lsof -i :3456`
2. Kill existing router: `killall ccr`
3. Or specify different port in config.json:
   ```json
   {
     "HOST": "127.0.0.1",
     "PORT": 3457
   }
   ```
4. Update Claude Code environment: `export ANTHROPIC_BASE_URL=http://127.0.0.1:3457`

#### Issue: "Memory issues in OrbStack VM"

**Symptoms:**
- Router crashes with OOM
- Slow performance

**Solutions:**
1. Increase VM memory: `orb edit claude-cerebras --memory 4G`
2. Limit log retention: Add `"LOG_RETENTION_DAYS": 7` to config
3. Increase swap space in VM
4. Reduce concurrent connections in config if applicable

---

## Monitoring and Maintenance

### Log Files

**Location:** `~/.claude-code-router/logs/`

**File Pattern:** `ccr-YYYYMMDD.log`

**Key Log Patterns:**
```bash
# View all router logs
tail -f ~/.claude-code-router/logs/ccr-*.log

# Filter for errors
grep -i error ~/.claude-code-router/logs/ccr-*.log

# Filter for Cerebras transformations
grep CEREBRAS-TRANSFORMER ~/.claude-code-router/logs/ccr-*.log

# Check API response times
grep "request.*ms" ~/.claude-code-router/logs/ccr-*.log
```

### Health Checks

```bash
# Router health
curl http://127.0.0.1:3456/health

# Expected response:
{
  "status": "ok",
  "version": "x.x.x",
  "providers": ["cerebras"]
}
```

### Performance Tuning

**Adjust API Timeout:**
```json
{
  "API_TIMEOUT_MS": 600000  // 10 minutes for long context
}
```

**Increase Buffer Size for Streaming:**
```javascript
// In transformer, if needed
const MAX_BUFFER_SIZE = 1024 * 1024; // 1MB
```

**Enable Compression:**
```javascript
// Add to request headers
headers: {
  ...req.headers,
  'Content-Type': 'application/json',
  'Accept-Encoding': 'gzip, deflate'
}
```

---

## Security Considerations

### API Key Management

✓ **DO:**
- Use environment variable interpolation (`$VAR_NAME`)
- Add config.json to `.gitignore`
- Rotate API keys regularly
- Use read-only API keys if available

✗ **DON'T:**
- Hardcode API keys in config.json
- Commit config.json with keys to version control
- Share config files with secrets
- Log API keys in plain text

### Network Security

- Router defaults to `127.0.0.1` (localhost only)
- To expose to network, set `"HOST": "0.0.0.0"` and add firewall rules
- Use reverse proxy (nginx) with SSL for production deployments
- Enable `APIKEY` auth in config for router itself

### Data Privacy

- Router logs HTTP requests but does not store responses by default
- Cerebras API handles data according to their privacy policy
- Consider local-only deployment for sensitive codebases

---

## Cost Considerations

### Cerebras GLM 4.7 Pricing

As of documentation date:
- **Input:** $2.25 per 1M tokens
- **Output:** $2.75 per 1M tokens
- **Context:** 131k tokens (paid), 64k (free)
- **Speed:** ~1000 tokens/sec

### Monitoring Usage

Cerebras API returns usage in response:
```json
{
  "usage": {
    "prompt_tokens": 1500,
    "completion_tokens": 800
  }
}
```

Transformer logs this, enabling cost tracking.

### Cost Optimization Tips

1. **Use background model** for simple tasks: Configure lightweight model if available
2. **Limit max_tokens** for short responses: Add `"max_tokens": 1000` for quick queries
3. **Cache responses** where possible: Implement caching layer in router
4. **Monitor token usage**: Track usage patterns via logs

---

## Alternative Approaches

### Option A: Use claude-code-mux

If custom transformer is too complex:

**Repository:** https://github.com/9j/claude-code-mux

**Advantages:**
- Built-in Cerebras support
- Rust-based (faster)
- Automatic failover
- Lower memory footprint

**Setup:**
```bash
# Install claude-code-mux
cargo install claude-code-mux

# Configure
cat > ~/.claude-code-mux/config.yaml << 'EOF'
provider: cerebras
api_key: $CEREBRAS_API_KEY
model: zai-glm-4.7
listen_address: "127.0.0.1:8080"
EOF

# Run
claude-code-mux

# Configure Claude Code
export ANTHROPIC_BASE_URL="http://127.0.0.1:8080"
claude
```

### Option B: Direct Z.ai Integration

If official Anthropic-compatible endpoint becomes available:

**Reference:** https://z.ai/subscribe

**Setup:**
```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Configure for Z.ai
cat > ~/.claude/settings.json << 'EOF'
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "$ZAI_API_KEY",
    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
    "API_TIMEOUT_MS": "3000000"
  }
}
EOF

export ZAI_API_KEY="your-zai-api-key"
claude
```

---

## Handoff Checklist

For the implementing engineer, verify:

- [ ] Node.js 18+ installed
- [ ] Claude Code Router installed via npm
- [ ] Custom transformer file created at `~/.claude-code-router/plugins/cerebras-transformer.js`
- [ ] Config file created at `~/.claude-code-router/config.json`
- [ ] CEREBRAS_API_KEY environment variable set
- [ ] Router starts successfully: `ccr start`
- [ ] Health check passes: `curl http://127.0.0.1:3456/health`
- [ ] Claude Code connects via `eval "$(ccr activate)"`
- [ ] Test query works: "Hello, what is 2+2?"
- [ ] Logs show successful transformations
- [ ] OrbStack isolation tested (if required)
- [ ] Model switching works: `/model cerebras,zai-glm-4.7`
- [ ] Streaming responses work correctly
- [ ] Tool calling tested (if needed)
- [ ] Documentation updated for team

---

## Contact and Support

### Resources

- **Claude Code Router:** https://github.com/musistudio/claude-code-router
- **Claude Code Router Docs:** https://musistudio.github.io/claude-code-router/
- **Cerebras API:** https://inference-docs.cerebras.ai/
- **Cerebras Pricing:** https://www.cerebras.ai/pricing
- **Issue Tracker:** https://github.com/musistudio/claude-code-router/issues (search for Cerebras)

### Getting Help

**Claude Code Router Community:**
- Discord: https://discord.gg/rdftVMaUcS
- GitHub Discussions: https://github.com/musistudio/claude-code-router/discussions

**Cerebras Support:**
- Documentation: https://inference-docs.cerebras.ai/
- Contact: Check their website for support channels

---

## Appendix: Complete Working Config Example

```json
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 300000,
  "LOG_RETENTION_DAYS": 30,
  "HOST": "127.0.0.1",
  "PORT": 3456,
  "Providers": [
    {
      "name": "cerebras",
      "api_base_url": "https://inference.cerebras.ai/v1/chat/completions",
      "api_key": "$CEREBRAS_API_KEY",
      "models": [
        "zai-glm-4.7",
        "glm-4.7"
      ],
      "transformer": {
        "request": "/home/username/.claude-code-router/plugins/cerebras-transformer.js::transformRequest",
        "response": "/home/username/.claude-code-router/plugins/cerebras-transformer.js::transformResponse",
        "streamChunk": "/home/username/.claude-code-router/plugins/cerebras-transformer.js::transformStreamChunk"
      }
    }
  ],
  "Router": {
    "default": "cerebras,zai-glm-4.7",
    "background": "cerebras,zai-glm-4.7",
    "think": "cerebras,zai-glm-4.7",
    "longContext": "cerebras,zai-glm-4.7",
    "longContextThreshold": 60000
  }
}
```

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Status:** Ready for Implementation
