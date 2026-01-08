#!/usr/bin/env bash
# 36-usage-limits.sh - Pre-flight usage limit checking for runners
# Checks API usage limits before starting roles to avoid mid-run failures

# -----------------------------------------------------------------------------
# Claude Code Credential Retrieval (multi-method)
# -----------------------------------------------------------------------------

# Get Claude Code OAuth token from available sources
# Priority: 1) Environment variable, 2) Keychain (macOS), 3) Credentials file
get_claude_token() {
  local token=""

  # Method 1: Environment variable
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "$CLAUDE_CODE_OAUTH_TOKEN"
    return 0
  fi

  # Method 2: macOS Keychain
  if command -v security &>/dev/null; then
    token=$(security find-generic-password -s "Claude Code-credentials" -a "Claude Code" -w 2>/dev/null || true)
    if [[ -n "$token" ]]; then
      # Token is JSON, extract accessToken
      local access_token
      access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null || true)
      if [[ -n "$access_token" ]]; then
        echo "$access_token"
        return 0
      fi
    fi
  fi

  # Method 3: Credentials file
  local creds_file="$HOME/.claude/.credentials.json"
  if [[ -f "$creds_file" ]]; then
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
      echo "$token"
      return 0
    fi
  fi

  return 1
}

# Get Claude organization ID from config
get_claude_org_id() {
  local config_file="$HOME/.claude.json"
  if [[ -f "$config_file" ]]; then
    jq -r '.oauthAccount.organizationUuid // empty' "$config_file" 2>/dev/null || true
  fi
}

# -----------------------------------------------------------------------------
# Codex Credential Retrieval
# -----------------------------------------------------------------------------

# Get Codex access token and account ID
get_codex_credentials() {
  local auth_file="$HOME/.codex/auth.json"
  if [[ -f "$auth_file" ]]; then
    local access_token account_id
    access_token=$(jq -r '.tokens.access_token // empty' "$auth_file" 2>/dev/null || true)
    account_id=$(jq -r '.tokens.account_id // empty' "$auth_file" 2>/dev/null || true)
    if [[ -n "$access_token" ]]; then
      echo "$access_token"
      echo "$account_id"
      return 0
    fi
  fi
  return 1
}

# -----------------------------------------------------------------------------
# Usage API Queries
# -----------------------------------------------------------------------------

# Query Claude usage API
# Tries multiple methods: 1) Session key env var, 2) OAuth endpoint
# Returns JSON with usage data or empty on failure
query_claude_usage() {
  local result=""

  # Method 1: Session key from environment (most reliable)
  if [[ -n "${CLAUDE_SESSION_KEY:-}" ]]; then
    local org_id
    org_id=$(get_claude_org_id)
    if [[ -n "$org_id" ]]; then
      # Use browser-like headers to avoid Cloudflare blocking
      result=$(curl -s --max-time 10 \
        "https://claude.ai/api/organizations/${org_id}/usage" \
        -H "accept: application/json, text/plain, */*" \
        -H "accept-language: en-US,en;q=0.9" \
        -H "content-type: application/json" \
        -H "Cookie: sessionKey=${CLAUDE_SESSION_KEY}" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        -H "Origin: https://claude.ai" \
        -H "Referer: https://claude.ai/" \
        2>/dev/null || true)

      # Check if we got a valid response (not an error)
      if [[ -n "$result" ]] && ! echo "$result" | jq -e '.error' &>/dev/null; then
        echo "$result"
        return 0
      fi
    fi
  fi

  # Method 2: OAuth token from keychain (may have limited scope)
  local token
  token=$(get_claude_token 2>/dev/null) || true

  if [[ -n "$token" ]]; then
    result=$(curl -s --max-time 10 \
      "https://api.anthropic.com/api/oauth/usage" \
      -H "Authorization: Bearer ${token}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      2>/dev/null || true)

    # Check if we got a valid response
    if [[ -n "$result" ]] && ! echo "$result" | jq -e '.error' &>/dev/null; then
      echo "$result"
      return 0
    fi
  fi

  # Both methods failed
  return 1
}

# Query OpenAI/Codex usage API
# Returns JSON with usage data or empty on failure
query_codex_usage() {
  local creds access_token account_id
  creds=$(get_codex_credentials) || return 1

  access_token=$(echo "$creds" | head -1)
  account_id=$(echo "$creds" | tail -1)

  if [[ -z "$access_token" ]]; then
    return 1
  fi

  local headers=(-H "accept: */*" -H "authorization: Bearer ${access_token}")
  if [[ -n "$account_id" ]]; then
    headers+=(-H "chatgpt-account-id: ${account_id}")
  fi

  curl -s --max-time 10 \
    "https://chatgpt.com/backend-api/wham/usage" \
    "${headers[@]}" \
    2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Usage Parsing
# -----------------------------------------------------------------------------

# Parse Claude usage response
# Returns: utilization_percent reset_timestamp
parse_claude_usage() {
  local json="$1"
  local window="${2:-five_hour}"  # five_hour, seven_day, etc.

  if [[ -z "$json" ]]; then
    return 1
  fi

  local utilization resets_at
  utilization=$(echo "$json" | jq -r ".${window}.utilization // 0" 2>/dev/null || echo "0")
  resets_at=$(echo "$json" | jq -r ".${window}.resets_at // empty" 2>/dev/null || true)

  echo "$utilization"
  echo "$resets_at"
}

# Parse Codex usage response
# Returns: used_percent reset_timestamp error_message
parse_codex_usage() {
  local json="$1"

  if [[ -z "$json" ]]; then
    return 1
  fi

  # Check for error response (like usage_limit_reached)
  local error_type error_message resets_at limit_reached
  error_type=$(echo "$json" | jq -r '.error.type // empty' 2>/dev/null || true)

  if [[ "$error_type" == "usage_limit_reached" ]]; then
    error_message=$(echo "$json" | jq -r '.error.message // "Usage limit reached"' 2>/dev/null)
    resets_at=$(echo "$json" | jq -r '.error.resets_at // empty' 2>/dev/null || true)
    echo "100"  # 100% used
    echo "$resets_at"
    echo "$error_message"
    return 0
  fi

  # Check if limit is reached via flag
  limit_reached=$(echo "$json" | jq -r '.rate_limit.limit_reached // false' 2>/dev/null || echo "false")
  if [[ "$limit_reached" == "true" ]]; then
    resets_at=$(echo "$json" | jq -r '.rate_limit.primary_window.reset_at // .rate_limit.reset_at // empty' 2>/dev/null || true)
    echo "100"  # 100% used
    echo "$resets_at"
    echo "Usage limit reached"
    return 0
  fi

  # Normal response - try primary_window first, fall back to top-level
  local used_percent
  used_percent=$(echo "$json" | jq -r '.rate_limit.primary_window.used_percent // .rate_limit.used_percent // 0' 2>/dev/null || echo "0")
  resets_at=$(echo "$json" | jq -r '.rate_limit.primary_window.reset_at // .rate_limit.reset_at // empty' 2>/dev/null || true)

  echo "$used_percent"
  echo "$resets_at"
  echo ""
}

# -----------------------------------------------------------------------------
# Pre-flight Check
# -----------------------------------------------------------------------------

# Check usage limits before starting a role
# Arguments: runner_type (claude|codex), warn_threshold (default 70), block_threshold (default 95)
# Returns: 0 = OK, 1 = warning (proceed), 2 = blocked (should not proceed)
# Outputs status info to stderr
check_usage_limits() {
  local runner_type="${1:-}"
  local warn_threshold="${2:-70}"
  local block_threshold="${3:-95}"

  local usage_json used_percent resets_at error_msg
  local result=0

  case "$runner_type" in
    claude)
      usage_json=$(query_claude_usage 2>/dev/null || true)
      if [[ -z "$usage_json" ]]; then
        echo "[usage] Could not query Claude usage (no credentials or API error)" >&2
        return 0  # Don't block on query failure
      fi

      local parsed
      parsed=$(parse_claude_usage "$usage_json" "five_hour")
      used_percent=$(echo "$parsed" | head -1)
      resets_at=$(echo "$parsed" | tail -1)
      ;;

    codex|openai)
      usage_json=$(query_codex_usage 2>/dev/null || true)
      if [[ -z "$usage_json" ]]; then
        echo "[usage] Could not query Codex usage (no credentials or API error)" >&2
        return 0  # Don't block on query failure
      fi

      local parsed
      parsed=$(parse_codex_usage "$usage_json")
      used_percent=$(echo "$parsed" | head -1)
      resets_at=$(echo "$parsed" | sed -n '2p')
      error_msg=$(echo "$parsed" | tail -1)

      if [[ -n "$error_msg" ]]; then
        echo "[usage] Codex API reports: $error_msg" >&2
      fi
      ;;

    *)
      # Unknown runner type, skip check
      return 0
      ;;
  esac

  # Convert to integer for comparison
  used_percent=${used_percent%.*}  # Remove decimal
  used_percent=${used_percent:-0}

  # Format reset time if available
  local reset_info=""
  if [[ -n "$resets_at" ]]; then
    if [[ "$resets_at" =~ ^[0-9]+$ ]]; then
      # Unix timestamp
      reset_info=" (resets at $(date -r "$resets_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$resets_at"))"
    else
      # ISO string
      reset_info=" (resets at $resets_at)"
    fi
  fi

  if [[ "$used_percent" -ge "$block_threshold" ]]; then
    echo "[usage] BLOCKED: $runner_type usage at ${used_percent}% (threshold: ${block_threshold}%)${reset_info}" >&2
    result=2
  elif [[ "$used_percent" -ge "$warn_threshold" ]]; then
    echo "[usage] WARNING: $runner_type usage at ${used_percent}% (threshold: ${warn_threshold}%)${reset_info}" >&2
    result=1
  else
    echo "[usage] OK: $runner_type usage at ${used_percent}%${reset_info}" >&2
    result=0
  fi

  return $result
}

# Calculate seconds until usage resets
# Arguments: resets_at (timestamp or ISO string)
get_seconds_until_reset() {
  local resets_at="$1"
  local now reset_epoch

  now=$(date +%s)

  if [[ "$resets_at" =~ ^[0-9]+$ ]]; then
    reset_epoch="$resets_at"
  else
    # Try to parse ISO string
    reset_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" +%s 2>/dev/null || echo "0")
  fi

  if [[ "$reset_epoch" -gt "$now" ]]; then
    echo $((reset_epoch - now))
  else
    echo "0"
  fi
}

# Human-readable time until reset
format_time_until_reset() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))

  if [[ "$hours" -gt 0 ]]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# -----------------------------------------------------------------------------
# Event Logging
# -----------------------------------------------------------------------------

# Log usage check event
log_usage_event() {
  local events_file="$1"
  local runner_type="$2"
  local used_percent="$3"
  local status="$4"  # ok, warning, blocked
  local resets_at="${5:-}"

  if [[ -z "$events_file" ]]; then
    return
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local event
  event=$(jq -n \
    --arg ts "$timestamp" \
    --arg type "usage_check" \
    --arg runner "$runner_type" \
    --arg percent "$used_percent" \
    --arg status "$status" \
    --arg resets "$resets_at" \
    '{
      timestamp: $ts,
      event: $type,
      runner: $runner,
      used_percent: ($percent | tonumber),
      status: $status,
      resets_at: (if $resets == "" then null else $resets end)
    }')

  echo "$event" >> "$events_file"
}

# -----------------------------------------------------------------------------
# Reactive Rate Limit Detection (during execution)
# -----------------------------------------------------------------------------

# Detect rate limit errors in runner output
# Returns 0 if rate limit detected, 1 otherwise
# Sets global variables: RATE_LIMIT_DETECTED, RATE_LIMIT_RESETS_AT, RATE_LIMIT_MESSAGE
detect_rate_limit_in_line() {
  local line="$1"

  RATE_LIMIT_DETECTED=0
  RATE_LIMIT_RESETS_AT=""
  RATE_LIMIT_MESSAGE=""

  # Pattern: Codex JSON error
  if echo "$line" | grep -q '"type":\s*"usage_limit_reached"'; then
    RATE_LIMIT_DETECTED=1
    RATE_LIMIT_MESSAGE="Codex usage limit reached"
    # Try to extract resets_at
    RATE_LIMIT_RESETS_AT=$(echo "$line" | grep -o '"resets_at":\s*[0-9]*' | grep -o '[0-9]*' || true)
    return 0
  fi

  # Pattern: Codex error message
  if echo "$line" | grep -qi "usage.limit.*reached\|rate.limit.*exceeded"; then
    RATE_LIMIT_DETECTED=1
    RATE_LIMIT_MESSAGE="Rate limit detected in output"
    # Try to extract reset time
    RATE_LIMIT_RESETS_AT=$(echo "$line" | grep -oE 'resets?_?(at|in)["\s:]+[0-9]+' | grep -o '[0-9]*' | head -1 || true)
    return 0
  fi

  # Pattern: HTTP 429
  if echo "$line" | grep -q "429\|Too Many Requests"; then
    RATE_LIMIT_DETECTED=1
    RATE_LIMIT_MESSAGE="HTTP 429 Too Many Requests"
    return 0
  fi

  # Pattern: Claude rate limit
  if echo "$line" | grep -qi "rate.limit\|usage.limit\|limit.*reached"; then
    # Avoid false positives from normal usage discussions
    if echo "$line" | grep -qiE "error|failed|exceeded|hit|reached"; then
      RATE_LIMIT_DETECTED=1
      RATE_LIMIT_MESSAGE="Rate limit error detected"
      return 0
    fi
  fi

  return 1
}

# Parse rate limit info from a block of output
# Arguments: output_text
# Returns: JSON with rate limit info or empty
parse_rate_limit_info() {
  local output="$1"
  local resets_at="" resets_in="" message=""

  # Try to find resets_at (unix timestamp)
  resets_at=$(echo "$output" | grep -oE '"resets_at":\s*[0-9]+' | grep -o '[0-9]*' | head -1 || true)

  # Try to find resets_in_seconds
  resets_in=$(echo "$output" | grep -oE '"resets_in_seconds":\s*[0-9]+' | grep -o '[0-9]*' | head -1 || true)

  # Try to find message
  message=$(echo "$output" | grep -oE '"message":\s*"[^"]*"' | sed 's/"message":\s*"//' | sed 's/"$//' | head -1 || true)

  # Calculate resets_at from resets_in if needed
  if [[ -z "$resets_at" && -n "$resets_in" ]]; then
    resets_at=$(($(date +%s) + resets_in))
  fi

  if [[ -n "$resets_at" || -n "$message" ]]; then
    jq -n \
      --arg resets_at "$resets_at" \
      --arg resets_in "$resets_in" \
      --arg message "$message" \
      '{
        resets_at: (if $resets_at != "" then ($resets_at | tonumber) else null end),
        resets_in_seconds: (if $resets_in != "" then ($resets_in | tonumber) else null end),
        message: (if $message != "" then $message else null end)
      }'
  fi
}

# Wait for rate limit to reset
# Arguments: resets_at (unix timestamp), max_wait_seconds (default: 7200)
# Returns: 0 on success, 1 on timeout
wait_for_rate_limit_reset() {
  local resets_at="$1"
  local max_wait="${2:-7200}"  # Default 2 hours max
  local check_interval=60      # Check every minute

  if [[ -z "$resets_at" ]]; then
    echo "[rate-limit] No reset time provided, waiting 5 minutes..." >&2
    sleep 300
    return 0
  fi

  local now wait_seconds
  now=$(date +%s)

  # Handle if resets_at is already a timestamp or needs parsing
  if [[ ! "$resets_at" =~ ^[0-9]+$ ]]; then
    resets_at=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" +%s 2>/dev/null || echo "$now")
  fi

  wait_seconds=$((resets_at - now))

  if [[ "$wait_seconds" -le 0 ]]; then
    echo "[rate-limit] Reset time already passed, continuing..." >&2
    return 0
  fi

  if [[ "$wait_seconds" -gt "$max_wait" ]]; then
    echo "[rate-limit] Wait time (${wait_seconds}s) exceeds max (${max_wait}s), aborting" >&2
    return 1
  fi

  local formatted_wait
  formatted_wait=$(format_time_until_reset "$wait_seconds")
  echo "[rate-limit] Waiting ${formatted_wait} until $(date -r "$resets_at" '+%Y-%m-%d %H:%M:%S')..." >&2

  # Wait with periodic status updates
  local waited=0
  while [[ "$waited" -lt "$wait_seconds" ]]; do
    local remaining=$((wait_seconds - waited))
    if [[ "$remaining" -gt "$check_interval" ]]; then
      sleep "$check_interval"
      waited=$((waited + check_interval))
      formatted_wait=$(format_time_until_reset "$remaining")
      echo "[rate-limit] Still waiting... ${formatted_wait} remaining" >&2
    else
      sleep "$remaining"
      waited=$((waited + remaining))
    fi
  done

  echo "[rate-limit] Wait complete, resuming..." >&2
  return 0
}

# -----------------------------------------------------------------------------
# Session Management for Resume
# -----------------------------------------------------------------------------

# Generate a session ID for tracking
generate_session_id() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    # Fallback: use date + random
    echo "session-$(date +%s)-$RANDOM"
  fi
}

# Build resume command for Claude Code
# Arguments: session_id, resume_message (optional)
build_claude_resume_command() {
  local session_id="$1"
  local message="${2:-continue from where you left off}"

  echo "claude" "--resume" "$session_id" "-p" "$message"
}

# Build resume command for Codex
# Arguments: thread_id, resume_message (optional)
build_codex_resume_command() {
  local thread_id="$1"
  local message="${2:-continue from where you left off}"

  echo "codex" "exec" "resume" "$thread_id" "$message"
}

# Extract thread/session ID from Codex JSON output
# Arguments: output_text
extract_codex_thread_id() {
  local output="$1"
  echo "$output" | grep -oE '"thread_id":\s*"[^"]*"' | sed 's/"thread_id":\s*"//' | sed 's/"$//' | head -1 || true
}
