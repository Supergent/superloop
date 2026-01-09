#!/bin/bash
# Run all benchmark scenarios for both systems
# Usage: ./run-all-benchmarks.sh [iterations]

set -euo pipefail

ITERATIONS=${1:-3}  # Default to 3 iterations
SYSTEMS=("vanilla" "glm")
SCENARIOS=("scenario_1" "scenario_2" "scenario_3" "scenario_4" "scenario_5" "scenario_6" "scenario_7" "scenario_8")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Running Full Benchmark Suite ===${NC}"
echo "Iterations per scenario: $ITERATIONS"
echo "Total tests: $((${#SYSTEMS[@]} * ${#SCENARIOS[@]} * ITERATIONS))"
echo ""

# Confirm before proceeding
read -p "This will take several hours. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Make scripts executable
chmod +x run-benchmark.sh

TOTAL_TESTS=$((${#SYSTEMS[@]} * ${#SCENARIOS[@]} * ITERATIONS))
CURRENT_TEST=0

for iteration in $(seq 1 $ITERATIONS); do
    echo -e "${BLUE}=== Iteration $iteration/$ITERATIONS ===${NC}"

    for scenario in "${SCENARIOS[@]}"; do
        for system in "${SYSTEMS[@]}"; do
            CURRENT_TEST=$((CURRENT_TEST + 1))
            echo ""
            echo -e "${YELLOW}[$CURRENT_TEST/$TOTAL_TESTS] Running: $system / $scenario / iteration $iteration${NC}"

            # Run the benchmark
            if ./run-benchmark.sh "$system" "$scenario" "$iteration"; then
                echo -e "${GREEN}✓ Completed successfully${NC}"
            else
                echo -e "${RED}✗ Failed${NC}"
                # Continue with other tests even if one fails
            fi

            # Brief pause between tests to avoid rate limits
            echo "Pausing 10 seconds before next test..."
            sleep 10
        done
    done
done

echo ""
echo -e "${GREEN}=== All Benchmarks Complete ===${NC}"
echo "Results saved in: benchmark-results/"
echo "Run ./analyze-results.py to generate comparison report"
