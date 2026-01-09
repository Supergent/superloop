#!/bin/bash
# Simple setup - creates the test script in the VM

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Setting up GLM test...${NC}"

# 1. Setup Bitcoin on Mac
echo "Preparing Bitcoin repo..."
rm -rf /Users/multiplicity/Work/bitcoin-test 2>/dev/null || true
cp -r /tmp/bitcoin-benchmark /Users/multiplicity/Work/bitcoin-test
cd /Users/multiplicity/Work/bitcoin-test
git reset --hard HEAD > /dev/null 2>&1
git clean -fd > /dev/null 2>&1

echo -e "${GREEN}✓ Bitcoin ready at /Users/multiplicity/Work/bitcoin-test${NC}"

# 2. Create startup script in VM
echo "Creating test script in VM..."

orb run -m claude-code-glm-cerebras bash -c 'cat > /tmp/run-test.sh << '\''EOFSCRIPT'\''
#!/bin/bash

echo "════════════════════════════════════════════════════════"
echo "GLM Test - Bitcoin Refactor"
echo "════════════════════════════════════════════════════════"
echo ""

# Source environment
source ~/.bashrc

# Kill existing
pkill -f cerebras-proxy.js 2>/dev/null || true
pkill -f ccr 2>/dev/null || true
sleep 2

# Start proxy
echo "Starting Cerebras proxy..."
node ~/cerebras-proxy.js > /tmp/cerebras-proxy.log 2>&1 &
sleep 3

if pgrep -f cerebras-proxy > /dev/null; then
    echo "✓ Proxy running"
else
    echo "✗ Proxy failed"
    exit 1
fi

# Start router
echo "Starting router..."
ccr start > /tmp/ccr.log 2>&1 &
sleep 3
eval "$(ccr activate)"
echo "✓ Router activated"

# Navigate
cd /Users/multiplicity/Work/bitcoin-test
echo "✓ In Bitcoin repo: $(pwd)"

# Verify
if [ ! -f "src/validation.cpp" ]; then
    echo "✗ ERROR: Bitcoin repo not found!"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "READY TO START!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Task: Rename CheckInputScripts → ValidateInputScripts"
echo ""
echo "When Claude starts, paste this:"
echo ""
echo "Rename the function CheckInputScripts to ValidateInputScripts everywhere in the Bitcoin codebase. Update the declaration, definition, all call sites, and any comments that reference it by name."
echo ""
echo "════════════════════════════════════════════════════════"
echo "⏱️  START YOUR TIMER after you paste!"
echo "════════════════════════════════════════════════════════"
echo ""

# Start Claude
claude --dangerously-skip-permissions
EOFSCRIPT
chmod +x /tmp/run-test.sh'

echo -e "${GREEN}✓ Test script created in VM${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup complete! Now run these 2 commands:${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  orb -m claude-code-glm-cerebras"
echo "  /tmp/run-test.sh"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
