#!/bin/bash
# GLM vs Vanilla Claude Code Benchmark Runner
# Usage: ./run-benchmark.sh [glm|vanilla] [scenario_1-8] [iteration_number]

set -euo pipefail

SYSTEM=$1  # "glm" or "vanilla"
SCENARIO=$2  # "scenario_1" through "scenario_8"
ITERATION=${3:-1}
BITCOIN_REPO="/tmp/bitcoin-benchmark"
OUTPUT_DIR="benchmark-results"
TIMESTAMP=$(date +%s)
RESULT_FILE="${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_iter${ITERATION}_${TIMESTAMP}.json"
LOG_FILE="${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_iter${ITERATION}_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== GLM vs Vanilla Benchmark ===${NC}"
echo "System: $SYSTEM"
echo "Scenario: $SCENARIO"
echo "Iteration: $ITERATION"
echo "Timestamp: $TIMESTAMP"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Ensure we're in the Bitcoin repo
if [ ! -d "$BITCOIN_REPO" ]; then
    echo -e "${RED}Error: Bitcoin repo not found at $BITCOIN_REPO${NC}"
    echo "Run setup-benchmark.sh first"
    exit 1
fi

cd "$BITCOIN_REPO"

# Reset repo to clean state (critical for edit scenarios)
echo -e "${YELLOW}Resetting repo to clean state...${NC}"
git reset --hard HEAD
git clean -fd

# Load the prompt from JSON
PROMPT=$(jq -r ".${SCENARIO}.prompt" < ../superloop/benchmark-prompts.json)
SCENARIO_TYPE=$(jq -r ".${SCENARIO}.type // \"search\"" < ../superloop/benchmark-prompts.json)

echo -e "${GREEN}Prompt:${NC} $PROMPT"
echo -e "${GREEN}Type:${NC} $SCENARIO_TYPE"
echo ""

# Set up environment
export CLAUDE_LOG_LEVEL=info
export BENCHMARK_MODE=1
export BENCHMARK_SCENARIO=$SCENARIO
export BENCHMARK_SYSTEM=$SYSTEM

# Pre-test snapshot (for edit validation)
if [ "$SCENARIO_TYPE" = "edit" ]; then
    echo -e "${YELLOW}Creating pre-edit snapshot...${NC}"
    git diff > "${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_iter${ITERATION}_pre.diff"
fi

# Start timing
START_TIME=$(date +%s.%N)

# Run the appropriate Claude Code version
echo -e "${GREEN}Starting test run...${NC}"
if [ "$SYSTEM" = "glm" ]; then
    # GLM runs in Orb VM with enhanced tools
    echo -e "${YELLOW}Running Claude-Code-GLM in Orb VM...${NC}"
    # TODO: Update with actual orb command
    # orb run -- claude --dangerously-skip-permissions chat "$PROMPT" 2>&1 | tee "$LOG_FILE"
    echo "ERROR: Orb VM execution not yet implemented" | tee "$LOG_FILE"
    exit 1
else
    # Vanilla runs directly on macOS
    echo -e "${YELLOW}Running Vanilla Claude Code...${NC}"
    timeout 600 claude \
        --dangerously-skip-permissions \
        chat "$PROMPT" \
        2>&1 | tee "$LOG_FILE"
fi

# End timing
END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc)

echo ""
echo -e "${GREEN}Test completed in ${DURATION}s${NC}"

# Post-test validation for edit scenarios
if [ "$SCENARIO_TYPE" = "edit" ]; then
    echo -e "${YELLOW}Capturing post-edit state...${NC}"
    git diff > "${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_iter${ITERATION}_post.diff"

    # Count modified files
    FILES_MODIFIED=$(git diff --name-only | wc -l)

    # Count lines changed
    LINES_CHANGED=$(git diff --shortstat | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ - | bc || echo 0)

    echo -e "${GREEN}Files modified: ${FILES_MODIFIED}${NC}"
    echo -e "${GREEN}Lines changed: ${LINES_CHANGED}${NC}"

    # Run validation command if specified
    VALIDATION_CMD=$(jq -r ".${SCENARIO}.validation // \"\"" < ../superloop/benchmark-prompts.json)
    if [ -n "$VALIDATION_CMD" ] && [ "$VALIDATION_CMD" != "null" ]; then
        echo -e "${YELLOW}Running validation: ${VALIDATION_CMD}${NC}"
        if eval "$VALIDATION_CMD" > "${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_iter${ITERATION}_validation.txt" 2>&1; then
            echo -e "${GREEN}✓ Validation passed${NC}"
            VALIDATION_PASSED=true
        else
            echo -e "${RED}✗ Validation failed${NC}"
            VALIDATION_PASSED=false
        fi
    fi

    # Try to compile (optional - can be slow)
    # echo -e "${YELLOW}Testing if code compiles...${NC}"
    # if ./autogen.sh && ./configure && make -j4; then
    #     echo -e "${GREEN}✓ Code compiles${NC}"
    # else
    #     echo -e "${RED}✗ Code does not compile${NC}"
    # fi
fi

# Parse log file for metrics
echo -e "${YELLOW}Parsing metrics from log...${NC}"

# Extract token counts (if available in logs)
# This depends on Claude Code's logging format
# TODO: Customize based on actual log format

# Create result JSON
cat > "$RESULT_FILE" <<EOF
{
  "test_id": "${SYSTEM}_${SCENARIO}_iter${ITERATION}_${TIMESTAMP}",
  "system": "$SYSTEM",
  "scenario": "$SCENARIO",
  "scenario_type": "$SCENARIO_TYPE",
  "iteration": $ITERATION,
  "timestamp_start": $START_TIME,
  "timestamp_end": $END_TIME,
  "duration_seconds": $DURATION,
  "prompt": $(echo "$PROMPT" | jq -Rs .),

  "edit_metrics": {
    "files_modified": ${FILES_MODIFIED:-0},
    "lines_changed": ${LINES_CHANGED:-0},
    "validation_passed": ${VALIDATION_PASSED:-null}
  },

  "log_file": "$LOG_FILE",
  "diff_file": "${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_iter${ITERATION}_post.diff"
}
EOF

echo -e "${GREEN}Results saved to: $RESULT_FILE${NC}"
echo ""

# Reset repo after test
echo -e "${YELLOW}Resetting repo for next test...${NC}"
git reset --hard HEAD
git clean -fd

echo -e "${GREEN}=== Benchmark complete ===${NC}"
