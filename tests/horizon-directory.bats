#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

@test "validate horizon directory accepts valid contract" {
  local directory_file="$TEMP_DIR/horizon-directory.json"
  cat > "$directory_file" <<'JSON'
{
  "version": 1,
  "contacts": [
    {
      "recipient": {"type": "local_agent", "id": "implementer"},
      "dispatch": {"adapter": "filesystem_outbox", "target": "local_agent/implementer.jsonl"},
      "ack": {"timeout_seconds": 300, "max_retries": 2, "retry_backoff_seconds": 60}
    },
    {
      "recipient": {"type": "human", "id": "alice"},
      "dispatch": {"adapter": "stdout"}
    }
  ]
}
JSON

  run "$PROJECT_ROOT/scripts/validate-horizon-directory.sh" --repo "$PROJECT_ROOT" --file "$directory_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: horizon directory file is valid"* ]]
}

@test "validate horizon directory fails on duplicate recipients" {
  local directory_file="$TEMP_DIR/horizon-directory-invalid.json"
  cat > "$directory_file" <<'JSON'
{
  "version": 1,
  "contacts": [
    {
      "recipient": {"type": "local_agent", "id": "implementer"},
      "dispatch": {"adapter": "filesystem_outbox", "target": "local_agent/implementer.jsonl"}
    },
    {
      "recipient": {"type": "local_agent", "id": "implementer"},
      "dispatch": {"adapter": "stdout"}
    }
  ]
}
JSON

  run "$PROJECT_ROOT/scripts/validate-horizon-directory.sh" --repo "$PROJECT_ROOT" --file "$directory_file"
  [ "$status" -ne 0 ]
}
