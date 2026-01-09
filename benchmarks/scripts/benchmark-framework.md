# Claude Code GLM vs Vanilla Benchmark Framework

## Test Scenarios for Bitcoin Codebase

### SEARCH SCENARIOS (Find the needle)

### Scenario 1: Basic Needle (Warm-up)
**Prompt:** "Find where the coinbase transaction maturity check (100 blocks) is implemented"
**Expected:** Should find `COINBASE_MATURITY` constant and its usage
**Difficulty:** Easy - literal search should work

### Scenario 2: Semantic Understanding Required
**Prompt:** "Where does the code handle the case when a block's transactions would exceed the maximum block weight?"
**Expected:** Block validation logic, weight calculation, rejection handling
**Difficulty:** Medium - requires understanding of concepts, not just grep

### Scenario 3: Multi-hop Reasoning
**Prompt:** "Trace how a transaction's fee rate affects its priority in block template construction, from mempool to GetBlockTemplate RPC"
**Expected:** Mempool fee tracking → mining algorithm → RPC interface
**Difficulty:** Hard - requires following code flow across multiple files

### Scenario 4: Deep Architecture Understanding
**Prompt:** "Find all places where signature validation can be skipped due to caching, and explain how cache invalidation is handled during reorgs"
**Expected:** Script cache, signature cache, reorg handling
**Difficulty:** Very Hard - requires understanding of caching architecture

---

### EDIT SCENARIOS (Find and modify)

### Scenario 5: Simple Single-File Edit
**Prompt:** "Change the coinbase maturity constant from 100 blocks to 150 blocks. Update the constant definition and any related comments."
**Expected:** Edit COINBASE_MATURITY and comments
**Difficulty:** Easy - single constant change
**Relace Advantage:** Instant application vs manual edit

### Scenario 6: Multi-Location Refactor
**Prompt:** "Rename the function CheckInputScripts to ValidateInputScripts everywhere it's used. Make sure to update the declaration, definition, all call sites, and comments."
**Expected:** Find ~10-20 locations and rename consistently
**Difficulty:** Medium - requires finding all usages
**Relace Advantage:** Parallel edits vs sequential Edit calls

### Scenario 7: Logic Change Requiring Understanding
**Prompt:** "Modify the transaction relay policy to reject transactions with a fee rate below 5 sat/vB instead of the current 1 sat/vB. Update the constant, validation logic, and error messages."
**Expected:** Find constant, validation checks, error strings
**Difficulty:** Hard - multiple related changes
**Relace Advantage:** Coordinated multi-file edits

### Scenario 8: Add New Feature with Multiple Touchpoints
**Prompt:** "Add a new RPC parameter 'max_fee_rate' to the sendrawtransaction RPC that rejects transactions exceeding the specified fee rate. Add the parameter definition, validation logic, error handling, and update the help text."
**Expected:** RPC definition, parsing, validation, tests, docs
**Difficulty:** Very Hard - new feature across multiple layers
**Relace Advantage:** Large coordinated changes vs many sequential edits

## Metrics to Capture

### Automated Metrics
```json
{
  "test_id": "uuid",
  "system": "glm|vanilla",
  "scenario": "scenario_1",
  "timestamp_start": "iso8601",
  "timestamp_end": "iso8601",
  "duration_seconds": 0.0,
  "time_to_first_tool_call": 0.0,
  "time_to_first_result": 0.0,

  "tokens": {
    "input_total": 0,
    "output_total": 0,
    "cache_read": 0,
    "cache_write": 0
  },

  "tool_calls": {
    "total_count": 0,
    "by_type": {
      "grep": 0,
      "glob": 0,
      "read": 0,
      "edit": 0,
      "bash": 0,
      "task": 0
    },
    "sequence": ["grep", "read", "grep", "read"]
  },

  "grep_metrics": {
    "total_calls": 0,
    "avg_results_per_call": 0.0,
    "semantic_searches": 0,
    "literal_searches": 0
  },

  "edit_metrics": {
    "total_edits": 0,
    "files_modified": 0,
    "lines_changed": 0,
    "edit_latency_avg_ms": 0.0,
    "parallel_edits": false,
    "failed_edits": 0,
    "time_to_first_edit": 0.0,
    "time_to_last_edit": 0.0
  },

  "api_metrics": {
    "total_requests": 0,
    "avg_latency_ms": 0.0,
    "model": "claude-sonnet-4-5"
  },

  "success": true,
  "found_target": true,
  "hallucinated": false
}
```

### Qualitative Metrics (Manual Review)

**For Search Scenarios:**
- **Accuracy:** Did it find the right code? (0-10)
- **Completeness:** Did it find all relevant locations? (0-10)
- **Explanation Quality:** How well did it explain findings? (0-10)
- **Efficiency:** Was the search strategy optimal? (0-10)
- **Reasoning Quality:** Did it show good understanding? (0-10)

**For Edit Scenarios:**
- **Correctness:** Are all edits correct? (0-10)
- **Completeness:** Did it catch all locations? (0-10)
- **Safety:** Did it avoid breaking changes? (0-10)
- **Code Quality:** Are edits clean and idiomatic? (0-10)
- **Verification:** Did it verify changes compile/pass tests? (0-10)

### Comparison Metrics
- **Speed Ratio:** `vanilla_time / glm_time`
- **Tool Efficiency:** `vanilla_tool_calls / glm_tool_calls`
- **Token Efficiency:** `vanilla_tokens / glm_tokens`
- **Cost Ratio:** `vanilla_cost / glm_cost`

## Test Execution Protocol

### Pre-Test Setup

1. **Clone Fresh Bitcoin Repo (identical for both)**
   ```bash
   git clone https://github.com/bitcoin/bitcoin.git /tmp/bitcoin-test
   cd /tmp/bitcoin-test
   git checkout v26.0  # Pin to specific version
   ```

2. **Clear All Caches**
   ```bash
   # Clear Claude cache
   rm -rf ~/.cache/claude-*

   # Clear Mantic cache (GLM)
   # (whatever the cache location is)
   ```

3. **Prepare Monitoring**
   - Start `time` wrapper
   - Start token counter (via API logs)
   - Start tool call logger (via hook or wrapper)

### Execution Script Template

```bash
#!/bin/bash
# run-benchmark.sh

SYSTEM=$1  # "glm" or "vanilla"
SCENARIO=$2  # "scenario_1" etc
OUTPUT_DIR="benchmark-results"
TIMESTAMP=$(date +%s)
RESULT_FILE="${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_${TIMESTAMP}.json"

# Prepare environment
cd /tmp/bitcoin-test
export CLAUDE_LOG_LEVEL=debug
export BENCHMARK_MODE=1

# Run test with timeout (10 minutes max)
timeout 600 claude \
  --dangerously-skip-permissions \
  --output-json \
  chat "$(cat prompts/${SCENARIO}.txt)" \
  2>&1 | tee "${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_${TIMESTAMP}.log"

# Parse results into JSON
# (post-processing script to extract metrics)
./parse-results.py "${OUTPUT_DIR}/${SYSTEM}_${SCENARIO}_${TIMESTAMP}.log" > "$RESULT_FILE"
```

### Running the Tests

```bash
# Run on macOS (vanilla)
./run-benchmark.sh vanilla scenario_1
./run-benchmark.sh vanilla scenario_2
./run-benchmark.sh vanilla scenario_3
./run-benchmark.sh vanilla scenario_4

# Run on Orb VM (GLM)
orb run ./run-benchmark.sh glm scenario_1
orb run ./run-benchmark.sh glm scenario_2
orb run ./run-benchmark.sh glm scenario_3
orb run ./run-benchmark.sh glm scenario_4

# Optional: Run multiple iterations
for i in {1..3}; do
  for scenario in scenario_{1..4}; do
    ./run-benchmark.sh vanilla $scenario
    orb run ./run-benchmark.sh glm $scenario
  done
done
```

## Analysis & Visualization

### Statistical Analysis
- Mean, median, std dev for each metric
- T-tests for significance
- Effect sizes (Cohen's d)

### Visualizations Needed
1. **Time comparison** (bar chart per scenario)
2. **Tool call sequences** (Sankey diagram)
3. **Token usage** (stacked bar chart)
4. **Success rate** (radar chart of qualitative metrics)
5. **Efficiency scatter** (time vs accuracy)

### Report Structure
```markdown
# Claude-Code-GLM vs Vanilla Benchmark Results

## Executive Summary
- Winner by metric
- Key findings
- Recommendations

## Detailed Results
### Scenario 1: Basic Needle
- Time: GLM 12s vs Vanilla 18s (1.5x faster)
- Tools: GLM 4 calls vs Vanilla 7 calls
- Quality: Both 10/10
- Analysis: Semantic search eliminated false positives

[... repeat for each scenario ...]

## Statistical Analysis
- Overall speed improvement: X%
- Tool call reduction: Y%
- Cost implications: Z%

## Conclusions & Next Steps
```

## Implementation Checklist

- [ ] Create fresh Bitcoin clone in neutral location
- [ ] Set up logging infrastructure
  - [ ] Token counter
  - [ ] Tool call tracker
  - [ ] Timing harness
- [ ] Write test prompts (4 scenarios)
- [ ] Create execution scripts
- [ ] Set up result collection
- [ ] Run vanilla tests (3 iterations × 4 scenarios)
- [ ] Run GLM tests (3 iterations × 4 scenarios)
- [ ] Manual quality review
- [ ] Statistical analysis
- [ ] Generate visualizations
- [ ] Write report

## Potential Issues & Mitigations

### Issue: Network Latency Variance
**Mitigation:** Run multiple iterations, use median times

### Issue: API Caching
**Mitigation:** Use different prompts with same intent, or add timestamp to prompt

### Issue: Non-deterministic Reasoning
**Mitigation:** Run multiple iterations, focus on aggregate metrics

### Issue: Orb VM Overhead
**Mitigation:** Measure baseline overhead separately, normalize results

### Issue: Different Model Versions
**Mitigation:** Document exact model IDs, consider this in analysis

## Cost Estimation

**Per Test Run:**
- Estimated tokens: ~50k-200k depending on scenario
- Vanilla cost: ~$1-4 per run
- GLM cost: Cerebras pricing (likely cheaper)
- Total for full suite: ~$50-100 per system

**Time Investment:**
- Setup: 2-3 hours
- Test execution: 4-6 hours (including iterations)
- Analysis: 2-4 hours
- Total: ~8-13 hours

## Expected Outcomes

### GLM Should Win On:
- Semantic search tasks (scenarios 2, 4)
- Tool call efficiency (fewer false positives)
- Potentially speed (Cerebras + better tools)

### Vanilla Might Win On:
- Simple literal searches (scenario 1)
- Stability/consistency
- Lower per-request latency (no VM overhead)

### Uncertain:
- Overall cost (depends on Cerebras pricing)
- Reasoning quality (same model)
- Complex multi-hop tasks (depends on tool interaction)
