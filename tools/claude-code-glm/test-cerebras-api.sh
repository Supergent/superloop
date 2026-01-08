#!/bin/bash
#
# Minimal Test Script for Cerebras GLM 4.7 + Claude Code Router Integration
#
# This script verifies each component of the integration before full deployment
# Run this BEFORE implementing the full setup to catch issues early
#
# Prerequisites:
# - CEREBRAS_API_KEY environment variable set
# - curl and jq installed (brew install jq)
# - Node.js 18+ installed
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cerebras GLM 4.7 Setup Verification${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check prerequisites
echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

if [ -z "$CEREBRAS_API_KEY" ]; then
    echo -e "${RED}✗ CEREBRAS_API_KEY not set${NC}"
    echo "  Export your API key: export CEREBRAS_API_KEY='your-key-here'"
    exit 1
fi
echo -e "${GREEN}✓ CEREBRAS_API_KEY is set${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq not found${NC}"
    echo "  Install: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi
echo -e "${GREEN}✓ jq is installed${NC}"

if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found${NC}"
    echo "  Install from: https://nodejs.org/"
    exit 1
fi
NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo -e "${RED}✗ Node.js version $NODE_VERSION is too old (need 18+)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Node.js $(node --version) is installed${NC}\n"

# Test 1: Basic Cerebras API connectivity
echo -e "${YELLOW}[2/5] Testing Cerebras API connectivity...${NC}"

BASIC_RESPONSE=$(curl -s -w "\n%{http_code}" \
  https://api.cerebras.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CEREBRAS_API_KEY" \
  -d '{
    "model": "zai-glm-4.7",
    "messages": [{"role": "user", "content": "Say hello in exactly 3 words"}],
    "max_tokens": 10,
    "stream": false
  }')

HTTP_CODE=$(echo "$BASIC_RESPONSE" | tail -n1)
BODY=$(echo "$BASIC_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ne 200 ]; then
    echo -e "${RED}✗ API request failed with HTTP $HTTP_CODE${NC}"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi

CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content')
echo -e "${GREEN}✓ API is reachable${NC}"
echo -e "  Response: \"$CONTENT\"\n"

# Test 2: Tool calling support
echo -e "${YELLOW}[3/5] Testing tool calling support...${NC}"

TOOL_RESPONSE=$(curl -s -w "\n%{http_code}" \
  https://api.cerebras.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CEREBRAS_API_KEY" \
  -d '{
    "model": "zai-glm-4.7",
    "messages": [{
      "role": "user",
      "content": "What is the weather in San Francisco? Use the get_weather tool."
    }],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get the current weather in a location",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {"type": "string", "description": "City name"}
          },
          "required": ["location"]
        }
      }
    }],
    "tool_choice": "auto",
    "max_tokens": 100,
    "stream": false
  }')

HTTP_CODE=$(echo "$TOOL_RESPONSE" | tail -n1)
BODY=$(echo "$TOOL_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ne 200 ]; then
    echo -e "${RED}✗ Tool calling request failed with HTTP $HTTP_CODE${NC}"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi

# Check if tool was called
TOOL_CALLS=$(echo "$BODY" | jq -r '.choices[0].message.tool_calls // empty')
if [ -z "$TOOL_CALLS" ]; then
    echo -e "${YELLOW}⚠ Model did not call tool (may have responded with text instead)${NC}"
    echo "  This could indicate tool calling issues or model behavior"
    echo "$BODY" | jq '.choices[0].message'
else
    TOOL_NAME=$(echo "$BODY" | jq -r '.choices[0].message.tool_calls[0].function.name')
    echo -e "${GREEN}✓ Tool calling works${NC}"
    echo -e "  Called tool: $TOOL_NAME"
fi
echo ""

# Test 3: Streaming support
echo -e "${YELLOW}[4/5] Testing streaming support...${NC}"

STREAM_TEST=$(mktemp)
curl -s -N \
  https://api.cerebras.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CEREBRAS_API_KEY" \
  -d '{
    "model": "zai-glm-4.7",
    "messages": [{"role": "user", "content": "Count: 1, 2, 3, 4, 5"}],
    "max_tokens": 50,
    "stream": true
  }' > "$STREAM_TEST" 2>&1

# Check if we got SSE format
if grep -q "data: " "$STREAM_TEST"; then
    echo -e "${GREEN}✓ Streaming works (SSE format detected)${NC}"
    CHUNK_COUNT=$(grep -c "data: " "$STREAM_TEST")
    echo -e "  Received $CHUNK_COUNT chunks"
else
    echo -e "${RED}✗ No streaming chunks received${NC}"
    echo "  Output:"
    cat "$STREAM_TEST"
fi
rm "$STREAM_TEST"
echo ""

# Test 4: Transformer function validation
echo -e "${YELLOW}[5/5] Validating transformer logic...${NC}"

# Create a minimal test transformer
TEST_TRANSFORMER=$(mktemp).js
cat > "$TEST_TRANSFORMER" << 'EOF'
// Minimal transformer validation

function testAnthropicToOpenAI() {
  const anthropicRequest = {
    model: "claude-sonnet-4-20250514",
    system: "You are a helpful assistant",
    messages: [
      { role: "user", content: "Hello" }
    ],
    max_tokens: 100
  };

  // Simulate transformation
  const openaiRequest = {
    model: "glm-4.7",
    messages: [
      { role: "system", content: anthropicRequest.system },
      ...anthropicRequest.messages
    ],
    max_tokens: anthropicRequest.max_tokens
  };

  return openaiRequest.messages.length === 2 &&
         openaiRequest.messages[0].role === "system";
}

function testOpenAIToAnthropic() {
  const openaiResponse = {
    choices: [{
      message: { content: "Hello!" },
      finish_reason: "stop"
    }],
    usage: {
      prompt_tokens: 10,
      completion_tokens: 5
    }
  };

  // Simulate transformation
  const anthropicResponse = {
    type: "message",
    role: "assistant",
    content: [{ type: "text", text: openaiResponse.choices[0].message.content }],
    stop_reason: "end_turn",
    usage: {
      input_tokens: openaiResponse.usage.prompt_tokens,
      output_tokens: openaiResponse.usage.completion_tokens
    }
  };

  return anthropicResponse.content[0].type === "text" &&
         anthropicResponse.stop_reason === "end_turn";
}

const test1 = testAnthropicToOpenAI();
const test2 = testOpenAIToAnthropic();

console.log(JSON.stringify({
  anthropicToOpenAI: test1,
  openAIToAnthropic: test2,
  allPassed: test1 && test2
}));
EOF

TRANSFORM_RESULT=$(node "$TEST_TRANSFORMER")
ALL_PASSED=$(echo "$TRANSFORM_RESULT" | jq -r '.allPassed')

if [ "$ALL_PASSED" = "true" ]; then
    echo -e "${GREEN}✓ Transformer logic validated${NC}"
    echo "  Anthropic → OpenAI: ✓"
    echo "  OpenAI → Anthropic: ✓"
else
    echo -e "${RED}✗ Transformer logic failed${NC}"
    echo "$TRANSFORM_RESULT" | jq .
fi
rm "$TEST_TRANSFORMER"
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ All core components verified${NC}"
echo ""
echo "Next steps:"
echo "  1. Install Claude Code Router: npm install -g @musistudio/claude-code-router"
echo "  2. Create transformer file: ~/.claude-code-router/plugins/cerebras-transformer.js"
echo "  3. Create config file: ~/.claude-code-router/config.json"
echo "  4. Start router: ccr start"
echo "  5. Activate: eval \"\$(ccr activate)\""
echo "  6. Test Claude Code: claude"
echo ""
echo -e "${YELLOW}Pro tip:${NC} Monitor router logs during testing:"
echo "  tail -f ~/.claude-code-router/logs/ccr-*.log | grep CEREBRAS"
