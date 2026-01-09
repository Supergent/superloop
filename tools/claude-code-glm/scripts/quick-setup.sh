#!/bin/bash
#
# Relace Quick Setup - One Command Installation
#
# This script sets up Relace integration in one command.
# No arguments needed - API key is embedded.
#

set -euo pipefail

# Your Relace API key
RELACE_API_KEY="rlc-uLuluhwUSAixYlinUqnjbhvQEiFrJSz82Lcmwg"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Relace Quick Setup for Claude Code GLM   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if installer exists
if [[ ! -f "$SCRIPT_DIR/install-relace.sh" ]]; then
    echo "Error: install-relace.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Run the installer
echo -e "${BLUE}[1/4]${NC} Running installer..."
"$SCRIPT_DIR/install-relace.sh" --api-key "$RELACE_API_KEY"

echo ""
echo -e "${BLUE}[2/4]${NC} Reloading shell configuration..."
source ~/.bashrc

echo ""
echo -e "${BLUE}[3/4]${NC} Running tests..."
"$SCRIPT_DIR/test-relace-hook.sh"

echo ""
echo -e "${BLUE}[4/4]${NC} Creating test file..."
cat > /tmp/relace-demo.js << 'EOF'
// Demo file for Relace integration
function calculateSum(numbers) {
  let sum = 0;
  for (let i = 0; i < numbers.length; i++) {
    sum += numbers[i];
  }
  return sum;
}

function calculateAverage(numbers) {
  if (numbers.length === 0) return 0;
  return calculateSum(numbers) / numbers.length;
}

function calculateMax(numbers) {
  if (numbers.length === 0) return null;
  let max = numbers[0];
  for (let i = 1; i < numbers.length; i++) {
    if (numbers[i] > max) {
      max = numbers[i];
    }
  }
  return max;
}

function calculateMin(numbers) {
  if (numbers.length === 0) return null;
  let min = numbers[0];
  for (let i = 1; i < numbers.length; i++) {
    if (numbers[i] < min) {
      min = numbers[i];
    }
  }
  return min;
}

// Test the functions
const testNumbers = [5, 2, 8, 1, 9, 3];
console.log("Sum:", calculateSum(testNumbers));
console.log("Average:", calculateAverage(testNumbers));
console.log("Max:", calculateMax(testNumbers));
console.log("Min:", calculateMin(testNumbers));
EOF

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Setup Complete! ✅               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo ""
echo -e "  1. Start Claude Code:"
echo -e "     ${YELLOW}claude${NC}"
echo ""
echo -e "  2. Try this prompt:"
echo -e "     ${YELLOW}\"Edit /tmp/relace-demo.js and add input validation to all functions\"${NC}"
echo ""
echo -e "  3. Watch Relace in action!"
echo ""
echo -e "${BLUE}Monitor in real-time (open new terminal):${NC}"
echo -e "  ${YELLOW}claude-relace-logs${NC}"
echo ""
echo -e "${BLUE}Toggle Relace:${NC}"
echo -e "  ${YELLOW}claude-relace-off${NC}   # Disable"
echo -e "  ${YELLOW}claude-relace-on${NC}    # Enable"
echo -e "  ${YELLOW}claude-relace-status${NC} # Check status"
echo ""
echo -e "${BLUE}View costs:${NC}"
echo -e "  ${YELLOW}claude-relace-costs${NC}"
echo ""
echo "Demo file created at: /tmp/relace-demo.js"
echo ""
