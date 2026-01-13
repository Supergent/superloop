# Usage tracking functions for Claude Code and Codex
# Extracts token counts and timing from session files

# Global variables for usage tracking
USAGE_TRACKING_ENABLED=1
USAGE_SESSION_ID=""
USAGE_THREAD_ID=""
USAGE_MODEL=""
USAGE_START_TIME=""
USAGE_END_TIME=""
USAGE_FILE=""

# Detect runner type from command array
# Returns: "claude", "codex", or "unknown"
detect_runner_type() {
  local -a cmd=("$@")
  local cmd_str="${cmd[*]}"

  if [[ "${cmd[0]}" == "claude" ]] || [[ "$cmd_str" == *"/claude "* ]] || [[ "$cmd_str" == *"/claude" ]]; then
    echo "claude"
  elif [[ "${cmd[0]}" == "codex" ]] || [[ "$cmd_str" == *"/codex "* ]] || [[ "$cmd_str" == *"/codex" ]]; then
    echo "codex"
  else
    echo "unknown"
  fi
}

# Generate a UUID for Claude session tracking
generate_session_id() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    # Fallback: generate pseudo-UUID from timestamp and random
    printf '%08x-%04x-%04x-%04x-%012x' \
      $((RANDOM * RANDOM)) \
      $((RANDOM)) \
      $((RANDOM)) \
      $((RANDOM)) \
      $((RANDOM * RANDOM * RANDOM))
  fi
}

# Get milliseconds timestamp
get_timestamp_ms() {
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: use python or perl for milliseconds
    python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || \
    perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000' 2>/dev/null || \
    echo "$(($(date +%s) * 1000))"
  else
    # Linux: date supports %N for nanoseconds
    echo "$(($(date +%s%N) / 1000000))"
  fi
}

# Find Claude session file by session ID
# Args: $1 = repo path, $2 = session_id
find_claude_session_file() {
  local repo="$1"
  local session_id="$2"
  local project_name
  project_name=$(basename "$repo")

  # Claude stores sessions in ~/.claude/projects/<project>/<session-id>.jsonl
  local session_file="$HOME/.claude/projects/-${project_name//\//-}/${session_id}.jsonl"

  if [[ -f "$session_file" ]]; then
    echo "$session_file"
    return 0
  fi

  # Try alternative path formats
  local alt_file
  for alt_file in "$HOME/.claude/projects"/*"$project_name"*/"${session_id}.jsonl"; do
    if [[ -f "$alt_file" ]]; then
      echo "$alt_file"
      return 0
    fi
  done

  return 1
}

# Find Codex session file by thread ID
# Args: $1 = thread_id
find_codex_session_file() {
  local thread_id="$1"

  # Codex stores sessions in ~/.codex/sessions/YYYY/MM/DD/rollout-*-<thread_id>.jsonl
  local session_file
  session_file=$(find "$HOME/.codex/sessions" -name "*${thread_id}.jsonl" -type f 2>/dev/null | head -n1)

  if [[ -n "$session_file" && -f "$session_file" ]]; then
    echo "$session_file"
    return 0
  fi

  return 1
}

# Extract usage from Claude session file
# Args: $1 = session_file
# Output: JSON object with usage stats
extract_claude_usage() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    echo '{"error": "session file not found"}'
    return 1
  fi

  # Extract usage from assistant messages
  jq -s '
    [.[] | select(.type == "assistant" and .message.usage != null) | .message.usage] |
    if length == 0 then
      {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
    else
      {
        "input_tokens": (map(.input_tokens // 0) | add),
        "output_tokens": (map(.output_tokens // 0) | add),
        "cache_read_input_tokens": (map(.cache_read_input_tokens // 0) | add),
        "cache_creation_input_tokens": (map(.cache_creation_input_tokens // 0) | add)
      }
    end
  ' "$session_file" 2>/dev/null || echo '{"error": "failed to parse session file"}'
}

# Extract usage from Codex session file
# Args: $1 = session_file
# Output: JSON object with usage stats
extract_codex_usage() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    echo '{"error": "session file not found"}'
    return 1
  fi

  # Extract token_count events from Codex JSONL
  jq -s '
    [.[] | select(.type == "event_msg" and .payload.type == "token_count") | .payload] |
    if length == 0 then
      {"input_tokens": 0, "output_tokens": 0}
    else
      {
        "input_tokens": (map(.input_tokens // 0) | add),
        "output_tokens": (map(.output_tokens // 0) | add)
      }
    end
  ' "$session_file" 2>/dev/null || echo '{"error": "failed to parse session file"}'
}

# Extract thread_id from Codex JSON output
# Args: $1 = log_file containing JSON output
extract_codex_thread_id() {
  local log_file="$1"

  if [[ ! -f "$log_file" ]]; then
    return 1
  fi

  # Look for thread.started event with thread_id
  local thread_id
  thread_id=$(grep -m1 '"thread_id"' "$log_file" 2>/dev/null | jq -r '.thread_id // empty' 2>/dev/null)

  if [[ -n "$thread_id" ]]; then
    echo "$thread_id"
    return 0
  fi

  return 1
}

# Extract thread_id from Codex session filename
# Session files are named: rollout-<timestamp>-<thread_id>.jsonl
# Args: $1 = session_file path
extract_thread_id_from_filename() {
  local session_file="$1"
  local filename
  filename=$(basename "$session_file")

  # Pattern: rollout-YYYYMMDD_HHMMSS_mmm-<thread_id>.jsonl
  # or: rollout-<number>-<thread_id>.jsonl
  if [[ "$filename" =~ ^rollout-.*-([a-zA-Z0-9_-]+)\.jsonl$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

# Find Codex session file by start time and extract thread_id
# Args: $1 = start_timestamp_seconds
# Sets: USAGE_THREAD_ID global
# Returns: 0 if found, 1 otherwise
find_and_set_codex_thread_id() {
  local start_ts="$1"
  local session_file thread_id

  # Find session file created after start time
  session_file=$(find "$HOME/.codex/sessions" -name "rollout-*.jsonl" -type f -newermt "@$start_ts" 2>/dev/null | head -n1 || true)

  if [[ -z "$session_file" ]]; then
    return 1
  fi

  # Extract thread_id from filename
  thread_id=$(extract_thread_id_from_filename "$session_file" || true)

  if [[ -n "$thread_id" ]]; then
    USAGE_THREAD_ID="$thread_id"
    return 0
  fi

  return 1
}

# Extract model from Claude session file
# Args: $1 = session_file
# Output: model name (e.g., "claude-sonnet-4-20250514")
extract_claude_model() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    return 1
  fi

  # Extract model from first assistant message
  local model
  model=$(jq -r '[.[] | select(.type == "assistant" and .message.model != null) | .message.model][0] // empty' "$session_file" 2>/dev/null)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  return 1
}

# Extract model from Codex log output
# Args: $1 = log_file
# Output: model name (e.g., "gpt-5.2-codex")
extract_codex_model_from_log() {
  local log_file="$1"

  if [[ ! -f "$log_file" ]]; then
    return 1
  fi

  # Look for "model: xxx" line in the header
  local model
  model=$(grep -m1 '^model:' "$log_file" 2>/dev/null | sed 's/^model:[[:space:]]*//' || true)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  return 1
}

# Extract model from Codex session file
# Args: $1 = session_file
# Output: model name
extract_codex_model() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    return 1
  fi

  # Try to find model in session metadata or messages
  local model
  model=$(jq -r '[.[] | select(.model != null) | .model][0] // empty' "$session_file" 2>/dev/null)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  # Try alternate structure
  model=$(jq -r '.model // empty' "$session_file" 2>/dev/null | head -1)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  return 1
}

# Write usage event to JSONL file
# Args: $1 = usage_file, $2 = iteration, $3 = role, $4 = duration_ms, $5 = usage_json, $6 = runner_type, $7 = session_file
write_usage_event() {
  local usage_file="$1"
  local iteration="$2"
  local role="$3"
  local duration_ms="$4"
  local usage_json="$5"
  local runner_type="$6"
  local session_file="${7:-}"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build the event JSON - include session/thread IDs and model from globals
  jq -n \
    --arg ts "$timestamp" \
    --argjson iter "$iteration" \
    --arg role "$role" \
    --argjson duration "$duration_ms" \
    --argjson usage "$usage_json" \
    --arg runner "$runner_type" \
    --arg session "$session_file" \
    --arg session_id "${USAGE_SESSION_ID:-}" \
    --arg thread_id "${USAGE_THREAD_ID:-}" \
    --arg model "${USAGE_MODEL:-}" \
    '{
      "timestamp": $ts,
      "iteration": $iter,
      "role": $role,
      "duration_ms": $duration,
      "runner": $runner,
      "model": (if $model == "" then null else $model end),
      "session_id": (if $session_id == "" then null else $session_id end),
      "thread_id": (if $thread_id == "" then null else $thread_id end),
      "usage": $usage,
      "session_file": (if $session == "" then null else $session end)
    }' >> "$usage_file"
}

# Write session entry to sessions manifest
# Args: $1 = sessions_file, $2 = iteration, $3 = role, $4 = runner_type, $5 = status, $6 = started_at, $7 = ended_at
write_session_entry() {
  local sessions_file="$1"
  local iteration="$2"
  local role="$3"
  local runner_type="$4"
  local status="$5"
  local started_at="$6"
  local ended_at="${7:-}"

  if [[ -z "$sessions_file" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$sessions_file")"

  jq -c -n \
    --argjson iter "$iteration" \
    --arg role "$role" \
    --arg runner "$runner_type" \
    --arg session_id "${USAGE_SESSION_ID:-}" \
    --arg thread_id "${USAGE_THREAD_ID:-}" \
    --arg model "${USAGE_MODEL:-}" \
    --arg status "$status" \
    --arg started_at "$started_at" \
    --arg ended_at "$ended_at" \
    '{
      iteration: $iter,
      role: $role,
      runner: $runner,
      model: (if $model == "" then null else $model end),
      session_id: (if $session_id == "" then null else $session_id end),
      thread_id: (if $thread_id == "" then null else $thread_id end),
      status: $status,
      started_at: $started_at,
      ended_at: (if $ended_at == "" then null else $ended_at end)
    }' >> "$sessions_file"
}

# Get the current session info as JSON (for state tracking)
get_current_session_json() {
  jq -c -n \
    --arg session_id "${USAGE_SESSION_ID:-}" \
    --arg thread_id "${USAGE_THREAD_ID:-}" \
    --arg runner "${CURRENT_RUNNER_TYPE:-unknown}" \
    '{
      session_id: (if $session_id == "" then null else $session_id end),
      thread_id: (if $thread_id == "" then null else $thread_id end),
      runner: $runner
    }'
}

# Prepare command with session tracking args
# Args: $1 = runner_type, rest = original command
# Sets: USAGE_SESSION_ID for claude
# Output: Modified command array elements (one per line)
prepare_tracked_command() {
  local runner_type="$1"
  shift
  local -a cmd=("$@")

  USAGE_SESSION_ID=""

  case "$runner_type" in
    claude)
      # Generate session ID and inject --session-id flag
      USAGE_SESSION_ID=$(generate_session_id)

      # Find where to insert --session-id (after 'claude' command)
      local inserted=0
      for i in "${!cmd[@]}"; do
        echo "${cmd[$i]}"
        if [[ $inserted -eq 0 && ("${cmd[$i]}" == "claude" || "${cmd[$i]}" == */claude) ]]; then
          echo "--session-id"
          echo "$USAGE_SESSION_ID"
          inserted=1
        fi
      done
      ;;

    codex)
      # For codex, we need --json flag to capture thread_id
      # But this changes output format, so we'll use timestamp-based matching instead
      # Just pass through the command unchanged
      for arg in "${cmd[@]}"; do
        echo "$arg"
      done
      ;;

    *)
      # Unknown runner, pass through unchanged
      for arg in "${cmd[@]}"; do
        echo "$arg"
      done
      ;;
  esac
}

# Main usage tracking wrapper
# Call this before and after running the command
# Args: $1 = action (start|end), $2 = usage_file, $3 = iteration, $4 = role, $5 = repo, $6 = runner_type, $7 = log_file (optional, for model extraction)
track_usage() {
  local action="$1"
  local usage_file="$2"
  local iteration="$3"
  local role="$4"
  local repo="$5"
  local runner_type="$6"
  local log_file="${7:-}"

  case "$action" in
    start)
      USAGE_START_TIME=$(get_timestamp_ms)
      USAGE_MODEL=""  # Reset model for new run
      ;;

    end)
      USAGE_END_TIME=$(get_timestamp_ms)
      local duration_ms=$((USAGE_END_TIME - USAGE_START_TIME))

      # Find and parse session file based on runner type
      local session_file=""
      local usage_json='{"input_tokens": 0, "output_tokens": 0}'

      case "$runner_type" in
        claude)
          if [[ -n "$USAGE_SESSION_ID" ]]; then
            session_file=$(find_claude_session_file "$repo" "$USAGE_SESSION_ID" || true)
            if [[ -n "$session_file" ]]; then
              usage_json=$(extract_claude_usage "$session_file")
              # Extract model from session file
              USAGE_MODEL=$(extract_claude_model "$session_file" || true)
            fi
          fi
          ;;

        codex)
          # For Codex, find the most recent session file modified after start time
          local start_ts=$((USAGE_START_TIME / 1000))
          session_file=$(find "$HOME/.codex/sessions" -name "rollout-*.jsonl" -type f -newermt "@$start_ts" 2>/dev/null | head -n1 || true)
          if [[ -n "$session_file" ]]; then
            usage_json=$(extract_codex_usage "$session_file")
            # Try to extract model from session file first
            USAGE_MODEL=$(extract_codex_model "$session_file" || true)
          fi
          # If no model from session, try log file
          if [[ -z "$USAGE_MODEL" && -n "$log_file" && -f "$log_file" ]]; then
            USAGE_MODEL=$(extract_codex_model_from_log "$log_file" || true)
          fi
          ;;
      esac

      # Write usage event
      if [[ -n "$usage_file" ]]; then
        mkdir -p "$(dirname "$usage_file")"
        write_usage_event "$usage_file" "$iteration" "$role" "$duration_ms" "$usage_json" "$runner_type" "$session_file"
      fi
      ;;
  esac
}
