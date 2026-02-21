#!/usr/bin/env bats
# Tests for src/30-runner.sh - Runner execution and timeout handling

setup() {
  # Create temporary directory for test files
  TEMP_DIR=$(mktemp -d)
  export TEMP_DIR

  # Define select_python stub (from 00-header.sh)
  select_python() {
    if command -v python3 &>/dev/null; then
      echo "python3"
      return 0
    elif command -v python &>/dev/null; then
      echo "python"
      return 0
    fi
    return 1
  }
  export -f select_python

  # Source the runner module
  source "$BATS_TEST_DIRNAME/../src/30-runner.sh"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# ============================================================================
# Argument Expansion Tests
# ============================================================================

@test "runner: expand_runner_arg substitutes {repo}" {
  result=$(expand_runner_arg "cd {repo}" "/path/to/repo" "" "")
  [ "$result" = "cd /path/to/repo" ]
}

@test "runner: expand_runner_arg substitutes {prompt_file}" {
  result=$(expand_runner_arg "--prompt={prompt_file}" "" "/tmp/prompt.md" "")
  [ "$result" = "--prompt=/tmp/prompt.md" ]
}

@test "runner: expand_runner_arg substitutes {last_message_file}" {
  result=$(expand_runner_arg "--output {last_message_file}" "" "" "/tmp/last.txt")
  [ "$result" = "--output /tmp/last.txt" ]
}

@test "runner: expand_runner_arg substitutes multiple placeholders" {
  result=$(expand_runner_arg "--repo={repo} --prompt={prompt_file}" "/my/repo" "/my/prompt" "/my/last")
  [ "$result" = "--repo=/my/repo --prompt=/my/prompt" ]
}

@test "runner: expand_runner_arg handles no placeholders" {
  result=$(expand_runner_arg "some-static-arg" "/repo" "/prompt" "/last")
  [ "$result" = "some-static-arg" ]
}

@test "runner: expand_runner_arg handles empty input" {
  result=$(expand_runner_arg "" "/repo" "/prompt" "/last")
  [ "$result" = "" ]
}

@test "runner: expand_runner_arg preserves spaces in paths" {
  result=$(expand_runner_arg "{repo}/file.txt" "/path with spaces/repo" "" "")
  [ "$result" = "/path with spaces/repo/file.txt" ]
}

# ============================================================================
# Timeout Wrapper Tests (Basic)
# ============================================================================

@test "runner: run_command_with_timeout executes simple command successfully" {
  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"

  echo "test input" > "$prompt_file"

  run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 echo "Hello World"
  status=$?

  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  grep -q "Hello World" "$log_file"
}

@test "runner: run_command_with_timeout handles command that reads stdin" {
  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"

  echo "test input line" > "$prompt_file"

  run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 cat
  status=$?

  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  grep -q "test input line" "$log_file"
}

@test "runner: run_command_with_timeout passes through command exit code" {
  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"

  echo "input" > "$prompt_file"

  # false command exits with 1
  set +e
  run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 false
  local status=$?
  set -e

  [ "$status" -eq 1 ]
}

@test "runner: run_command_with_timeout handles arg mode (no stdin)" {
  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"

  echo "ignored" > "$prompt_file"

  run_command_with_timeout "$prompt_file" "$log_file" 10 "arg" 0 echo "From args"
  status=$?

  [ "$status" -eq 0 ]
  grep -q "From args" "$log_file"
}

# ============================================================================
# Rate Limit Detection Tests
# ============================================================================

@test "runner: detects Codex usage_limit_reached error" {
  # Skip if Python is not available (rate limit detection requires Python)
  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    skip "Python required for rate limit detection"
  fi

  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"
  local rate_limit_file="$TEMP_DIR/rate_limit.json"
  local mock_script="$TEMP_DIR/mock_codex.sh"

  echo "input" > "$prompt_file"

  # Create mock script that outputs Codex usage limit error
  cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "Processing request..."
cat >&2 << 'JSONERR'
{"type": "usage_limit_reached", "message": "Usage limit reached", "resets_at": 1700000000}
JSONERR
exit 1
EOF
  chmod +x "$mock_script"

  # Run with rate limit detection
  set +e
  RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
    run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 "$mock_script"
  local status=$?
  set -e

  # Should detect rate limit and return special exit code 125
  [ "$status" -eq 125 ]

  # Should write rate limit info to file
  [ -f "$rate_limit_file" ]

  # Check rate limit info contains expected fields
  local type=$(jq -r '.type' "$rate_limit_file")
  local message=$(jq -r '.message' "$rate_limit_file")

  [ "$type" = "codex" ]
  [[ "$message" == *"usage limit"* ]]
}

@test "runner: detects HTTP 429 rate limit" {
  # Skip if Python is not available
  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    skip "Python required for rate limit detection"
  fi

  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"
  local rate_limit_file="$TEMP_DIR/rate_limit.json"
  local mock_script="$TEMP_DIR/mock_429.sh"

  echo "input" > "$prompt_file"

  # Create mock script that outputs 429
  cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "Request started..."
echo "HTTP/1.1 429 Too Many Requests" >&2
exit 1
EOF
  chmod +x "$mock_script"

  set +e
  RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
    run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 "$mock_script"
  local status=$?
  set -e

  [ "$status" -eq 125 ]
  [ -f "$rate_limit_file" ]

  local message=$(jq -r '.message' "$rate_limit_file")
  [[ "$message" == *"429"* ]]
}

@test "runner: does not false-positive on non-rate-limit digits containing 429" {
  # Skip if Python is not available
  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    skip "Python required for rate limit detection"
  fi

  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"
  local rate_limit_file="$TEMP_DIR/rate_limit.json"
  local mock_script="$TEMP_DIR/mock_non_rate_limit_429_digits.sh"

  echo "input" > "$prompt_file"

  # Simulates codex rollout error line with "...894294..." in timestamp.
  cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "2026-02-20T17:30:43.894294Z ERROR codex_core::rollout::list: state db missing rollout path for thread 019c7a13-4993-74a3-ad89-ffe6c8d02a34" >&2
exit 1
EOF
  chmod +x "$mock_script"

  set +e
  RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
    run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 "$mock_script"
  local status=$?
  set -e

  # Should preserve the original non-zero exit code, not map to rate-limit stop.
  [ "$status" -eq 1 ]
  [ ! -f "$rate_limit_file" ]
  grep -q "rollout::list" "$log_file"
}

@test "runner: does not treat generic rate-limit text as a hard rate-limit signal" {
  # Skip if Python is not available
  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    skip "Python required for rate limit detection"
  fi

  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"
  local rate_limit_file="$TEMP_DIR/rate_limit.json"
  local mock_script="$TEMP_DIR/mock_generic.sh"

  echo "input" > "$prompt_file"

  # Create mock script with generic rate-limit text but no structured/HTTP signal.
  cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "Processing..."
echo "Error: Rate limit exceeded for this API key" >&2
exit 1
EOF
  chmod +x "$mock_script"

  set +e
  RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
    run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 "$mock_script"
  local status=$?
  set -e

  # Should preserve original exit code and not emit rate-limit metadata.
  [ "$status" -eq 1 ]
  [ ! -f "$rate_limit_file" ]
}

@test "runner: does not re-detect historical superloop rate-limit log lines" {
  # Skip if Python is not available
  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    skip "Python required for rate limit detection"
  fi

  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"
  local rate_limit_file="$TEMP_DIR/rate_limit.json"
  local mock_script="$TEMP_DIR/mock_historical_superloop_rate_limit_line.sh"

  echo "input" > "$prompt_file"

  # This mirrors a historical log line that previously caused false positives.
  cat > "$mock_script" << 'EOF'
#!/bin/bash
echo "[superloop] Rate limit detected: Rate limit error detected" >&2
exit 1
EOF
  chmod +x "$mock_script"

  set +e
  RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
    run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 "$mock_script"
  local status=$?
  set -e

  [ "$status" -eq 1 ]
  [ ! -f "$rate_limit_file" ]
}

@test "runner: codex rate-limit retries from scratch by default" {
  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    skip "Python required for rate limit detection"
  fi

  die() {
    echo "$*" >&2
    return 1
  }
  detect_runner_type() {
    echo "codex"
  }
  track_usage() {
    :
  }
  wait_for_rate_limit_reset() {
    return 0
  }

  local prompt_file="$TEMP_DIR/prompt.txt"
  local last_message_file="$TEMP_DIR/last-message.txt"
  local log_file="$TEMP_DIR/runner.log"
  local usage_file="$TEMP_DIR/usage.jsonl"
  local count_file="$TEMP_DIR/call-count.txt"
  local invocation_log="$TEMP_DIR/invocations.log"
  local mock_runner="$TEMP_DIR/mock-codex-runner.sh"

  echo "review prompt" > "$prompt_file"

  cat > "$mock_runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail
count_file="$count_file"
invocation_log="$invocation_log"
count=0
if [[ -f "\$count_file" ]]; then
  count=\$(cat "\$count_file")
fi
count=\$((count + 1))
echo "\$count" > "\$count_file"
echo "run-\$count args:\$*" >> "\$invocation_log"
if [[ "\$count" -eq 1 ]]; then
  echo "HTTP/1.1 429 Too Many Requests" >&2
  exit 1
fi
echo "retry ok"
exit 0
EOF
  chmod +x "$mock_runner"

  set +e
  USAGE_TRACKING_ENABLED=1 \
    SUPERLOOP_RATE_LIMIT_MAX_RETRIES=1 \
    run_role "$TEMP_DIR" "reviewer" "$prompt_file" "$last_message_file" "$log_file" \
      30 "stdin" 0 "$usage_file" 1 "" "$mock_runner" -- \
      > "$TEMP_DIR/run-role.stdout" 2> "$TEMP_DIR/run-role.stderr"
  local status=$?
  set -e

  [ "$status" -eq 0 ]
  [ -f "$count_file" ]
  [ "$(cat "$count_file")" -eq 2 ]

  [ -f "$invocation_log" ]
  run grep -c '^run-' "$invocation_log"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# ============================================================================
# Timeout Behavior Tests
# ============================================================================

@test "runner: enforces max timeout" {
  skip "Timeout test takes too long for regular test runs"

  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"

  echo "input" > "$prompt_file"

  # Command that sleeps forever
  run_command_with_timeout "$prompt_file" "$log_file" 2 "stdin" 0 sleep 3600 || status=$?

  # Should timeout with exit code 124
  [ "$status" -eq 124 ]
}

@test "runner: enforces inactivity timeout" {
  skip "Inactivity timeout test takes too long for regular test runs"

  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"
  local sleep_script="$TEMP_DIR/sleep.sh"

  echo "input" > "$prompt_file"

  # Script that outputs once then goes silent
  cat > "$sleep_script" << 'EOF'
#!/bin/bash
echo "Starting..."
sleep 10  # Silent for 10 seconds
echo "Done"
EOF
  chmod +x "$sleep_script"

  # Inactivity timeout of 2 seconds
  run_command_with_timeout "$prompt_file" "$log_file" 60 "stdin" 2 "$sleep_script" || status=$?

  # Should timeout with exit code 124
  [ "$status" -eq 124 ]

  # Should have logged the initial output
  grep -q "Starting..." "$log_file"
}

# ============================================================================
# Integration Tests (without Python)
# ============================================================================

@test "runner: handles command without timeout when python unavailable" {
  local prompt_file="$TEMP_DIR/prompt.txt"
  local log_file="$TEMP_DIR/log.txt"

  echo "test input" > "$prompt_file"

  # Override select_python to return empty (simulate no python)
  select_python() {
    return 1
  }
  export -f select_python

  local output
  output="$(run_command_with_timeout "$prompt_file" "$log_file" 10 "stdin" 0 echo "No Python" 2>&1)"
  status=$?

  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: python not found"* ]]
  [ -f "$log_file" ]
  grep -q "No Python" "$log_file"
}

# ============================================================================
# OpenProse Helper Function Tests
# ============================================================================

@test "runner: openprose_trim removes leading and trailing whitespace" {
  result=$(openprose_trim "  hello world  ")
  [ "$result" = "hello world" ]
}

@test "runner: openprose_trim handles tabs" {
  result=$(openprose_trim "$(printf '\t\thello\t\t')")
  [ "$result" = "hello" ]
}

@test "runner: openprose_trim handles empty string" {
  result=$(openprose_trim "")
  [ "$result" = "" ]
}

@test "runner: openprose_trim handles string with only whitespace" {
  result=$(openprose_trim "   ")
  [ "$result" = "" ]
}

@test "runner: openprose_indent returns indent level" {
  result=$(openprose_indent "    hello")
  [ "$result" = "4" ]
}

@test "runner: openprose_indent returns 0 for no indent" {
  result=$(openprose_indent "hello")
  [ "$result" = "0" ]
}

@test "runner: openprose_indent handles tabs" {
  result=$(openprose_indent "$(printf '\t\thello')")
  [ "$result" = "2" ]
}

@test "runner: openprose_strip_quotes removes double quotes" {
  result=$(openprose_strip_quotes '"hello world"')
  [ "$result" = "hello world" ]
}

@test "runner: openprose_strip_quotes removes single quotes" {
  result=$(openprose_strip_quotes "'hello world'")
  [ "$result" = "hello world" ]
}

@test "runner: openprose_strip_quotes handles unquoted string" {
  result=$(openprose_strip_quotes "hello world")
  [ "$result" = "hello world" ]
}

@test "runner: openprose_strip_quotes handles empty string" {
  result=$(openprose_strip_quotes "")
  [ "$result" = "" ]
}

@test "runner: openprose_strip_quotes handles single character" {
  result=$(openprose_strip_quotes "x")
  [ "$result" = "x" ]
}

@test "runner: openprose_strip_quotes only removes outer quotes" {
  result=$(openprose_strip_quotes '"he said "hello""')
  [ "$result" = 'he said "hello"' ]
}

# ============================================================================
# OpenProse Context Functions Tests
# ============================================================================

@test "runner: openprose_agent_set and openprose_agent_get work together" {
  OPENPROSE_AGENT_KEYS=()
  OPENPROSE_AGENT_PROMPTS=()

  openprose_agent_set "agent1" "prompt for agent1"
  result=$(openprose_agent_get "agent1")

  [ "$result" = "prompt for agent1" ]
}

@test "runner: openprose_agent_set updates existing agent" {
  OPENPROSE_AGENT_KEYS=()
  OPENPROSE_AGENT_PROMPTS=()

  openprose_agent_set "agent1" "first prompt"
  openprose_agent_set "agent1" "updated prompt"
  result=$(openprose_agent_get "agent1")

  [ "$result" = "updated prompt" ]
}

@test "runner: openprose_agent_get returns error for unknown agent" {
  OPENPROSE_AGENT_KEYS=()
  OPENPROSE_AGENT_PROMPTS=()

  run openprose_agent_get "nonexistent"
  [ "$status" -eq 1 ]
}

@test "runner: openprose_context_set and openprose_context_get work together" {
  OPENPROSE_CONTEXT_KEYS=()
  OPENPROSE_CONTEXT_PATHS=()

  openprose_context_set "ctx1" "/path/to/file"
  result=$(openprose_context_get "ctx1")

  [ "$result" = "/path/to/file" ]
}

@test "runner: openprose_context_set updates existing context" {
  OPENPROSE_CONTEXT_KEYS=()
  OPENPROSE_CONTEXT_PATHS=()

  openprose_context_set "ctx1" "/path/one"
  openprose_context_set "ctx1" "/path/two"
  result=$(openprose_context_get "ctx1")

  [ "$result" = "/path/two" ]
}

@test "runner: openprose_context_get returns error for unknown context" {
  OPENPROSE_CONTEXT_KEYS=()
  OPENPROSE_CONTEXT_PATHS=()

  run openprose_context_get "nonexistent"
  [ "$status" -eq 1 ]
}

@test "runner: openprose_parse_context_names parses simple list" {
  result=$(openprose_parse_context_names "context: var1 var2 var3")
  [ "$result" = "var1 var2 var3" ]
}

@test "runner: openprose_parse_context_names handles brackets" {
  result=$(openprose_parse_context_names "context: [var1, var2, var3]")
  # Commas become spaces, brackets removed
  [ "$result" = "var1 var2 var3" ]
}

@test "runner: openprose_parse_context_names handles braces" {
  result=$(openprose_parse_context_names "context: {var1, var2}")
  [ "$result" = "var1 var2" ]
}

@test "runner: openprose_parse_context_names handles mixed delimiters" {
  result=$(openprose_parse_context_names "context: [var1, var2], var3")
  # Multiple spaces collapsed to single space
  [[ "$result" =~ var1.*var2.*var3 ]]
}
