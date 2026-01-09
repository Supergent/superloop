#!/bin/bash
#
# Relace Instant Apply Hook for Claude Code
# Version: 1.0.0
#
# This PreToolUse hook intercepts Edit tool calls and processes them through
# Relace's instant apply API for fast, efficient code merging using abbreviated
# snippets with "// ... rest of code ..." markers.
#
# Features:
# - Multiple toggle mechanisms (env var, project-level, file-size)
# - Automatic fallback to standard Edit on errors
# - Performance logging and cost tracking
# - Comprehensive error handling
# - Debug mode for troubleshooting
#
# Installation:
#   1. Copy this script to ~/claude-code-relace-hook.sh in your VM
#   2. chmod +x ~/claude-code-relace-hook.sh
#   3. Set RELACE_API_KEY environment variable
#   4. Configure hooks in ~/.claude/settings.json
#
# Usage:
#   export RELACE_ENABLED=true   # Enable (default)
#   export RELACE_ENABLED=false  # Disable
#   touch .no-relace             # Disable for current project
#
# Environment Variables:
#   RELACE_API_KEY              - Your Relace API key (required)
#   RELACE_ENABLED              - Enable/disable hook (default: true)
#   RELACE_MIN_FILE_SIZE        - Minimum file size in lines (default: 100)
#   RELACE_TIMEOUT              - API timeout in seconds (default: 30)
#   RELACE_DEBUG                - Enable debug logging (default: false)
#   RELACE_LOG_DIR              - Log directory (default: ~/.claude/relace-logs)
#   RELACE_COST_TRACKING        - Enable cost tracking (default: true)
#
# Exit Codes:
#   0 = Success or fallback (allow tool execution)
#   2 = Block tool execution (with error message to stderr)
#   Other = Non-blocking error shown to user
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# API Configuration
RELACE_API_KEY="${RELACE_API_KEY:-}"
RELACE_ENDPOINT="${RELACE_ENDPOINT:-https://instantapply.endpoint.relace.run/v1/code/apply}"
RELACE_TIMEOUT="${RELACE_TIMEOUT:-30}"

# Toggle Configuration
RELACE_ENABLED="${RELACE_ENABLED:-true}"
RELACE_MIN_FILE_SIZE="${RELACE_MIN_FILE_SIZE:-100}"

# Logging Configuration
RELACE_DEBUG="${RELACE_DEBUG:-false}"
RELACE_LOG_DIR="${RELACE_LOG_DIR:-$HOME/.claude/relace-logs}"
RELACE_COST_TRACKING="${RELACE_COST_TRACKING:-true}"

# Performance Configuration
RELACE_PERFORMANCE_LOG="${RELACE_LOG_DIR}/performance.log"
RELACE_COST_LOG="${RELACE_LOG_DIR}/costs.csv"
RELACE_ERROR_LOG="${RELACE_LOG_DIR}/errors.log"

# Abbreviation markers to detect (regex)
ABBREVIATION_MARKERS='(\.\.\.|keep.*code|rest.*file|existing.*code|unchanged.*code|same.*above|same.*below)'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Ensure log directory exists
mkdir -p "$RELACE_LOG_DIR"

log_debug() {
    if [[ "$RELACE_DEBUG" == "true" ]]; then
        echo "[RELACE-HOOK DEBUG] $*" >&2
    fi
}

log_info() {
    echo "[RELACE-HOOK] $*" >&2
}

log_error() {
    echo "[RELACE-HOOK ERROR] $*" >&2
}

log_performance() {
    local duration=$1
    local prompt_tokens=$2
    local completion_tokens=$3
    local file_size=$4

    if [[ "$RELACE_DEBUG" == "true" ]]; then
        local total_tokens=$((prompt_tokens + completion_tokens))
        local tps=0
        if [[ $duration -gt 0 ]]; then
            tps=$((total_tokens / duration))
        fi

        log_debug "Performance: ${duration}s, Tokens: $total_tokens, Speed: ${tps} tok/s"

        # Log to file for analysis
        echo "$(date -Iseconds),$duration,$prompt_tokens,$completion_tokens,$file_size,$tps" >> "$RELACE_PERFORMANCE_LOG"
    fi
}

log_cost() {
    local prompt_tokens=$1
    local completion_tokens=$2
    local file_path=$3

    if [[ "$RELACE_COST_TRACKING" == "true" ]]; then
        # Relace pricing (update with current rates)
        # These are placeholder values - update based on actual Relace pricing
        local prompt_cost_per_1m=1.0
        local completion_cost_per_1m=1.0

        local cost=$(awk "BEGIN {printf \"%.6f\", ($prompt_tokens * $prompt_cost_per_1m / 1000000) + ($completion_tokens * $completion_cost_per_1m / 1000000)}")

        # Initialize CSV header if file doesn't exist
        if [[ ! -f "$RELACE_COST_LOG" ]]; then
            echo "timestamp,file,prompt_tokens,completion_tokens,cost_usd" > "$RELACE_COST_LOG"
        fi

        echo "$(date -Iseconds),\"$file_path\",$prompt_tokens,$completion_tokens,$cost" >> "$RELACE_COST_LOG"

        log_debug "Cost: \$${cost} ($prompt_tokens prompt + $completion_tokens completion tokens)"
    fi
}

log_api_error() {
    local error_msg=$1
    local file_path=$2

    echo "$(date -Iseconds),\"$file_path\",\"$error_msg\"" >> "$RELACE_ERROR_LOG"

    # Check for high error rate (last 100 calls)
    if [[ -f "$RELACE_ERROR_LOG" ]]; then
        local recent_errors=$(tail -100 "$RELACE_ERROR_LOG" | wc -l)
        if [[ $recent_errors -gt 50 ]]; then
            log_error "High error rate detected: $recent_errors errors in last 100 calls. Consider disabling Relace."
        fi
    fi
}

# ============================================================================
# TOGGLE CHECKS
# ============================================================================

check_enabled() {
    # 1. Global enable/disable via environment variable
    if [[ "$RELACE_ENABLED" != "true" ]]; then
        log_debug "Relace disabled globally (RELACE_ENABLED=$RELACE_ENABLED)"
        return 1
    fi

    # 2. Check for .no-relace file in current directory or home
    if [[ -f "${PWD}/.no-relace" ]]; then
        log_debug "Relace disabled for project (found ${PWD}/.no-relace)"
        return 1
    fi

    if [[ -f "${HOME}/.no-relace" ]]; then
        log_debug "Relace disabled globally (found ${HOME}/.no-relace)"
        return 1
    fi

    return 0
}

check_prerequisites() {
    # Check for required commands
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install with: apt-get install jq"
        return 1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl not found. Install with: apt-get install curl"
        return 1
    fi

    # Check for API key
    if [[ -z "$RELACE_API_KEY" ]]; then
        log_debug "RELACE_API_KEY not set. Falling back to standard Edit."
        return 1
    fi

    return 0
}

# ============================================================================
# MAIN PROCESSING
# ============================================================================

main() {
    local start_time=$(date +%s)

    log_debug "Hook triggered"

    # Check if Relace is enabled
    if ! check_enabled; then
        exit 0  # Pass through to standard Edit
    fi

    # Check prerequisites
    if ! check_prerequisites; then
        exit 0  # Pass through to standard Edit
    fi

    # Read tool call data from stdin
    local tool_data
    tool_data=$(cat) || {
        log_error "Failed to read tool data from stdin"
        exit 0
    }

    log_debug "Tool data received"

    # Extract tool input
    local tool_input
    tool_input=$(echo "$tool_data" | jq -r '.tool_input') || {
        log_error "Failed to parse tool_input from tool data"
        exit 0
    }

    # Extract parameters
    local file_path
    local old_string
    local new_string
    local replace_all

    file_path=$(echo "$tool_input" | jq -r '.file_path')
    old_string=$(echo "$tool_input" | jq -r '.old_string')
    new_string=$(echo "$tool_input" | jq -r '.new_string')
    replace_all=$(echo "$tool_input" | jq -r '.replace_all // false')

    log_debug "File: $file_path"
    log_debug "Replace all: $replace_all"

    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        exit 0  # Pass through (Edit tool will handle error)
    fi

    # Check file size threshold
    local file_size
    file_size=$(wc -l < "$file_path")

    if [[ $file_size -lt $RELACE_MIN_FILE_SIZE ]]; then
        log_debug "File too small ($file_size lines < $RELACE_MIN_FILE_SIZE threshold). Using standard Edit."
        exit 0
    fi

    # Check if new_string contains abbreviation markers
    if ! echo "$new_string" | grep -qE "$ABBREVIATION_MARKERS"; then
        log_debug "No abbreviation markers detected in new_string. Using standard Edit."
        exit 0
    fi

    log_debug "Abbreviated snippet detected. Processing through Relace API..."

    # Read original file content
    local initial_code
    initial_code=$(cat "$file_path") || {
        log_error "Failed to read file: $file_path"
        exit 0
    }

    local edit_snippet="$new_string"

    # Build Relace API request
    local request_json
    request_json=$(jq -n \
        --arg initial_code "$initial_code" \
        --arg edit_snippet "$edit_snippet" \
        '{
            initial_code: $initial_code,
            edit_snippet: $edit_snippet
        }') || {
        log_error "Failed to build API request JSON"
        exit 0
    }

    log_debug "Calling Relace API (timeout: ${RELACE_TIMEOUT}s)..."

    # Call Relace API
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "$RELACE_ENDPOINT" \
        -H "Authorization: Bearer $RELACE_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$request_json" \
        --max-time "$RELACE_TIMEOUT" 2>&1) || {
        log_error "Relace API call failed"
        log_api_error "API call failed: $response" "$file_path"
        exit 0  # Fall back to standard Edit
    }

    # Extract HTTP code and body
    http_code=$(echo "$response" | tail -1)
    response=$(echo "$response" | head -n -1)

    log_debug "Relace API response: HTTP $http_code"

    # Check HTTP status
    if [[ "$http_code" != "200" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null || echo "HTTP $http_code")
        log_error "Relace API error: $error_msg"
        log_api_error "$error_msg" "$file_path"
        exit 0  # Fall back to standard Edit
    fi

    # Extract merged code
    local merged_code
    merged_code=$(echo "$response" | jq -r '.mergedCode') || {
        log_error "Failed to parse mergedCode from API response"
        exit 0
    }

    if [[ -z "$merged_code" || "$merged_code" == "null" ]]; then
        log_error "Received empty or null mergedCode from API"
        exit 0
    fi

    log_debug "Successfully merged code (${#merged_code} chars)"

    # Extract usage stats
    local prompt_tokens=0
    local completion_tokens=0

    if echo "$response" | jq -e '.usage' > /dev/null 2>&1; then
        prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
        completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
    fi

    # Log performance
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_performance "$duration" "$prompt_tokens" "$completion_tokens" "$file_size"

    # Log costs
    log_cost "$prompt_tokens" "$completion_tokens" "$file_path"

    # Modify tool input to use merged code
    # Strategy: Replace old_string with entire original file, and new_string with merged result
    # This ensures the Edit tool replaces the entire file content
    local modified_input
    modified_input=$(echo "$tool_input" | jq \
        --arg merged "$merged_code" \
        --arg original "$initial_code" \
        '.old_string = $original | .new_string = $merged') || {
        log_error "Failed to build modified tool input"
        exit 0
    }

    # Output modified tool data
    echo "$tool_data" | jq \
        --argjson modified_input "$modified_input" \
        '.tool_input = $modified_input' || {
        log_error "Failed to output modified tool data"
        exit 0
    }

    log_debug "Tool input modified successfully. Relace processing complete."

    exit 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Run main function
main "$@"
