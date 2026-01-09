# Claude-Code-GLM vs Vanilla Benchmark - Quick Start Guide

## What This Tests

This benchmark compares two systems:

1. **Claude-Code-GLM (Orb VM)**: Enhanced with Cerebras inference, Mantic semantic search, and Relace instant edit
2. **Vanilla Claude Code (macOS)**: Standard implementation

We test both **search** and **edit** scenarios on the Bitcoin codebase to measure:
- Speed (time to completion)
- Tool efficiency (number of tool calls)
- Edit accuracy (files modified, validation success)
- Reasoning quality

## Test Scenarios

### Search Scenarios (1-4)
1. **Basic Needle**: Find COINBASE_MATURITY constant
2. **Semantic Search**: Block weight validation logic
3. **Multi-hop Reasoning**: Fee priority through mempool→mining→RPC
4. **Deep Architecture**: Signature caching and reorg handling

### Edit Scenarios (5-8)
5. **Simple Edit**: Change one constant value
6. **Multi-location Refactor**: Rename function across codebase
7. **Logic Change**: Update fee policy threshold
8. **New Feature**: Add RPC parameter with validation

## Quick Start (5 minutes for single test)

### 1. Setup
```bash
cd /Users/multiplicity/Work/superloop

# Make scripts executable
chmod +x setup-benchmark.sh run-benchmark.sh run-all-benchmarks.sh analyze-results.py

# Clone Bitcoin repo and prepare environment
./setup-benchmark.sh
```

### 2. Run Single Test (for testing)
```bash
# Test vanilla on simple scenario
./run-benchmark.sh vanilla scenario_1 1

# Test GLM on simple scenario (after configuring Orb)
./run-benchmark.sh glm scenario_1 1
```

### 3. Run Full Suite (several hours)
```bash
# Run all scenarios, 3 iterations each
./run-all-benchmarks.sh 3

# Or just specific scenarios
for i in 1 2 3; do
  ./run-benchmark.sh vanilla scenario_5 $i
  ./run-benchmark.sh glm scenario_5 $i
done
```

### 4. Analyze Results
```bash
# Generate comparison report
./analyze-results.py --output benchmark-report.md

# View report
cat benchmark-report.md
```

## What to Expect

### GLM Should Excel At:
- **Semantic searches** (scenarios 2, 4) - Mantic eliminates false positives
- **Multi-file edits** (scenarios 6, 7, 8) - Relace instant apply
- **Overall speed** - Cerebras inference + better tools

### Vanilla Might Excel At:
- **Simple literal searches** (scenario 1) - no semantic overhead
- **Stability** - no VM overhead
- **Single-file edits** (scenario 5) - less coordination needed

## Output Files

Each test generates:
```
benchmark-results/
├── vanilla_scenario_1_iter1_1704844800.json   # Metrics
├── vanilla_scenario_1_iter1_1704844800.log    # Full log
├── vanilla_scenario_1_iter1_1704844800_post.diff  # Git diff (for edits)
└── vanilla_scenario_1_iter1_1704844800_validation.txt  # Validation output
```

## Reading the Results

### JSON Metrics
```json
{
  "duration_seconds": 12.5,
  "edit_metrics": {
    "files_modified": 3,
    "lines_changed": 15,
    "validation_passed": true
  }
}
```

### Markdown Report
The analysis script generates a report with:
- Executive summary (average speedup, winner)
- Per-scenario breakdown (time, edits, validation)
- Statistical comparison table
- Recommendations

## Troubleshooting

### "Bitcoin repo not found"
Run `./setup-benchmark.sh` first

### "Orb VM execution not yet implemented"
Update `run-benchmark.sh` line ~60 with your actual Orb command:
```bash
orb run -- claude --dangerously-skip-permissions chat "$PROMPT"
```

### Tests timing out
Increase timeout in `run-benchmark.sh` line ~58:
```bash
timeout 600  # 10 minutes, increase if needed
```

### Different results each run
This is normal due to non-deterministic LLM behavior. Run multiple iterations and use median values.

## Advanced Usage

### Custom Scenarios
Edit `benchmark-prompts.json` to add your own:
```json
"scenario_9_custom": {
  "name": "My Custom Test",
  "difficulty": "medium",
  "type": "edit",
  "prompt": "Your prompt here...",
  "expected_files": ["src/foo.cpp"],
  "validation": "grep 'expected_change' src/foo.cpp"
}
```

### Measure Token Usage
Enable detailed logging:
```bash
export CLAUDE_LOG_LEVEL=debug
./run-benchmark.sh vanilla scenario_1 1
# Parse tokens from log file
```

### Test Other Codebases
Modify `setup-benchmark.sh` to clone a different repo:
```bash
BITCOIN_REPO="/tmp/linux-benchmark"
git clone --depth 1 https://github.com/torvalds/linux.git "$BITCOIN_REPO"
```

## Time & Cost Estimates

### Single Scenario (1 iteration)
- Search: 30s - 5min
- Edit: 1min - 10min
- Cost: ~$0.50 - $2.00 per run

### Full Suite (8 scenarios × 3 iterations × 2 systems)
- Time: 4-8 hours
- Cost: ~$50-100 total
- Recommendation: Run overnight

## Next Steps After Benchmarking

1. **Analyze tool call patterns**: Which searches were more efficient?
2. **Review edit quality**: Did Relace make cleaner edits?
3. **Profile Orb overhead**: How much does VM add?
4. **Test other codebases**: Linux kernel, Chromium, LLVM
5. **Measure cost per task**: Token usage × pricing

## Key Metrics to Watch

### Speed
- **Duration**: Total time to complete task
- **Time to first tool call**: How fast did it start working?
- **Time to first result**: When did it find the needle?

### Efficiency
- **Tool calls**: Fewer is better (less API overhead)
- **Grep precision**: Fewer false positives means better semantic search
- **Edit count**: Parallel edits should reduce this

### Quality
- **Validation success**: Did the edit work correctly?
- **Files modified**: Did it find all locations?
- **Code compiles**: No breaking changes?

## Expected Outcomes

If GLM is properly configured with Mantic + Relace + Cerebras:
- **1.5-3x speedup** on edit scenarios
- **Fewer tool calls** due to semantic search
- **Higher validation success** due to instant edit accuracy
- **Lower latency** if Cerebras is faster than Claude API

If these don't materialize, investigate:
- Orb VM overhead
- Mantic semantic search configuration
- Relace integration
- Network latency to Cerebras
