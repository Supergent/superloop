#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
  STATUS_FILE="$TEMP_DIR/reviewer.status.json"
  RESULT_FILE="$TEMP_DIR/reviewer.json"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

write_status() {
  local status_value="$1"
  local should_run_value="$2"
  cat > "$STATUS_FILE" <<JSON
{"status":"$status_value","should_run":$should_run_value}
JSON
}

write_result() {
  local body="$1"
  cat > "$RESULT_FILE" <<JSON
$body
JSON
}

@test "assert-rlms-canary passes for healthy canary artifacts" {
  write_status "ok" "true"
  write_result '{"ok":true,"highlights":["mock_root_complete"],"citations":[{"signal":"semantic_match"}]}'

  run "$PROJECT_ROOT/scripts/assert-rlms-canary.sh" \
    --status-file "$STATUS_FILE" \
    --result-file "$RESULT_FILE" \
    --require-highlight-pattern "mock_root_complete"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "assertions passed" ]]
}

@test "assert-rlms-canary fails when should_run is false and required" {
  write_status "ok" "false"
  write_result '{"ok":true,"highlights":["mock_root_complete"],"citations":[{"signal":"semantic_match"}]}'

  run "$PROJECT_ROOT/scripts/assert-rlms-canary.sh" \
    --status-file "$STATUS_FILE" \
    --result-file "$RESULT_FILE" \
    --require-should-run true

  [ "$status" -ne 0 ]
  [[ "$output" =~ "expected should_run=true" ]]
}

@test "assert-rlms-canary fails when citation threshold is not met" {
  write_status "ok" "true"
  write_result '{"ok":true,"highlights":["mock_root_complete"],"citations":[]}'

  run "$PROJECT_ROOT/scripts/assert-rlms-canary.sh" \
    --status-file "$STATUS_FILE" \
    --result-file "$RESULT_FILE" \
    --min-citations 1

  [ "$status" -ne 0 ]
  [[ "$output" =~ "citation threshold failed" ]]
}

@test "assert-rlms-canary fails when only fallback citations are present" {
  write_status "ok" "true"
  write_result '{"ok":true,"highlights":["mock_root_complete"],"citations":[{"signal":"file_reference"}]}'

  run "$PROJECT_ROOT/scripts/assert-rlms-canary.sh" \
    --status-file "$STATUS_FILE" \
    --result-file "$RESULT_FILE" \
    --min-citations 1 \
    --min-non-fallback-citations 1 \
    --fallback-signals file_reference

  [ "$status" -ne 0 ]
  [[ "$output" =~ "non-fallback citation threshold failed" ]]
}

@test "assert-rlms-canary fails when required highlight pattern is missing" {
  write_status "ok" "true"
  write_result '{"ok":true,"highlights":["different_highlight"],"citations":[{"signal":"semantic_match"}]}'

  run "$PROJECT_ROOT/scripts/assert-rlms-canary.sh" \
    --status-file "$STATUS_FILE" \
    --result-file "$RESULT_FILE" \
    --require-highlight-pattern "mock_root_complete"

  [ "$status" -ne 0 ]
  [[ "$output" =~ "required highlight pattern not found" ]]
}
