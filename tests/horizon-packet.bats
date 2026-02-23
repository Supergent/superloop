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

@test "horizon packet create writes queued packet and telemetry" {
  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id pkt-001 \
    --horizon-ref HZ-alpha \
    --sender planner \
    --recipient-type local_agent \
    --recipient-id implementer \
    --intent "implement slice" \
    --authority "eng-manager"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.status' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "queued" ]

  run jq -r '.traceId | type' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "string" ]

  run jq -r '.horizonRef' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "HZ-alpha" ]

  [ -f "$REPO_DIR/.superloop/horizons/packets/pkt-001.json" ]
  [ -f "$REPO_DIR/.superloop/horizons/telemetry/packets.jsonl" ]

  run jq -r '.action' "$REPO_DIR/.superloop/horizons/telemetry/packets.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "create" ]
}

@test "horizon packet create accepts seam fields and evidence refs" {
  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id pkt-002 \
    --horizon-ref HZ-beta \
    --sender planner \
    --recipient-type human \
    --recipient-id user-1 \
    --intent "request approval" \
    --trace-id trace-hz-001 \
    --ttl-seconds 600 \
    --evidence-ref "artifact://run-summary" \
    --evidence-ref "artifact://review-note"

  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.traceId' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "trace-hz-001" ]

  run jq -r '.ttlSeconds' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "600" ]

  run jq -r '.evidenceRefs | index("artifact://run-summary") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.evidenceRefs | index("artifact://review-note") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "horizon packet transition updates state and completion timestamp" {
  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id pkt-003 \
    --horizon-ref HZ-gamma \
    --sender planner \
    --recipient-type local_agent \
    --recipient-id implementer \
    --intent "execute change"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" transition \
    --repo "$REPO_DIR" \
    --packet-id pkt-003 \
    --to-status dispatched \
    --by dispatcher \
    --reason "selected recipient" \
    --evidence-ref "artifact://dispatch-log"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" transition \
    --repo "$REPO_DIR" \
    --packet-id pkt-003 \
    --to-status acknowledged \
    --by implementer \
    --reason "accepted"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" transition \
    --repo "$REPO_DIR" \
    --packet-id pkt-003 \
    --to-status in_progress \
    --by implementer \
    --reason "started work"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" transition \
    --repo "$REPO_DIR" \
    --packet-id pkt-003 \
    --to-status completed \
    --by implementer \
    --reason "delivered"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-003
  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.status' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "completed" ]

  run jq -r '.completedAt != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.transitions | length' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]

  run jq -r '.evidenceRefs | index("artifact://dispatch-log") != null' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -lc "wc -l < '$REPO_DIR/.superloop/horizons/telemetry/packets.jsonl'"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "horizon packet transition rejects invalid state move" {
  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id pkt-004 \
    --horizon-ref HZ-delta \
    --sender planner \
    --recipient-type local_agent \
    --recipient-id implementer \
    --intent "invalid transition check"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" transition \
    --repo "$REPO_DIR" \
    --packet-id pkt-004 \
    --to-status completed \
    --by implementer \
    --reason "should fail"

  [ "$status" -ne 0 ]
  [[ "$output" == *"transition from queued to completed is not allowed"* ]]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-004
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "queued" ]
}

@test "horizon packet list supports horizon and status filters" {
  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id pkt-005 \
    --horizon-ref HZ-A \
    --sender planner \
    --recipient-type local_agent \
    --recipient-id impl-a \
    --intent "task-a"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id pkt-006 \
    --horizon-ref HZ-B \
    --sender planner \
    --recipient-type local_agent \
    --recipient-id impl-b \
    --intent "task-b"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" transition \
    --repo "$REPO_DIR" \
    --packet-id pkt-006 \
    --to-status dispatched \
    --by dispatcher \
    --reason "routed"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" list --repo "$REPO_DIR"
  [ "$status" -eq 0 ]
  run jq -r 'length' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" list --repo "$REPO_DIR" --horizon-ref HZ-A
  [ "$status" -eq 0 ]
  run jq -r '.[0].packetId' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "pkt-005" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" list --repo "$REPO_DIR" --status dispatched
  [ "$status" -eq 0 ]
  run jq -r '.[0].packetId' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "pkt-006" ]
}

@test "horizon packet show fails for missing packet id" {
  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id missing-pkt
  [ "$status" -ne 0 ]
  [[ "$output" == *"packet not found"* ]]
}
