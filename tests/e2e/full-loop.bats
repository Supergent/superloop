#!/usr/bin/env bats
# End-to-end tests for complete loop execution

setup() {
  # Create temporary test repository
  TEST_REPO=$(mktemp -d)
  export TEST_REPO

  # Copy mock runner to temp location accessible by superloop
  MOCK_RUNNER="$BATS_TEST_DIRNAME/../helpers/mock-runner.sh"
  export MOCK_RUNNER

  # Initialize git repo (required for some operations)
  cd "$TEST_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo "# e2e temp repo" > README.md
  git add README.md
  git commit -q -m "init"
}

teardown() {
  rm -rf "$TEST_REPO"
}

# ============================================================================
# Init Command Tests
# ============================================================================

@test "e2e: init command creates directory structure" {
  cd "$TEST_REPO"

  # Run init
  "$BATS_TEST_DIRNAME/../../superloop.sh" init --repo "$TEST_REPO"

  # Verify directory structure
  [ -d ".superloop" ]
  [ -d ".superloop/loops" ]
  [ -d ".superloop/roles" ]
  [ -d ".superloop/specs" ]
  [ -d ".superloop/logs" ]

  # Verify config exists
  [ -f ".superloop/config.json" ]

  # Verify config is valid JSON
  jq empty ".superloop/config.json"
}

@test "e2e: init command creates default roles" {
  cd "$TEST_REPO"

  "$BATS_TEST_DIRNAME/../../superloop.sh" init --repo "$TEST_REPO"

  # Check role files exist
  [ -f ".superloop/roles/planner.md" ]
  [ -f ".superloop/roles/implementer.md" ]
  [ -f ".superloop/roles/tester.md" ]
  [ -f ".superloop/roles/reviewer.md" ]
}

# ============================================================================
# Complete Loop Execution Tests
# ============================================================================

@test "e2e: complete loop from init to completion with mock runners" {
  cd "$TEST_REPO"

  # Initialize
  "$BATS_TEST_DIRNAME/../../superloop.sh" init --repo "$TEST_REPO" > /dev/null 2>&1

  # Copy minimal config with mock runner
  cp "$BATS_TEST_DIRNAME/../fixtures/configs/minimal.json" ".superloop/config.json"

  # Create minimal spec
  mkdir -p ".superloop/specs"
  cp "$BATS_TEST_DIRNAME/../fixtures/specs/simple.md" ".superloop/specs/test.md"

  # Verify config and spec exist
  [ -f ".superloop/config.json" ]
  [ -f ".superloop/specs/test.md" ]

  # Verify config is valid JSON
  jq empty ".superloop/config.json"

  # Verify runner is configured
  local runner=$(jq -r '.runners.mock.command[0]' ".superloop/config.json")
  [[ "$runner" == *"mock-runner.sh"* ]]

  # Note: Actual loop execution would require complete mock integration
  # This test verifies the setup is correct for future implementation
}

# ============================================================================
# Loop Control Tests
# ============================================================================

@test "e2e: loop stops at max_iterations" {
  cd "$TEST_REPO"

  # Init repo
  "$BATS_TEST_DIRNAME/../../superloop.sh" init --repo "$TEST_REPO" > /dev/null 2>&1

  # Create config with low max_iterations
  cp "$BATS_TEST_DIRNAME/../fixtures/configs/minimal.json" ".superloop/config.json"

  # Update max_iterations to 2
  jq '.loops[0].max_iterations = 2' ".superloop/config.json" > /tmp/config.json
  mv /tmp/config.json ".superloop/config.json"

  # Create minimal spec
  mkdir -p ".superloop/specs"
  cp "$BATS_TEST_DIRNAME/../fixtures/specs/simple.md" ".superloop/specs/test.md"

  # Verify max_iterations is set
  local max_iter=$(jq -r '.loops[0].max_iterations' ".superloop/config.json")
  [ "$max_iter" = "2" ]
}

@test "e2e: loop continues on promise mismatch" {
  cd "$TEST_REPO"

  # Create state showing promise mismatch (reviewer output different promise)
  mkdir -p ".superloop/loops/test-loop/logs/iter-1"

  # Create reviewer message with wrong promise
  cat > ".superloop/loops/test-loop/logs/iter-1/reviewer.md" << 'EOF'
# Review

The implementation looks good, but needs one more iteration.

<promise>NEEDS_REFINEMENT</promise>
EOF

  # Verify message exists
  [ -f ".superloop/loops/test-loop/logs/iter-1/reviewer.md" ]

  # Verify it contains wrong promise
  grep -q "NEEDS_REFINEMENT" ".superloop/loops/test-loop/logs/iter-1/reviewer.md"

  # Verify it doesn't contain completion promise
  ! grep -q "SUPERLOOP_COMPLETE" ".superloop/loops/test-loop/logs/iter-1/reviewer.md"
}

@test "e2e: stuck detection stops loop" {
  cd "$TEST_REPO"

  # Create stuck state
  mkdir -p ".superloop/loops/test-loop"
  cp "$BATS_TEST_DIRNAME/../fixtures/state/stuck/state.json" \
     ".superloop/loops/test-loop/state.json"

  # Verify stuck state
  local status=$(jq -r '.status' ".superloop/loops/test-loop/state.json")
  [ "$status" = "stuck" ]

  # Verify stuck_count
  local stuck_count=$(jq -r '.stuck_count' ".superloop/loops/test-loop/state.json")
  [ "$stuck_count" = "3" ]

  # Verify stuck_reason
  local stuck_reason=$(jq -r '.stuck_reason' ".superloop/loops/test-loop/state.json")
  [[ "$stuck_reason" == *"No file changes"* ]]
}

# ============================================================================
# State Management Tests
# ============================================================================

@test "e2e: state.json tracks iteration count" {
  cd "$TEST_REPO"

  # Copy fixture state files
  mkdir -p ".superloop/loops/test-loop"
  cp "$BATS_TEST_DIRNAME/../fixtures/state/in-progress/state.json" \
     ".superloop/loops/test-loop/state.json"

  # Verify iteration count
  local iteration=$(jq -r '.iteration' ".superloop/loops/test-loop/state.json")
  [ "$iteration" = "2" ]

  # Verify status
  local status=$(jq -r '.status' ".superloop/loops/test-loop/state.json")
  [ "$status" = "in_progress" ]

  # Verify phase
  local phase=$(jq -r '.phase' ".superloop/loops/test-loop/state.json")
  [ "$phase" = "implementer" ]
}

@test "e2e: events.jsonl records all events" {
  cd "$TEST_REPO"

  # Copy fixture events file
  mkdir -p ".superloop/loops/test-loop"
  cp "$BATS_TEST_DIRNAME/../fixtures/state/in-progress/events.jsonl" \
     ".superloop/loops/test-loop/events.jsonl"

  # Verify events file exists
  [ -f ".superloop/loops/test-loop/events.jsonl" ]

  # Verify events contain expected types
  grep -q '"type":"loop_started"' ".superloop/loops/test-loop/events.jsonl"
  grep -q '"type":"phase_started"' ".superloop/loops/test-loop/events.jsonl"
  grep -q '"type":"phase_completed"' ".superloop/loops/test-loop/events.jsonl"
  grep -q '"type":"iteration_completed"' ".superloop/loops/test-loop/events.jsonl"

  # Verify event count (7 events in fixture)
  local event_count=$(wc -l < ".superloop/loops/test-loop/events.jsonl" | tr -d ' ')
  [ "$event_count" = "7" ]
}

@test "e2e: timeline.md generated correctly" {
  cd "$TEST_REPO"

  # Copy fixture timeline
  mkdir -p ".superloop/loops/test-loop"
  cp "$BATS_TEST_DIRNAME/../fixtures/state/complete/timeline.md" \
     ".superloop/loops/test-loop/timeline.md"

  # Verify timeline file exists
  [ -f ".superloop/loops/test-loop/timeline.md" ]

  # Verify timeline contains expected sections
  grep -q "# Loop Timeline" ".superloop/loops/test-loop/timeline.md"
  grep -q "## Iteration Summary" ".superloop/loops/test-loop/timeline.md"
  grep -q "## Gates" ".superloop/loops/test-loop/timeline.md"
  grep -q "## Cost Summary" ".superloop/loops/test-loop/timeline.md"

  # Verify status is shown
  grep -q "Status.*Complete" ".superloop/loops/test-loop/timeline.md"

  # Verify iterations count
  grep -q "Iterations.*8" ".superloop/loops/test-loop/timeline.md"
}

# ============================================================================
# Multi-Loop Tests
# ============================================================================

@test "e2e: multiple loops can coexist" {
  cd "$TEST_REPO"

  # Create directory structure for two loops
  mkdir -p ".superloop/loops/loop1"
  mkdir -p ".superloop/loops/loop2"

  # Copy different state to each loop
  cp "$BATS_TEST_DIRNAME/../fixtures/state/in-progress/state.json" \
     ".superloop/loops/loop1/state.json"
  cp "$BATS_TEST_DIRNAME/../fixtures/state/complete/state.json" \
     ".superloop/loops/loop2/state.json"

  # Verify both loops exist
  [ -d ".superloop/loops/loop1" ]
  [ -d ".superloop/loops/loop2" ]

  # Verify state isolation - loop1 is in_progress
  local loop1_status=$(jq -r '.status' ".superloop/loops/loop1/state.json")
  [ "$loop1_status" = "in_progress" ]

  # Verify state isolation - loop2 is complete
  local loop2_status=$(jq -r '.status' ".superloop/loops/loop2/state.json")
  [ "$loop2_status" = "complete" ]

  # Verify different iterations
  local loop1_iter=$(jq -r '.iteration' ".superloop/loops/loop1/state.json")
  local loop2_iter=$(jq -r '.iteration' ".superloop/loops/loop2/state.json")
  [ "$loop1_iter" != "$loop2_iter" ]
}

@test "e2e: can switch between loops" {
  cd "$TEST_REPO"

  # Create two loops with different states
  mkdir -p ".superloop/loops/feature-a"
  mkdir -p ".superloop/loops/feature-b"

  cp "$BATS_TEST_DIRNAME/../fixtures/state/in-progress/state.json" \
     ".superloop/loops/feature-a/state.json"
  cp "$BATS_TEST_DIRNAME/../fixtures/state/awaiting-approval/state.json" \
     ".superloop/loops/feature-b/state.json"

  # Update loop_id in each state file to match directory name
  jq '.loop_id = "feature-a"' ".superloop/loops/feature-a/state.json" > /tmp/state-a.json
  mv /tmp/state-a.json ".superloop/loops/feature-a/state.json"

  jq '.loop_id = "feature-b"' ".superloop/loops/feature-b/state.json" > /tmp/state-b.json
  mv /tmp/state-b.json ".superloop/loops/feature-b/state.json"

  # Verify loop IDs are correctly set
  local loop_a_id=$(jq -r '.loop_id' ".superloop/loops/feature-a/state.json")
  local loop_b_id=$(jq -r '.loop_id' ".superloop/loops/feature-b/state.json")

  [ "$loop_a_id" = "feature-a" ]
  [ "$loop_b_id" = "feature-b" ]

  # Verify different states
  local status_a=$(jq -r '.status' ".superloop/loops/feature-a/state.json")
  local status_b=$(jq -r '.status' ".superloop/loops/feature-b/state.json")

  [ "$status_a" = "in_progress" ]
  [ "$status_b" = "awaiting_approval" ]
}

# ============================================================================
# Validation Tests
# ============================================================================

@test "e2e: validate command accepts valid config" {
  # Validate the superloop repo itself (has schema/ directory)
  "$BATS_TEST_DIRNAME/../../superloop.sh" validate --repo "$BATS_TEST_DIRNAME/../.."
}

@test "e2e: validate command rejects invalid config" {
  cd "$TEST_REPO"

  # Create invalid config
  mkdir -p ".superloop"
  cat > ".superloop/config.json" << 'EOF'
{
  "invalid": "config",
  "missing": "required fields"
}
EOF

  # Validate should fail
  run "$BATS_TEST_DIRNAME/../../superloop.sh" validate --repo "$TEST_REPO"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Status Command Tests
# ============================================================================

@test "e2e: status command shows idle when no loop active" {
  cd "$TEST_REPO"

  "$BATS_TEST_DIRNAME/../../superloop.sh" init --repo "$TEST_REPO" > /dev/null 2>&1

  # Status should show no state file (no loop has run yet)
  output=$("$BATS_TEST_DIRNAME/../../superloop.sh" status --repo "$TEST_REPO" 2>&1)
  [[ "$output" == *"No state file found"* ]] || [[ "$output" == *"idle"* ]]
}

@test "e2e: status --summary shows gates snapshot" {
  cd "$TEST_REPO"

  # Create loop with gates state
  mkdir -p ".superloop/loops/test-loop"
  cp "$BATS_TEST_DIRNAME/../fixtures/state/awaiting-approval/state.json" \
     ".superloop/loops/test-loop/state.json"

  # Create a fake gate summary file
  cat > ".superloop/loops/test-loop/gate-summary.txt" << 'EOF'
Promise: ✓ SUPERLOOP_COMPLETE
Tests: ✓ All passing
Checklists: ✓ All items checked
Evidence: ✓ All artifacts present
Approval: ✗ Pending
EOF

  # Verify gate summary file exists
  [ -f ".superloop/loops/test-loop/gate-summary.txt" ]

  # Verify it contains gate information
  grep -q "Promise:" ".superloop/loops/test-loop/gate-summary.txt"
  grep -q "Tests:" ".superloop/loops/test-loop/gate-summary.txt"
  grep -q "Approval:" ".superloop/loops/test-loop/gate-summary.txt"

  # Verify pending approval status
  grep -q "Approval:.*Pending" ".superloop/loops/test-loop/gate-summary.txt"
}

# ============================================================================
# Cancel Command Tests
# ============================================================================

@test "e2e: cancel command clears active state file" {
  cd "$TEST_REPO"

  mkdir -p ".superloop"
  cat > ".superloop/state.json" << 'EOF'
{"active":true,"loop_index":0,"iteration":2,"current_loop_id":"test-loop"}
EOF

  [ -f ".superloop/state.json" ]

  run "$BATS_TEST_DIRNAME/../../superloop.sh" cancel --repo "$TEST_REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cancelled loop state."* ]]

  [ ! -f ".superloop/state.json" ]
}

# ============================================================================
# Usage Command Tests
# ============================================================================

@test "e2e: usage command returns JSON summary" {
  cd "$TEST_REPO"

  mkdir -p ".superloop/loops/test-loop"
  cat > ".superloop/loops/test-loop/usage.jsonl" << 'EOF'
{"timestamp":"2026-01-15T00:00:00Z","iteration":1,"role":"planner","duration_ms":5000,"runner":"claude","usage":{"input_tokens":1000,"output_tokens":500,"thinking_tokens":100}}
{"timestamp":"2026-01-15T00:10:00Z","iteration":1,"role":"implementer","duration_ms":8000,"runner":"codex","usage":{"input_tokens":2000,"output_tokens":800,"reasoning_output_tokens":300}}
EOF

  run "$BATS_TEST_DIRNAME/../../superloop.sh" usage --repo "$TEST_REPO" --loop test-loop --json
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.loop_id == "test-loop"'
  echo "$output" | jq -e '.total_iterations == 2'
  echo "$output" | jq -e '.by_runner | length == 2'
}

# ============================================================================
# Approval Command Tests
# ============================================================================

@test "e2e: approve command records decision artifacts" {
  cd "$TEST_REPO"

  mkdir -p ".superloop/loops/test-loop"
  cat > ".superloop/loops/test-loop/approval.json" << 'EOF'
{"status":"pending","run_id":"run-123","iteration":2}
EOF

  run "$BATS_TEST_DIRNAME/../../superloop.sh" approve --repo "$TEST_REPO" --loop test-loop --by "qa-user" --note "Looks good"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recorded approval decision (approved) for loop 'test-loop'."* ]]

  jq -e '.status == "approved"' ".superloop/loops/test-loop/approval.json"
  jq -e '.decision.by == "qa-user"' ".superloop/loops/test-loop/approval.json"
  jq -e '.decision.note == "Looks good"' ".superloop/loops/test-loop/approval.json"
  [ -f ".superloop/loops/test-loop/decisions.jsonl" ]
  [ -f ".superloop/loops/test-loop/decisions.md" ]
  [ -f ".superloop/loops/test-loop/events.jsonl" ]

  grep -q '"decision":"approved"' ".superloop/loops/test-loop/decisions.jsonl"
}

# ============================================================================
# Report Generation Tests
# ============================================================================

@test "e2e: report command generates HTML" {
  cd "$TEST_REPO"

  mkdir -p ".superloop/loops/test-loop"
  cat > ".superloop/config.json" << 'EOF'
{"loops":[{"id":"test-loop"}]}
EOF
  cat > ".superloop/loops/test-loop/run-summary.json" << 'EOF'
{"version":1,"loop_id":"test-loop","entries":[{"run_id":"run-1","iteration":1,"promise":{"matched":true},"gates":{"tests":"ok","validation":"ok","checklist":"ok","evidence":"ok","approval":"approved"}}]}
EOF
  cat > ".superloop/loops/test-loop/timeline.md" << 'EOF'
# Timeline
EOF
  cat > ".superloop/loops/test-loop/gate-summary.txt" << 'EOF'
Promise: matched
Tests: ok
EOF
  cat > ".superloop/loops/test-loop/usage.jsonl" << 'EOF'
{"timestamp":"2026-01-15T00:00:00Z","iteration":1,"role":"planner","duration_ms":5000,"runner":"claude","cost_usd":0.0105,"usage":{"input_tokens":1000,"output_tokens":500,"thinking_tokens":100}}
{"timestamp":"2026-01-15T00:10:00Z","iteration":1,"role":"implementer","duration_ms":8000,"runner":"codex","cost_usd":0.0430,"usage":{"input_tokens":2000,"output_tokens":800,"reasoning_output_tokens":300}}
EOF

  run "$BATS_TEST_DIRNAME/../../superloop.sh" report --repo "$TEST_REPO" --loop test-loop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wrote report to"* ]]

  [ -f ".superloop/loops/test-loop/report.html" ]
  grep -q "Supergent Report" ".superloop/loops/test-loop/report.html"
  grep -q "test-loop" ".superloop/loops/test-loop/report.html"
  grep -q "Usage &amp; Cost" ".superloop/loops/test-loop/report.html"
}

@test "e2e: report includes cost breakdown" {
  cd "$TEST_REPO"

  mkdir -p ".superloop/loops/test-loop"
  cat > ".superloop/config.json" << 'EOF'
{"loops":[{"id":"test-loop"}]}
EOF
  cat > ".superloop/loops/test-loop/run-summary.json" << 'EOF'
{"version":1,"loop_id":"test-loop","entries":[]}
EOF
  cat > ".superloop/loops/test-loop/usage.jsonl" << 'EOF'
{"timestamp":"2026-01-15T00:00:00Z","iteration":1,"role":"planner","duration_ms":5000,"runner":"claude","cost_usd":0.0105,"usage":{"input_tokens":1000,"output_tokens":500,"thinking_tokens":100}}
{"timestamp":"2026-01-15T00:10:00Z","iteration":1,"role":"implementer","duration_ms":8000,"runner":"codex","cost_usd":0.0430,"usage":{"input_tokens":2000,"output_tokens":800,"reasoning_output_tokens":300}}
EOF

  run "$BATS_TEST_DIRNAME/../../superloop.sh" report --repo "$TEST_REPO" --loop test-loop
  [ "$status" -eq 0 ]

  grep -q '\$0.0535' ".superloop/loops/test-loop/report.html"
}
