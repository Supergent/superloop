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
    --horizon-ref HZ-ack \
    --sender planner \
    --recipient-type "$recipient_type" \
    --recipient-id "$recipient_id" \
    --intent "ack test"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" dispatch \
    --repo "$REPO_DIR" \
    --actor dispatcher \
    --reason "initial dispatch"
  [ "$status" -eq 0 ]
}

@test "horizon ack ingest transitions dispatched packet to acknowledged and dedupes" {
  create_dispatched_packet pkt-ack-001 local_agent worker-ack

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-ack-001
  [ "$status" -eq 0 ]
  local packet_trace_id
  packet_trace_id="$(jq -r '.traceId' <<<"$output")"

  local receipt_file="$TEMP_DIR/receipts.jsonl"
  jq -cn \
    --arg packet_id "pkt-ack-001" \
    --arg trace_id "$packet_trace_id" \
    '{schemaVersion:"v1",packetId:$packet_id,traceId:$trace_id,status:"acknowledged",by:"delivery-gateway",reason:"delivered"}' > "$receipt_file"

  run "$PROJECT_ROOT/scripts/horizon-ack.sh" ingest --repo "$REPO_DIR" --file "$receipt_file"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-ack-001
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "acknowledged" ]

  run "$PROJECT_ROOT/scripts/horizon-ack.sh" ingest --repo "$REPO_DIR" --file "$receipt_file"
  [ "$status" -eq 0 ]
  run jq -r '.summary.duplicateCount' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.processedKeys | length' "$REPO_DIR/.superloop/horizons/ack-state.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "horizon ack ingest rejects missing required fields" {
  create_dispatched_packet pkt-ack-002 local_agent worker-ack-2

  local receipt_file="$TEMP_DIR/receipts-invalid.jsonl"
  jq -cn '{schemaVersion:"v1",packetId:"pkt-ack-002",status:"acknowledged"}' > "$receipt_file"

  run "$PROJECT_ROOT/scripts/horizon-ack.sh" ingest --repo "$REPO_DIR" --file "$receipt_file"
  [ "$status" -eq 0 ]

  run jq -r '.summary.rejectedCount' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-ack-002
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "dispatched" ]
}
