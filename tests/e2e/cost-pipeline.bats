#!/usr/bin/env bats
# End-to-end tests for cost tracking pipeline
# Tests the flow: runner execution → usage extraction → cost calculation → report

setup() {
  # Create temporary directory for test files
  TEMP_DIR=$(mktemp -d)
  export TEMP_DIR

  # Source required modules
  source "$BATS_TEST_DIRNAME/../../src/00-header.sh"
  source "$BATS_TEST_DIRNAME/../../src/35-usage.sh"
  source "$BATS_TEST_DIRNAME/../../src/37-pricing.sh"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# ============================================================================
# End-to-End Pipeline Tests
# ============================================================================

@test "e2e-cost: complete pipeline from Claude session to cost calculation" {
  # Create mock Claude session file
  local session_file="$TEMP_DIR/claude-session.jsonl"
  cat > "$session_file" << 'EOF'
{"type":"assistant","message":{"id":"msg_123","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":500,"thinking_tokens":100}}}
{"type":"assistant","message":{"id":"msg_124","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":2000,"output_tokens":800,"thinking_tokens":200}}}
EOF

  # Step 1: Extract usage
  local usage=$(extract_claude_usage "$session_file")

  # Verify usage extraction
  local input=$(echo "$usage" | jq -r '.input_tokens')
  local output=$(echo "$usage" | jq -r '.output_tokens')
  local thinking=$(echo "$usage" | jq -r '.thinking_tokens')

  [ "$input" = "3000" ]
  [ "$output" = "1300" ]
  [ "$thinking" = "300" ]

  # Step 2: Extract model
  local model=$(extract_claude_model "$session_file")
  [ "$model" = "claude-sonnet-4-5-20250929" ]

  # Step 3: Calculate cost
  local cost=$(calculate_claude_cost "$model" "$usage")

  # Verify cost calculation is non-zero and reasonable
  # input: 3000 tokens * $3/MTok = $0.009
  # output: 1300 tokens * $15/MTok = $0.0195
  # thinking: 300 tokens * $15/MTok = $0.0045
  # total should be around $0.033
  [[ "$cost" != "0.000000" ]]

  # Check cost is in reasonable range ($0.01 to $0.10)
  local cost_val=$(echo "$cost" | awk '{printf "%.0f", $1 * 1000}')
  [ "$cost_val" -gt 10 ]
  [ "$cost_val" -lt 100 ]

  # Step 4: Format cost
  local formatted=$(format_cost "$cost")
  [[ "$formatted" == \$0.* ]]
}

@test "e2e-cost: complete pipeline from Codex session to cost calculation" {
  # Create mock Codex session file with proper event structure
  # Note: extract_codex_usage takes the LAST token_count event (cumulative totals)
  local session_file="$TEMP_DIR/codex-session.jsonl"
  cat > "$session_file" << 'EOF'
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"output_tokens":1000,"reasoning_output_tokens":300,"cached_input_tokens":0}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5000,"output_tokens":2500,"reasoning_output_tokens":700,"cached_input_tokens":1000}}}}
{"model":"gpt-5.2-codex"}
EOF

  # Step 1: Extract usage (takes last token_count event)
  local usage=$(extract_codex_usage "$session_file")

  # Verify usage extraction
  local input=$(echo "$usage" | jq -r '.input_tokens')
  local output=$(echo "$usage" | jq -r '.output_tokens')
  local cached=$(echo "$usage" | jq -r '.cached_input_tokens')
  local reasoning_output=$(echo "$usage" | jq -r '.reasoning_output_tokens')

  [ "$input" = "5000" ]
  [ "$output" = "2500" ]
  [ "$cached" = "1000" ]
  [ "$reasoning_output" = "700" ]

  # Step 2: Extract model
  local model=$(extract_codex_model "$session_file")
  [ "$model" = "gpt-5.2-codex" ]

  # Step 3: Calculate cost
  local cost=$(calculate_codex_cost "$model" "$usage")

  # Verify cost (with reasoning and cache tokens)
  # This will vary based on Codex pricing, but should be non-zero
  [[ "$cost" != "0.000000" ]]

  # Step 4: Format cost
  local formatted=$(format_cost "$cost")
  [[ "$formatted" == \$* ]]
}

@test "e2e-cost: multi-iteration usage aggregation" {
  local usage_file="$TEMP_DIR/usage.jsonl"

  # Write usage events for multiple iterations
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Iteration 1
  jq -c -n \
    --arg ts "$timestamp" \
    --arg model "claude-sonnet-4-5-20250929" \
    '{
      timestamp: $ts,
      iteration: 1,
      role: "planner",
      runner: "claude",
      model: $model,
      usage: {input_tokens: 1000, output_tokens: 500, thinking_tokens: 100},
      cost_usd: 0.0105
    }' >> "$usage_file"

  # Iteration 2
  jq -c -n \
    --arg ts "$timestamp" \
    --arg model "claude-sonnet-4-5-20250929" \
    '{
      timestamp: $ts,
      iteration: 2,
      role: "implementer",
      runner: "claude",
      model: $model,
      usage: {input_tokens: 2000, output_tokens: 800, thinking_tokens: 200},
      cost_usd: 0.021
    }' >> "$usage_file"

  # Aggregate usage
  local total_cost=$(jq -s 'map(.cost_usd) | add' "$usage_file")
  local total_input=$(jq -s 'map(.usage.input_tokens) | add' "$usage_file")
  local total_output=$(jq -s 'map(.usage.output_tokens) | add' "$usage_file")

  [ "$total_input" = "3000" ]
  [ "$total_output" = "1300" ]

  # Cost should be sum of iterations (0.0105 + 0.021 = 0.0315)
  # Check it's in the right range
  local cost_cents=$(awk -v cost="$total_cost" 'BEGIN {printf "%.0f", cost * 100}')
  [ "$cost_cents" -eq 3 ]
}

@test "e2e-cost: mixed runner cost aggregation" {
  local usage_file="$TEMP_DIR/usage.jsonl"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Claude usage
  jq -c -n \
    --arg ts "$timestamp" \
    '{
      timestamp: $ts,
      iteration: 1,
      role: "planner",
      runner: "claude",
      model: "claude-sonnet-4-5-20250929",
      usage: {input_tokens: 1000, output_tokens: 500, thinking_tokens: 100},
      cost_usd: 0.0105
    }' >> "$usage_file"

  # Codex usage
  jq -c -n \
    --arg ts "$timestamp" \
    '{
      timestamp: $ts,
      iteration: 1,
      role: "implementer",
      runner: "codex",
      model: "gpt-5.2-codex",
      usage: {input_tokens: 2000, output_tokens: 1000, reasoning_input_tokens: 500, reasoning_output_tokens: 300},
      cost_usd: 0.025
    }' >> "$usage_file"

  # Aggregate by runner
  local claude_cost=$(jq -s 'map(select(.runner == "claude") | .cost_usd) | add' "$usage_file")
  local codex_cost=$(jq -s 'map(select(.runner == "codex") | .cost_usd) | add' "$usage_file")
  local total_cost=$(jq -s 'map(.cost_usd) | add' "$usage_file")

  [ "$claude_cost" = "0.0105" ]
  [ "$codex_cost" = "0.025" ]

  # Total should be sum of both (0.0105 + 0.025 = 0.0355)
  # Check it's in the right range (about 3.6 cents)
  local cost_cents=$(awk -v cost="$total_cost" 'BEGIN {printf "%.0f", cost * 100}')
  [ "$cost_cents" -ge 3 ]
  [ "$cost_cents" -le 4 ]
}

# ============================================================================
# Usage Event Writing Tests
# ============================================================================

@test "e2e-cost: usage events written in correct JSONL format" {
  local usage_file="$TEMP_DIR/usage.jsonl"

  # Write multiple events with correct signature
  # write_usage_event(usage_file, iteration, role, duration_ms, usage_json, runner_type, session_file)
  write_usage_event "$usage_file" 1 "planner" 30000 \
    '{"input_tokens":1000,"output_tokens":500,"thinking_tokens":100}' "claude" ""

  write_usage_event "$usage_file" 1 "implementer" 45000 \
    '{"input_tokens":2000,"output_tokens":800,"thinking_tokens":200}' "claude" ""

  # Verify file has exactly 2 lines
  local line_count=$(wc -l < "$usage_file" | tr -d ' ')
  [ "$line_count" = "2" ]

  # Verify each line is valid JSON
  head -n 1 "$usage_file" | jq empty
  tail -n 1 "$usage_file" | jq empty

  # Verify each line is compact (no newlines within)
  # Each line should have exactly the expected fields
  local first_role=$(head -n 1 "$usage_file" | jq -r '.role')
  local second_role=$(tail -n 1 "$usage_file" | jq -r '.role')

  [ "$first_role" = "planner" ]
  [ "$second_role" = "implementer" ]
}

# ============================================================================
# Cost Formatter Tests
# ============================================================================

@test "e2e-cost: cost formatters produce human-readable output" {
  # Test dollar formatting (format_cost uses 4 decimals for < $0.01, 3 for < $1, 2 for >= $1)
  [ "$(format_cost '0.000500')" = "\$0.0005" ]
  [ "$(format_cost '0.005000')" = "\$0.0050" ]
  [ "$(format_cost '0.150000')" = "\$0.150" ]
  [ "$(format_cost '1.500000')" = "\$1.50" ]
  [ "$(format_cost '15.000000')" = "\$15.00" ]

  # Test token formatting
  [ "$(format_tokens '500')" = "500" ]
  [ "$(format_tokens '1500')" = "1.5K" ]
  [ "$(format_tokens '1500000')" = "1.5M" ]

  # Test duration formatting (input is milliseconds)
  [ "$(format_duration '45000')" = "45s" ]
  [ "$(format_duration '90000')" = "1m 30s" ]
  [ "$(format_duration '3665000')" = "1h 1m 5s" ]
}

# ============================================================================
# Pricing Table Tests
# ============================================================================

@test "e2e-cost: pricing table has all supported models" {
  # Claude models
  local claude_sonnet=$(get_model_pricing "claude-sonnet-4-5-20250929")
  [[ "$claude_sonnet" != "" ]]
  echo "$claude_sonnet" | jq -e '.input'

  local claude_opus=$(get_model_pricing "claude-opus-4-5-20241101")
  [[ "$claude_opus" != "" ]]
  echo "$claude_opus" | jq -e '.input'

  # Codex models
  local codex_52=$(get_model_pricing "gpt-5.2-codex")
  [[ "$codex_52" != "" ]]
  echo "$codex_52" | jq -e '.input'

  local codex_50=$(get_model_pricing "gpt-5.0-codex")
  [[ "$codex_50" != "" ]]
  echo "$codex_50" | jq -e '.input'
}

@test "e2e-cost: unknown models get fallback pricing" {
  local unknown=$(get_model_pricing "unknown-model-xyz")
  [[ "$unknown" != "" ]]

  # Should have fallback pricing
  local input_price=$(echo "$unknown" | jq -r '.input_per_mtok')
  [[ "$input_price" != "null" ]]
  [[ "$input_price" != "" ]]
}

# ============================================================================
# Integration with Report Generation
# ============================================================================

@test "e2e-cost: usage data ready for report inclusion" {
  local usage_file="$TEMP_DIR/usage.jsonl"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Create realistic usage data
  for i in {1..3}; do
    jq -c -n \
      --arg ts "$timestamp" \
      --arg iter "$i" \
      '{
        timestamp: $ts,
        iteration: ($iter | tonumber),
        role: "implementer",
        runner: "claude",
        model: "claude-sonnet-4-5-20250929",
        usage: {input_tokens: 5000, output_tokens: 2000, thinking_tokens: 500},
        cost_usd: 0.040
      }' >> "$usage_file"
  done

  # Calculate summary stats for report
  local total_iterations=$(jq -s 'length' "$usage_file")
  local total_cost=$(jq -s 'map(.cost_usd) | add' "$usage_file")
  local avg_cost=$(jq -s 'map(.cost_usd) | add / length' "$usage_file")
  local total_tokens=$(jq -s 'map(.usage.input_tokens + .usage.output_tokens + .usage.thinking_tokens) | add' "$usage_file")

  [ "$total_iterations" = "3" ]
  [ "$total_cost" = "0.12" ]
  [ "$avg_cost" = "0.04" ]
  [ "$total_tokens" = "22500" ]
}

@test "e2e-cost: per-role cost breakdown available" {
  local usage_file="$TEMP_DIR/usage.jsonl"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Add events for different roles
  for role in planner implementer tester reviewer; do
    jq -c -n \
      --arg ts "$timestamp" \
      --arg role "$role" \
      '{
        timestamp: $ts,
        iteration: 1,
        role: $role,
        runner: "claude",
        model: "claude-sonnet-4-5-20250929",
        usage: {input_tokens: 1000, output_tokens: 500, thinking_tokens: 100},
        cost_usd: 0.0105
      }' >> "$usage_file"
  done

  # Calculate per-role costs
  local planner_cost=$(jq -s 'map(select(.role == "planner") | .cost_usd) | add' "$usage_file")
  local implementer_cost=$(jq -s 'map(select(.role == "implementer") | .cost_usd) | add' "$usage_file")
  local tester_cost=$(jq -s 'map(select(.role == "tester") | .cost_usd) | add' "$usage_file")
  local reviewer_cost=$(jq -s 'map(select(.role == "reviewer") | .cost_usd) | add' "$usage_file")

  [ "$planner_cost" = "0.0105" ]
  [ "$implementer_cost" = "0.0105" ]
  [ "$tester_cost" = "0.0105" ]
  [ "$reviewer_cost" = "0.0105" ]
}
