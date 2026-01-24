# Infrastructure Recovery System - Phase 1
# Enables automatic recovery from common infrastructure failures

# Check if a command is in the auto-approve list
# Returns 0 if approved, 1 if not
is_recovery_approved() {
  local command="$1"
  shift
  local auto_approve=("$@")

  for approved in "${auto_approve[@]}"; do
    if [[ "$command" == "$approved" ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a command is in the require-human list (blocked)
# Returns 0 if blocked, 1 if not
is_recovery_blocked() {
  local command="$1"
  shift
  local require_human=("$@")

  for blocked in "${require_human[@]}"; do
    # Support glob patterns with * wildcard
    if [[ "$blocked" == *"*"* ]]; then
      # Convert glob to regex: * -> .*
      local pattern="${blocked//\*/.*}"
      if [[ "$command" =~ ^$pattern$ ]]; then
        return 0
      fi
    elif [[ "$command" == "$blocked" ]]; then
      return 0
    fi
  done
  return 1
}

# Execute a recovery command
# Returns exit code of the command
execute_recovery() {
  local repo="$1"
  local command="$2"
  local working_dir="${3:-.}"
  local timeout_seconds="${4:-120}"

  local full_dir="$repo"
  if [[ "$working_dir" != "." && "$working_dir" != "./" ]]; then
    full_dir="$repo/$working_dir"
  fi

  if [[ ! -d "$full_dir" ]]; then
    echo "Recovery working directory does not exist: $full_dir" >&2
    return 1
  fi

  local start_time
  start_time=$(date +%s)

  # Execute with timeout
  local output
  local exit_code
  set +e
  output=$(cd "$full_dir" && timeout "$timeout_seconds" bash -c "$command" 2>&1)
  exit_code=$?
  set -e

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Return structured result via stdout
  jq -n \
    --arg command "$command" \
    --arg working_dir "$working_dir" \
    --argjson exit_code "$exit_code" \
    --argjson duration_ms "$((duration * 1000))" \
    --arg output "$output" \
    '{command: $command, working_dir: $working_dir, exit_code: $exit_code, duration_ms: $duration_ms, output: $output}'

  return $exit_code
}

# Process recovery.json and attempt recovery if appropriate
# Returns:
#   0 - recovery executed successfully
#   1 - recovery executed but failed
#   2 - recovery skipped (not approved, blocked, or disabled)
#   3 - no recovery.json found
process_recovery() {
  local repo="$1"
  local loop_dir="$2"
  local events_file="$3"
  local loop_id="$4"
  local iteration="$5"
  local run_id="$6"
  local recovery_enabled="$7"
  local max_recoveries="$8"
  local cooldown_seconds="$9"
  local on_unknown="${10}"
  shift 10
  local auto_approve=()
  local require_human=()

  # Parse remaining args: auto_approve items, then "---", then require_human items
  local in_require_human=0
  for arg in "$@"; do
    if [[ "$arg" == "---" ]]; then
      in_require_human=1
      continue
    fi
    if [[ $in_require_human -eq 1 ]]; then
      require_human+=("$arg")
    else
      auto_approve+=("$arg")
    fi
  done

  local recovery_file="$loop_dir/recovery.json"
  local recovery_state_file="$loop_dir/recovery-state.json"

  # Check if recovery is enabled
  if [[ "$recovery_enabled" != "true" ]]; then
    return 2
  fi

  # Check if recovery.json exists
  if [[ ! -f "$recovery_file" ]]; then
    return 3
  fi

  # Read recovery proposal
  local category command working_dir timeout_seconds confidence
  category=$(jq -r '.category // "unknown"' "$recovery_file")
  command=$(jq -r '.recovery.command // ""' "$recovery_file")
  working_dir=$(jq -r '.recovery.working_dir // "."' "$recovery_file")
  timeout_seconds=$(jq -r '.recovery.timeout_seconds // 120' "$recovery_file")
  confidence=$(jq -r '.recovery.confidence // "unknown"' "$recovery_file")

  if [[ -z "$command" ]]; then
    echo "Recovery proposal has no command" >&2
    return 2
  fi

  # Log recovery_proposed event
  local proposed_data
  proposed_data=$(jq -c '.' "$recovery_file")
  log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_proposed" "$proposed_data"

  # Check recovery count limit
  local recovery_count=0
  if [[ -f "$recovery_state_file" ]]; then
    recovery_count=$(jq -r ".recoveries_this_run // 0" "$recovery_state_file")
    local last_recovery_time
    last_recovery_time=$(jq -r ".last_recovery_time // 0" "$recovery_state_file")

    # Check cooldown
    local now
    now=$(date +%s)
    local elapsed=$((now - last_recovery_time))
    if [[ $elapsed -lt $cooldown_seconds ]]; then
      local cooldown_data
      cooldown_data=$(jq -n \
        --arg command "$command" \
        --argjson elapsed "$elapsed" \
        --argjson cooldown "$cooldown_seconds" \
        '{command: $command, reason: "cooldown", elapsed_seconds: $elapsed, cooldown_seconds: $cooldown}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_skipped" "$cooldown_data"
      return 2
    fi
  fi

  if [[ $recovery_count -ge $max_recoveries ]]; then
    local limit_data
    limit_data=$(jq -n \
      --arg command "$command" \
      --argjson count "$recovery_count" \
      --argjson max "$max_recoveries" \
      '{command: $command, reason: "max_recoveries_reached", count: $count, max: $max}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_skipped" "$limit_data"
    return 2
  fi

  # Check if command is blocked
  if is_recovery_blocked "$command" "${require_human[@]}"; then
    local blocked_data
    blocked_data=$(jq -n \
      --arg command "$command" \
      --arg category "$category" \
      '{command: $command, category: $category, reason: "require_human"}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_blocked" "$blocked_data"
    return 2
  fi

  # Check if command is approved
  if ! is_recovery_approved "$command" "${auto_approve[@]}"; then
    # Command not in auto_approve list
    if [[ "$on_unknown" == "deny" ]]; then
      local denied_data
      denied_data=$(jq -n \
        --arg command "$command" \
        --arg category "$category" \
        '{command: $command, category: $category, reason: "not_in_auto_approve"}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_denied" "$denied_data"
      return 2
    elif [[ "$on_unknown" == "escalate" ]]; then
      local escalate_data
      escalate_data=$(jq -n \
        --arg command "$command" \
        --arg category "$category" \
        --arg confidence "$confidence" \
        '{command: $command, category: $category, confidence: $confidence, reason: "not_in_auto_approve"}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_escalated" "$escalate_data"
      # Write escalation file for Phase 2
      jq -n \
        --arg timestamp "$(timestamp)" \
        --arg loop_id "$loop_id" \
        --argjson iteration "$iteration" \
        --arg type "recovery_approval_required" \
        --arg status "pending" \
        --argjson recovery_proposal "$proposed_data" \
        --arg reason "Command not in auto_approve list" \
        '{timestamp: $timestamp, loop_id: $loop_id, iteration: $iteration, type: $type, status: $status, recovery_proposal: $recovery_proposal, reason: $reason}' \
        > "$loop_dir/escalation.json"
      return 2
    fi
    # on_unknown == "allow" falls through to execute
  fi

  # Log approval and execute
  local approved_data
  approved_data=$(jq -n \
    --arg command "$command" \
    --arg category "$category" \
    --arg source "auto" \
    '{command: $command, category: $category, source: $source}')
  log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_approved" "$approved_data"

  echo "Executing recovery: $command"

  local result
  local exec_rc=0
  set +e
  result=$(execute_recovery "$repo" "$command" "$working_dir" "$timeout_seconds")
  exec_rc=$?
  set -e

  # Update recovery state
  local now
  now=$(date +%s)
  jq -n \
    --argjson recoveries_this_run "$((recovery_count + 1))" \
    --argjson last_recovery_time "$now" \
    '{recoveries_this_run: $recoveries_this_run, last_recovery_time: $last_recovery_time}' \
    > "$recovery_state_file"

  if [[ $exec_rc -eq 0 ]]; then
    local success_data
    success_data=$(echo "$result" | jq -c '. + {status: "success"}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_executed" "$success_data"
    echo "Recovery successful"
    # Remove recovery.json after successful execution
    rm -f "$recovery_file"
    return 0
  else
    local failure_data
    failure_data=$(echo "$result" | jq -c '. + {status: "failed"}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_failed" "$failure_data"
    echo "Recovery failed with exit code $exec_rc"
    return 1
  fi
}

# Parse recovery config from loop JSON
# Outputs space-separated: enabled max_recoveries cooldown on_unknown
parse_recovery_config() {
  local loop_json="$1"

  local enabled max_recoveries cooldown on_unknown
  enabled=$(echo "$loop_json" | jq -r '.recovery.enabled // false')
  max_recoveries=$(echo "$loop_json" | jq -r '.recovery.max_auto_recoveries_per_run // 3')
  cooldown=$(echo "$loop_json" | jq -r '.recovery.cooldown_seconds // 60')
  on_unknown=$(echo "$loop_json" | jq -r '.recovery.on_unknown // "escalate"')

  echo "$enabled $max_recoveries $cooldown $on_unknown"
}

# Parse auto_approve list from loop JSON
# Outputs newline-separated commands
parse_recovery_auto_approve() {
  local loop_json="$1"
  echo "$loop_json" | jq -r '.recovery.auto_approve // [] | .[]'
}

# Parse require_human list from loop JSON
# Outputs newline-separated patterns
parse_recovery_require_human() {
  local loop_json="$1"
  echo "$loop_json" | jq -r '.recovery.require_human // [] | .[]'
}
