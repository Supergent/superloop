#!/usr/bin/env bats
# Tests for src/40-gates.sh - Gate management and approval system
# Target coverage: 90%+

# Load the module under test
load_module() {
  # Source header first for common functions
  source "$PROJECT_ROOT/src/00-header.sh"
  # Source the gates module
  source "$PROJECT_ROOT/src/40-gates.sh"
}

setup() {
  # Get project root
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"

  # Create temp directory for tests
  TEMP_DIR="$(mktemp -d)"
  LOOP_DIR="$TEMP_DIR/loop1"
  mkdir -p "$LOOP_DIR"

  # Load the module
  load_module
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# =============================================================================
# extract_promise
# =============================================================================

@test "gates: extract_promise finds promise tag in message" {
  local message_file="$TEMP_DIR/message.txt"

  cat > "$message_file" << 'EOF'
# Implementation Complete

I have implemented the feature.

<promise>SUPERLOOP_COMPLETE</promise>

Ready for review.
EOF

  result=$(extract_promise "$message_file")
  [ "$result" = "SUPERLOOP_COMPLETE" ]
}

@test "gates: extract_promise returns empty for no promise tag" {
  local message_file="$TEMP_DIR/message.txt"

  echo "No promise here" > "$message_file"

  result=$(extract_promise "$message_file")
  [ "$result" = "" ]
}

@test "gates: extract_promise returns empty for missing file" {
  result=$(extract_promise "$TEMP_DIR/nonexistent.txt")
  [ "$result" = "" ]
}

@test "gates: extract_promise handles promise with whitespace" {
  local message_file="$TEMP_DIR/message.txt"

  cat > "$message_file" << 'EOF'
<promise>
  FEATURE_COMPLETE
</promise>
EOF

  result=$(extract_promise "$message_file")
  [ "$result" = "FEATURE_COMPLETE" ]
}

@test "gates: extract_promise handles promise with newlines" {
  local message_file="$TEMP_DIR/message.txt"

  cat > "$message_file" << 'EOF'
<promise>
TESTS_PASS
CHECKLIST_COMPLETE
</promise>
EOF

  result=$(extract_promise "$message_file")
  # Should normalize whitespace to single spaces
  [[ "$result" =~ "TESTS_PASS" ]]
  [[ "$result" =~ "CHECKLIST_COMPLETE" ]]
}

@test "gates: extract_promise handles multiple promise tags (uses first)" {
  local message_file="$TEMP_DIR/message.txt"

  cat > "$message_file" << 'EOF'
<promise>FIRST_PROMISE</promise>
Some text
<promise>SECOND_PROMISE</promise>
EOF

  result=$(extract_promise "$message_file")
  [ "$result" = "FIRST_PROMISE" ]
}

# =============================================================================
# snapshot_file and restore_if_unchanged
# =============================================================================

@test "gates: snapshot_file copies existing file" {
  local file="$TEMP_DIR/test.txt"
  local snapshot="$TEMP_DIR/test.txt.snap"

  echo "original content" > "$file"

  snapshot_file "$file" "$snapshot"

  [ -f "$snapshot" ]
  [ "$(cat "$snapshot")" = "original content" ]
}

@test "gates: snapshot_file creates empty snapshot for missing file" {
  local file="$TEMP_DIR/missing.txt"
  local snapshot="$TEMP_DIR/missing.txt.snap"

  snapshot_file "$file" "$snapshot"

  [ -f "$snapshot" ]
  [ ! -s "$snapshot" ]  # File exists but is empty
}

@test "gates: restore_if_unchanged restores unchanged file" {
  local file="$TEMP_DIR/test.txt"
  local snapshot="$TEMP_DIR/test.txt.snap"

  echo "content" > "$file"
  snapshot_file "$file" "$snapshot"

  # File unchanged
  restore_if_unchanged "$file" "$snapshot"

  [ -f "$file" ]
  [ "$(cat "$file")" = "content" ]
  [ ! -f "$snapshot" ]  # Snapshot should be removed
}

@test "gates: restore_if_unchanged keeps changed file" {
  local file="$TEMP_DIR/test.txt"
  local snapshot="$TEMP_DIR/test.txt.snap"

  echo "original" > "$file"
  snapshot_file "$file" "$snapshot"

  echo "changed" > "$file"

  restore_if_unchanged "$file" "$snapshot"

  [ -f "$file" ]
  [ "$(cat "$file")" = "changed" ]
  [ ! -f "$snapshot" ]  # Snapshot should be removed
}

@test "gates: restore_if_unchanged restores missing file from snapshot" {
  local file="$TEMP_DIR/test.txt"
  local snapshot="$TEMP_DIR/test.txt.snap"

  echo "content" > "$snapshot"

  restore_if_unchanged "$file" "$snapshot"

  [ -f "$file" ]
  [ "$(cat "$file")" = "content" ]
  [ ! -f "$snapshot" ]  # Snapshot moved to file
}

@test "gates: restore_if_unchanged handles missing snapshot" {
  local file="$TEMP_DIR/test.txt"
  local snapshot="$TEMP_DIR/test.txt.snap"

  echo "content" > "$file"

  restore_if_unchanged "$file" "$snapshot"

  [ -f "$file" ]
  [ "$(cat "$file")" = "content" ]
}

@test "gates: restore_if_unchanged handles empty snapshot path" {
  local file="$TEMP_DIR/test.txt"

  echo "content" > "$file"

  restore_if_unchanged "$file" ""

  [ -f "$file" ]
  [ "$(cat "$file")" = "content" ]
}

# =============================================================================
# write_gate_summary
# =============================================================================

@test "gates: write_gate_summary writes correct format" {
  local summary_file="$TEMP_DIR/gate_summary.txt"

  write_gate_summary "$summary_file" "true" "passed" "passed" "passed" "passed" "passed" "ok" "false" "approved"

  [ -f "$summary_file" ]
  content=$(cat "$summary_file")
  [[ "$content" =~ "promise=true" ]]
  [[ "$content" =~ "tests=passed" ]]
  [[ "$content" =~ "validation=passed" ]]
  [[ "$content" =~ "prerequisites=passed" ]]
  [[ "$content" =~ "checklist=passed" ]]
  [[ "$content" =~ "evidence=passed" ]]
  [[ "$content" =~ "lifecycle=ok" ]]
  [[ "$content" =~ "stuck=false" ]]
  [[ "$content" =~ "approval=approved" ]]
}

@test "gates: write_gate_summary handles all gates failed" {
  local summary_file="$TEMP_DIR/gate_summary.txt"

  write_gate_summary "$summary_file" "false" "failed" "failed" "failed" "incomplete" "missing" "failed" "true" "pending"

  content=$(cat "$summary_file")
  [[ "$content" =~ "promise=false" ]]
  [[ "$content" =~ "tests=failed" ]]
  [[ "$content" =~ "validation=failed" ]]
  [[ "$content" =~ "prerequisites=failed" ]]
  [[ "$content" =~ "checklist=incomplete" ]]
  [[ "$content" =~ "evidence=missing" ]]
  [[ "$content" =~ "lifecycle=failed" ]]
  [[ "$content" =~ "stuck=true" ]]
  [[ "$content" =~ "approval=pending" ]]
}

@test "gates: write_gate_summary defaults approval to skipped" {
  local summary_file="$TEMP_DIR/gate_summary.txt"

  write_gate_summary "$summary_file" "true" "passed" "passed" "passed" "passed" "passed" "ok" "false"

  content=$(cat "$summary_file")
  [[ "$content" =~ "approval=skipped" ]]
}

# =============================================================================
# write_iteration_notes
# =============================================================================

@test "gates: write_iteration_notes creates notes file" {
  local notes_file="$TEMP_DIR/notes.txt"

  write_iteration_notes "$notes_file" "loop1" "5" "true" "passed" "passed" "passed" "complete" "always" "found" "ok" "2" "5" "approved"

  [ -f "$notes_file" ]
  content=$(cat "$notes_file")
  [[ "$content" =~ "Iteration: 5" ]]
  [[ "$content" =~ "Loop: loop1" ]]
  [[ "$content" =~ "Promise matched: true" ]]
  [[ "$content" =~ "Tests: passed (mode: always)" ]]
  [[ "$content" =~ "Validation: passed" ]]
  [[ "$content" =~ "Prerequisites: passed" ]]
  [[ "$content" =~ "Checklist: complete" ]]
  [[ "$content" =~ "Evidence: found" ]]
  [[ "$content" =~ "Lifecycle: ok" ]]
  [[ "$content" =~ "Approval: approved" ]]
  [[ "$content" =~ "Stuck streak: 2/5" ]]
  [[ "$content" =~ "Next steps:" ]]
}

@test "gates: write_iteration_notes handles skipped optional gates" {
  local notes_file="$TEMP_DIR/notes.txt"

  write_iteration_notes "$notes_file" "loop1" "1" "false" "passed" "" "" "complete" "onchange"

  content=$(cat "$notes_file")
  [[ "$content" =~ "Validation: skipped" ]]
  [[ "$content" =~ "Prerequisites: skipped" ]]
  [[ "$content" =~ "Evidence: skipped" ]]
  [[ "$content" =~ "Lifecycle: unknown" ]]
  [[ "$content" =~ "Approval: skipped" ]]
  [[ "$content" =~ "Stuck streak: 0/0" ]]
}

# =============================================================================
# write_reviewer_packet
# =============================================================================

@test "gates: write_reviewer_packet creates comprehensive packet" {
  local packet_file="$TEMP_DIR/reviewer_packet.md"
  local gate_summary="$TEMP_DIR/gate_summary.txt"
  local test_status="$TEMP_DIR/test_status.txt"
  local test_report="$TEMP_DIR/test_report.txt"
  local evidence_file="$TEMP_DIR/evidence.txt"
  local checklist_status="$TEMP_DIR/checklist_status.txt"
  local checklist_remaining="$TEMP_DIR/checklist_remaining.txt"
  local validation_status="$TEMP_DIR/validation_status.txt"
  local validation_results="$TEMP_DIR/validation_results.txt"

  echo "Gates: all passed" > "$gate_summary"
  echo "Tests: passed" > "$test_status"
  echo "Test report content" > "$test_report"
  echo "Evidence: found" > "$evidence_file"
  echo "Checklist: complete" > "$checklist_status"
  echo "No items remaining" > "$checklist_remaining"
  echo "Validation: passed" > "$validation_status"
  echo "All checks passed" > "$validation_results"

  write_reviewer_packet "$LOOP_DIR" "loop1" "3" "$gate_summary" "$test_status" \
    "$test_report" "$evidence_file" "$checklist_status" "$checklist_remaining" \
    "$validation_status" "$validation_results" "$packet_file"

  [ -f "$packet_file" ]
  content=$(cat "$packet_file")
  [[ "$content" =~ "# Reviewer Packet" ]]
  [[ "$content" =~ "Loop: loop1" ]]
  [[ "$content" =~ "Iteration: 3" ]]
  [[ "$content" =~ "## Gate Summary" ]]
  [[ "$content" =~ "Gates: all passed" ]]
  [[ "$content" =~ "## Test Status" ]]
  [[ "$content" =~ "Tests: passed" ]]
  [[ "$content" =~ "## Test Report" ]]
  [[ "$content" =~ "Test report content" ]]
  [[ "$content" =~ "## Evidence" ]]
  [[ "$content" =~ "Evidence: found" ]]
  [[ "$content" =~ "## Checklist Status" ]]
  [[ "$content" =~ "Checklist: complete" ]]
  [[ "$content" =~ "## Validation" ]]
  [[ "$content" =~ "Validation: passed" ]]
  [[ "$content" =~ "All checks passed" ]]
}

@test "gates: write_reviewer_packet handles missing files gracefully" {
  local packet_file="$TEMP_DIR/reviewer_packet.md"

  write_reviewer_packet "$LOOP_DIR" "loop1" "1" \
    "/nonexistent/gate_summary" "/nonexistent/test_status" \
    "/nonexistent/test_report" "/nonexistent/evidence" \
    "/nonexistent/checklist_status" "/nonexistent/checklist_remaining" \
    "/nonexistent/validation_status" "/nonexistent/validation_results" \
    "$packet_file"

  [ -f "$packet_file" ]
  content=$(cat "$packet_file")
  [[ "$content" =~ "Missing gate summary" ]]
  [[ "$content" =~ "Missing test status" ]]
  [[ "$content" =~ "Missing test report" ]]
  [[ "$content" =~ "Missing evidence manifest" ]]
  [[ "$content" =~ "Missing checklist status" ]]
  [[ "$content" =~ "Missing checklist remaining list" ]]
  [[ "$content" =~ "Missing validation status" ]]
}

# =============================================================================
# read_approval_status
# =============================================================================

@test "gates: read_approval_status returns none for missing file" {
  result=$(read_approval_status "$TEMP_DIR/nonexistent.json")
  [ "$result" = "none" ]
}

@test "gates: read_approval_status reads status from valid JSON" {
  local approval_file="$TEMP_DIR/approval.json"

  echo '{"status": "approved"}' > "$approval_file"

  result=$(read_approval_status "$approval_file")
  [ "$result" = "approved" ]
}

@test "gates: read_approval_status defaults to pending for missing status field" {
  local approval_file="$TEMP_DIR/approval.json"

  echo '{"other": "field"}' > "$approval_file"

  result=$(read_approval_status "$approval_file")
  [ "$result" = "pending" ]
}

@test "gates: read_approval_status defaults to pending for null status" {
  local approval_file="$TEMP_DIR/approval.json"

  echo '{"status": null}' > "$approval_file"

  result=$(read_approval_status "$approval_file")
  [ "$result" = "pending" ]
}

@test "gates: read_approval_status handles invalid JSON" {
  local approval_file="$TEMP_DIR/approval.json"

  echo 'invalid json' > "$approval_file"

  result=$(read_approval_status "$approval_file")
  [ "$result" = "pending" ]
}

@test "gates: read_approval_status handles rejected status" {
  local approval_file="$TEMP_DIR/approval.json"

  echo '{"status": "rejected"}' > "$approval_file"

  result=$(read_approval_status "$approval_file")
  [ "$result" = "rejected" ]
}

# =============================================================================
# write_approval_request
# =============================================================================

@test "gates: write_approval_request creates valid JSON" {
  local approval_file="$TEMP_DIR/approval.json"

  write_approval_request "$approval_file" "loop1" "run1" "3" \
    "2024-01-15T10:00:00Z" "2024-01-15T10:30:00Z" \
    "SUPERLOOP_COMPLETE" "SUPERLOOP_COMPLETE" "true" \
    "passed" "passed" "passed" "complete" "found" \
    "ok" \
    "$TEMP_DIR/gate_summary" "$TEMP_DIR/evidence" \
    "$TEMP_DIR/reviewer" "$TEMP_DIR/test_report" \
    "$TEMP_DIR/plan" "$TEMP_DIR/notes"

  [ -f "$approval_file" ]

  # Validate JSON structure
  status=$(jq -r '.status' "$approval_file")
  [ "$status" = "pending" ]

  loop_id=$(jq -r '.loop_id' "$approval_file")
  [ "$loop_id" = "loop1" ]

  iteration=$(jq -r '.iteration' "$approval_file")
  [ "$iteration" = "3" ]

  promise_matched=$(jq -r '.candidate.promise.matched' "$approval_file")
  [ "$promise_matched" = "true" ]

  tests_status=$(jq -r '.candidate.gates.tests' "$approval_file")
  [ "$tests_status" = "passed" ]
  prerequisites_status=$(jq -r '.candidate.gates.prerequisites' "$approval_file")
  [ "$prerequisites_status" = "passed" ]
  lifecycle_status=$(jq -r '.candidate.gates.lifecycle' "$approval_file")
  [ "$lifecycle_status" = "ok" ]
}

@test "gates: write_approval_request handles false promise match" {
  local approval_file="$TEMP_DIR/approval.json"

  write_approval_request "$approval_file" "loop1" "run1" "1" \
    "2024-01-15T10:00:00Z" "2024-01-15T10:01:00Z" \
    "SUPERLOOP_COMPLETE" "OTHER_PROMISE" "false" \
    "failed" "failed" "failed" "incomplete" "missing" \
    "failed" \
    "" "" "" "" "" ""

  promise_matched=$(jq -r '.candidate.promise.matched' "$approval_file")
  [ "$promise_matched" = "false" ]

  promise_text=$(jq -r '.candidate.promise.text' "$approval_file")
  [ "$promise_text" = "OTHER_PROMISE" ]
}

@test "gates: write_approval_request handles empty promise text" {
  local approval_file="$TEMP_DIR/approval.json"

  write_approval_request "$approval_file" "loop1" "run1" "1" \
    "2024-01-15T10:00:00Z" "2024-01-15T10:01:00Z" \
    "SUPERLOOP_COMPLETE" "" "false" \
    "passed" "passed" "passed" "complete" "found" \
    "ok" \
    "" "" "" "" "" ""

  promise_text=$(jq -r '.candidate.promise.text' "$approval_file")
  [ "$promise_text" = "null" ]
}

@test "gates: write_approval_request includes all gate statuses" {
  local approval_file="$TEMP_DIR/approval.json"

  write_approval_request "$approval_file" "loop1" "run1" "5" \
    "2024-01-15T10:00:00Z" "2024-01-15T10:30:00Z" \
    "COMPLETE" "COMPLETE" "true" \
    "passed" "skipped" "ok" "incomplete" "missing" \
    "failed" \
    "" "" "" "" "" ""

  tests=$(jq -r '.candidate.gates.tests' "$approval_file")
  [ "$tests" = "passed" ]

  validation=$(jq -r '.candidate.gates.validation' "$approval_file")
  [ "$validation" = "skipped" ]
  prerequisites=$(jq -r '.candidate.gates.prerequisites' "$approval_file")
  [ "$prerequisites" = "ok" ]

  checklist=$(jq -r '.candidate.gates.checklist' "$approval_file")
  [ "$checklist" = "incomplete" ]

  evidence=$(jq -r '.candidate.gates.evidence' "$approval_file")
  [ "$evidence" = "missing" ]

  lifecycle=$(jq -r '.candidate.gates.lifecycle' "$approval_file")
  [ "$lifecycle" = "failed" ]
}

@test "gates: write_approval_request includes file references" {
  local approval_file="$TEMP_DIR/approval.json"

  write_approval_request "$approval_file" "loop1" "run1" "2" \
    "2024-01-15T10:00:00Z" "2024-01-15T10:10:00Z" \
    "DONE" "DONE" "true" \
    "passed" "passed" "passed" "complete" "found" \
    "ok" \
    "/path/to/gate_summary" "/path/to/evidence" \
    "/path/to/reviewer" "/path/to/test_report" \
    "/path/to/plan" "/path/to/notes"

  gate_summary=$(jq -r '.files.gate_summary' "$approval_file")
  [ "$gate_summary" = "/path/to/gate_summary" ]

  test_report=$(jq -r '.files.test_report' "$approval_file")
  [ "$test_report" = "/path/to/test_report" ]

  plan=$(jq -r '.files.plan' "$approval_file")
  [ "$plan" = "/path/to/plan" ]
}
