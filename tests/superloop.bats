#!/usr/bin/env bats

# Superloop test suite
# Run with: bats tests/

setup() {
  # Get the directory where the test file is located
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"

  # Create a temporary directory for test fixtures
  TEMP_DIR="$(mktemp -d)"

  # Create a minimal test repo structure
  mkdir -p "$TEMP_DIR/.superloop/specs"
  mkdir -p "$TEMP_DIR/.superloop/roles"

  # Copy role definitions
  cp -r "$PROJECT_ROOT/.superloop/roles/"* "$TEMP_DIR/.superloop/roles/" 2>/dev/null || true
}

teardown() {
  # Clean up temp directory
  rm -rf "$TEMP_DIR"
}

# =============================================================================
# Version and Help
# =============================================================================

@test "superloop --version shows version" {
  run "$PROJECT_ROOT/superloop.sh" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "superloop --help shows usage" {
  run "$PROJECT_ROOT/superloop.sh" --help
  # --help exits with 1 (by design - no command given)
  [[ "$output" =~ "Usage:" ]]
}

@test "superloop with no args shows usage" {
  run "$PROJECT_ROOT/superloop.sh"
  # No args exits with 1 (by design - no command given)
  [[ "$output" =~ "Usage:" ]]
}

# =============================================================================
# Config Validation
# =============================================================================

@test "validate succeeds with valid config" {
  # Create valid config
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    }
  },
  "loops": []
}
EOF

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok" ]]
}

@test "validate fails with invalid config" {
  # Create invalid config (has runners but loops has wrong type)
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto"]
    }
  },
  "loops": "not-an-array"
}
EOF

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -ne 0 ]
}

@test "validate fails with missing config" {
  rm -f "$TEMP_DIR/.superloop/config.json"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -ne 0 ]
}

@test "validate --static accepts valid rlms configuration" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo runner"]
    }
  },
  "loops": [{
    "id": "rlms-valid",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
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
      "mode": "hybrid",
      "request_keyword": "RLMS_REQUEST",
      "auto": {"max_lines": 1000, "max_estimated_tokens": 50000, "max_files": 10},
      "roles": {"reviewer": true},
      "limits": {"max_steps": 20, "max_depth": 2, "timeout_seconds": 120},
      "output": {"format": "json", "require_citations": true},
      "policy": {"force_on": false, "force_off": false, "fail_mode": "warn_and_continue"}
    },
    "roles": {"reviewer": {"runner": "shell"}}
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json" --static
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok: static analysis passed" ]]
}

@test "validate --static fails when rlms policy force_on and force_off are both true" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo runner"]
    }
  },
  "loops": [{
    "id": "rlms-invalid",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
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
      "mode": "hybrid",
      "request_keyword": "RLMS_REQUEST",
      "policy": {"force_on": true, "force_off": true, "fail_mode": "warn_and_continue"}
    },
    "roles": {"reviewer": {"runner": "shell"}}
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json" --static
  [ "$status" -ne 0 ]
  [[ "$output" =~ "RLMS_INVALID" ]]
}

# =============================================================================
# List Command
# =============================================================================

@test "list shows no loops when empty" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    }
  },
  "loops": []
}
EOF

  run "$PROJECT_ROOT/superloop.sh" list --repo "$TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No loops configured" ]]
}

@test "list shows configured loops" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    }
  },
  "loops": [{
    "id": "test-loop",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": ["planner", "implementer", "tester", "reviewer"]
  }]
}
EOF

  # Create spec file
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" list --repo "$TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "test-loop" ]]
}

# =============================================================================
# Status Command
# =============================================================================

@test "status works with no state" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    }
  },
  "loops": [{
    "id": "test-loop",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": ["planner", "implementer", "tester", "reviewer"]
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" status --repo "$TEMP_DIR"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Init Command
# =============================================================================

@test "init creates .superloop directory structure" {
  INIT_DIR="$(mktemp -d)"

  run "$PROJECT_ROOT/superloop.sh" init --repo "$INIT_DIR"
  [ "$status" -eq 0 ]
  [ -d "$INIT_DIR/.superloop" ]
  [ -d "$INIT_DIR/.superloop/roles" ]
  [ -f "$INIT_DIR/.superloop/config.json" ]

  rm -rf "$INIT_DIR"
}

# =============================================================================
# Dry Run
# =============================================================================

@test "run --dry-run works without runners" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    }
  },
  "loops": [{
    "id": "test-loop",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": ["planner", "implementer", "tester", "reviewer"]
  }]
}
EOF

  # Copy schema to test repo so it can be found
  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop test-loop --dry-run
  [ "$status" -eq 0 ]
}

# =============================================================================
# Role Defaults
# =============================================================================

@test "config with role_defaults validates" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    },
    "claude": {
      "command": ["claude"],
      "args": ["--dangerously-skip-permissions", "-C", "{repo}", "-"]
    }
  },
  "role_defaults": {
    "planner": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "max"},
    "implementer": {"runner": "claude", "model": "claude-sonnet-4-5-20250929", "thinking": "standard"},
    "tester": {"runner": "claude", "model": "claude-sonnet-4-5-20250929", "thinking": "standard"},
    "reviewer": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "max"}
  },
  "loops": []
}
EOF

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok" ]]
}

@test "config with per-role model and thinking validates" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    }
  },
  "loops": [{
    "id": "test-loop",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": {
      "planner": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "max"},
      "implementer": {"runner": "codex", "model": "gpt-5.1-codex", "thinking": "standard"},
      "tester": {"runner": "codex", "model": "gpt-5.1-codex-mini", "thinking": "low"},
      "reviewer": {"runner": "codex", "model": "gpt-5.2-codex", "thinking": "high"}
    }
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok" ]]
}
