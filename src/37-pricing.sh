# Pricing data and cost calculation for Claude and Codex models
# Prices are per million tokens (MTok)
# Last updated: 2026-01-14

# -----------------------------------------------------------------------------
# Pricing Tables (USD per Million Tokens)
# -----------------------------------------------------------------------------

# Get pricing for a model
# Args: $1 = model_id (e.g., "claude-sonnet-4-5-20250929", "gpt-5.2-codex")
# Output: JSON object with pricing per MTok
get_model_pricing() {
  local model="$1"

  # Normalize model ID (remove date suffixes for matching)
  local model_base
  model_base=$(echo "$model" | sed -E 's/-[0-9]{8}$//')

  case "$model_base" in
    # Claude 4.5 models
    claude-opus-4-5|claude-opus-4.5)
      echo '{"input": 5, "output": 25, "thinking": 25, "cache_read": 0.50, "cache_write": 6.25}'
      ;;
    claude-sonnet-4-5|claude-sonnet-4.5)
      echo '{"input": 3, "output": 15, "thinking": 15, "cache_read": 0.30, "cache_write": 3.75}'
      ;;
    claude-haiku-4-5|claude-haiku-4.5)
      echo '{"input": 1, "output": 5, "thinking": 5, "cache_read": 0.10, "cache_write": 1.25}'
      ;;

    # Claude 4.x models
    claude-opus-4|claude-opus-4.1)
      echo '{"input": 15, "output": 75, "thinking": 75, "cache_read": 1.50, "cache_write": 18.75}'
      ;;
    claude-sonnet-4)
      echo '{"input": 3, "output": 15, "thinking": 15, "cache_read": 0.30, "cache_write": 3.75}'
      ;;

    # OpenAI/Codex models
    gpt-5.2-codex|gpt-5.2-codex-*)
      echo '{"input": 1.75, "output": 14, "reasoning": 14, "cached_input": 0.18}'
      ;;
    gpt-5.1-codex|gpt-5.1-codex-*|gpt-5.1-codex-max|gpt-5.1-codex-mini)
      echo '{"input": 1.25, "output": 10, "reasoning": 10, "cached_input": 0.125}'
      ;;
    gpt-5-codex|gpt-5-codex-*)
      echo '{"input": 1.25, "output": 10, "reasoning": 10, "cached_input": 0.125}'
      ;;

    # Default fallback (use Sonnet 4.5 pricing as reasonable default)
    *)
      echo '{"input": 3, "output": 15, "thinking": 15, "reasoning": 15, "cache_read": 0.30, "cache_write": 3.75, "cached_input": 0.30}'
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Cost Calculation
# -----------------------------------------------------------------------------

# Calculate cost for Claude usage
# Args: $1 = model, $2 = usage_json (with input_tokens, output_tokens, thinking_tokens, cache_read_input_tokens, cache_creation_input_tokens)
# Output: cost in USD (decimal)
calculate_claude_cost() {
  local model="$1"
  local usage_json="$2"

  local pricing
  pricing=$(get_model_pricing "$model")

  # Extract token counts (default to 0)
  local input_tokens output_tokens thinking_tokens cache_read cache_write
  input_tokens=$(echo "$usage_json" | jq -r '.input_tokens // 0')
  output_tokens=$(echo "$usage_json" | jq -r '.output_tokens // 0')
  thinking_tokens=$(echo "$usage_json" | jq -r '.thinking_tokens // 0')
  cache_read=$(echo "$usage_json" | jq -r '.cache_read_input_tokens // 0')
  cache_write=$(echo "$usage_json" | jq -r '.cache_creation_input_tokens // 0')

  # Extract prices
  local price_input price_output price_thinking price_cache_read price_cache_write
  price_input=$(echo "$pricing" | jq -r '.input')
  price_output=$(echo "$pricing" | jq -r '.output')
  price_thinking=$(echo "$pricing" | jq -r '.thinking // .output')
  price_cache_read=$(echo "$pricing" | jq -r '.cache_read // .input')
  price_cache_write=$(echo "$pricing" | jq -r '.cache_write // .input')

  # Calculate cost (tokens / 1M * price_per_MTok)
  # Using awk for floating point math
  awk -v input="$input_tokens" -v output="$output_tokens" -v thinking="$thinking_tokens" \
      -v cache_read="$cache_read" -v cache_write="$cache_write" \
      -v p_input="$price_input" -v p_output="$price_output" -v p_thinking="$price_thinking" \
      -v p_cache_read="$price_cache_read" -v p_cache_write="$price_cache_write" \
      'BEGIN {
        cost = (input / 1000000 * p_input) + \
               (output / 1000000 * p_output) + \
               (thinking / 1000000 * p_thinking) + \
               (cache_read / 1000000 * p_cache_read) + \
               (cache_write / 1000000 * p_cache_write)
        printf "%.6f\n", cost
      }'
}

# Calculate cost for Codex usage
# Args: $1 = model, $2 = usage_json (with input_tokens, output_tokens, reasoning_output_tokens, cached_input_tokens)
# Output: cost in USD (decimal)
calculate_codex_cost() {
  local model="$1"
  local usage_json="$2"

  local pricing
  pricing=$(get_model_pricing "$model")

  # Extract token counts (default to 0)
  local input_tokens output_tokens reasoning_tokens cached_tokens
  input_tokens=$(echo "$usage_json" | jq -r '.input_tokens // 0')
  output_tokens=$(echo "$usage_json" | jq -r '.output_tokens // 0')
  reasoning_tokens=$(echo "$usage_json" | jq -r '.reasoning_output_tokens // 0')
  cached_tokens=$(echo "$usage_json" | jq -r '.cached_input_tokens // 0')

  # Extract prices
  local price_input price_output price_reasoning price_cached
  price_input=$(echo "$pricing" | jq -r '.input')
  price_output=$(echo "$pricing" | jq -r '.output')
  price_reasoning=$(echo "$pricing" | jq -r '.reasoning // .output')
  price_cached=$(echo "$pricing" | jq -r '.cached_input // (.input * 0.1)')

  # Calculate cost (tokens / 1M * price_per_MTok)
  # Note: input_tokens from Codex is non-cached input, so we add cached separately
  awk -v input="$input_tokens" -v output="$output_tokens" -v reasoning="$reasoning_tokens" \
      -v cached="$cached_tokens" \
      -v p_input="$price_input" -v p_output="$price_output" -v p_reasoning="$price_reasoning" \
      -v p_cached="$price_cached" \
      'BEGIN {
        cost = (input / 1000000 * p_input) + \
               (output / 1000000 * p_output) + \
               (reasoning / 1000000 * p_reasoning) + \
               (cached / 1000000 * p_cached)
        printf "%.6f\n", cost
      }'
}

# Calculate cost based on runner type
# Args: $1 = runner_type (claude|codex), $2 = model, $3 = usage_json
# Output: cost in USD (decimal)
calculate_cost() {
  local runner_type="$1"
  local model="$2"
  local usage_json="$3"

  case "$runner_type" in
    claude)
      calculate_claude_cost "$model" "$usage_json"
      ;;
    codex|openai)
      calculate_codex_cost "$model" "$usage_json"
      ;;
    *)
      # Unknown runner, return 0
      echo "0"
      ;;
  esac
}

# Format cost as human-readable string
# Args: $1 = cost (decimal USD)
# Output: formatted string (e.g., "$0.0042", "$1.23")
format_cost() {
  local cost="$1"

  awk -v cost="$cost" 'BEGIN {
    if (cost < 0.01) {
      printf "$%.4f\n", cost
    } else if (cost < 1) {
      printf "$%.3f\n", cost
    } else {
      printf "$%.2f\n", cost
    }
  }'
}

# -----------------------------------------------------------------------------
# Aggregate Usage Summary
# -----------------------------------------------------------------------------

# Aggregate usage from JSONL file
# Args: $1 = usage_file (path to usage.jsonl)
# Output: JSON summary with totals per runner, per role, and overall
aggregate_usage() {
  local usage_file="$1"

  if [[ ! -f "$usage_file" ]]; then
    echo '{"error": "usage file not found"}'
    return 1
  fi

  jq -s '
    # Group by runner type
    group_by(.runner) |
    map({
      runner: .[0].runner,
      total_duration_ms: (map(.duration_ms) | add),
      total_cost_usd: 0,
      by_role: (group_by(.role) | map({
        role: .[0].role,
        iterations: length,
        duration_ms: (map(.duration_ms) | add),
        usage: (
          if .[0].runner == "claude" then
            {
              input_tokens: (map(.usage.input_tokens // 0) | add),
              output_tokens: (map(.usage.output_tokens // 0) | add),
              thinking_tokens: (map(.usage.thinking_tokens // 0) | add),
              cache_read_input_tokens: (map(.usage.cache_read_input_tokens // 0) | add),
              cache_creation_input_tokens: (map(.usage.cache_creation_input_tokens // 0) | add)
            }
          else
            {
              input_tokens: (map(.usage.input_tokens // 0) | add),
              output_tokens: (map(.usage.output_tokens // 0) | add),
              reasoning_output_tokens: (map(.usage.reasoning_output_tokens // 0) | add),
              cached_input_tokens: (map(.usage.cached_input_tokens // 0) | add)
            }
          end
        )
      })),
      totals: (
        if .[0].runner == "claude" then
          {
            input_tokens: (map(.usage.input_tokens // 0) | add),
            output_tokens: (map(.usage.output_tokens // 0) | add),
            thinking_tokens: (map(.usage.thinking_tokens // 0) | add),
            cache_read_input_tokens: (map(.usage.cache_read_input_tokens // 0) | add),
            cache_creation_input_tokens: (map(.usage.cache_creation_input_tokens // 0) | add)
          }
        else
          {
            input_tokens: (map(.usage.input_tokens // 0) | add),
            output_tokens: (map(.usage.output_tokens // 0) | add),
            reasoning_output_tokens: (map(.usage.reasoning_output_tokens // 0) | add),
            cached_input_tokens: (map(.usage.cached_input_tokens // 0) | add)
          }
        end
      )
    }) |
    {
      by_runner: .,
      total_duration_ms: (map(.total_duration_ms) | add),
      total_iterations: ([.[].by_role[].iterations] | add)
    }
  ' "$usage_file" 2>/dev/null || echo '{"error": "failed to aggregate usage"}'
}

# Calculate total cost from aggregated usage
# Args: $1 = aggregated_json (from aggregate_usage), $2 = default_claude_model, $3 = default_codex_model
# Output: JSON with costs added
calculate_aggregate_costs() {
  local aggregated="$1"
  local claude_model="${2:-claude-sonnet-4-5}"
  local codex_model="${3:-gpt-5.2-codex}"

  local total_cost=0
  local result="$aggregated"

  # Process each runner
  for runner in $(echo "$aggregated" | jq -r '.by_runner[].runner'); do
    local runner_totals model cost
    runner_totals=$(echo "$aggregated" | jq -r ".by_runner[] | select(.runner == \"$runner\") | .totals")

    if [[ "$runner" == "claude" ]]; then
      model="$claude_model"
      cost=$(calculate_claude_cost "$model" "$runner_totals")
    else
      model="$codex_model"
      cost=$(calculate_codex_cost "$model" "$runner_totals")
    fi

    total_cost=$(awk -v t="$total_cost" -v c="$cost" 'BEGIN { printf "%.6f", t + c }')

    # Update runner cost in result
    result=$(echo "$result" | jq --arg runner "$runner" --argjson cost "$cost" '
      .by_runner |= map(if .runner == $runner then .total_cost_usd = $cost else . end)
    ')
  done

  # Add total cost
  echo "$result" | jq --argjson cost "$total_cost" '. + {total_cost_usd: $cost}'
}

# -----------------------------------------------------------------------------
# Usage Command
# -----------------------------------------------------------------------------

# Format duration in human-readable form
format_duration() {
  local ms="$1"
  local seconds=$((ms / 1000))
  local minutes=$((seconds / 60))
  local hours=$((minutes / 60))

  if [[ $hours -gt 0 ]]; then
    printf "%dh %dm %ds" $hours $((minutes % 60)) $((seconds % 60))
  elif [[ $minutes -gt 0 ]]; then
    printf "%dm %ds" $minutes $((seconds % 60))
  else
    printf "%ds" $seconds
  fi
}

# Format token count with K/M suffix
format_tokens() {
  local tokens="$1"
  if [[ $tokens -ge 1000000 ]]; then
    awk -v t="$tokens" 'BEGIN { printf "%.1fM", t/1000000 }'
  elif [[ $tokens -ge 1000 ]]; then
    awk -v t="$tokens" 'BEGIN { printf "%.1fK", t/1000 }'
  else
    echo "$tokens"
  fi
}

# Usage command - display usage summary for a loop
# Args: $1 = repo, $2 = loop_id, $3 = config_path, $4 = json_output (0|1)
usage_cmd() {
  local repo="$1"
  local loop_id="$2"
  local config_path="$3"
  local json_output="${4:-0}"

  # If no loop_id, try to find one
  if [[ -z "$loop_id" ]]; then
    # Get first loop from config
    if [[ -f "$config_path" ]]; then
      loop_id=$(jq -r '.loops[0].id // empty' "$config_path" 2>/dev/null || true)
    fi
    if [[ -z "$loop_id" ]]; then
      echo "error: no loop specified and no loops in config" >&2
      return 1
    fi
  fi

  local loop_dir="$repo/.superloop/loops/$loop_id"
  local usage_file="$loop_dir/usage.jsonl"

  if [[ ! -f "$usage_file" ]]; then
    echo "error: no usage data found for loop '$loop_id'" >&2
    echo "       expected: $usage_file" >&2
    return 1
  fi

  # Aggregate usage
  local aggregated
  aggregated=$(aggregate_usage "$usage_file")

  if echo "$aggregated" | jq -e '.error' >/dev/null 2>&1; then
    echo "error: $(echo "$aggregated" | jq -r '.error')" >&2
    return 1
  fi

  # Calculate costs (try to get models from usage data)
  local claude_model codex_model
  claude_model=$(jq -s -r '[.[] | select(.runner == "claude") | .model][0] // "claude-sonnet-4-5"' "$usage_file" 2>/dev/null)
  codex_model=$(jq -s -r '[.[] | select(.runner == "codex") | .model][0] // "gpt-5.2-codex"' "$usage_file" 2>/dev/null)

  local with_costs
  with_costs=$(calculate_aggregate_costs "$aggregated" "$claude_model" "$codex_model")

  # JSON output mode
  if [[ "$json_output" -eq 1 ]]; then
    echo "$with_costs" | jq --arg loop "$loop_id" '. + {loop_id: $loop}'
    return 0
  fi

  # Human-readable output
  echo "Usage Summary: $loop_id"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  local total_iterations total_duration total_cost
  total_iterations=$(echo "$with_costs" | jq -r '.total_iterations // 0')
  total_duration=$(echo "$with_costs" | jq -r '.total_duration_ms // 0')
  total_cost=$(echo "$with_costs" | jq -r '.total_cost_usd // 0')

  printf "Total: %s iterations, %s, %s\n\n" \
    "$total_iterations" \
    "$(format_duration "$total_duration")" \
    "$(format_cost "$total_cost")"

  # Per-runner breakdown
  local runners
  runners=$(echo "$with_costs" | jq -r '.by_runner[].runner' 2>/dev/null)

  for runner in $runners; do
    local runner_data runner_cost runner_duration
    runner_data=$(echo "$with_costs" | jq ".by_runner[] | select(.runner == \"$runner\")")
    runner_cost=$(echo "$runner_data" | jq -r '.total_cost_usd // 0')
    runner_duration=$(echo "$runner_data" | jq -r '.total_duration_ms // 0')

    echo "[$runner] $(format_cost "$runner_cost"), $(format_duration "$runner_duration")"
    echo "───────────────────────────────────────────────────────────────"

    # Per-role breakdown
    local roles
    roles=$(echo "$runner_data" | jq -r '.by_role[].role')

    for role in $roles; do
      local role_data iters role_dur
      role_data=$(echo "$runner_data" | jq ".by_role[] | select(.role == \"$role\")")
      iters=$(echo "$role_data" | jq -r '.iterations')
      role_dur=$(echo "$role_data" | jq -r '.duration_ms // 0')

      # Token breakdown
      local input output thinking cached
      input=$(echo "$role_data" | jq -r '.usage.input_tokens // 0')
      output=$(echo "$role_data" | jq -r '.usage.output_tokens // 0')

      if [[ "$runner" == "claude" ]]; then
        thinking=$(echo "$role_data" | jq -r '.usage.thinking_tokens // 0')
        cached=$(echo "$role_data" | jq -r '.usage.cache_read_input_tokens // 0')
      else
        thinking=$(echo "$role_data" | jq -r '.usage.reasoning_output_tokens // 0')
        cached=$(echo "$role_data" | jq -r '.usage.cached_input_tokens // 0')
      fi

      printf "  %-12s %dx  %s  in:%-6s out:%-6s" \
        "$role" "$iters" "$(format_duration "$role_dur")" \
        "$(format_tokens "$input")" "$(format_tokens "$output")"

      if [[ "$thinking" -gt 0 ]]; then
        printf " think:%-6s" "$(format_tokens "$thinking")"
      fi
      if [[ "$cached" -gt 0 ]]; then
        printf " cache:%-6s" "$(format_tokens "$cached")"
      fi
      echo ""
    done
    echo ""
  done
}
