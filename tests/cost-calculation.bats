#!/usr/bin/env bats
# Tests for src/37-pricing.sh - Cost calculation and pricing

setup() {
  # Create temporary directory for test files
  TEMP_DIR=$(mktemp -d)
  export TEMP_DIR

  # Source the pricing module
  source "$BATS_TEST_DIRNAME/../src/37-pricing.sh"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# ============================================================================
# Pricing Lookup Tests
# ============================================================================

@test "pricing: get_model_pricing returns correct pricing for Claude Sonnet 4.5" {
  result=$(get_model_pricing "claude-sonnet-4-5")

  input=$(echo "$result" | jq -r '.input')
  output=$(echo "$result" | jq -r '.output')
  thinking=$(echo "$result" | jq -r '.thinking')
  cache_read=$(echo "$result" | jq -r '.cache_read')
  cache_write=$(echo "$result" | jq -r '.cache_write')

  [ "$input" = "3" ]
  [ "$output" = "15" ]
  [ "$thinking" = "15" ]
  [ "$cache_read" = "0.30" ]
  [ "$cache_write" = "3.75" ]
}

@test "pricing: get_model_pricing returns correct pricing for Claude Sonnet 4.5 with date suffix" {
  result=$(get_model_pricing "claude-sonnet-4-5-20250929")

  input=$(echo "$result" | jq -r '.input')
  [ "$input" = "3" ]
}

@test "pricing: get_model_pricing returns correct pricing for Claude Opus 4.5" {
  result=$(get_model_pricing "claude-opus-4-5")

  input=$(echo "$result" | jq -r '.input')
  output=$(echo "$result" | jq -r '.output')

  [ "$input" = "5" ]
  [ "$output" = "25" ]
}

@test "pricing: get_model_pricing returns correct pricing for Claude Haiku 4.5" {
  result=$(get_model_pricing "claude-haiku-4-5")

  input=$(echo "$result" | jq -r '.input')
  output=$(echo "$result" | jq -r '.output')

  [ "$input" = "1" ]
  [ "$output" = "5" ]
}

@test "pricing: get_model_pricing returns correct pricing for Claude Opus 4" {
  result=$(get_model_pricing "claude-opus-4")

  input=$(echo "$result" | jq -r '.input')
  output=$(echo "$result" | jq -r '.output')

  [ "$input" = "15" ]
  [ "$output" = "75" ]
}

@test "pricing: get_model_pricing returns correct pricing for Codex gpt-5.2" {
  result=$(get_model_pricing "gpt-5.2-codex")

  input=$(echo "$result" | jq -r '.input')
  output=$(echo "$result" | jq -r '.output')
  reasoning=$(echo "$result" | jq -r '.reasoning')
  cached_input=$(echo "$result" | jq -r '.cached_input')

  [ "$input" = "1.75" ]
  [ "$output" = "14" ]
  [ "$reasoning" = "14" ]
  [ "$cached_input" = "0.18" ]
}

@test "pricing: get_model_pricing returns correct pricing for Codex gpt-5.1" {
  result=$(get_model_pricing "gpt-5.1-codex")

  input=$(echo "$result" | jq -r '.input')
  output=$(echo "$result" | jq -r '.output')

  [ "$input" = "1.25" ]
  [ "$output" = "10" ]
}

@test "pricing: get_model_pricing handles unknown models with fallback" {
  result=$(get_model_pricing "unknown-model-xyz")

  # Should use Sonnet 4.5 pricing as fallback
  input=$(echo "$result" | jq -r '.input')
  output=$(echo "$result" | jq -r '.output')

  [ "$input" = "3" ]
  [ "$output" = "15" ]
}

@test "pricing: get_model_pricing handles alternate naming (4.5 vs 4-5)" {
  result=$(get_model_pricing "claude-sonnet-4.5")

  input=$(echo "$result" | jq -r '.input')
  [ "$input" = "3" ]
}

# ============================================================================
# Claude Cost Calculation Tests
# ============================================================================

@test "pricing: calculate_claude_cost computes correct USD amount for basic usage" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"thinking_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}'

  result=$(calculate_claude_cost "claude-sonnet-4-5" "$usage")

  # input: 1M tokens * $3/MTok = $3.00
  # output: 500K tokens * $15/MTok = $7.50
  # total: $10.50
  [ "$result" = "10.500000" ]
}

@test "pricing: calculate_claude_cost includes thinking tokens separately" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"thinking_tokens":100000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}'

  result=$(calculate_claude_cost "claude-sonnet-4-5" "$usage")

  # input: 1M * $3 = $3.00
  # output: 500K * $15 = $7.50
  # thinking: 100K * $15 = $1.50
  # total: $12.00
  [ "$result" = "12.000000" ]
}

@test "pricing: calculate_claude_cost includes cache read tokens at discounted rate" {
  local usage='{"input_tokens":1000000,"output_tokens":0,"thinking_tokens":0,"cache_read_input_tokens":500000,"cache_creation_input_tokens":0}'

  result=$(calculate_claude_cost "claude-sonnet-4-5" "$usage")

  # input: 1M * $3 = $3.00
  # cache_read: 500K * $0.30 = $0.15
  # total: $3.15
  [ "$result" = "3.150000" ]
}

@test "pricing: calculate_claude_cost includes cache write tokens" {
  local usage='{"input_tokens":1000000,"output_tokens":0,"thinking_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":500000}'

  result=$(calculate_claude_cost "claude-sonnet-4-5" "$usage")

  # input: 1M * $3 = $3.00
  # cache_write: 500K * $3.75 = $1.875
  # total: $4.875
  [ "$result" = "4.875000" ]
}

@test "pricing: calculate_claude_cost handles missing token fields with defaults" {
  local usage='{"input_tokens":100000,"output_tokens":50000}'

  result=$(calculate_claude_cost "claude-sonnet-4-5" "$usage")

  # input: 100K * $3 = $0.30
  # output: 50K * $15 = $0.75
  # total: $1.05
  [ "$result" = "1.050000" ]
}

@test "pricing: calculate_claude_cost handles zero tokens" {
  local usage='{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}'

  result=$(calculate_claude_cost "claude-sonnet-4-5" "$usage")

  [ "$result" = "0.000000" ]
}

@test "pricing: calculate_claude_cost works with different models" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"thinking_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}'

  # Haiku (cheaper)
  result_haiku=$(calculate_claude_cost "claude-haiku-4-5" "$usage")

  # Opus (more expensive)
  result_opus=$(calculate_claude_cost "claude-opus-4-5" "$usage")

  # Haiku: 1M * $1 + 500K * $5 = $3.50
  [ "$result_haiku" = "3.500000" ]

  # Opus: 1M * $5 + 500K * $25 = $17.50
  [ "$result_opus" = "17.500000" ]
}

# ============================================================================
# Codex Cost Calculation Tests
# ============================================================================

@test "pricing: calculate_codex_cost computes correct USD amount for basic usage" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"reasoning_output_tokens":0,"cached_input_tokens":0}'

  result=$(calculate_codex_cost "gpt-5.2-codex" "$usage")

  # input: 1M * $1.75 = $1.75
  # output: 500K * $14 = $7.00
  # total: $8.75
  [ "$result" = "8.750000" ]
}

@test "pricing: calculate_codex_cost includes reasoning output tokens" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"reasoning_output_tokens":200000,"cached_input_tokens":0}'

  result=$(calculate_codex_cost "gpt-5.2-codex" "$usage")

  # input: 1M * $1.75 = $1.75
  # output: 500K * $14 = $7.00
  # reasoning: 200K * $14 = $2.80
  # total: $11.55
  [ "$result" = "11.550000" ]
}

@test "pricing: calculate_codex_cost includes cached input tokens at discounted rate" {
  local usage='{"input_tokens":1000000,"output_tokens":0,"reasoning_output_tokens":0,"cached_input_tokens":500000}'

  result=$(calculate_codex_cost "gpt-5.2-codex" "$usage")

  # input: 1M * $1.75 = $1.75
  # cached: 500K * $0.18 = $0.09
  # total: $1.84
  [ "$result" = "1.840000" ]
}

@test "pricing: calculate_codex_cost handles missing token fields with defaults" {
  local usage='{"input_tokens":100000,"output_tokens":50000}'

  result=$(calculate_codex_cost "gpt-5.2-codex" "$usage")

  # input: 100K * $1.75 = $0.175
  # output: 50K * $14 = $0.70
  # total: $0.875
  [ "$result" = "0.875000" ]
}

@test "pricing: calculate_codex_cost handles zero tokens" {
  local usage='{"input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"cached_input_tokens":0}'

  result=$(calculate_codex_cost "gpt-5.2-codex" "$usage")

  [ "$result" = "0.000000" ]
}

@test "pricing: calculate_codex_cost works with different models" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"reasoning_output_tokens":0,"cached_input_tokens":0}'

  # gpt-5.2 (more expensive)
  result_52=$(calculate_codex_cost "gpt-5.2-codex" "$usage")

  # gpt-5.1 (cheaper)
  result_51=$(calculate_codex_cost "gpt-5.1-codex" "$usage")

  # gpt-5.2: 1M * $1.75 + 500K * $14 = $8.75
  [ "$result_52" = "8.750000" ]

  # gpt-5.1: 1M * $1.25 + 500K * $10 = $6.25
  [ "$result_51" = "6.250000" ]
}

# ============================================================================
# Generic Cost Calculation Tests
# ============================================================================

@test "pricing: calculate_cost routes to Claude calculator" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"thinking_tokens":0}'

  result=$(calculate_cost "claude" "claude-sonnet-4-5" "$usage")

  # Should match calculate_claude_cost result
  [ "$result" = "10.500000" ]
}

@test "pricing: calculate_cost routes to Codex calculator for codex runner" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"reasoning_output_tokens":0}'

  result=$(calculate_cost "codex" "gpt-5.2-codex" "$usage")

  # Should match calculate_codex_cost result
  [ "$result" = "8.750000" ]
}

@test "pricing: calculate_cost routes to Codex calculator for openai runner" {
  local usage='{"input_tokens":1000000,"output_tokens":500000,"reasoning_output_tokens":0}'

  result=$(calculate_cost "openai" "gpt-5.2-codex" "$usage")

  # Should match calculate_codex_cost result
  [ "$result" = "8.750000" ]
}

@test "pricing: calculate_cost returns 0 for unknown runner" {
  local usage='{"input_tokens":1000000,"output_tokens":500000}'

  result=$(calculate_cost "unknown" "some-model" "$usage")

  [ "$result" = "0" ]
}

# ============================================================================
# Cost Formatting Tests
# ============================================================================

@test "pricing: format_cost formats small amounts with 4 decimals" {
  result=$(format_cost "0.0042")
  [ "$result" = "\$0.0042" ]
}

@test "pricing: format_cost formats sub-dollar amounts with 3 decimals" {
  result=$(format_cost "0.123")
  [ "$result" = "\$0.123" ]
}

@test "pricing: format_cost formats dollar amounts with 2 decimals" {
  result=$(format_cost "12.345")
  [ "$result" = "\$12.35" ]
}

@test "pricing: format_cost handles zero" {
  result=$(format_cost "0")
  [ "$result" = "\$0.0000" ]
}

@test "pricing: format_cost handles large amounts" {
  result=$(format_cost "999.99")
  [ "$result" = "\$999.99" ]
}

# ============================================================================
# Duration Formatting Tests
# ============================================================================

@test "pricing: format_duration formats seconds only" {
  result=$(format_duration "5000")
  [ "$result" = "5s" ]
}

@test "pricing: format_duration formats minutes and seconds" {
  result=$(format_duration "125000")
  [ "$result" = "2m 5s" ]
}

@test "pricing: format_duration formats hours, minutes, and seconds" {
  result=$(format_duration "3725000")
  [ "$result" = "1h 2m 5s" ]
}

@test "pricing: format_duration handles zero" {
  result=$(format_duration "0")
  [ "$result" = "0s" ]
}

@test "pricing: format_duration handles exactly 1 minute" {
  result=$(format_duration "60000")
  [ "$result" = "1m 0s" ]
}

@test "pricing: format_duration handles exactly 1 hour" {
  result=$(format_duration "3600000")
  [ "$result" = "1h 0m 0s" ]
}

# ============================================================================
# Token Formatting Tests
# ============================================================================

@test "pricing: format_tokens displays small numbers as-is" {
  result=$(format_tokens "123")
  [ "$result" = "123" ]
}

@test "pricing: format_tokens displays thousands with K suffix" {
  result=$(format_tokens "5000")
  [ "$result" = "5.0K" ]
}

@test "pricing: format_tokens displays millions with M suffix" {
  result=$(format_tokens "2500000")
  [ "$result" = "2.5M" ]
}

@test "pricing: format_tokens handles exactly 1K" {
  result=$(format_tokens "1000")
  [ "$result" = "1.0K" ]
}

@test "pricing: format_tokens handles exactly 1M" {
  result=$(format_tokens "1000000")
  [ "$result" = "1.0M" ]
}

@test "pricing: format_tokens rounds to one decimal" {
  result=$(format_tokens "1234567")
  [ "$result" = "1.2M" ]
}

# ============================================================================
# Usage Aggregation Tests
# ============================================================================

@test "pricing: aggregate_usage aggregates Claude usage from JSONL file" {
  local usage_file="$TEMP_DIR/usage.jsonl"

  # Create mock usage file
  cat > "$usage_file" << 'EOF'
{"timestamp":"2024-01-15T10:00:00Z","iteration":1,"role":"planner","duration_ms":5000,"runner":"claude","model":"claude-sonnet-4-5","usage":{"input_tokens":1000,"output_tokens":500,"thinking_tokens":100}}
{"timestamp":"2024-01-15T10:05:00Z","iteration":2,"role":"implementer","duration_ms":8000,"runner":"claude","model":"claude-sonnet-4-5","usage":{"input_tokens":2000,"output_tokens":1000,"thinking_tokens":200}}
EOF

  result=$(aggregate_usage "$usage_file")

  # Check totals
  total_iterations=$(echo "$result" | jq -r '.total_iterations')
  total_duration=$(echo "$result" | jq -r '.total_duration_ms')

  [ "$total_iterations" = "2" ]
  [ "$total_duration" = "13000" ]

  # Check Claude runner totals
  claude_input=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "claude") | .totals.input_tokens')
  claude_output=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "claude") | .totals.output_tokens')
  claude_thinking=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "claude") | .totals.thinking_tokens')

  [ "$claude_input" = "3000" ]
  [ "$claude_output" = "1500" ]
  [ "$claude_thinking" = "300" ]
}

@test "pricing: aggregate_usage aggregates Codex usage from JSONL file" {
  local usage_file="$TEMP_DIR/usage-codex.jsonl"

  # Create mock usage file
  cat > "$usage_file" << 'EOF'
{"timestamp":"2024-01-15T10:00:00Z","iteration":1,"role":"planner","duration_ms":3000,"runner":"codex","model":"gpt-5.2-codex","usage":{"input_tokens":800,"output_tokens":400,"reasoning_output_tokens":100,"cached_input_tokens":200}}
{"timestamp":"2024-01-15T10:03:00Z","iteration":2,"role":"implementer","duration_ms":5000,"runner":"codex","model":"gpt-5.2-codex","usage":{"input_tokens":1200,"output_tokens":600,"reasoning_output_tokens":150,"cached_input_tokens":300}}
EOF

  result=$(aggregate_usage "$usage_file")

  # Check Codex runner totals
  codex_input=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "codex") | .totals.input_tokens')
  codex_output=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "codex") | .totals.output_tokens')
  codex_reasoning=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "codex") | .totals.reasoning_output_tokens')
  codex_cached=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "codex") | .totals.cached_input_tokens')

  [ "$codex_input" = "2000" ]
  [ "$codex_output" = "1000" ]
  [ "$codex_reasoning" = "250" ]
  [ "$codex_cached" = "500" ]
}

@test "pricing: aggregate_usage groups by role" {
  local usage_file="$TEMP_DIR/usage-roles.jsonl"

  cat > "$usage_file" << 'EOF'
{"iteration":1,"role":"planner","duration_ms":2000,"runner":"claude","usage":{"input_tokens":500,"output_tokens":250}}
{"iteration":2,"role":"implementer","duration_ms":3000,"runner":"claude","usage":{"input_tokens":1000,"output_tokens":500}}
{"iteration":3,"role":"planner","duration_ms":2500,"runner":"claude","usage":{"input_tokens":600,"output_tokens":300}}
EOF

  result=$(aggregate_usage "$usage_file")

  # Check role grouping
  planner_iters=$(echo "$result" | jq -r '.by_runner[0].by_role[] | select(.role == "planner") | .iterations')
  implementer_iters=$(echo "$result" | jq -r '.by_runner[0].by_role[] | select(.role == "implementer") | .iterations')

  [ "$planner_iters" = "2" ]
  [ "$implementer_iters" = "1" ]

  # Check planner totals (2 iterations)
  planner_input=$(echo "$result" | jq -r '.by_runner[0].by_role[] | select(.role == "planner") | .usage.input_tokens')
  [ "$planner_input" = "1100" ]
}

@test "pricing: aggregate_usage handles missing file" {
  result=$(aggregate_usage "/nonexistent/usage.jsonl" 2>&1 || true)

  error=$(echo "$result" | jq -r '.error')
  [ "$error" = "usage file not found" ]
}

@test "pricing: aggregate_usage handles empty file" {
  local usage_file="$TEMP_DIR/empty.jsonl"
  touch "$usage_file"

  result=$(aggregate_usage "$usage_file")

  # Should fail gracefully or return empty structure
  # jq -s on empty file returns empty array, which causes division by zero
  error=$(echo "$result" | jq -r '.error // empty')
  [ -n "$error" ] || [ "$(echo "$result" | jq -r '.total_iterations // 0')" = "0" ]
}

# ============================================================================
# Aggregate Cost Calculation Tests
# ============================================================================

@test "pricing: calculate_aggregate_costs adds costs to aggregated usage" {
  local usage_file="$TEMP_DIR/usage-for-costs.jsonl"

  cat > "$usage_file" << 'EOF'
{"iteration":1,"role":"planner","duration_ms":5000,"runner":"claude","model":"claude-sonnet-4-5","usage":{"input_tokens":1000000,"output_tokens":500000,"thinking_tokens":0}}
EOF

  aggregated=$(aggregate_usage "$usage_file")
  result=$(calculate_aggregate_costs "$aggregated" "claude-sonnet-4-5" "gpt-5.2-codex")

  # Check that total_cost_usd is added
  total_cost=$(echo "$result" | jq -r '.total_cost_usd')

  # Expected: 1M * $3 + 500K * $15 = $10.50
  [ "$total_cost" = "10.500000" ]

  # Check runner-specific cost
  runner_cost=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "claude") | .total_cost_usd')
  [ "$runner_cost" = "10.500000" ]
}

@test "pricing: calculate_aggregate_costs handles mixed runners" {
  local usage_file="$TEMP_DIR/usage-mixed.jsonl"

  cat > "$usage_file" << 'EOF'
{"iteration":1,"role":"planner","duration_ms":5000,"runner":"claude","model":"claude-sonnet-4-5","usage":{"input_tokens":1000000,"output_tokens":0,"thinking_tokens":0}}
{"iteration":2,"role":"implementer","duration_ms":3000,"runner":"codex","model":"gpt-5.2-codex","usage":{"input_tokens":1000000,"output_tokens":0,"reasoning_output_tokens":0,"cached_input_tokens":0}}
EOF

  aggregated=$(aggregate_usage "$usage_file")
  result=$(calculate_aggregate_costs "$aggregated" "claude-sonnet-4-5" "gpt-5.2-codex")

  # Claude: 1M * $3 = $3.00
  # Codex: 1M * $1.75 = $1.75
  # Total: $4.75

  total_cost=$(echo "$result" | jq -r '.total_cost_usd')
  [ "$total_cost" = "4.750000" ]
}

@test "pricing: calculate_aggregate_costs uses default models when not specified" {
  local usage_file="$TEMP_DIR/usage-defaults.jsonl"

  cat > "$usage_file" << 'EOF'
{"iteration":1,"role":"planner","duration_ms":5000,"runner":"claude","usage":{"input_tokens":1000000,"output_tokens":0,"thinking_tokens":0}}
EOF

  aggregated=$(aggregate_usage "$usage_file")

  # Call without specifying models (should use defaults)
  result=$(calculate_aggregate_costs "$aggregated")

  # Should use default Claude Sonnet 4.5 pricing
  runner_cost=$(echo "$result" | jq -r '.by_runner[] | select(.runner == "claude") | .total_cost_usd')
  [ "$runner_cost" = "3.000000" ]
}

# ============================================================================
# Integration Tests
# ============================================================================

@test "pricing: end-to-end cost calculation for realistic usage" {
  local usage_file="$TEMP_DIR/usage-e2e.jsonl"

  # Realistic usage: 3 iterations with Claude
  cat > "$usage_file" << 'EOF'
{"iteration":1,"role":"planner","duration_ms":12000,"runner":"claude","model":"claude-sonnet-4-5","usage":{"input_tokens":15000,"output_tokens":8000,"thinking_tokens":2000,"cache_read_input_tokens":5000,"cache_creation_input_tokens":1000}}
{"iteration":2,"role":"implementer","duration_ms":45000,"runner":"claude","model":"claude-sonnet-4-5","usage":{"input_tokens":25000,"output_tokens":15000,"thinking_tokens":5000,"cache_read_input_tokens":10000,"cache_creation_input_tokens":0}}
{"iteration":3,"role":"tester","duration_ms":18000,"runner":"claude","model":"claude-sonnet-4-5","usage":{"input_tokens":12000,"output_tokens":6000,"thinking_tokens":1000,"cache_read_input_tokens":8000,"cache_creation_input_tokens":0}}
EOF

  # Aggregate and calculate costs
  aggregated=$(aggregate_usage "$usage_file")
  result=$(calculate_aggregate_costs "$aggregated" "claude-sonnet-4-5")

  # Verify structure
  total_iterations=$(echo "$result" | jq -r '.total_iterations')
  total_cost=$(echo "$result" | jq -r '.total_cost_usd')

  [ "$total_iterations" = "3" ]

  # Cost calculation:
  # Input: 52000 / 1M * $3 = $0.156
  # Output: 29000 / 1M * $15 = $0.435
  # Thinking: 8000 / 1M * $15 = $0.120
  # Cache read: 23000 / 1M * $0.30 = $0.0069
  # Cache write: 1000 / 1M * $3.75 = $0.00375
  # Total: ~$0.721

  # Check that cost is calculated (approximately)
  [[ $(echo "$total_cost > 0.7" | bc -l) -eq 1 ]]
  [[ $(echo "$total_cost < 0.8" | bc -l) -eq 1 ]]
}

@test "pricing: verify all formatters produce expected output" {
  # Cost formatting
  cost_small=$(format_cost "0.0015")
  cost_medium=$(format_cost "0.456")
  cost_large=$(format_cost "123.45")

  [ "$cost_small" = "\$0.0015" ]
  [ "$cost_medium" = "\$0.456" ]
  [ "$cost_large" = "\$123.45" ]

  # Duration formatting
  dur_sec=$(format_duration "7000")
  dur_min=$(format_duration "195000")
  dur_hour=$(format_duration "5430000")

  [ "$dur_sec" = "7s" ]
  [ "$dur_min" = "3m 15s" ]
  [ "$dur_hour" = "1h 30m 30s" ]

  # Token formatting
  tok_small=$(format_tokens "999")
  tok_k=$(format_tokens "15000")
  tok_m=$(format_tokens "3500000")

  [ "$tok_small" = "999" ]
  [ "$tok_k" = "15.0K" ]
  [ "$tok_m" = "3.5M" ]
}
