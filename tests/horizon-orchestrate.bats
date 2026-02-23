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

create_packet() {
  local packet_id="$1"
  local horizon_ref="$2"
  local recipient_type="$3"
  local recipient_id="$4"
  local intent="$5"
  shift 5
  run "$PROJECT_ROOT/scripts/horizon-packet.sh" create \
    --repo "$REPO_DIR" \
    --packet-id "$packet_id" \
    --horizon-ref "$horizon_ref" \
    --sender planner \
    --recipient-type "$recipient_type" \
    --recipient-id "$recipient_id" \
    --intent "$intent" "$@"
  [ "$status" -eq 0 ]
}

@test "horizon orchestrate plan marks ttl-expired packet as blocked" {
  create_packet pkt-fresh HZ-a local_agent impl-a "fresh task" --ttl-seconds 600
  create_packet pkt-stale HZ-a local_agent impl-b "stale task" --ttl-seconds 60

  local stale_file="$REPO_DIR/.superloop/horizons/packets/pkt-stale.json"
  run bash -lc "jq -c '.createdAt=\"2020-01-01T00:00:00Z\" | .updatedAt=\"2020-01-01T00:00:00Z\"' '$stale_file' > '$stale_file.tmp' && mv '$stale_file.tmp' '$stale_file'"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" plan --repo "$REPO_DIR"
  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.summary.selectedCount' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.summary.dispatchableCount' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.summary.blockedByReason.packet_ttl_expired' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.items[] | select(.packetId=="pkt-stale") | .dispatchable' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.items[] | select(.packetId=="pkt-stale") | (.blockedReasons | index("packet_ttl_expired") != null)' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "horizon orchestrate dispatch with filesystem_outbox transitions packet" {
  create_packet pkt-010 HZ-ops local_agent worker-a "run change"

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" dispatch \
    --repo "$REPO_DIR" \
    --actor dispatcher \
    --reason "orchestrator_dispatch"
  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.execution.dispatchedCount' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.execution.failedCount' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-010
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "dispatched" ]

  local outbox_file="$REPO_DIR/.superloop/horizons/outbox/local_agent/worker-a.jsonl"
  [ -f "$outbox_file" ]

  run jq -r '.packet.packetId' "$outbox_file"
  [ "$status" -eq 0 ]
  [ "$output" = "pkt-010" ]

  local orch_telemetry="$REPO_DIR/.superloop/horizons/telemetry/orchestrator.jsonl"
  [ -f "$orch_telemetry" ]

  run jq -r '.category' "$orch_telemetry"
  [ "$status" -eq 0 ]
  [ "$output" = "horizon_orchestrator_run" ]
}

@test "horizon orchestrate dispatch dry-run does not mutate packets" {
  create_packet pkt-020 HZ-ops local_agent worker-b "preview only"

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" dispatch --repo "$REPO_DIR" --dry-run
  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.execution.status' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "dry_run" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-020
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "queued" ]

  [ ! -d "$REPO_DIR/.superloop/horizons/outbox" ]
}

@test "horizon orchestrate dispatch respects horizon filter and limit" {
  create_packet pkt-100 HZ-a local_agent worker-1 "task 1"
  create_packet pkt-101 HZ-a local_agent worker-2 "task 2"
  create_packet pkt-102 HZ-b local_agent worker-3 "task 3"

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" dispatch \
    --repo "$REPO_DIR" \
    --horizon-ref HZ-a \
    --limit 1
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-100
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "dispatched" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-101
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "queued" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-102
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "queued" ]
}

@test "horizon orchestrate dispatch stdout adapter emits envelope in result" {
  create_packet pkt-200 HZ-c human alice "request review"

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" dispatch \
    --repo "$REPO_DIR" \
    --adapter stdout
  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.execution.dispatchedCount' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.execution.results[0].envelope.packet.packetId' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "pkt-200" ]

  run "$PROJECT_ROOT/scripts/horizon-packet.sh" show --repo "$REPO_DIR" --packet-id pkt-200
  [ "$status" -eq 0 ]
  run jq -r '.status' <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" = "dispatched" ]

  [ ! -d "$REPO_DIR/.superloop/horizons/outbox" ]
}

@test "horizon orchestrate required directory blocks unknown recipients" {
  create_packet pkt-dir-001 HZ-dir local_agent worker-dir "directory required"

  local directory_file="$REPO_DIR/.superloop/horizon-directory.json"
  cat > "$directory_file" <<'JSON'
{
  "version": 1,
  "contacts": [
    {
      "recipient": {"type": "local_agent", "id": "different-worker"},
      "dispatch": {"adapter": "filesystem_outbox", "target": "local_agent/different-worker.jsonl"}
    }
  ]
}
JSON

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" plan \
    --repo "$REPO_DIR" \
    --directory-mode required \
    --directory-file "$directory_file"
  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.summary.blockedByReason.directory_contact_not_found' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.items[0].dispatchable' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "horizon orchestrate directory contact can override dispatch adapter" {
  create_packet pkt-dir-002 HZ-dir local_agent worker-dir-2 "directory override"

  local directory_file="$REPO_DIR/.superloop/horizon-directory.json"
  cat > "$directory_file" <<'JSON'
{
  "version": 1,
  "contacts": [
    {
      "recipient": {"type": "local_agent", "id": "worker-dir-2"},
      "dispatch": {"adapter": "stdout"},
      "ack": {"timeout_seconds": 900, "max_retries": 5, "retry_backoff_seconds": 120}
    }
  ]
}
JSON

  run "$PROJECT_ROOT/scripts/horizon-orchestrate.sh" dispatch \
    --repo "$REPO_DIR" \
    --directory-mode required \
    --directory-file "$directory_file"
  [ "$status" -eq 0 ]
  local result_json="$output"

  run jq -r '.execution.results[0].adapter' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "stdout" ]

  run jq -r '.items[0].ackPolicy.maxRetries' <<<"$result_json"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]

  [ ! -d "$REPO_DIR/.superloop/horizons/outbox" ]
}
