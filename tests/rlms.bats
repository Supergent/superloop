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

  SAMPLE_CONTEXT_FILE="$TEMP_DIR/sample-context.py"
  cat > "$SAMPLE_CONTEXT_FILE" <<'EOF'
class ExampleService:
  def run(self):
    return "ok"

def helper():
  return 42
EOF

  ROOT_SUCCESS_LLM="$TEMP_DIR/mock-root-success.sh"
  cat > "$ROOT_SUCCESS_LLM" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'PY'
files = list_files()
if files:
    snippet = read_file(files[0], 1, 80)
    summary = sub_rlm("summarize:\\n" + snippet, depth=1)
    append_highlight("subcall:" + summary)
    matches = grep("class\\s+", files[0], 3, "")
    for m in matches:
        add_citation(m["path"], m["start_line"], m["end_line"], m["signal"], m["snippet"])
set_final({"highlights": ["root_complete"], "citations": []})
PY
EOF
  chmod +x "$ROOT_SUCCESS_LLM"

  ROOT_IMPORT_LLM="$TEMP_DIR/mock-root-import.sh"
  cat > "$ROOT_IMPORT_LLM" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'PY'
import os
set_final({"highlights": ["should_not_run"], "citations": []})
PY
EOF
  chmod +x "$ROOT_IMPORT_LLM"

  ROOT_DEPTH_LLM="$TEMP_DIR/mock-root-depth.sh"
  cat > "$ROOT_DEPTH_LLM" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'PY'
sub_rlm("first", depth=2)
set_final({"highlights": ["depth"], "citations": []})
PY
EOF
  chmod +x "$ROOT_DEPTH_LLM"

  SUBCALL_SUCCESS_LLM="$TEMP_DIR/mock-subcall-success.sh"
  cat > "$SUBCALL_SUCCESS_LLM" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
payload="$(cat)"
if [[ -n "${MOCK_SUBCALL_LOG_FILE:-}" ]]; then
  printf '%s\n' "$payload" >> "$MOCK_SUBCALL_LOG_FILE"
fi
echo "chunk-ok"
EOF
  chmod +x "$SUBCALL_SUCCESS_LLM"
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

@test "rlms REPL worker executes sandboxed root code with subcall CLI" {
  local context_file_list="$TEMP_DIR/context-files.txt"
  printf '%s\n' "$SAMPLE_CONTEXT_FILE" > "$context_file_list"
  local output_dir="$TEMP_DIR/rlms-success"
  local root_command_json
  root_command_json=$(jq -cn --arg cmd "$ROOT_SUCCESS_LLM" '[$cmd]')
  local subcall_command_json
  subcall_command_json=$(jq -cn --arg cmd "$SUBCALL_SUCCESS_LLM" '[$cmd]')

  run env MOCK_SUBCALL_LOG_FILE="$TEMP_DIR/subcall.log" \
    "$PROJECT_ROOT/scripts/rlms" \
      --repo "$TEMP_DIR" \
      --loop-id rlms-loop \
      --role reviewer \
      --iteration 1 \
      --context-file-list "$context_file_list" \
      --output-dir "$output_dir" \
      --max-steps 5 \
      --max-depth 2 \
      --timeout-seconds 60 \
      --root-command-json "$root_command_json" \
      --root-args-json '[]' \
      --root-prompt-mode stdin \
      --subcall-command-json "$subcall_command_json" \
      --subcall-args-json '[]' \
      --subcall-prompt-mode stdin \
      --require-citations true \
      --format json
  [ "$status" -eq 0 ]

  run jq -r '.ok' "$output_dir/result.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.stats.subcall_count // 0' "$output_dir/result.json"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  run jq -r '.citations | length' "$output_dir/result.json"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  [ -f "$TEMP_DIR/subcall.log" ]
}

@test "rlms REPL worker rejects sandbox violations from root code" {
  local context_file_list="$TEMP_DIR/context-files.txt"
  printf '%s\n' "$SAMPLE_CONTEXT_FILE" > "$context_file_list"
  local output_dir="$TEMP_DIR/rlms-sandbox-fail"
  local root_command_json
  root_command_json=$(jq -cn --arg cmd "$ROOT_IMPORT_LLM" '[$cmd]')
  local subcall_command_json
  subcall_command_json=$(jq -cn --arg cmd "$SUBCALL_SUCCESS_LLM" '[$cmd]')

  run "$PROJECT_ROOT/scripts/rlms" \
    --repo "$TEMP_DIR" \
    --loop-id rlms-loop \
    --role reviewer \
    --iteration 1 \
    --context-file-list "$context_file_list" \
    --output-dir "$output_dir" \
    --max-steps 5 \
    --max-depth 2 \
    --timeout-seconds 60 \
    --root-command-json "$root_command_json" \
    --root-args-json '[]' \
    --root-prompt-mode stdin \
    --subcall-command-json "$subcall_command_json" \
    --subcall-args-json '[]' \
    --subcall-prompt-mode stdin \
    --require-citations true \
    --format json
  [ "$status" -ne 0 ]

  run jq -r '.error_code' "$output_dir/result.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sandbox_violation" ]
}

@test "rlms REPL worker enforces subcall depth limits" {
  local context_file_list="$TEMP_DIR/context-files.txt"
  printf '%s\n' "$SAMPLE_CONTEXT_FILE" > "$context_file_list"
  local output_dir="$TEMP_DIR/rlms-depth-fail"
  local root_command_json
  root_command_json=$(jq -cn --arg cmd "$ROOT_DEPTH_LLM" '[$cmd]')
  local subcall_command_json
  subcall_command_json=$(jq -cn --arg cmd "$SUBCALL_SUCCESS_LLM" '[$cmd]')

  run "$PROJECT_ROOT/scripts/rlms" \
    --repo "$TEMP_DIR" \
    --loop-id rlms-loop \
    --role reviewer \
    --iteration 1 \
    --context-file-list "$context_file_list" \
    --output-dir "$output_dir" \
    --max-steps 5 \
    --max-depth 1 \
    --timeout-seconds 60 \
    --root-command-json "$root_command_json" \
    --root-args-json '[]' \
    --root-prompt-mode stdin \
    --subcall-command-json "$subcall_command_json" \
    --subcall-args-json '[]' \
    --subcall-prompt-mode stdin \
    --require-citations true \
    --format json
  [ "$status" -ne 0 ]

  run jq -r '.error_code' "$output_dir/result.json"
  [ "$status" -eq 0 ]
  [ "$output" = "limit_exceeded" ]

  run jq -r '.error' "$output_dir/result.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "depth exceeded" ]]
}
