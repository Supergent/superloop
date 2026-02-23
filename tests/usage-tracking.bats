#!/usr/bin/env bats
# Tests for src/35-usage.sh - Usage tracking for Claude and Codex

setup() {
  # Create temporary directory for test files
  TEMP_DIR=$(mktemp -d)
  export TEMP_DIR

  # Source the usage tracking module
  source "$BATS_TEST_DIRNAME/../src/35-usage.sh"

  # Create mock home directory structure for session files
  MOCK_HOME="$TEMP_DIR/home"
  mkdir -p "$MOCK_HOME/.claude/projects"
  mkdir -p "$MOCK_HOME/.codex/sessions/2024/01/15"

  # Override HOME for session file lookups
  export HOME="$MOCK_HOME"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# ============================================================================
# Runner Type Detection Tests
# ============================================================================

@test "usage: detect_runner_type identifies claude from command" {
  result=$(detect_runner_type "claude" "--session-id" "abc123" "code")
  [ "$result" = "claude" ]
}

@test "usage: detect_runner_type identifies claude from path" {
  result=$(detect_runner_type "/usr/local/bin/claude" "code")
  [ "$result" = "claude" ]
}

@test "usage: detect_runner_type identifies codex from command" {
  result=$(detect_runner_type "codex" "run" "--prompt" "test")
  [ "$result" = "codex" ]
}

@test "usage: detect_runner_type identifies codex from path" {
  result=$(detect_runner_type "/opt/codex/bin/codex" "run")
  [ "$result" = "codex" ]
}

@test "usage: detect_runner_type returns unknown for other commands" {
  result=$(detect_runner_type "bash" "script.sh")
  [ "$result" = "unknown" ]
}

# ============================================================================
# Session ID Generation Tests
# ============================================================================

@test "usage: generate_session_id produces valid UUID format" {
  result=$(generate_session_id)

  # UUID format: 8-4-4-4-12 hex characters
  [[ "$result" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "usage: generate_session_id produces unique IDs" {
  id1=$(generate_session_id)
  id2=$(generate_session_id)

  [ "$id1" != "$id2" ]
}

# ============================================================================
# Timestamp Tests
# ============================================================================

@test "usage: get_timestamp_ms returns numeric millisecond timestamp" {
  result=$(get_timestamp_ms)

  # Should be a 13-digit number (milliseconds since epoch)
  [[ "$result" =~ ^[0-9]{13,}$ ]]
}

@test "usage: get_timestamp_ms timestamps are increasing" {
  ts1=$(get_timestamp_ms)
  sleep 0.1
  ts2=$(get_timestamp_ms)

  [ "$ts2" -gt "$ts1" ]
}

# ============================================================================
# Claude Session File Location Tests
# ============================================================================

@test "usage: find_claude_session_file locates session by project name" {
  local repo="$TEMP_DIR/my-project"
  mkdir -p "$repo"

  local session_id="abc-123-def"
  local session_file="$MOCK_HOME/.claude/projects/-my-project/${session_id}.jsonl"
  mkdir -p "$(dirname "$session_file")"
  touch "$session_file"

  result=$(find_claude_session_file "$repo" "$session_id")
  [ "$result" = "$session_file" ]
}

@test "usage: find_claude_session_file handles slashes in project name" {
  local repo="$TEMP_DIR/my/nested/project"
  mkdir -p "$repo"

  local session_id="xyz-789"
  # Slashes should be converted to dashes
  local session_file="$MOCK_HOME/.claude/projects/-my-nested-project/${session_id}.jsonl"
  mkdir -p "$(dirname "$session_file")"
  touch "$session_file"

  result=$(find_claude_session_file "$repo" "$session_id")
  [ "$result" = "$session_file" ]
}

@test "usage: find_claude_session_file returns error when not found" {
  local repo="$TEMP_DIR/nonexistent"
  mkdir -p "$repo"

  run find_claude_session_file "$repo" "missing-id"
  [ "$status" -eq 1 ]
}

@test "usage: find_claude_session_file tries alternative path formats" {
  local repo="$TEMP_DIR/project"
  mkdir -p "$repo"

  local session_id="alt-123"
  # Create in alternative location
  local alt_dir="$MOCK_HOME/.claude/projects/some-prefix-project-suffix"
  mkdir -p "$alt_dir"
  local session_file="$alt_dir/${session_id}.jsonl"
  touch "$session_file"

  result=$(find_claude_session_file "$repo" "$session_id")
  [ "$result" = "$session_file" ]
}

# ============================================================================
# Codex Session File Location Tests
# ============================================================================

@test "usage: find_codex_session_file locates session by thread ID" {
  local thread_id="thread-abc-123"
  local session_file="$MOCK_HOME/.codex/sessions/2024/01/15/rollout-20240115_100000-${thread_id}.jsonl"
  mkdir -p "$(dirname "$session_file")"
  touch "$session_file"

  result=$(find_codex_session_file "$thread_id")
  [ "$result" = "$session_file" ]
}

@test "usage: find_codex_session_file handles multiple matching files" {
  local thread_id="thread-xyz"
  # Create multiple files with same thread ID (should return first)
  local file1="$MOCK_HOME/.codex/sessions/2024/01/14/rollout-001-${thread_id}.jsonl"
  local file2="$MOCK_HOME/.codex/sessions/2024/01/15/rollout-002-${thread_id}.jsonl"

  mkdir -p "$(dirname "$file1")"
  mkdir -p "$(dirname "$file2")"
  touch "$file1"
  touch "$file2"

  result=$(find_codex_session_file "$thread_id")
  # Should find one of them
  [[ "$result" =~ $thread_id\.jsonl$ ]]
}

@test "usage: find_codex_session_file returns error when not found" {
  run find_codex_session_file "nonexistent-thread"
  [ "$status" -eq 1 ]
}

# ============================================================================
# Claude Usage Extraction Tests
# ============================================================================

@test "usage: extract_claude_usage parses session JSONL" {
  local session_file="$TEMP_DIR/claude-session.jsonl"

  # Create mock Claude session file with usage data
  cat > "$session_file" << 'EOF'
{"type":"user","message":{"role":"user","content":"Hello"}}
{"type":"assistant","message":{"role":"assistant","content":"Hi!","model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":50,"thinking_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"type":"user","message":{"role":"user","content":"How are you?"}}
{"type":"assistant","message":{"role":"assistant","content":"Good!","model":"claude-sonnet-4-20250514","usage":{"input_tokens":150,"output_tokens":75,"thinking_tokens":10,"cache_read_input_tokens":50,"cache_creation_input_tokens":100}}}
EOF

  result=$(extract_claude_usage "$session_file")

  # Verify totals are summed correctly
  input=$(echo "$result" | jq -r '.input_tokens')
  output=$(echo "$result" | jq -r '.output_tokens')
  thinking=$(echo "$result" | jq -r '.thinking_tokens')
  cache_read=$(echo "$result" | jq -r '.cache_read_input_tokens')
  cache_creation=$(echo "$result" | jq -r '.cache_creation_input_tokens')

  [ "$input" = "250" ]
  [ "$output" = "125" ]
  [ "$thinking" = "10" ]
  [ "$cache_read" = "50" ]
  [ "$cache_creation" = "100" ]
}

@test "usage: extract_claude_usage extracts thinking_tokens separately" {
  local session_file="$TEMP_DIR/claude-thinking.jsonl"

  cat > "$session_file" << 'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":500,"thinking_tokens":32000}}}
EOF

  result=$(extract_claude_usage "$session_file")
  thinking=$(echo "$result" | jq -r '.thinking_tokens')

  [ "$thinking" = "32000" ]
}

@test "usage: extract_claude_usage handles missing usage gracefully" {
  local session_file="$TEMP_DIR/claude-no-usage.jsonl"

  cat > "$session_file" << 'EOF'
{"type":"user","message":{"role":"user","content":"Test"}}
EOF

  result=$(extract_claude_usage "$session_file")

  # Should return zeros
  input=$(echo "$result" | jq -r '.input_tokens')
  output=$(echo "$result" | jq -r '.output_tokens')

  [ "$input" = "0" ]
  [ "$output" = "0" ]
}

@test "usage: extract_claude_usage handles missing file" {
  result=$(extract_claude_usage "/nonexistent/file.jsonl" 2>&1 || true)

  error=$(echo "$result" | jq -r '.error')
  [ "$error" = "session file not found" ]
}

@test "usage: extract_claude_usage handles invalid JSON" {
  local session_file="$TEMP_DIR/invalid.jsonl"
  echo "not valid json" > "$session_file"

  result=$(extract_claude_usage "$session_file")
  error=$(echo "$result" | jq -r '.error')

  [ "$error" = "failed to parse session file" ]
}

# ============================================================================
# Codex Usage Extraction Tests
# ============================================================================

@test "usage: extract_codex_usage parses session JSONL" {
  local session_file="$TEMP_DIR/codex-session.jsonl"

  # Create mock Codex session file with token_count events
  cat > "$session_file" << 'EOF'
{"type":"event_msg","payload":{"type":"thread.started","thread_id":"abc123"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"output_tokens":250,"cached_input_tokens":100,"reasoning_output_tokens":50}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":800,"output_tokens":400,"cached_input_tokens":200,"reasoning_output_tokens":150}}}}
EOF

  result=$(extract_codex_usage "$session_file")

  # Should take the LAST token_count event (cumulative totals)
  input=$(echo "$result" | jq -r '.input_tokens')
  output=$(echo "$result" | jq -r '.output_tokens')
  cached=$(echo "$result" | jq -r '.cached_input_tokens')
  reasoning=$(echo "$result" | jq -r '.reasoning_output_tokens')

  [ "$input" = "800" ]
  [ "$output" = "400" ]
  [ "$cached" = "200" ]
  [ "$reasoning" = "150" ]
}

@test "usage: extract_codex_usage extracts reasoning_output_tokens" {
  local session_file="$TEMP_DIR/codex-reasoning.jsonl"

  cat > "$session_file" << 'EOF'
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"output_tokens":500,"reasoning_output_tokens":25000}}}}
EOF

  result=$(extract_codex_usage "$session_file")
  reasoning=$(echo "$result" | jq -r '.reasoning_output_tokens')

  [ "$reasoning" = "25000" ]
}

@test "usage: extract_codex_usage handles missing token_count events" {
  local session_file="$TEMP_DIR/codex-no-tokens.jsonl"

  cat > "$session_file" << 'EOF'
{"type":"event_msg","payload":{"type":"thread.started"}}
EOF

  result=$(extract_codex_usage "$session_file")

  # Should return zeros
  input=$(echo "$result" | jq -r '.input_tokens')
  output=$(echo "$result" | jq -r '.output_tokens')

  [ "$input" = "0" ]
  [ "$output" = "0" ]
}

@test "usage: extract_codex_usage handles missing file" {
  result=$(extract_codex_usage "/nonexistent/file.jsonl" 2>&1 || true)

  error=$(echo "$result" | jq -r '.error')
  [ "$error" = "session file not found" ]
}

@test "usage: extract_codex_usage handles invalid JSON" {
  local session_file="$TEMP_DIR/invalid-codex.jsonl"
  echo "not valid json at all" > "$session_file"

  result=$(extract_codex_usage "$session_file")
  error=$(echo "$result" | jq -r '.error')

  [ "$error" = "failed to parse session file" ]
}

# ============================================================================
# Thread ID Extraction Tests
# ============================================================================

@test "usage: extract_thread_id_from_filename parses rollout filename" {
  result=$(extract_thread_id_from_filename "rollout-20240115_100000-threadabc123.jsonl")
  [ "$result" = "threadabc123" ]
}

@test "usage: extract_thread_id_from_filename handles simple rollout pattern" {
  result=$(extract_thread_id_from_filename "rollout-001-mythreadid.jsonl")
  [ "$result" = "mythreadid" ]
}

@test "usage: extract_thread_id_from_filename handles full path" {
  result=$(extract_thread_id_from_filename "/path/to/rollout-123-xyz.jsonl")
  [ "$result" = "xyz" ]
}

@test "usage: extract_thread_id_from_filename preserves dashed UUID thread IDs" {
  result=$(extract_thread_id_from_filename "rollout-2026-02-18T20-18-16-019c7379-ed87-7320-8162-a71a386c08f7.jsonl")
  [ "$result" = "019c7379-ed87-7320-8162-a71a386c08f7" ]
}

@test "usage: extract_thread_id_from_filename returns error for invalid format" {
  run extract_thread_id_from_filename "not-a-rollout-file.jsonl"
  [ "$status" -eq 1 ]
}

@test "usage: extract_codex_thread_id extracts from log file JSON" {
  local log_file="$TEMP_DIR/codex.log"

  cat > "$log_file" << 'EOF'
{"type":"thread.started","thread_id":"extracted-thread-123"}
{"type":"other","data":"stuff"}
EOF

  result=$(extract_codex_thread_id "$log_file")
  [ "$result" = "extracted-thread-123" ]
}

@test "usage: extract_codex_thread_id returns error for missing file" {
  run extract_codex_thread_id "/nonexistent/log.txt"
  [ "$status" -eq 1 ]
}

# ============================================================================
# Model Extraction Tests
# ============================================================================

@test "usage: extract_claude_model extracts model from session" {
  local session_file="$TEMP_DIR/claude-model.jsonl"

  cat > "$session_file" << 'EOF'
{"type":"user","message":{"content":"Hi"}}
{"type":"assistant","message":{"model":"claude-sonnet-4-20250514","content":"Hello"}}
EOF

  result=$(extract_claude_model "$session_file")
  [ "$result" = "claude-sonnet-4-20250514" ]
}

@test "usage: extract_claude_model returns first model when multiple" {
  local session_file="$TEMP_DIR/claude-multi-model.jsonl"

  cat > "$session_file" << 'EOF'
{"type":"assistant","message":{"model":"claude-sonnet-4-20250514","content":"First"}}
{"type":"assistant","message":{"model":"claude-opus-4-20250514","content":"Second"}}
EOF

  result=$(extract_claude_model "$session_file")
  [ "$result" = "claude-sonnet-4-20250514" ]
}

@test "usage: extract_claude_model handles missing model" {
  local session_file="$TEMP_DIR/claude-no-model.jsonl"

  cat > "$session_file" << 'EOF'
{"type":"user","message":{"content":"Test"}}
EOF

  run extract_claude_model "$session_file"
  [ "$status" -eq 1 ]
}

@test "usage: extract_codex_model_from_log extracts model from header" {
  local log_file="$TEMP_DIR/codex.log"

  cat > "$log_file" << 'EOF'
model: gpt-5.2-codex
thread_id: abc123
Some other output
EOF

  result=$(extract_codex_model_from_log "$log_file")
  [ "$result" = "gpt-5.2-codex" ]
}

@test "usage: extract_codex_model_from_log handles whitespace" {
  local log_file="$TEMP_DIR/codex-spaces.log"

  cat > "$log_file" << 'EOF'
model:     gpt-5.2-codex-pro
EOF

  result=$(extract_codex_model_from_log "$log_file")
  [ "$result" = "gpt-5.2-codex-pro" ]
}

# ============================================================================
# Usage Event Writing Tests
# ============================================================================

@test "usage: write_usage_event creates valid JSONL entry" {
  local usage_file="$TEMP_DIR/usage.jsonl"
  local usage_json='{"input_tokens":100,"output_tokens":50,"thinking_tokens":10}'

  USAGE_SESSION_ID="session-123"
  USAGE_THREAD_ID=""
  USAGE_MODEL="claude-sonnet-4-20250514"

  write_usage_event "$usage_file" 1 "planner" 5000 "$usage_json" "claude" "/path/to/session.jsonl"

  [ -f "$usage_file" ]

  # Validate JSON structure
  iteration=$(jq -r '.iteration' "$usage_file")
  role=$(jq -r '.role' "$usage_file")
  duration=$(jq -r '.duration_ms' "$usage_file")
  runner=$(jq -r '.runner' "$usage_file")
  model=$(jq -r '.model' "$usage_file")
  session_id=$(jq -r '.session_id' "$usage_file")
  input_tokens=$(jq -r '.usage.input_tokens' "$usage_file")

  [ "$iteration" = "1" ]
  [ "$role" = "planner" ]
  [ "$duration" = "5000" ]
  [ "$runner" = "claude" ]
  [ "$model" = "claude-sonnet-4-20250514" ]
  [ "$session_id" = "session-123" ]
  [ "$input_tokens" = "100" ]
}

@test "usage: write_usage_event includes timestamp" {
  local usage_file="$TEMP_DIR/usage-ts.jsonl"
  local usage_json='{"input_tokens":50,"output_tokens":25}'

  USAGE_MODEL=""
  write_usage_event "$usage_file" 2 "implementer" 3000 "$usage_json" "codex" ""

  timestamp=$(jq -r '.timestamp' "$usage_file")

  # Should be ISO 8601 format
  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "usage: write_usage_event handles null model gracefully" {
  local usage_file="$TEMP_DIR/usage-no-model.jsonl"
  local usage_json='{"input_tokens":10,"output_tokens":5}'

  USAGE_MODEL=""
  write_usage_event "$usage_file" 3 "tester" 1000 "$usage_json" "unknown" ""

  model=$(jq -r '.model' "$usage_file")
  [ "$model" = "null" ]
}

@test "usage: write_usage_event appends to existing file" {
  local usage_file="$TEMP_DIR/usage-append.jsonl"
  local usage_json='{"input_tokens":100,"output_tokens":50}'

  USAGE_MODEL="model-1"
  write_usage_event "$usage_file" 1 "planner" 2000 "$usage_json" "claude" ""

  USAGE_MODEL="model-2"
  write_usage_event "$usage_file" 2 "implementer" 3000 "$usage_json" "codex" ""

  # Should have 2 lines
  line_count=$(wc -l < "$usage_file" | tr -d ' ')
  [ "$line_count" = "2" ]

  # Check both entries
  first_iter=$(sed -n '1p' "$usage_file" | jq -r '.iteration')
  second_iter=$(sed -n '2p' "$usage_file" | jq -r '.iteration')

  [ "$first_iter" = "1" ]
  [ "$second_iter" = "2" ]
}

@test "usage: write_usage_event aggregates usage across iterations" {
  local usage_file="$TEMP_DIR/usage-aggregate.jsonl"

  # Iteration 1
  USAGE_MODEL="claude-sonnet-4-20250514"
  write_usage_event "$usage_file" 1 "planner" 5000 '{"input_tokens":1000,"output_tokens":500}' "claude" ""

  # Iteration 2
  write_usage_event "$usage_file" 2 "implementer" 8000 '{"input_tokens":2000,"output_tokens":1000}' "claude" ""

  # Iteration 3
  write_usage_event "$usage_file" 3 "tester" 3000 '{"input_tokens":500,"output_tokens":250}' "claude" ""

  # Aggregate totals using jq
  total_input=$(jq -s '[.[].usage.input_tokens] | add' "$usage_file")
  total_output=$(jq -s '[.[].usage.output_tokens] | add' "$usage_file")
  total_duration=$(jq -s '[.[].duration_ms] | add' "$usage_file")

  [ "$total_input" = "3500" ]
  [ "$total_output" = "1750" ]
  [ "$total_duration" = "16000" ]
}

# ============================================================================
# Session Entry Writing Tests
# ============================================================================

@test "usage: write_session_entry creates valid JSONL entry" {
  local sessions_file="$TEMP_DIR/sessions.jsonl"

  USAGE_SESSION_ID="session-abc"
  USAGE_MODEL="claude-sonnet-4-20250514"

  write_session_entry "$sessions_file" 1 "planner" "claude" "success" "2024-01-15T10:00:00Z" "2024-01-15T10:05:00Z"

  [ -f "$sessions_file" ]

  iteration=$(jq -r '.iteration' "$sessions_file")
  role=$(jq -r '.role' "$sessions_file")
  runner=$(jq -r '.runner' "$sessions_file")
  status=$(jq -r '.status' "$sessions_file")
  model=$(jq -r '.model' "$sessions_file")

  [ "$iteration" = "1" ]
  [ "$role" = "planner" ]
  [ "$runner" = "claude" ]
  [ "$status" = "success" ]
  [ "$model" = "claude-sonnet-4-20250514" ]
}

@test "usage: write_session_entry handles missing ended_at" {
  local sessions_file="$TEMP_DIR/sessions-running.jsonl"

  USAGE_SESSION_ID="session-123"
  write_session_entry "$sessions_file" 2 "implementer" "codex" "running" "2024-01-15T11:00:00Z" ""

  ended_at=$(jq -r '.ended_at' "$sessions_file")
  [ "$ended_at" = "null" ]
}

# ============================================================================
# Command Preparation Tests
# ============================================================================

@test "usage: prepare_tracked_command injects session-id for claude" {
  result=$(prepare_tracked_command "claude" "claude" "code" "--thinking" "extended")

  # Should have session-id injected after claude command
  echo "$result" | grep -q "^claude$"
  echo "$result" | grep -q "^--session-id$"
  echo "$result" | grep -q "^code$"

  # Check that a UUID-format session ID is in the output
  echo "$result" | grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' > /dev/null
}

@test "usage: prepare_tracked_command passes through codex unchanged" {
  local original_cmd=("codex" "run" "--prompt" "test")
  result=$(prepare_tracked_command "codex" "${original_cmd[@]}")

  # Should be unchanged
  echo "$result" | grep -q "^codex$"
  echo "$result" | grep -q "^run$"
  echo "$result" | grep -q "^--prompt$"
  echo "$result" | grep -q "^test$"
}

@test "usage: prepare_tracked_command handles unknown runner" {
  result=$(prepare_tracked_command "unknown" "some" "command")

  echo "$result" | grep -q "^some$"
  echo "$result" | grep -q "^command$"
}

# ============================================================================
# Integration Tests
# ============================================================================

@test "usage: track_usage start records start time" {
  track_usage "start" "" 1 "planner" "/repo" "claude" ""

  [ -n "$USAGE_START_TIME" ]
  [ "$USAGE_MODEL" = "" ]
}

@test "usage: track_usage end calculates duration" {
  local usage_file="$TEMP_DIR/usage-track.jsonl"

  # Start tracking
  USAGE_START_TIME=$(get_timestamp_ms)
  sleep 0.2

  # Create mock Claude session file
  local session_id="track-test-123"
  USAGE_SESSION_ID="$session_id"

  local project="test-project"
  local session_file="$MOCK_HOME/.claude/projects/-${project}/${session_id}.jsonl"
  mkdir -p "$(dirname "$session_file")"

  cat > "$session_file" << 'EOF'
{"type":"assistant","message":{"model":"claude-sonnet-4-20250514","usage":{"input_tokens":100,"output_tokens":50,"thinking_tokens":5}}}
EOF

  # End tracking
  track_usage "end" "$usage_file" 1 "planner" "$TEMP_DIR/$project" "claude" ""

  [ -f "$usage_file" ]

  # Verify duration is > 0
  duration=$(jq -r '.duration_ms' "$usage_file")
  [ "$duration" -gt 0 ]

  # Verify model was extracted
  model=$(jq -r '.model' "$usage_file")
  [ "$model" = "claude-sonnet-4-20250514" ]
}

@test "usage: track_usage end handles missing session file gracefully" {
  local usage_file="$TEMP_DIR/usage-no-session.jsonl"

  USAGE_START_TIME=$(get_timestamp_ms)
  USAGE_SESSION_ID="nonexistent-session"

  track_usage "end" "$usage_file" 1 "planner" "/repo" "claude" ""

  # Should still write event with zero tokens
  [ -f "$usage_file" ]

  input=$(jq -r '.usage.input_tokens' "$usage_file")
  [ "$input" = "0" ]
}

# ============================================================================
# Current Session JSON Tests
# ============================================================================

@test "usage: get_current_session_json returns valid JSON" {
  USAGE_SESSION_ID="test-session"
  USAGE_THREAD_ID="test-thread"
  CURRENT_RUNNER_TYPE="claude"

  result=$(get_current_session_json)

  session_id=$(echo "$result" | jq -r '.session_id')
  thread_id=$(echo "$result" | jq -r '.thread_id')
  runner=$(echo "$result" | jq -r '.runner')

  [ "$session_id" = "test-session" ]
  [ "$thread_id" = "test-thread" ]
  [ "$runner" = "claude" ]
}

@test "usage: get_current_session_json handles empty values" {
  USAGE_SESSION_ID=""
  USAGE_THREAD_ID=""
  CURRENT_RUNNER_TYPE=""

  result=$(get_current_session_json)

  session_id=$(echo "$result" | jq -r '.session_id')
  thread_id=$(echo "$result" | jq -r '.thread_id')
  runner=$(echo "$result" | jq -r '.runner')

  [ "$session_id" = "null" ]
  [ "$thread_id" = "null" ]
  [ "$runner" = "unknown" ]
}
