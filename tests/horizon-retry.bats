#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
  REPO_DIR="$TEMP_DIR/repo"
  mkdir -p "$REPO_DIR/.superloop/horizons"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

create_dispatched_packet() {
  local packet_id="$1"
  local recipient_type="$2"
  local recipient_id="$3"

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id "$packet_id" \
    --horizon-ref HZ-retry \
    --sender planner \
    --recipient-type "$recipient_type" \
    --recipient-id "$recipient_id" \
    --intent "retry test"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" dispatch \
    --repo "$REPO_DIR" \
    --actor dispatcher \
    --reason "initial dispatch"
  [ "$status" -eq 0 ]
}

mark_packet_stale() {
  local packet_id="$1"
  local packet_file="$REPO_DIR/.superloop/horizons/packets/$packet_id.json"
  run bash -lc "jq -c '.updatedAt=\"2020-01-01T00:00:00Z\"' '$packet_file' > '$packet_file.tmp' && mv '$packet_file.tmp' '$packet_file'"
  [ "$status" -eq 0 ]
}

@test "horizon retry reconcile redispatches timed-out packet and updates retry state" {
  create_dispatched_packet pkt-retry-001 local_agent worker-retry
  mark_packet_stale pkt-retry-001

  run "$PROJECT_ROOT/scripts/horizon-retry.sh" reconcile \
    --repo "$REPO_DIR" \
    --ack-timeout-seconds 1 \
    --max-retries 2 \
    --retry-backoff-seconds 0
  [ "$status" -eq 0 ]

  run jq -r '.summary.retriedCount' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  local outbox_file="$REPO_DIR/.superloop/horizons/outbox/local_agent/worker-retry.jsonl"
  run bash -lc "wc -l < '$outbox_file'"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.packets["pkt-retry-001"].retryCount' "$REPO_DIR/.superloop/horizons/retry-state.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-retry-001
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "dispatched" ]
}

@test "horizon retry reconcile escalates to dead letter after retry budget exhausted" {
  create_dispatched_packet pkt-retry-002 local_agent worker-retry-2
  mark_packet_stale pkt-retry-002

  run "$PROJECT_ROOT/scripts/horizon-retry.sh" reconcile \
    --repo "$REPO_DIR" \
    --ack-timeout-seconds 1 \
    --max-retries 1 \
    --retry-backoff-seconds 0
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-retry.sh" reconcile \
    --repo "$REPO_DIR" \
    --ack-timeout-seconds 1 \
    --max-retries 1 \
    --retry-backoff-seconds 0
  [ "$status" -eq 0 ]

  run jq -r '.summary.escalatedCount' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-retry-002
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "escalated" ]

  local dead_letter_file="$REPO_DIR/.superloop/horizons/telemetry/dead-letter.jsonl"
  [ -f "$dead_letter_file" ]

  run jq -r '.packetId' "$dead_letter_file"
  [ "$status" -eq 0 ]
  [ "$output" = "pkt-retry-002" ]
}
