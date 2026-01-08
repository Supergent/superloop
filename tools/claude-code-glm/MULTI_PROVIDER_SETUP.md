# Multi-Provider Setup: Cerebras + Z.ai

## Overview

Configure your `claude-code-glm` VM to support **both** Cerebras and Z.ai providers, switchable on-the-fly with Claude Code's `/model` command.

## Why Both?

| Provider | Best For | API Format | Transform | Speed | Cost |
|----------|----------|------------|-----------|-------|------|
| **Cerebras** | Max speed | OpenAI | Custom | 1000-1700 TPS | $2.25-2.75/1M |
| **Z.ai** | Best pricing | Anthropic | None needed | TBD | "3× usage" + 50% off |

## Setup Instructions

### Step 1: Get Z.ai API Key

1. Visit https://z.ai/model-api
2. Register/Login
3. Create API Key at https://z.ai/manage-apikey/apikey-list
4. Copy your key

### Step 2: Update VM Router Config

SSH into your VM:
```bash
orb shell claude-code-glm
```

Edit the router config:
```bash
nano ~/.claude-code-router/config.json
```

Update to this multi-provider config:
```json
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 300000,
  "Providers": [
    {
      "name": "cerebras",
      "api_base_url": "https://api.cerebras.ai/v1/chat/completions",
      "api_key": "$CEREBRAS_API_KEY",
      "models": [
        "zai-glm-4.7",
        "zai-glm-4.6",
        "llama3.1-8b",
        "llama-3.3-70b"
      ],
      "transformer": {
        "request": "/home/multiplicity/.claude-code-router/plugins/cerebras-transformer.js::transformRequest",
        "response": "/home/multiplicity/.claude-code-router/plugins/cerebras-transformer.js::transformResponse",
        "streamChunk": "/home/multiplicity/.claude-code-router/plugins/cerebras-transformer.js::transformStreamChunk"
      }
    },
    {
      "name": "zai",
      "api_base_url": "https://api.z.ai/api/anthropic/v1/messages",
      "api_key": "$ZAI_API_KEY",
      "models": [
        "glm-4.7",
        "glm-4.5-air"
      ]
      // Note: NO transformer needed! Z.ai is Anthropic-compatible
    }
  ],
  "Router": {
    "default": "zai,glm-4.7",
    "background": "zai,glm-4.7",
    "think": "cerebras,zai-glm-4.7",
    "longContext": "cerebras,zai-glm-4.7"
  }
}
```

**Key Changes:**
- Added Z.ai as second provider
- **No transformer** for Z.ai (Anthropic-native!)
- Set Z.ai as default (better pricing)
- Cerebras for "think" tasks (higher speed)

### Step 3: Add Z.ai API Key to Environment

```bash
# Edit bashrc
nano ~/.bashrc

# Add this line (replace with your key):
export ZAI_API_KEY="your-zai-api-key-here"

# Save and reload
source ~/.bashrc
```

### Step 4: Restart Router

```bash
# Stop existing router
pkill -f ccr

# Start with new config
export CEREBRAS_API_KEY="csk-your-cerebras-api-key-here"
export ZAI_API_KEY="your-zai-key"
ccr start &
sleep 3

# Activate and test
eval "$(ccr activate)"
claude
```

## Usage: Switching Between Providers

### In Claude Code Session

```bash
# Check current model
/status

# Switch to Z.ai (default, cheaper)
/model zai,glm-4.7

# Switch to Cerebras (faster)
/model cerebras,zai-glm-4.7

# Try Z.ai's lighter model
/model zai,glm-4.5-air

# Try Cerebras Llama
/model cerebras,llama-3.3-70b
```

### Pre-configured Routing

The config above sets:
- **Default tasks**: Z.ai GLM-4.7 (best pricing)
- **Background tasks**: Z.ai GLM-4.7 (cost-efficient)
- **Thinking tasks**: Cerebras GLM-4.7 (high speed)
- **Long context**: Cerebras GLM-4.7 (high speed)

Claude Code Router automatically routes based on task type!

## Decision Matrix

### Use Z.ai When:
- ✅ Cost is primary concern
- ✅ Standard response times acceptable
- ✅ 50% off promo active
- ✅ Daily development work
- ✅ Learning/experimentation

### Use Cerebras When:
- ✅ Speed is critical
- ✅ Large codebases (need fast iteration)
- ✅ Complex reasoning tasks
- ✅ Time-sensitive debugging
- ✅ Want to test transformer tech

## Testing Both Providers

### Test Z.ai
```bash
# In Claude Code:
/model zai,glm-4.7
What is 2+2?
```

Check logs:
```bash
tail -f ~/.claude-code-router/logs/ccr-*.log | grep -i "zai\|provider"
```

### Test Cerebras
```bash
# In Claude Code:
/model cerebras,zai-glm-4.7
What is 2+2?
```

Check logs:
```bash
tail -f ~/.claude-code-router/logs/ccr-*.log | grep -i "cerebras\|transformer"
```

## Pricing Comparison Example

### 1 Million Token Usage:

**Cerebras:**
- Input: $2.25
- Output: $2.75
- **Total: ~$5.00**

**Z.ai with 50% off:**
- Marketed as "3× usage at fraction of cost"
- 50% off first purchase
- 10-20% extra discount
- **Estimated: ~$1.00-2.00** (need to verify actual pricing)

**Potential Savings: 60-80%** by using Z.ai for most tasks!

## Monitoring Usage

Track which provider you're using more:

```bash
# Count requests per provider
grep -c "provider.*cerebras" ~/.claude-code-router/logs/ccr-*.log
grep -c "provider.*zai" ~/.claude-code-router/logs/ccr-*.log
```

## Advanced: Auto-Switching Based on Cost

You could create a custom router that switches providers based on:
- Time of day (Z.ai during development, Cerebras for demos)
- Task complexity (simple = Z.ai, complex = Cerebras)
- Monthly usage limits (Z.ai until limit, then Cerebras)

## Troubleshooting

### Z.ai Not Working

```bash
# Check API key is set
echo $ZAI_API_KEY

# Test Z.ai endpoint directly
curl -X POST https://api.z.ai/api/anthropic/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ZAI_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "glm-4.7",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

### Provider Not Switching

```bash
# Restart router
ccr restart

# Check config is valid JSON
cat ~/.claude-code-router/config.json | jq .

# View router logs
tail -50 ~/.claude-code-router/logs/ccr-*.log
```

### Both Providers Active?

```bash
# Check registered providers
curl -s http://127.0.0.1:3456/ | jq .
```

## Recommended Workflow

1. **Start with Z.ai as default** (best pricing)
2. **Switch to Cerebras when needed** (high-speed tasks)
3. **Monitor usage and costs**
4. **Adjust Router.default** based on your usage patterns

## Summary

✅ **One VM, two providers**
✅ **Switch instantly with `/model`**
✅ **Z.ai: Best pricing, Anthropic-native, no transformer**
✅ **Cerebras: Highest speed, custom transformer**
✅ **Automatic routing by task type**
✅ **Compare performance/cost in real-time**

**Next**: Get Z.ai API key and add to config!
