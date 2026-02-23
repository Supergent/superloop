#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
  REPO_DIR="$TEMP_DIR/repo"
  mkdir -p "$REPO_DIR/.superloop/horizons/outbox"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

write_envelope_file() {
  local relative_path="$1"
  local payload="$2"

  local abs_path="$REPO_DIR/.superloop/horizons/outbox/$relative_path"
  mkdir -p "$(dirname "$abs_path")"
  printf '%s\n' "$payload" > "$abs_path"
}

@test "horizon bridge ingests valid envelope, ignores unknown extras, and queues pending confirmation intent" {
  write_envelope_file "local_agent/worker-a.jsonl" '{"schemaVersion":"v1","timestamp":"2026-02-23T00:00:00Z","category":"horizon_dispatch","traceId":"trace-alpha","packet":{"packetId":"pkt-001","recipient":{"type":"local_agent","id":"worker-a"},"intent":"run change"},"evidenceRefs":["ev://window"],"unknownExtra":{"safe":true}}'

  run "$PROJECT_ROOT/scripts/ops-manager-horizon-bridge.sh" --repo "$REPO_DIR"
  [ "$status" -eq 0 ]

  local queue_file="$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-queue.json"
  local state_file="$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-state.json"
  local telemetry_file="$REPO_DIR/.superloop/ops-manager/fleet/telemetry/horizon-bridge.jsonl"

  [ -f "$queue_file" ]
  [ -f "$state_file" ]
  [ -f "$telemetry_file" ]

  run jq -r '.summary.intentCount' "$queue_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.intents[0].status' "$queue_file"
  [ "$status" -eq 0 ]
  [ "$output" = "pending_operator_confirmation" ]

  run jq -r '.intents[0].autonomous.eligible' "$queue_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.summary.claimedFileCount' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.processedFileCount' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.rejectedFileCount' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.reasonCodes | index("horizon_bridge_queue_updated") != null' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -lc "find '$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-claims/processed' -type f | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  [ ! -f "$REPO_DIR/.superloop/horizons/outbox/local_agent/worker-a.jsonl" ]
}

@test "horizon bridge is replay-safe and dedupes by packetId plus traceId" {
  write_envelope_file "local_agent/worker-a.jsonl" '{"schemaVersion":"v1","timestamp":"2026-02-23T00:00:00Z","category":"horizon_dispatch","traceId":"trace-dup","packet":{"packetId":"pkt-dup","recipient":{"type":"local_agent","id":"worker-a"},"intent":"review"},"evidenceRefs":[]}'

  run "$PROJECT_ROOT/scripts/ops-manager-horizon-bridge.sh" --repo "$REPO_DIR"
  [ "$status" -eq 0 ]

  write_envelope_file "local_agent/worker-b.jsonl" '{"schemaVersion":"v1","timestamp":"2026-02-23T00:00:30Z","category":"horizon_dispatch","traceId":"trace-dup","packet":{"packetId":"pkt-dup","recipient":{"type":"local_agent","id":"worker-b"},"intent":"review"},"evidenceRefs":["ev://same"]}'

  run "$PROJECT_ROOT/scripts/ops-manager-horizon-bridge.sh" --repo "$REPO_DIR"
  [ "$status" -eq 0 ]

  local queue_file="$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-queue.json"
  local state_file="$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-state.json"

  run jq -r '.summary.intentCount' "$queue_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.duplicateEnvelopeCount' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.dedupe.keyCount' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "horizon bridge fails closed for missing required contract fields and moves claim to rejected" {
  write_envelope_file "human/alice.jsonl" '{"schemaVersion":"v1","timestamp":"2026-02-23T00:01:00Z","category":"horizon_dispatch","traceId":"trace-missing","packet":{"packetId":"pkt-missing","recipient":{"type":"human","id":"alice"}},"evidenceRefs":["ev://missing-intent"]}'

  run "$PROJECT_ROOT/scripts/ops-manager-horizon-bridge.sh" --repo "$REPO_DIR"
  [ "$status" -eq 2 ]

  local queue_file="$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-queue.json"
  local state_file="$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-state.json"

  run jq -r '.status' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "failed_contract_validation" ]

  run jq -r '.summary.rejectedFileCount' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.reasonCodes | index("horizon_bridge_contract_validation_failed") != null' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.summary.intentCount' "$queue_file"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run bash -lc "find '$REPO_DIR/.superloop/ops-manager/fleet/horizon-bridge-claims/rejected' -type f | wc -l"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
