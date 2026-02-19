#!/usr/bin/env bats

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  TEMP_DIR="$(mktemp -d)"

  mkdir -p "$TEMP_DIR/.superloop/specs"
  mkdir -p "$TEMP_DIR/.superloop/roles"
  cp -r "$PROJECT_ROOT/.superloop/roles/"* "$TEMP_DIR/.superloop/roles/" 2>/dev/null || true

  cat > "$TEMP_DIR/.superloop/specs/rlms.md" <<'EOF'
# RLMS Spec

Baseline requirement for RLMS integration tests.
EOF

  MARKER_RLMS="$TEMP_DIR/marker-rlms.sh"
  cat > "$MARKER_RLMS" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$output_dir"
if [[ -n "${RLMS_MARKER_FILE:-}" ]]; then
  touch "$RLMS_MARKER_FILE"
fi
cat > "$output_dir/result.json" <<'JSON'
{"ok":true,"generated_at":"2026-01-01T00:00:00Z","loop_id":"rlms-loop","role":"reviewer","iteration":1,"highlights":["marker"]}
JSON
cat > "$output_dir/summary.md" <<'MD'
# RLMS Analysis

- marker summary
MD
exit 0
EOF
  chmod +x "$MARKER_RLMS"

  FAILING_RLMS="$TEMP_DIR/failing-rlms.sh"
  cat > "$FAILING_RLMS" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$output_dir"
cat > "$output_dir/result.json" <<'JSON'
{"ok":false,"error":"forced failure from test rlms script"}
JSON
cat > "$output_dir/summary.md" <<'MD'
# RLMS Analysis

forced failure from test rlms script
MD
exit 1
EOF
  chmod +x "$FAILING_RLMS"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

write_loop_config() {
  local mode="$1"
  local fail_mode="$2"
  local force_on="$3"
  local max_lines="$4"
  local max_tokens="$5"
  local request_keyword="$6"

  cat > "$TEMP_DIR/.superloop/config.json" <<EOF
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo '<promise>DONE</promise>' > \\"{last_message_file}\\""],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "rlms-loop",
    "spec_file": ".superloop/specs/rlms.md",
    "max_iterations": 3,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "rlms": {
      "enabled": true,
      "mode": "$mode",
      "request_keyword": "$request_keyword",
      "auto": {"max_lines": $max_lines, "max_estimated_tokens": $max_tokens, "max_files": 40},
      "roles": {"reviewer": true},
      "limits": {"max_steps": 20, "max_depth": 2, "timeout_seconds": 60},
      "output": {"format": "json", "require_citations": true},
      "policy": {"force_on": $force_on, "force_off": false, "fail_mode": "$fail_mode"}
    },
    "roles": {
      "reviewer": {"runner": "shell"}
    }
  }]
}
EOF
}

@test "rlms requested mode does not run when keyword is absent" {
  write_loop_config "requested" "warn_and_continue" "false" 999999 999999 "RLMS_CALL_NOW"
  run env SUPERLOOP_RLMS_SCRIPT="$MARKER_RLMS" RLMS_MARKER_FILE="$TEMP_DIR/rlms-called" \
    "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop rlms-loop
  [ "$status" -eq 0 ]
  [ ! -f "$TEMP_DIR/rlms-called" ]
  [ -f "$TEMP_DIR/.superloop/loops/rlms-loop/rlms/latest/reviewer.status.json" ]
  run jq -r '.should_run' "$TEMP_DIR/.superloop/loops/rlms-loop/rlms/latest/reviewer.status.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "rlms hybrid mode auto-triggers on large context" {
  write_loop_config "hybrid" "warn_and_continue" "false" 1 999999 "NOT_PRESENT"
  run env SUPERLOOP_RLMS_SCRIPT="$MARKER_RLMS" RLMS_MARKER_FILE="$TEMP_DIR/rlms-called" \
    "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop rlms-loop
  [ "$status" -eq 0 ]
  [ -f "$TEMP_DIR/rlms-called" ]
  [ -f "$TEMP_DIR/.superloop/loops/rlms-loop/rlms/latest/reviewer.json" ]
}

@test "rlms warn_and_continue allows role execution when rlms fails" {
  write_loop_config "auto" "warn_and_continue" "true" 999999 999999 "NOT_PRESENT"
  run env SUPERLOOP_RLMS_SCRIPT="$FAILING_RLMS" \
    "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop rlms-loop
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Loop 'rlms-loop' complete" ]]
  run jq -r '.status' "$TEMP_DIR/.superloop/loops/rlms-loop/rlms/latest/reviewer.status.json"
  [ "$status" -eq 0 ]
  [ "$output" = "failed" ]
}

@test "rlms fail_role stops execution when rlms fails" {
  write_loop_config "auto" "fail_role" "true" 999999 999999 "NOT_PRESENT"
  run env SUPERLOOP_RLMS_SCRIPT="$FAILING_RLMS" \
    "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop rlms-loop
  [ "$status" -ne 0 ]
  [[ "$output" =~ "RLMS failed for role 'reviewer'" ]]
}

@test "rlms artifacts are included in evidence manifest when evidence is enabled" {
  write_loop_config "hybrid" "warn_and_continue" "false" 1 999999 "NOT_PRESENT"
  jq '.loops[0].evidence.enabled = true | .loops[0].evidence.require_on_completion = false' \
    "$TEMP_DIR/.superloop/config.json" > "$TEMP_DIR/.superloop/config.tmp.json"
  mv "$TEMP_DIR/.superloop/config.tmp.json" "$TEMP_DIR/.superloop/config.json"

  run env SUPERLOOP_RLMS_SCRIPT="$MARKER_RLMS" RLMS_MARKER_FILE="$TEMP_DIR/rlms-called" \
    "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop rlms-loop
  [ "$status" -eq 0 ]

  local evidence_file="$TEMP_DIR/.superloop/loops/rlms-loop/evidence.json"
  [ -f "$evidence_file" ]

  run jq -r '.rlms.index_file' "$evidence_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "rlms/index.json" ]]

  run jq -r '.rlms.latest | length' "$evidence_file"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
