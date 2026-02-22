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

  # Initialize a git repository so lifecycle gating has a mainline ref.
  git -C "$TEMP_DIR" init -q -b main
  git -C "$TEMP_DIR" config user.email "test@example.com"
  git -C "$TEMP_DIR" config user.name "Test User"
  echo "# temp repo" > "$TEMP_DIR/README.md"
  git -C "$TEMP_DIR" add README.md
  git -C "$TEMP_DIR" commit -q -m "init"
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

@test "validate --static fails when tests are enabled with empty commands" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo runner"]
    }
  },
  "loops": [{
    "id": "tests-empty",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "on_promise", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": {"reviewer": {"runner": "shell"}}
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json" --static
  [ "$status" -ne 0 ]
  [[ "$output" =~ "expected at least 1 items" || "$output" =~ "TESTS_CONFIG_INVALID" ]]
}

@test "validate --static fails when tests commands are blank strings" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo runner"]
    }
  },
  "loops": [{
    "id": "tests-blank",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "every", "commands": ["   "]},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": {"reviewer": {"runner": "shell"}}
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json" --static
  [ "$status" -ne 0 ]
  [[ "$output" =~ "TESTS_CONFIG_INVALID" ]]
}

@test "validate --static fails when prerequisites are required but checks are empty" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo runner"]
    }
  },
  "loops": [{
    "id": "prereq-empty",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "prerequisites": {"enabled": true, "require_on_completion": true, "checks": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": {"reviewer": {"runner": "shell"}}
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json" --static
  [ "$status" -ne 0 ]
  [[ "$output" =~ "PREREQUISITES_CONFIG_INVALID" ]]
}

@test "validate --static accepts prerequisites when checks are valid" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo runner"]
    }
  },
  "loops": [{
    "id": "prereq-valid",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 10,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "prerequisites": {
      "enabled": true,
      "require_on_completion": true,
      "checks": [
        {"type": "file_exists", "path": ".superloop/specs/test.md"},
        {"type": "file_nonempty", "path": ".superloop/specs/test.md", "min_chars": 3}
      ]
    },
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": {"reviewer": {"runner": "shell"}}
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json" --static
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok: static analysis passed" ]]
}

@test "prerequisite-verifier fails on unchecked markdown checklist items" {
  cat > "$TEMP_DIR/phase.md" << 'EOF'
# Phase
- [ ] unresolved item
EOF

  local cfg='{"checks":[{"id":"phase","type":"markdown_checklist_complete","path":"phase.md"}]}'
  run "$PROJECT_ROOT/scripts/prerequisite-verifier.js" --repo "$TEMP_DIR" --config "$cfg"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "\"reason\":\"unchecked_items_remaining\"" ]]
}

@test "prerequisite-verifier passes when placeholders are absent and content is present" {
  cat > "$TEMP_DIR/jtbd.md" << 'EOF'
| Segment ID | Segment Name |
| --- | --- |
| US-001 | Core builder |
EOF

  local cfg='{"checks":[{"id":"no-placeholders","type":"file_regex_absent","path":"jtbd.md","pattern":"\\| US-00[1-3] \\|\\s*\\|"},{"id":"has-segment","type":"file_contains_all","path":"jtbd.md","needles":["Core builder"]}]}'
  run "$PROJECT_ROOT/scripts/prerequisite-verifier.js" --repo "$TEMP_DIR" --config "$cfg"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\"ok\":true" ]]
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

@test "validate accepts delegation configuration with legacy and explicit wake labels" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "shell": {
      "command": ["bash"],
      "args": ["-lc", "echo runner"]
    }
  },
  "loops": [{
    "id": "delegation-valid",
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
    "delegation": {
      "enabled": true,
      "dispatch_mode": "parallel",
      "wake_policy": "after_all",
      "max_children": 3,
      "max_parallel": 2,
      "max_waves": 2,
      "child_timeout_seconds": 180,
      "retry_limit": 1,
      "roles": {
        "planner": {
          "enabled": true,
          "mode": "reconnaissance"
        },
        "implementer": {
          "enabled": true,
          "wake_policy": "on_wave_complete",
          "max_parallel": 2
        },
        "tester": {
          "enabled": true,
          "wake_policy": "immediate"
        }
      }
    },
    "roles": {"implementer": {"runner": "shell"}, "reviewer": {"runner": "shell"}}
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" validate --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok" ]]
}

@test "runner-smoke fails for native claude config using -C" {
  mkdir -p "$TEMP_DIR/bin"
  cat > "$TEMP_DIR/bin/claude" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  echo '{"loggedIn": true}'
  exit 0
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "claude 1.0.0"
  exit 0
fi
echo "ok"
exit 0
EOF
  chmod +x "$TEMP_DIR/bin/claude"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "claude": {
      "command": ["claude"],
      "args": ["--dangerously-skip-permissions", "--print", "-C", "{repo}", "-"],
      "prompt_mode": "stdin"
    }
  },
  "loops": []
}
EOF

  run env PATH="$TEMP_DIR/bin:$PATH" "$PROJECT_ROOT/superloop.sh" runner-smoke --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "PROBE_RUNNER_ARGS_INVALID" ]]
}

@test "runner-smoke passes for native claude config with --print and auth" {
  mkdir -p "$TEMP_DIR/bin"
  cat > "$TEMP_DIR/bin/claude" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  echo '{"loggedIn": true}'
  exit 0
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "claude 1.0.0"
  exit 0
fi
echo "ok"
exit 0
EOF
  chmod +x "$TEMP_DIR/bin/claude"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "claude": {
      "command": ["claude"],
      "args": ["--dangerously-skip-permissions", "--print", "-"],
      "prompt_mode": "stdin"
    }
  },
  "loops": []
}
EOF

  run env PATH="$TEMP_DIR/bin:$PATH" "$PROJECT_ROOT/superloop.sh" runner-smoke --repo "$TEMP_DIR" --schema "$PROJECT_ROOT/schema/config.schema.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok: runner smoke checks passed" ]]
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
# Lifecycle Audit Command
# =============================================================================

@test "lifecycle-audit passes on clean repository and writes JSON output" {
  git -C "$TEMP_DIR" checkout -q main
  echo "base" > "$TEMP_DIR/README.md"
  git -C "$TEMP_DIR" add README.md
  git -C "$TEMP_DIR" commit -q -m "init"

  local out_json="$TEMP_DIR/lifecycle-report.json"
  run "$PROJECT_ROOT/superloop.sh" lifecycle-audit --repo "$TEMP_DIR" --feature-prefix "feat/" --main-ref main --json-out "$out_json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ahead_without_pr: 0" ]]
  [[ "$output" =~ "behind_and_dirty_worktree: 0" ]]
  [ -f "$out_json" ]

  run jq -r '.status' "$out_json"
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "lifecycle-audit strict fails on stale merged local feature branch" {
  git -C "$TEMP_DIR" checkout -q main
  echo "base" > "$TEMP_DIR/README.md"
  git -C "$TEMP_DIR" add README.md
  git -C "$TEMP_DIR" commit -q -m "init"

  git -C "$TEMP_DIR" checkout -q -b feat/lifecycle-stale
  echo "feature" > "$TEMP_DIR/feature.txt"
  git -C "$TEMP_DIR" add feature.txt
  git -C "$TEMP_DIR" commit -q -m "feature"

  git -C "$TEMP_DIR" checkout -q main
  git -C "$TEMP_DIR" merge -q --no-ff feat/lifecycle-stale -m "merge feature"

  run "$PROJECT_ROOT/superloop.sh" lifecycle-audit --repo "$TEMP_DIR" --feature-prefix "feat/lifecycle" --main-ref main --strict
  [ "$status" -ne 0 ]
  [[ "$output" =~ "stale_merged_local_branch: 1" ]]
}

@test "lifecycle-audit strict fails when feature worktree is behind and dirty" {
  git -C "$TEMP_DIR" checkout -q main
  echo "base" > "$TEMP_DIR/README.md"
  git -C "$TEMP_DIR" add README.md
  git -C "$TEMP_DIR" commit -q -m "init"

  git -C "$TEMP_DIR" branch feat/lifecycle-drift
  git -C "$TEMP_DIR" worktree add -q "$TEMP_DIR/wt-drift" feat/lifecycle-drift

  echo "main-update" >> "$TEMP_DIR/README.md"
  git -C "$TEMP_DIR" add README.md
  git -C "$TEMP_DIR" commit -q -m "main update"

  echo "dirty-change" >> "$TEMP_DIR/wt-drift/README.md"

  run "$PROJECT_ROOT/superloop.sh" lifecycle-audit --repo "$TEMP_DIR" --feature-prefix "feat/lifecycle" --main-ref main --strict
  [ "$status" -ne 0 ]
  [[ "$output" =~ "behind_and_dirty_worktree: 1" ]]
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

@test "init scaffolds codex-only runners and role mappings" {
  INIT_DIR="$(mktemp -d)"

  run "$PROJECT_ROOT/superloop.sh" init --repo "$INIT_DIR"
  [ "$status" -eq 0 ]

  run jq -r '.runners | keys | join(",")' "$INIT_DIR/.superloop/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]

  run jq -r '.loops[0].roles.implementer.runner' "$INIT_DIR/.superloop/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]

  run jq -r '.loops[0].roles.tester.runner' "$INIT_DIR/.superloop/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]

  run jq -e '.runners["claude-vanilla"] == null and .runners["claude-glm-mantic"] == null' "$INIT_DIR/.superloop/config.json"
  [ "$status" -eq 0 ]

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

@test "run --dry-run resolves lifecycle main ref to HEAD on detached checkout" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "-"]
    }
  },
  "loops": [{
    "id": "detached-head-loop",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 3,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "lifecycle": {
      "enabled": true,
      "require_on_completion": true,
      "strict": true,
      "block_on_failure": true,
      "feature_prefix": "feat/",
      "main_ref": "origin/main",
      "no_fetch": true
    },
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": ["planner", "implementer", "tester", "reviewer"]
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  git -C "$TEMP_DIR" checkout -q --detach HEAD
  git -C "$TEMP_DIR" branch -D main >/dev/null
  run git -C "$TEMP_DIR" rev-parse --verify "main^{commit}"
  [ "$status" -ne 0 ]

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop detached-head-loop --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dry-run summary (detached-head-loop)" ]]
}

@test "run blocks reentrant invocation for the same active loop id" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["-lc", "cat >/dev/null"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "reentrant-loop",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 5,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  cat > "$TEMP_DIR/.superloop/state.json" << 'EOF'
{
  "active": true,
  "loop_index": 0,
  "iteration": 2,
  "current_loop_id": "reentrant-loop",
  "updated_at": "2026-02-20T00:00:00Z"
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop reentrant-loop --skip-validate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "reentrant run blocked" ]]
  [[ "$output" =~ "reentrant-loop" ]]
}

@test "cancel stops active run process and clears active-run metadata" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["-lc", "sleep 120"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "cancel-loop",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 5,
    "completion_promise": "DONE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop cancel-loop --skip-validate >"$TEMP_DIR/run.log" 2>&1 &
  local run_pid=$!

  local active_file="$TEMP_DIR/.superloop/active-run.json"
  local seen_active=0
  for _ in $(seq 1 100); do
    if [[ -f "$active_file" ]]; then
      seen_active=1
      break
    fi
    sleep 0.1
  done
  [ "$seen_active" -eq 1 ]

  run "$PROJECT_ROOT/superloop.sh" cancel --repo "$TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Cancelled loop state" ]]

  local exited=0
  for _ in $(seq 1 30); do
    if ! kill -0 "$run_pid" 2>/dev/null; then
      exited=1
      break
    fi
    sleep 0.2
  done

  if [[ "$exited" -ne 1 ]]; then
    kill -KILL "$run_pid" 2>/dev/null || true
  fi

  [ "$exited" -eq 1 ]
  [ ! -f "$TEMP_DIR/.superloop/active-run.json" ]
  [ ! -f "$TEMP_DIR/.superloop/state.json" ]
}

@test "run --dry-run accepts delegation wake alias values" {
  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["tests/helpers/mock-runner.sh", "success"],
      "args": [],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-dry-run",
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
    "delegation": {
      "enabled": true,
      "dispatch_mode": "parallel",
      "wake_policy": "after_all",
      "roles": {
        "implementer": {"enabled": true, "wake_policy": "immediate"}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-dry-run --dry-run
  [ "$status" -eq 0 ]
}

@test "run executes implementer delegation request and emits child artifacts/events" {
  cat > "$TEMP_DIR/mock-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
cat >/dev/null
cat > "$OUTPUT_FILE" << 'OUT'
Delegated execution complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/mock-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/mock-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-live",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 2,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 2,
      "max_parallel": 2,
      "max_waves": 2,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-live/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-live/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-1",
          "prompt": "Draft implementation notes for delegated task",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-live
  [ "$status" -eq 0 ]

  local delegation_status="$TEMP_DIR/.superloop/loops/delegation-live/delegation/iter-1/implementer/status.json"
  local delegation_summary="$TEMP_DIR/.superloop/loops/delegation-live/delegation/iter-1/implementer/summary.md"
  local delegation_child_status="$TEMP_DIR/.superloop/loops/delegation-live/delegation/iter-1/implementer/children/wave-1/task-1/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-live/events.jsonl"

  [ -f "$delegation_status" ]
  [ -f "$delegation_summary" ]
  [ -f "$delegation_child_status" ]
  [ -f "$events_file" ]

  run jq -r '.status' "$delegation_status"
  [ "$status" -eq 0 ]
  [ "$output" = "executed_ok" ]

  run jq -r '.execution.executed_children' "$delegation_status"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.limits.max_parallel' "$delegation_status"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.scheduler.state_model' "$delegation_status"
  [ "$status" -eq 0 ]
  [ "$output" = "pending->running->terminal" ]

  run jq -r '.execution.terminal_state_counts.completed' "$delegation_status"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.execution.terminal_state_counts.skipped' "$delegation_status"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.terminal_state' "$delegation_child_status"
  [ "$status" -eq 0 ]
  [ "$output" = "completed" ]

  run jq -r '.implemented' "$delegation_status"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -lc "grep -q '\"event\":\"delegation_child_start\"' '$events_file'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q '\"event\":\"delegation_child_end\"' '$events_file'"
  [ "$status" -eq 0 ]
}

@test "run generates implementer delegation request via request pass and executes children" {
  cat > "$TEMP_DIR/handshake-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"

if printf '%s' "$PROMPT" | grep -q "Write delegation request JSON to this exact file path:"; then
  REQUEST_PATH=$(printf '%s\n' "$PROMPT" | awk '/Write delegation request JSON to this exact file path:/{getline; print; exit}')
  REQUEST_PATH="$(echo "$REQUEST_PATH" | xargs)"
  mkdir -p "$(dirname "$REQUEST_PATH")"
  cat > "$REQUEST_PATH" << 'JSON'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "auto-task",
          "prompt": "Generated from request pass",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
JSON
  cat > "$OUTPUT_FILE" << 'OUT'
Delegation request generated.
OUT
  exit 0
fi

cat > "$OUTPUT_FILE" << 'OUT'
Normal role completion.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/handshake-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/handshake-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-handshake",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 2,
      "max_waves": 2,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-handshake
  [ "$status" -eq 0 ]

  local request_file="$TEMP_DIR/.superloop/loops/delegation-handshake/delegation/iter-1/implementer/request.json"
  local status_file="$TEMP_DIR/.superloop/loops/delegation-handshake/delegation/iter-1/implementer/status.json"
  local summary_file="$TEMP_DIR/.superloop/loops/delegation-handshake/delegation/iter-1/implementer/summary.md"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-handshake/events.jsonl"

  [ -f "$request_file" ]
  [ -f "$status_file" ]
  [ -f "$summary_file" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -q '\"event\":\"delegation_request_pass_start\"' '$events_file'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q '\"event\":\"delegation_request_pass_end\"' '$events_file'"
  [ "$status" -eq 0 ]
}

@test "run continues safely when implementer delegation request is invalid JSON" {
  cat > "$TEMP_DIR/invalid-request-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
cat >/dev/null
cat > "$OUTPUT_FILE" << 'OUT'
Role finished.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/invalid-request-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/invalid-request-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-invalid-request",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 2,
      "max_waves": 2,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-invalid-request/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-invalid-request/delegation/requests/implementer.json" << 'EOF'
{ invalid json
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-invalid-request
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-invalid-request/delegation/iter-1/implementer/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-invalid-request/events.jsonl"

  [ -f "$status_file" ]
  run jq -r '.status' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "request_invalid" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run bash -lc "grep -q '\"event\":\"delegation_child_start\"' '$events_file'"
  [ "$status" -ne 0 ]
}

@test "implementer prompt includes delegation status and summary references" {
  cat > "$TEMP_DIR/prompt-ref-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
cat >/dev/null
cat > "$OUTPUT_FILE" << 'OUT'
Role done.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/prompt-ref-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/prompt-ref-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-prompt-ref",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-prompt-ref/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-prompt-ref/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-1",
          "prompt": "Produce child output for prompt reference test",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-prompt-ref
  [ "$status" -eq 0 ]

  local implementer_prompt="$TEMP_DIR/.superloop/loops/delegation-prompt-ref/prompts/implementer.md"
  local summary_file_rel=".superloop/loops/delegation-prompt-ref/delegation/iter-1/implementer/summary.md"

  [ -f "$implementer_prompt" ]
  run bash -lc "grep -q -- '- Delegation status: ' '$implementer_prompt'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q -- '- Delegation summary: $summary_file_rel' '$implementer_prompt'"
  [ "$status" -eq 0 ]
}

@test "run executes delegated children in parallel wave mode" {
  cat > "$TEMP_DIR/parallel-wave-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  sleep 2
fi
cat > "$OUTPUT_FILE" << 'OUT'
Parallel wave runner done.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/parallel-wave-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/parallel-wave-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-parallel-wave",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "parallel",
      "wake_policy": "on_wave_complete",
      "max_children": 2,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-parallel-wave/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-parallel-wave/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {"id": "task-1", "prompt": "Parallel child 1"},
        {"id": "task-2", "prompt": "Parallel child 2"}
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-parallel-wave
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-parallel-wave/delegation/iter-1/implementer/status.json"
  local child_status_1="$TEMP_DIR/.superloop/loops/delegation-parallel-wave/delegation/iter-1/implementer/children/wave-1/task-1/status.json"
  local child_status_2="$TEMP_DIR/.superloop/loops/delegation-parallel-wave/delegation/iter-1/implementer/children/wave-1/task-2/status.json"
  local child_usage_1="$TEMP_DIR/.superloop/loops/delegation-parallel-wave/delegation/iter-1/implementer/children/wave-1/task-1/usage.jsonl"
  local child_usage_2="$TEMP_DIR/.superloop/loops/delegation-parallel-wave/delegation/iter-1/implementer/children/wave-1/task-2/usage.jsonl"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-parallel-wave/events.jsonl"
  [ -f "$status_file" ]
  [ -f "$child_status_1" ]
  [ -f "$child_status_2" ]
  [ -f "$child_usage_1" ]
  [ -f "$child_usage_2" ]

  run jq -r '.dispatch_mode_effective' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "parallel" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.limits.max_parallel' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run bash -lc "grep -q '\"event\":\"delegation_wave_dispatch\"' '$events_file'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q '\"event\":\"delegation_wave_queue_drain\"' '$events_file'"
  [ "$status" -eq 0 ]

  # Use child completion timestamps to assert concurrent execution without relying on host load.
  run jq -n \
    --slurpfile c1 "$child_status_1" \
    --slurpfile c2 "$child_status_2" \
    '
      (($c1[0].generated_at | fromdateiso8601) - ($c2[0].generated_at | fromdateiso8601)) as $diff
      | if $diff < 0 then -$diff else $diff end
    '
  [ "$status" -eq 0 ]
  local ts_diff="${output%%.*}"
  [ "$ts_diff" -le 2 ]
}

@test "run enforces max_parallel=1 as sequential cap in parallel mode" {
  cat > "$TEMP_DIR/parallel-cap-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  sleep 2
fi
cat > "$OUTPUT_FILE" << 'OUT'
Parallel cap runner done.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/parallel-cap-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/parallel-cap-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-parallel-cap-one",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "parallel",
      "wake_policy": "on_wave_complete",
      "max_children": 3,
      "max_parallel": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-parallel-cap-one/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-parallel-cap-one/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {"id": "task-1", "prompt": "Parallel child 1"},
        {"id": "task-2", "prompt": "Parallel child 2"},
        {"id": "task-3", "prompt": "Parallel child 3"}
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-parallel-cap-one
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-one/delegation/iter-1/implementer/status.json"
  local child_status_1="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-one/delegation/iter-1/implementer/children/wave-1/task-1/status.json"
  local child_status_2="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-one/delegation/iter-1/implementer/children/wave-1/task-2/status.json"
  local child_status_3="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-one/delegation/iter-1/implementer/children/wave-1/task-3/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-one/events.jsonl"

  [ -f "$status_file" ]
  [ -f "$child_status_1" ]
  [ -f "$child_status_2" ]
  [ -f "$child_status_3" ]

  run jq -r '.limits.max_parallel' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.scheduler.invariants.cap_enforced' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -n \
    --slurpfile c1 "$child_status_1" \
    --slurpfile c2 "$child_status_2" \
    --slurpfile c3 "$child_status_3" \
    '[($c1[0].generated_at | fromdateiso8601), ($c2[0].generated_at | fromdateiso8601), ($c3[0].generated_at | fromdateiso8601)] | (max - min)'
  [ "$status" -eq 0 ]
  local ts_span="${output%%.*}"
  [ "$ts_span" -ge 4 ]

  run bash -lc "grep -q '\"event\":\"delegation_wave_dispatch\"' '$events_file'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q '\"event\":\"delegation_wave_queue_drain\"' '$events_file'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q '\"phase\":\"cap_gate\"' '$events_file'"
  [ "$status" -eq 0 ]
}

@test "run enforces max_parallel=2 bounded overlap in parallel mode" {
  cat > "$TEMP_DIR/parallel-cap-two-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  sleep 2
fi
cat > "$OUTPUT_FILE" << 'OUT'
Parallel cap two runner done.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/parallel-cap-two-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/parallel-cap-two-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-parallel-cap-two",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "parallel",
      "wake_policy": "on_wave_complete",
      "max_children": 3,
      "max_parallel": 2,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-parallel-cap-two/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-parallel-cap-two/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {"id": "task-1", "prompt": "Parallel child 1"},
        {"id": "task-2", "prompt": "Parallel child 2"},
        {"id": "task-3", "prompt": "Parallel child 3"}
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-parallel-cap-two
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-two/delegation/iter-1/implementer/status.json"
  local child_status_1="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-two/delegation/iter-1/implementer/children/wave-1/task-1/status.json"
  local child_status_2="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-two/delegation/iter-1/implementer/children/wave-1/task-2/status.json"
  local child_status_3="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-two/delegation/iter-1/implementer/children/wave-1/task-3/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-parallel-cap-two/events.jsonl"

  [ -f "$status_file" ]
  [ -f "$child_status_1" ]
  [ -f "$child_status_2" ]
  [ -f "$child_status_3" ]
  [ -f "$events_file" ]

  run jq -r '.limits.max_parallel' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -s '[.[] | select(.event == "delegation_wave_dispatch") | .data.active_workers] | max' "$events_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -s '[.[] | select(.event == "delegation_wave_dispatch") | .data.active_workers] | any(. > 2)' "$events_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "run adapts delegated execution on child completion and stops remaining work" {
  cat > "$TEMP_DIR/adaptive-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"

if printf '%s' "$PROMPT" | grep -q "Write adaptation decision JSON to this exact file path:"; then
  DECISION_PATH=$(printf '%s\n' "$PROMPT" | awk '/Write adaptation decision JSON to this exact file path:/{getline; print; exit}')
  DECISION_PATH="$(echo "$DECISION_PATH" | xargs)"
  mkdir -p "$(dirname "$DECISION_PATH")"
  cat > "$DECISION_PATH" << 'JSON'
{
  "continue_wave": false,
  "continue_delegation": false,
  "reason": "First child surfaced enough signal"
}
JSON
  cat > "$OUTPUT_FILE" << 'OUT'
Adaptation decision written.
OUT
  exit 0
fi

if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  cat > "$OUTPUT_FILE" << 'OUT'
Delegated child output.
OUT
  exit 0
fi

cat > "$OUTPUT_FILE" << 'OUT'
Role complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/adaptive-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/adaptive-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-adaptive-child-complete",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_child_complete",
      "max_children": 3,
      "max_waves": 2,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-adaptive-child-complete/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-adaptive-child-complete/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {"id": "task-1", "prompt": "Analyze initial signal"},
        {"id": "task-2", "prompt": "Follow-up branch"},
        {"id": "task-3", "prompt": "Deep dive branch"}
      ]
    },
    {
      "id": "wave-2",
      "children": [
        {"id": "task-4", "prompt": "Would run only if delegation continues"}
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-adaptive-child-complete
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-adaptive-child-complete/delegation/iter-1/implementer/status.json"
  local adaptation_decision_file="$TEMP_DIR/.superloop/loops/delegation-adaptive-child-complete/delegation/iter-1/implementer/adaptation/wave-1/after-child-1.decision.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-adaptive-child-complete/events.jsonl"

  [ -f "$status_file" ]
  [ -f "$adaptation_decision_file" ]

  run jq -r '.wake_policy_effective' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "on_child_complete" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.execution.skipped_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.adaptation.status' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "enabled" ]

  run jq -r '.adaptation.counters.replans_attempted' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.adaptation.counters.replans_applied' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -q '\"event\":\"delegation_adaptation_start\"' '$events_file'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q '\"event\":\"delegation_adaptation_end\"' '$events_file'"
  [ "$status" -eq 0 ]
}

@test "run adapts on child completion in parallel dispatch without wake policy coercion" {
  cat > "$TEMP_DIR/adaptive-parallel-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"

PROMPT="$(cat)"

if printf '%s' "$PROMPT" | grep -q "Write adaptation decision JSON to this exact file path:"; then
  DECISION_PATH=$(printf '%s\n' "$PROMPT" | awk '/Write adaptation decision JSON to this exact file path:/{getline; print; exit}')
  DECISION_PATH="$(echo "$DECISION_PATH" | xargs)"
  mkdir -p "$(dirname "$DECISION_PATH")"
  cat > "$DECISION_PATH" << 'JSON'
{
  "continue_wave": false,
  "continue_delegation": false,
  "reason": "First completion is sufficient"
}
JSON
  cat > "$OUTPUT_FILE" << 'OUT'
Adaptation decision written.
OUT
  exit 0
fi

cat > "$OUTPUT_FILE" << 'OUT'
Role complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/adaptive-parallel-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/adaptive-parallel-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-adaptive-parallel",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "parallel",
      "wake_policy": "on_child_complete",
      "max_children": 3,
      "max_parallel": 3,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-adaptive-parallel/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-adaptive-parallel/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {"id": "task-1", "prompt": "Parallel child 1"},
        {"id": "task-2", "prompt": "Parallel child 2"},
        {"id": "task-3", "prompt": "Parallel child 3"}
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-adaptive-parallel
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-adaptive-parallel/delegation/iter-1/implementer/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-adaptive-parallel/events.jsonl"

  [ -f "$status_file" ]

  run jq -r '.wake_policy_effective' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "on_child_complete" ]

  run jq -r '.adaptation.status' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "enabled" ]

  run jq -r '.adaptation.reason' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "on_child_complete_parallel" ]

  run jq -r '.adaptation.counters.replans_attempted' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.adaptation.counters.replans_applied' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.execution.policy_reason' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "adaptation_decision" ]

  run jq -r '.execution.completion_order | length' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run jq -r '.execution.aggregation_order | length' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]

  run bash -lc "find '$TEMP_DIR/.superloop/loops/delegation-adaptive-parallel/delegation/iter-1/implementer/adaptation' -name '*.decision.json' | wc -l | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -q '\"event\":\"delegation_adaptation_start\"' '$events_file'"
  [ "$status" -eq 0 ]
}

@test "run fails role when delegation failure_policy is fail_role" {
  cat > "$TEMP_DIR/fail-role-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  cat > "$OUTPUT_FILE" << 'OUT'
Child failed.
OUT
  exit 9
fi
cat > "$OUTPUT_FILE" << 'OUT'
Role complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/fail-role-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/fail-role-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-fail-role",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "failure_policy": "fail_role",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-fail-role/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-fail-role/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {"id": "task-1", "prompt": "This child should fail"}
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-fail-role
  [ "$status" -ne 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-fail-role/delegation/iter-1/implementer/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-fail-role/events.jsonl"
  [ -f "$status_file" ]

  run jq -r '.policy.failure_policy' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "fail_role" ]

  run jq -r '.fail_role.triggered' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.execution.failed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -q '\"event\":\"delegation_fail_role\"' '$events_file'"
  [ "$status" -eq 0 ]
}

@test "run applies delegation retry backoff policy on child retries" {
  cat > "$TEMP_DIR/retry-backoff-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  ATTEMPT_FILE="$(dirname "$OUTPUT_FILE")/attempt-count.txt"
  ATTEMPT=0
  if [[ -f "$ATTEMPT_FILE" ]]; then
    ATTEMPT="$(cat "$ATTEMPT_FILE")"
  fi
  ATTEMPT=$((ATTEMPT + 1))
  printf '%s\n' "$ATTEMPT" > "$ATTEMPT_FILE"
  if [[ "$ATTEMPT" -lt 2 ]]; then
    cat > "$OUTPUT_FILE" << 'OUT'
First attempt failed.
OUT
    exit 7
  fi
  cat > "$OUTPUT_FILE" << 'OUT'
Second attempt succeeded.
OUT
  exit 0
fi
cat > "$OUTPUT_FILE" << 'OUT'
Role complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/retry-backoff-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/retry-backoff-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-retry-backoff",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "failure_policy": "warn_and_continue",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 1,
      "retry_backoff_seconds": 1,
      "retry_backoff_max_seconds": 1,
      "roles": {
        "implementer": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-retry-backoff/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-retry-backoff/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {"id": "task-1", "prompt": "This child should retry once"}
      ]
    }
  ]
}
EOF

  local started_at ended_at elapsed
  started_at=$(date +%s)
  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-retry-backoff
  ended_at=$(date +%s)
  elapsed=$((ended_at - started_at))
  [ "$status" -eq 0 ]
  [ "$elapsed" -ge 1 ]

  local child_status_file="$TEMP_DIR/.superloop/loops/delegation-retry-backoff/delegation/iter-1/implementer/children/wave-1/task-1/status.json"
  [ -f "$child_status_file" ]

  run jq -r '.attempts' "$child_status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run jq -r '.status' "$child_status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "run executes planner delegation in reconnaissance mode and emits artifacts/events" {
  cat > "$TEMP_DIR/planner-recon-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
cat >/dev/null
cat > "$OUTPUT_FILE" << 'OUT'
Planner reconnaissance run complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/planner-recon-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/planner-recon-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-planner-recon",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "planner": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-planner-recon/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-planner-recon/delegation/requests/planner.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "research-scan",
          "prompt": "Survey recent architectural risks and summarize findings with file references.",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-planner-recon
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon/delegation/iter-1/planner/status.json"
  local child_prompt="$TEMP_DIR/.superloop/loops/delegation-planner-recon/delegation/iter-1/planner/children/wave-1/research-scan/prompt.md"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon/events.jsonl"

  [ -f "$status_file" ]
  [ -f "$child_prompt" ]
  [ -f "$events_file" ]

  run jq -r '.enabled' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.mode' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "reconnaissance" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -q 'Reconnaissance-only mode:' '$child_prompt'"
  [ "$status" -eq 0 ]

  run jq -r 'select(.event == "delegation_child_start" and .role == "planner") | .event' "$events_file"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "run generates planner delegation request via request pass and executes reconnaissance child" {
  cat > "$TEMP_DIR/planner-request-pass-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"

if printf '%s' "$PROMPT" | grep -q "Write delegation request JSON to this exact file path:"; then
  REQUEST_PATH=$(printf '%s\n' "$PROMPT" | awk '/Write delegation request JSON to this exact file path:/{getline; print; exit}')
  REQUEST_PATH="$(echo "$REQUEST_PATH" | xargs)"
  mkdir -p "$(dirname "$REQUEST_PATH")"
  cat > "$REQUEST_PATH" << 'JSON'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "planner-probe",
          "prompt": "Read current docs and summarize delegation concerns.",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
JSON
  cat > "$OUTPUT_FILE" << 'OUT'
Planner request generated.
OUT
  exit 0
fi

cat > "$OUTPUT_FILE" << 'OUT'
Role complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/planner-request-pass-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/planner-request-pass-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-planner-request-pass",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "planner": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-planner-request-pass
  [ "$status" -eq 0 ]

  local request_file="$TEMP_DIR/.superloop/loops/delegation-planner-request-pass/delegation/iter-1/planner/request.json"
  local status_file="$TEMP_DIR/.superloop/loops/delegation-planner-request-pass/delegation/iter-1/planner/status.json"
  local child_prompt="$TEMP_DIR/.superloop/loops/delegation-planner-request-pass/delegation/iter-1/planner/children/wave-1/planner-probe/prompt.md"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-planner-request-pass/events.jsonl"

  [ -f "$request_file" ]
  [ -f "$status_file" ]
  [ -f "$child_prompt" ]

  run jq -r '.mode' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "reconnaissance" ]

  run jq -r '.execution.executed_children' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -q 'Reconnaissance-only mode:' '$child_prompt'"
  [ "$status" -eq 0 ]

  run jq -r 'select(.event == "delegation_request_pass_start" and .role == "planner") | .event' "$events_file"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "planner reconnaissance violation downgrades child when failure_policy is warn_and_continue" {
  cat > "$TEMP_DIR/planner-recon-violation-warn.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  CONTEXT_FILE=$(printf '%s\n' "$PROMPT" | awk '/Context files \(read as needed\):/{getline; gsub(/^- /,"",$0); print; exit}')
  REPO_ROOT="${CONTEXT_FILE%%/.superloop/*}"
  if [[ -n "$REPO_ROOT" ]]; then
    printf 'recon touch\n' > "$REPO_ROOT/recon-touch.txt"
  fi
fi
cat > "$OUTPUT_FILE" << 'OUT'
Role done.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/planner-recon-violation-warn.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/planner-recon-violation-warn.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-planner-recon-violation-warn",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "failure_policy": "warn_and_continue",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "planner": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-warn/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-warn/delegation/requests/planner.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-1",
          "prompt": "Recon task expected to stay read-only",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-planner-recon-violation-warn
  [ "$status" -eq 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-warn/delegation/iter-1/planner/status.json"
  local child_status="$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-warn/delegation/iter-1/planner/children/wave-1/task-1/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-warn/events.jsonl"
  [ -f "$status_file" ]
  [ -f "$child_status" ]

  run jq -r '.mode' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "reconnaissance" ]

  run jq -r '.reconnaissance.violations' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.fail_role.triggered' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.status' "$child_status"
  [ "$status" -eq 0 ]
  [ "$output" = "policy_violation" ]

  run bash -lc "grep -q 'recon_violation_warned' '$status_file'"
  [ "$status" -eq 0 ]

  run jq -r 'select(.event == "delegation_recon_violation" and .role == "planner") | .event' "$events_file"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "planner reconnaissance violation defaults to fail_role when failure_policy is unset" {
  cat > "$TEMP_DIR/planner-recon-violation-default.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  CONTEXT_FILE=$(printf '%s\n' "$PROMPT" | awk '/Context files \(read as needed\):/{getline; gsub(/^- /,"",$0); print; exit}')
  REPO_ROOT="${CONTEXT_FILE%%/.superloop/*}"
  if [[ -n "$REPO_ROOT" ]]; then
    printf 'recon touch\n' > "$REPO_ROOT/recon-touch-default.txt"
  fi
fi
cat > "$OUTPUT_FILE" << 'OUT'
Role done.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/planner-recon-violation-default.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/planner-recon-violation-default.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-planner-recon-violation-default",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "planner": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-default/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-default/delegation/requests/planner.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-1",
          "prompt": "Recon task expected to stay read-only",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-planner-recon-violation-default
  [ "$status" -ne 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-default/delegation/iter-1/planner/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-default/events.jsonl"
  [ -f "$status_file" ]

  run jq -r '.policy.failure_policy' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "fail_role" ]

  run jq -r '.fail_role.triggered' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -lc "grep -q 'planner_recon_default_fail_role' '$status_file'"
  [ "$status" -eq 0 ]

  run jq -r 'select(.event == "delegation_fail_role" and .role == "planner") | .event' "$events_file"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "planner reconnaissance violation fails role when failure_policy is fail_role" {
  cat > "$TEMP_DIR/planner-recon-violation-fail.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
PROMPT="$(cat)"
if printf '%s' "$PROMPT" | grep -q "You are a delegated child agent in Superloop."; then
  CONTEXT_FILE=$(printf '%s\n' "$PROMPT" | awk '/Context files \(read as needed\):/{getline; gsub(/^- /,"",$0); print; exit}')
  REPO_ROOT="${CONTEXT_FILE%%/.superloop/*}"
  if [[ -n "$REPO_ROOT" ]]; then
    printf 'recon touch\n' > "$REPO_ROOT/recon-touch-fail.txt"
  fi
fi
cat > "$OUTPUT_FILE" << 'OUT'
Role done.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/planner-recon-violation-fail.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/planner-recon-violation-fail.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-planner-recon-violation-fail",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "failure_policy": "fail_role",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "planner": {"enabled": true}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-fail/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-fail/delegation/requests/planner.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-1",
          "prompt": "Recon task expected to stay read-only",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-planner-recon-violation-fail
  [ "$status" -ne 0 ]

  local status_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-fail/delegation/iter-1/planner/status.json"
  local events_file="$TEMP_DIR/.superloop/loops/delegation-planner-recon-violation-fail/events.jsonl"
  [ -f "$status_file" ]

  run jq -r '.reconnaissance.violations' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.fail_role.triggered' "$status_file"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run bash -lc "grep -q 'recon_violation_fail_role' '$status_file'"
  [ "$status" -eq 0 ]

  run jq -r 'select(.event == "delegation_recon_violation" and .role == "planner") | .event' "$events_file"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run jq -r 'select(.event == "delegation_fail_role" and .role == "planner") | .data.stop_reason' "$events_file"
  [ "$status" -eq 0 ]
  [ "$output" = "recon_violation_fail_role" ]
}

@test "run summary, timeline, and status summary include delegation rollup metrics" {
  cat > "$TEMP_DIR/delegation-rollup-runner.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT_FILE="${1:-/dev/stdout}"
cat >/dev/null
cat > "$OUTPUT_FILE" << 'OUT'
Role complete.
<promise>SUPERLOOP_COMPLETE</promise>
OUT
EOF
  chmod +x "$TEMP_DIR/delegation-rollup-runner.sh"

  cat > "$TEMP_DIR/.superloop/config.json" << 'EOF'
{
  "runners": {
    "mock": {
      "command": ["bash"],
      "args": ["{repo}/delegation-rollup-runner.sh", "{last_message_file}"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [{
    "id": "delegation-summary-rollup",
    "spec_file": ".superloop/specs/test.md",
    "max_iterations": 1,
    "completion_promise": "SUPERLOOP_COMPLETE",
    "checklists": [],
    "tests": {"mode": "disabled", "commands": []},
    "evidence": {"enabled": false, "require_on_completion": false, "artifacts": []},
    "approval": {"enabled": false, "require_on_completion": false},
    "reviewer_packet": {"enabled": false},
    "timeouts": {"enabled": false, "default": 300, "planner": 120, "implementer": 300, "tester": 300, "reviewer": 120},
    "stuck": {"enabled": false, "threshold": 3, "action": "report_and_stop", "ignore": []},
    "delegation": {
      "enabled": true,
      "dispatch_mode": "serial",
      "wake_policy": "on_wave_complete",
      "max_children": 1,
      "max_waves": 1,
      "child_timeout_seconds": 120,
      "retry_limit": 0,
      "roles": {
        "planner": {"enabled": false},
        "implementer": {"enabled": true},
        "tester": {"enabled": false},
        "reviewer": {"enabled": false}
      }
    },
    "roles": {
      "planner": {"runner": "mock"},
      "implementer": {"runner": "mock"},
      "tester": {"runner": "mock"},
      "reviewer": {"runner": "mock"}
    }
  }]
}
EOF

  mkdir -p "$TEMP_DIR/schema"
  cp "$PROJECT_ROOT/schema/config.schema.json" "$TEMP_DIR/schema/"
  echo "# Test Spec" > "$TEMP_DIR/.superloop/specs/test.md"

  mkdir -p "$TEMP_DIR/.superloop/loops/delegation-summary-rollup/delegation/requests"
  cat > "$TEMP_DIR/.superloop/loops/delegation-summary-rollup/delegation/requests/implementer.json" << 'EOF'
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-1",
          "prompt": "Delegated summary rollup task",
          "context_files": [".superloop/specs/test.md"]
        }
      ]
    }
  ]
}
EOF

  run "$PROJECT_ROOT/superloop.sh" run --repo "$TEMP_DIR" --loop delegation-summary-rollup
  [ "$status" -eq 0 ]

  local summary_file="$TEMP_DIR/.superloop/loops/delegation-summary-rollup/run-summary.json"
  local timeline_file="$TEMP_DIR/.superloop/loops/delegation-summary-rollup/timeline.md"
  [ -f "$summary_file" ]
  [ -f "$timeline_file" ]

  run jq -r '.entries[-1].delegation.enabled_roles' "$summary_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.entries[-1].delegation.executed_children' "$summary_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run jq -r '.entries[-1].delegation.failed_children' "$summary_file"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]

  run jq -r '.entries[-1].delegation.by_role.implementer.executed_children' "$summary_file"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run bash -lc "grep -q 'delegation_roles=' '$timeline_file'"
  [ "$status" -eq 0 ]
  run bash -lc "grep -q 'delegation_children=1' '$timeline_file'"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/superloop.sh" status --repo "$TEMP_DIR" --loop delegation-summary-rollup --summary
  [ "$status" -eq 0 ]
  [[ "$output" =~ delegation_enabled_roles=1 ]]
  [[ "$output" =~ delegation_children=1 ]]
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
