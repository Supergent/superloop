#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

write_enabled_webhook_config() {
  local path="$1"
  cat > "$path" <<'JSON'
{
  "schemaVersion": "v1",
  "defaultMinSeverity": "warning",
  "sinks": {
    "webhook-a": {
      "enabled": true,
      "type": "webhook",
      "urlEnv": "OPS_MANAGER_TEST_WEBHOOK_URL",
      "timeoutSeconds": 5
    }
  },
  "routing": {
    "defaultSinks": [
      "webhook-a"
    ],
    "categorySeverity": {
      "health_degraded": "warning"
    },
    "routes": [
      {
        "category": "health_degraded",
        "sinks": [
          "webhook-a"
        ],
        "minSeverity": "warning",
        "enabled": true
      }
    ]
  }
}
JSON
}

@test "alert sink resolver lists default sink catalog entries" {
  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" --list-sinks
  [ "$status" -eq 0 ]
  [[ "$output" == *"webhook-default"* ]]
  [[ "$output" == *"slack-default"* ]]
  [[ "$output" == *"pagerduty-default"* ]]
}

@test "alert sink resolver returns default config summary" {
  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh"
  [ "$status" -eq 0 ]
  local resolver_json="$output"

  run jq -r '.defaultMinSeverity' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "warning" ]

  run jq -r '.enabledSinkCount' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "alert sink resolver rejects severity without category" {
  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" --severity warning
  [ "$status" -ne 0 ]
  [[ "$output" == *"--severity requires --category"* ]]
}

@test "alert sink resolver fails closed when enabled sink secret env var is missing" {
  local config_file="$TEMP_DIR/enabled-webhook.json"
  write_enabled_webhook_config "$config_file"

  run "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" --config-file "$config_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"enabled sink secret env var(s) are unset"* ]]
}

@test "alert sink resolver resolves route and dispatchable sinks when env var is set" {
  local config_file="$TEMP_DIR/enabled-webhook.json"
  write_enabled_webhook_config "$config_file"

  run env OPS_MANAGER_TEST_WEBHOOK_URL="https://example.test/webhook" \
    "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" \
    --config-file "$config_file" \
    --category health_degraded \
    --severity warning
  [ "$status" -eq 0 ]
  local route_json="$output"

  run jq -r '.shouldDispatch' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.dispatchableSinks | length' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.dispatchableSinks[0].id' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "webhook-a" ]
}

@test "alert sink resolver enforces min severity gate during category resolution" {
  local config_file="$TEMP_DIR/enabled-webhook.json"
  write_enabled_webhook_config "$config_file"

  run env OPS_MANAGER_TEST_WEBHOOK_URL="https://example.test/webhook" \
    "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh" \
    --config-file "$config_file" \
    --category health_degraded \
    --severity info
  [ "$status" -eq 0 ]
  local route_json="$output"

  run jq -r '.shouldDispatch' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.dispatchableSinks | length' <<<"$route_json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "alert sink resolver uses OPS_MANAGER_ALERT_SINKS_FILE when --config-file is omitted" {
  local config_file="$TEMP_DIR/custom-config.json"
  cat > "$config_file" <<'JSON'
{
  "schemaVersion": "v1",
  "defaultMinSeverity": "critical",
  "sinks": {
    "webhook-a": {
      "enabled": false,
      "type": "webhook",
      "urlEnv": "OPS_MANAGER_TEST_WEBHOOK_URL"
    }
  },
  "routing": {
    "defaultSinks": [
      "webhook-a"
    ],
    "categorySeverity": {},
    "routes": []
  }
}
JSON

  run env OPS_MANAGER_ALERT_SINKS_FILE="$config_file" \
    "$PROJECT_ROOT/scripts/ops-manager-alert-sink-config.sh"
  [ "$status" -eq 0 ]
  local resolver_json="$output"

  run jq -r '.sourceFile' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "$config_file" ]

  run jq -r '.defaultMinSeverity' <<<"$resolver_json"
  [ "$status" -eq 0 ]
  [ "$output" = "critical" ]
}
