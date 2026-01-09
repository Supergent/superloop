#!/bin/bash
# Setup script for GLM vs Vanilla benchmark
# Clones Bitcoin repo and prepares environment

set -euo pipefail

BITCOIN_REPO="/tmp/bitcoin-benchmark"
BITCOIN_VERSION="v26.0"  # Pin to specific version for consistency

echo "=== Benchmark Setup ==="
echo "Target directory: $BITCOIN_REPO"
echo "Bitcoin version: $BITCOIN_VERSION"
echo ""

# Remove existing repo if present
if [ -d "$BITCOIN_REPO" ]; then
    echo "Removing existing Bitcoin repo..."
    rm -rf "$BITCOIN_REPO"
fi

# Clone Bitcoin
echo "Cloning Bitcoin repository..."
git clone --branch "$BITCOIN_VERSION" --depth 1 \
    https://github.com/bitcoin/bitcoin.git \
    "$BITCOIN_REPO"

cd "$BITCOIN_REPO"

# Verify checkout
CURRENT_VERSION=$(git describe --tags)
echo "Checked out: $CURRENT_VERSION"

# Create output directory
mkdir -p "$(dirname "$0")/benchmark-results"

# Clear any existing caches
echo ""
echo "Clearing caches..."
rm -rf ~/.cache/claude-* 2>/dev/null || true

# TODO: Clear Mantic cache if applicable
# rm -rf ~/.cache/mantic-* 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
echo "Bitcoin repo ready at: $BITCOIN_REPO"
echo "Run benchmarks with: ./run-benchmark.sh [glm|vanilla] [scenario_1-8]"
