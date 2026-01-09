#!/bin/bash
# Single Best Test - Scenario 6: Multi-Location Refactor
# This will show GLM's advantage with Mantic + Relace

set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

BITCOIN_REPO="/tmp/bitcoin-benchmark"
PROMPT="Rename the function CheckInputScripts to ValidateInputScripts everywhere in the Bitcoin codebase. Update the declaration, definition, all call sites, and any comments that reference it by name."

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Scenario 6: Multi-Location Refactor Test                 ║${NC}"
echo -e "${GREEN}║  The BEST test to show GLM advantages                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Task:${NC} Rename CheckInputScripts → ValidateInputScripts"
echo -e "${BLUE}Expected:${NC} ~10-20 locations across Bitcoin codebase"
echo ""

cd "$BITCOIN_REPO"

# ============================================================================
# TEST 1: VANILLA CLAUDE CODE
# ============================================================================

echo -e "${YELLOW}▶ TEST 1: Vanilla Claude Code${NC}"
echo ""

# Reset to clean state
git reset --hard HEAD > /dev/null 2>&1
git clean -fd > /dev/null 2>&1

VANILLA_START=$(date +%s)

echo "$PROMPT" | claude --dangerously-skip-permissions chat 2>&1 | tee /tmp/vanilla-scenario6.log

VANILLA_END=$(date +%s)
VANILLA_DURATION=$((VANILLA_END - VANILLA_START))

# Count changes
VANILLA_FILES=$(git diff --name-only | wc -l | tr -d ' ')
VANILLA_LINES=$(git diff --shortstat | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)

# Count tool calls from log
VANILLA_GREP=$(grep -c "Grep\|🔍" /tmp/vanilla-scenario6.log 2>/dev/null || echo 0)
VANILLA_READ=$(grep -c "Read\|📖" /tmp/vanilla-scenario6.log 2>/dev/null || echo 0)
VANILLA_EDIT=$(grep -c "Edit\|✏️" /tmp/vanilla-scenario6.log 2>/dev/null || echo 0)
VANILLA_TOOLS=$((VANILLA_GREP + VANILLA_READ + VANILLA_EDIT))

# Validate rename was successful
VANILLA_OLD_COUNT=$(git diff | grep -c "CheckInputScripts" 2>/dev/null || echo 0)
VANILLA_NEW_COUNT=$(git diff | grep -c "ValidateInputScripts" 2>/dev/null || echo 0)

echo ""
echo -e "${GREEN}✓ Vanilla Complete${NC}"
echo -e "  Time: ${VANILLA_DURATION}s"
echo -e "  Files: $VANILLA_FILES"
echo -e "  Lines: $VANILLA_LINES"
echo -e "  Tools: $VANILLA_TOOLS (${VANILLA_GREP}g + ${VANILLA_READ}r + ${VANILLA_EDIT}e)"
echo ""

# Save vanilla diff
git diff > /tmp/vanilla-scenario6.diff

# ============================================================================
# TEST 2: GLM (Cerebras + Mantic + Relace)
# ============================================================================

echo -e "${YELLOW}▶ TEST 2: GLM (Orb VM)${NC}"
echo ""

# Reset to clean state
git reset --hard HEAD > /dev/null 2>&1
git clean -fd > /dev/null 2>&1

# Get API key
API_KEY=$(orb run -m claude-code-glm-cerebras grep "CEREBRAS_API_KEY" /home/multiplicity/.bashrc | cut -d'"' -f2)

GLM_START=$(date +%s)

# Run GLM test
echo "$PROMPT" | orb run -m claude-code-glm-cerebras bash -c "
export CEREBRAS_API_KEY='$API_KEY'

# Kill existing
pkill -f cerebras-proxy.js 2>/dev/null || true
pkill -f ccr 2>/dev/null || true
sleep 2

# Start proxy
node ~/cerebras-proxy.js > /tmp/cerebras-proxy.log 2>&1 &
sleep 3

# Start router
ccr start > /tmp/ccr.log 2>&1 &
sleep 3

# Activate
eval \"\$(ccr activate)\"

# Go to bitcoin repo
cd /tmp/bitcoin-benchmark

# Run test
claude --dangerously-skip-permissions chat
" 2>&1 | tee /tmp/glm-scenario6.log

GLM_END=$(date +%s)
GLM_DURATION=$((GLM_END - GLM_START))

# Count changes
GLM_FILES=$(git diff --name-only | wc -l | tr -d ' ')
GLM_LINES=$(git diff --shortstat | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)

# Count tool calls
GLM_GREP=$(grep -c "Grep\|🔍" /tmp/glm-scenario6.log 2>/dev/null || echo 0)
GLM_READ=$(grep -c "Read\|📖" /tmp/glm-scenario6.log 2>/dev/null || echo 0)
GLM_EDIT=$(grep -c "Edit\|✏️" /tmp/glm-scenario6.log 2>/dev/null || echo 0)
GLM_TOOLS=$((GLM_GREP + GLM_READ + GLM_EDIT))

# Validate
GLM_OLD_COUNT=$(git diff | grep -c "CheckInputScripts" 2>/dev/null || echo 0)
GLM_NEW_COUNT=$(git diff | grep -c "ValidateInputScripts" 2>/dev/null || echo 0)

echo ""
echo -e "${GREEN}✓ GLM Complete${NC}"
echo -e "  Time: ${GLM_DURATION}s"
echo -e "  Files: $GLM_FILES"
echo -e "  Lines: $GLM_LINES"
echo -e "  Tools: $GLM_TOOLS (${GLM_GREP}g + ${GLM_READ}r + ${GLM_EDIT}e)"
echo ""

# Save GLM diff
git diff > /tmp/glm-scenario6.diff

# ============================================================================
# COMPARISON
# ============================================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    RESULTS COMPARISON                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Time comparison
echo -e "${BLUE}⏱  Speed:${NC}"
echo "  Vanilla: ${VANILLA_DURATION}s"
echo "  GLM:     ${GLM_DURATION}s"

if [ "$GLM_DURATION" -lt "$GLM_DURATION" ]; then
    SPEEDUP=$(echo "scale=2; $VANILLA_DURATION / $GLM_DURATION" | bc)
    SAVED=$((VANILLA_DURATION - GLM_DURATION))
    echo -e "  ${GREEN}✓ GLM ${SPEEDUP}x faster! (saved ${SAVED}s)${NC}"
elif [ "$VANILLA_DURATION" -lt "$GLM_DURATION" ]; then
    SLOWDOWN=$(echo "scale=2; $GLM_DURATION / $VANILLA_DURATION" | bc)
    echo -e "  ${YELLOW}✓ Vanilla faster (GLM ${SLOWDOWN}x slower)${NC}"
else
    echo "  = Tie"
fi

echo ""

# Tool efficiency
echo -e "${BLUE}🔧 Tool Efficiency:${NC}"
echo "  Vanilla: $VANILLA_TOOLS total ($VANILLA_GREP grep, $VANILLA_READ read, $VANILLA_EDIT edit)"
echo "  GLM:     $GLM_TOOLS total ($GLM_GREP grep, $GLM_READ read, $GLM_EDIT edit)"

if [ "$GLM_TOOLS" -lt "$VANILLA_TOOLS" ]; then
    REDUCTION=$((VANILLA_TOOLS - GLM_TOOLS))
    PCT=$(echo "scale=1; $REDUCTION * 100 / $VANILLA_TOOLS" | bc)
    echo -e "  ${GREEN}✓ GLM ${PCT}% fewer tool calls ($REDUCTION less)${NC}"
elif [ "$VANILLA_TOOLS" -lt "$GLM_TOOLS" ]; then
    INCREASE=$((GLM_TOOLS - VANILLA_TOOLS))
    echo -e "  ${YELLOW}✓ Vanilla more efficient ($INCREASE fewer calls)${NC}"
else
    echo "  = Tie"
fi

echo ""

# Quality
echo -e "${BLUE}✅ Quality:${NC}"
echo "  Vanilla: $VANILLA_FILES files, $VANILLA_LINES lines changed"
echo "  GLM:     $GLM_FILES files, $GLM_LINES lines changed"

if [ "$VANILLA_FILES" -eq "$GLM_FILES" ] && [ "$VANILLA_LINES" -eq "$GLM_LINES" ]; then
    echo -e "  ${GREEN}✓ Identical changes${NC}"
else
    echo -e "  ${YELLOW}⚠ Different changes - manual review needed${NC}"
fi

echo ""

# Overall winner
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"

if [ "$GLM_DURATION" -lt "$VANILLA_DURATION" ] && [ "$GLM_TOOLS" -le "$VANILLA_TOOLS" ]; then
    echo -e "${GREEN}🏆 WINNER: GLM${NC}"
    echo "   Faster AND more efficient!"
elif [ "$VANILLA_DURATION" -lt "$GLM_DURATION" ] && [ "$VANILLA_TOOLS" -le "$GLM_TOOLS" ]; then
    echo -e "${YELLOW}🏆 WINNER: Vanilla${NC}"
    echo "   Faster AND more efficient"
else
    echo -e "${BLUE}🤝 MIXED RESULTS${NC}"
    echo "   Each system has advantages"
fi

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "Logs saved:"
echo "  - /tmp/vanilla-scenario6.log"
echo "  - /tmp/vanilla-scenario6.diff"
echo "  - /tmp/glm-scenario6.log"
echo "  - /tmp/glm-scenario6.diff"
