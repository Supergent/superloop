init_cmd() {
  local repo="$1"
  local force="$2"
  local superloop_dir="$repo/.superloop"

  mkdir -p "$superloop_dir/roles" "$superloop_dir/loops" "$superloop_dir/logs" "$superloop_dir/specs"

  if [[ -f "$superloop_dir/config.json" && $force -ne 1 ]]; then
    die "found existing $superloop_dir/config.json (use --force to overwrite)"
  fi

  cat > "$superloop_dir/config.json" <<'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "--output-last-message", "{last_message_file}", "-"],
      "prompt_mode": "stdin"
    },
    "claude-vanilla": {
      "command": ["claude-vanilla"],
      "args": ["--dangerously-skip-permissions", "--print", "-C", "{repo}", "-"],
      "prompt_mode": "stdin"
    },
    "claude-glm-mantic": {
      "command": ["claude-glm-mantic"],
      "args": ["--dangerously-skip-permissions", "--print", "-C", "{repo}", "-"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [
    {
      "id": "initiation",
      "spec_file": ".superloop/specs/initiation.md",
      "max_iterations": 20,
      "completion_promise": "SUPERLOOP_COMPLETE",
      "checklists": [],
      "tests": {
        "mode": "on_promise",
        "commands": []
      },
      "evidence": {
        "enabled": true,
        "require_on_completion": true,
        "artifacts": []
      },
      "approval": {
        "enabled": false,
        "require_on_completion": true
      },
      "reviewer_packet": {
        "enabled": true
      },
      "timeouts": {
        "enabled": true,
        "default": 900,
        "planner": 300,
        "implementer": 900,
        "tester": 300,
        "reviewer": 1200
      },
      "stuck": {
        "enabled": true,
        "threshold": 3,
        "action": "report_and_stop",
        "ignore": [
          ".superloop/**",
          ".git/**",
          "node_modules/**",
          "dist/**",
          "build/**",
          "coverage/**",
          ".next/**",
          ".venv/**",
          ".tox/**",
          ".cache/**"
        ]
      },
      "roles": {
        "planner": {"runner": "codex"},
        "implementer": {"runner": "claude-vanilla"},
        "tester": {"runner": "claude-glm-mantic"},
        "reviewer": {"runner": "codex"}
      }
    }
  ]
}
EOF

  cat > "$superloop_dir/specs/initiation.md" <<'EOF'
# Feature: [Your Feature Name]

## Overview

Replace this with a description of what you're building and why.

Use `/construct-superloop` in Claude Code for guided spec creation.

## Requirements

- [ ] REQ-1: [First requirement]
- [ ] REQ-2: [Second requirement]

## Technical Approach

[Describe the implementation approach]

## Acceptance Criteria

- [ ] AC-1: When [action], then [expected result]
- [ ] AC-2: When [action], then [expected result]

## Constraints

- **Performance**: [requirements]
- **Security**: [requirements]
- **Compatibility**: [requirements]

## Out of Scope

- [What's not included]
EOF

  cat > "$superloop_dir/roles/planner.md" <<'EOF'
You are the Planner.

## Responsibilities

### First Iteration (Initiation)

If PLAN.MD does not exist or is empty, create the full feature plan:

**Create PLAN.MD** with this structure:
```markdown
# {Feature Name}

## Goal
{Main objective - one clear sentence}

## Scope
- {What's included}
- {What's included}

## Non-Goals (this iteration)
- {Explicitly out of scope}

## Primary References
- {Key file}: {purpose}

## Architecture
{High-level description of components and their interactions}

## Decisions
- {Key decision and rationale}

## Risks / Constraints
- {Known risk or constraint}

## Phases
- **Phase 1**: {Brief description}
- **Phase 2**: {Brief description} (if applicable)
```

**Create tasks/PHASE_1.MD** with atomic tasks:
```markdown
# Phase 1 - {Phase Title}

## P1.1 {Task Group Name}
1. [ ] {Atomic task with file path}
2. [ ] {Atomic task with file path}
   1. [ ] {Sub-task}
   2. [ ] {Sub-task}

## P1.2 {Task Group Name}
1. [ ] {Atomic task}
2. [ ] {Atomic task}

## P1.V Validation
1. [ ] {Validation criterion}
```

### Subsequent Iterations

1. Read the current PLAN.MD and active PHASE file.
2. Review iteration notes for blockers or test failures.
3. If current phase has unchecked tasks, no changes needed.
4. If current phase is complete (all `[x]`), create the next PHASE file.
5. Update PLAN.MD only if scope, decisions, or architecture must change.

## Atomic Task Format

Tasks use hierarchical numbering for deep referenceability:
- `P1.1` = Phase 1, Task Group 1
- `P1.1.3` = Phase 1, Task Group 1, Task 3
- `P1.1.3.2` = Sub-task 2 of Task 3

Each task MUST:
- Be a single, verifiable unit of work
- Include the target file path when modifying code
- Use `[ ]` checkbox format for tracking
- Be completable by the implementer in one pass

Example:
```markdown
## P1.2 API Endpoint Setup
1. [ ] Create `src/api/users.ts` with GET /users endpoint
2. [ ] Add authentication middleware to `src/middleware/auth.ts`
   1. [ ] Implement JWT validation
   2. [ ] Add role-based access check
3. [ ] Wire endpoint in `src/routes/index.ts`
```

## Rules

- Do NOT modify code or run tests.
- Do NOT output a promise tag.
- Create the `tasks/` directory and PHASE files as needed.
- Minimize churn: do not rewrite completed tasks or unchanged sections.
- Keep tasks atomic: if a task feels too big, break it into sub-tasks.
- Write PLAN.MD to the plan file path listed in context.
- Write PHASE files to the tasks/ directory under the loop directory.
EOF

  cat > "$superloop_dir/roles/implementer.md" <<'EOF'
You are the Implementer.

## Responsibilities

1. Read PLAN.MD for context, architecture, and decisions.
2. Read the active PHASE file (in tasks/ directory) for current tasks.
3. Work through unchecked tasks (`[ ]`) in order.
4. Check off tasks as you complete them: change `[ ]` to `[x]`.
5. Write implementation notes to the implementer report.

## Workflow

1. Find the first unchecked task in the active PHASE file.
2. Implement that task completely.
3. Mark it `[x]` in the PHASE file.
4. Repeat until all tasks are checked or you hit a blocker.

## Task Completion

When you complete a task, update the PHASE file:

Before:
```markdown
1. [ ] Create `src/api/users.ts` with GET /users endpoint
```

After:
```markdown
1. [x] Create `src/api/users.ts` with GET /users endpoint
```

## Rules

- Do NOT edit the spec or PLAN.MD (only the planner modifies those).
- Do NOT run tests (the wrapper handles that).
- Do NOT output a promise tag.
- DO update PHASE files to check off completed tasks.
- Work through tasks in order unless blocked.
- If blocked, note the blocker and move to the next unblocked task.
- Write your summary to the implementer report file path listed in context.

## Implementer Report Format

Always include these sections:

```markdown
## Tasks Completed
- P1.2.1: Created src/api/users.ts
- P1.2.2: Added auth middleware

## Files Touched
- CREATED: src/api/users.ts
- MODIFIED: src/middleware/auth.ts

## Blockers (if any)
- P1.2.3: Blocked on missing database schema

## Notes
- Additional context for the next iteration
```
EOF

  cat > "$superloop_dir/roles/tester.md" <<'EOF'
You are the Quality Engineer.

## Responsibilities

### Analysis (always)
- Read automated test results from test-status.json and test-output.txt.
- Read validation results (preflight, smoke tests, agent-browser) if present.
- Summarize failures, identify patterns, and note gaps in test coverage.

### Exploration (when browser tools are available)
- Use agent-browser to verify the implementation works correctly.
- Focus on areas NOT covered by automated tests.
- Check user-facing flows from a fresh perspective.
- Look for issues the implementer may have missed:
  - Broken interactions
  - Missing error handling
  - Incorrect behavior
  - Visual/layout problems
- Document findings with screenshots when useful.

## Browser Testing Workflow

When agent-browser is available:

1. `agent-browser open <url>` - Navigate to the application
2. `agent-browser snapshot -i` - Get interactive elements with refs
3. Interact using refs: `click @e1`, `fill @e2 "text"`, `select @e3 "option"`
4. `agent-browser screenshot <path>` - Capture state when needed
5. Re-snapshot after page changes to get new refs.

## Rules
- Do NOT modify code.
- Do NOT run automated test suites (the wrapper handles that).
- Do NOT re-verify things automated tests already cover well.
- Focus exploration on gaps and user-facing behavior.
- Report issues with clear reproduction steps.
- Do not output a promise tag.
- Minimize report churn: if findings are unchanged, do not edit the report.
- Write your report to the test report file path listed in context.
EOF

  cat > "$superloop_dir/roles/reviewer.md" <<'EOF'
You are the Reviewer.

Responsibilities:
- Read the reviewer packet first (if present), then verify against the spec as needed.
- Read the checklist status, test status, and reports.
- Validate that requirements are met and gates are green.
- Write a short review report.

Rules:
- Do not modify code.
- Only output <promise>...</promise> if tests pass, checklists are complete, and the spec is satisfied.
- Minimize report churn: if the review report already reflects the current state and no gates changed, do not edit it.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged text).
- Write your review to the reviewer report file path listed in context.
EOF

  # Install Claude Code skill for agent-browser
  local claude_skills_dir="$repo/.claude/skills/agent-browser"
  mkdir -p "$claude_skills_dir"
  cat > "$claude_skills_dir/SKILL.md" <<'EOF'
---
name: agent-browser
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when you need to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
---

# Browser Automation with agent-browser

## Quick start

```bash
agent-browser open <url>        # Navigate to page
agent-browser snapshot -i       # Get interactive elements with refs
agent-browser click @e1         # Click element by ref
agent-browser fill @e2 "text"   # Fill input by ref
agent-browser close             # Close browser
```

## Core workflow

1. Navigate: `agent-browser open <url>`
2. Snapshot: `agent-browser snapshot -i` (returns elements with refs like `@e1`, `@e2`)
3. Interact using refs from the snapshot
4. Re-snapshot after navigation or significant DOM changes

## Commands

### Navigation
```bash
agent-browser open <url>      # Navigate to URL
agent-browser back            # Go back
agent-browser forward         # Go forward
agent-browser reload          # Reload page
agent-browser close           # Close browser
```

### Snapshot (page analysis)
```bash
agent-browser snapshot        # Full accessibility tree
agent-browser snapshot -i     # Interactive elements only (recommended)
agent-browser snapshot -c     # Compact output
agent-browser snapshot -d 3   # Limit depth to 3
```

### Interactions (use @refs from snapshot)
```bash
agent-browser click @e1           # Click
agent-browser dblclick @e1        # Double-click
agent-browser fill @e2 "text"     # Clear and type
agent-browser type @e2 "text"     # Type without clearing
agent-browser press Enter         # Press key
agent-browser press Control+a     # Key combination
agent-browser hover @e1           # Hover
agent-browser check @e1           # Check checkbox
agent-browser uncheck @e1         # Uncheck checkbox
agent-browser select @e1 "value"  # Select dropdown
agent-browser scroll down 500     # Scroll page
agent-browser scrollintoview @e1  # Scroll element into view
```

### Get information
```bash
agent-browser get text @e1        # Get element text
agent-browser get value @e1       # Get input value
agent-browser get title           # Get page title
agent-browser get url             # Get current URL
```

### Screenshots
```bash
agent-browser screenshot          # Screenshot to stdout
agent-browser screenshot path.png # Save to file
agent-browser screenshot --full   # Full page
```

### Wait
```bash
agent-browser wait @e1                     # Wait for element
agent-browser wait 2000                    # Wait milliseconds
agent-browser wait --text "Success"        # Wait for text
agent-browser wait --load networkidle      # Wait for network idle
```

### Semantic locators (alternative to refs)
```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign In" click
agent-browser find label "Email" fill "user@test.com"
```

## Example: Form submission

```bash
agent-browser open https://example.com/form
agent-browser snapshot -i
# Output shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Submit" [ref=e3]

agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait --load networkidle
agent-browser snapshot -i  # Check result
```

## Example: Authentication with saved state

```bash
# Login once
agent-browser open https://app.example.com/login
agent-browser snapshot -i
agent-browser fill @e1 "username"
agent-browser fill @e2 "password"
agent-browser click @e3
agent-browser wait --url "**/dashboard"
agent-browser state save auth.json

# Later sessions: load saved state
agent-browser state load auth.json
agent-browser open https://app.example.com/dashboard
```

## Sessions (parallel browsers)

```bash
agent-browser --session test1 open site-a.com
agent-browser --session test2 open site-b.com
agent-browser session list
```

## JSON output (for parsing)

Add `--json` for machine-readable output:
```bash
agent-browser snapshot -i --json
agent-browser get text @e1 --json
```

## Debugging

```bash
agent-browser open example.com --headed  # Show browser window
agent-browser console                    # View console messages
agent-browser errors                     # View page errors
```
EOF

  echo "Initialized .superloop in $superloop_dir"
  echo "Installed agent-browser skill in $claude_skills_dir"
}

run_cmd() {
  local repo="$1"
  local config_path="$2"
  local target_loop_id="$3"
  local fast_mode="$4"
  local dry_run="$5"

  need_cmd jq

  local superloop_dir="$repo/.superloop"
  local state_file="$superloop_dir/state.json"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi

  local loop_count
  loop_count=$(jq '.loops | length' "$config_path")
  if [[ "$loop_count" == "0" ]]; then
    die "config has no loops"
  fi

  # Check if using runners registry (per-role) or single runner (legacy)
  local has_runners_registry
  has_runners_registry=$(jq -r 'if .runners then "true" else "false" end' "$config_path")
  local runners_json=""
  if [[ "$has_runners_registry" == "true" ]]; then
    runners_json=$(jq -c '.runners // {}' "$config_path")
  fi

  # Parse default runner (legacy mode or fallback)
  local -a default_runner_command=()
  while IFS= read -r line; do
    default_runner_command+=("$line")
  done < <(jq -r '.runner.command[]?' "$config_path")

  local -a default_runner_args=()
  while IFS= read -r line; do
    default_runner_args+=("$line")
  done < <(jq -r '.runner.args[]?' "$config_path")

  local -a default_runner_fast_args=()
  while IFS= read -r line; do
    default_runner_fast_args+=("$line")
  done < <(jq -r '.runner.fast_args[]?' "$config_path")

  local default_runner_prompt_mode
  default_runner_prompt_mode=$(jq -r '.runner.prompt_mode // "stdin"' "$config_path")

  # Validate: must have either runner or runners
  if [[ ${#default_runner_command[@]} -eq 0 && "$has_runners_registry" != "true" ]]; then
    die "either runner.command or runners registry is required"
  fi

  if [[ "$default_runner_prompt_mode" != "stdin" && "$default_runner_prompt_mode" != "file" ]]; then
    default_runner_prompt_mode="stdin"
  fi

  # Helper function to get runner config for a role
  get_runner_for_role() {
    local role="$1"
    local role_runner_name="$2"  # From roles config, may be empty
    local runner_name=""

    # If role has explicit runner assignment, use it
    if [[ -n "$role_runner_name" ]]; then
      runner_name="$role_runner_name"
    fi

    # If we have a runner name and runners registry, look it up
    if [[ -n "$runner_name" && -n "$runners_json" ]]; then
      local runner_config
      runner_config=$(jq -c --arg name "$runner_name" '.[$name] // empty' <<<"$runners_json")
      if [[ -n "$runner_config" ]]; then
        echo "$runner_config"
        return 0
      else
        echo "warning: runner '$runner_name' not found in registry, using default" >&2
      fi
    fi

    # Fall back to default runner
    if [[ ${#default_runner_command[@]} -gt 0 ]]; then
      jq -n \
        --argjson cmd "$(printf '%s\n' "${default_runner_command[@]}" | jq -R . | jq -s .)" \
        --argjson args "$(printf '%s\n' "${default_runner_args[@]}" | jq -R . | jq -s .)" \
        --argjson fast_args "$(printf '%s\n' "${default_runner_fast_args[@]}" | jq -R . | jq -s .)" \
        --arg prompt_mode "$default_runner_prompt_mode" \
        '{command: $cmd, args: $args, fast_args: $fast_args, prompt_mode: $prompt_mode}'
      return 0
    fi

    return 1
  }

  # For backward compatibility, set up default runner variables
  local -a runner_command=("${default_runner_command[@]}")
  local -a runner_args=("${default_runner_args[@]}")
  local -a runner_fast_args=("${default_runner_fast_args[@]}")
  local runner_prompt_mode="$default_runner_prompt_mode"

  if [[ "${dry_run:-0}" -ne 1 && ${#runner_command[@]} -gt 0 ]]; then
    need_exec "${runner_command[0]}"
  fi

  local -a runner_active_args=("${runner_args[@]}")
  if [[ "${fast_mode:-0}" -eq 1 ]]; then
    if [[ ${#runner_fast_args[@]} -gt 0 ]]; then
      runner_active_args=("${runner_fast_args[@]}")
    elif [[ ${#runner_args[@]} -gt 0 ]]; then
      echo "warning: --fast set but runner.fast_args is empty; using runner.args" >&2
    fi
  fi

  local loop_index=0
  local iteration=1
  if [[ "${dry_run:-0}" -ne 1 && -f "$state_file" ]]; then
    loop_index=$(jq -r '.loop_index // 0' "$state_file")
    iteration=$(jq -r '.iteration // 1' "$state_file")
    local active
    active=$(jq -r '.active // true' "$state_file")
    if [[ "$active" != "true" ]]; then
      loop_index=0
      iteration=1
    fi
  fi

  if [[ -n "$target_loop_id" ]]; then
    local found_index
    found_index=$(jq -r --arg id "$target_loop_id" '.loops | to_entries[] | select(.value.id == $id) | .key' "$config_path" | head -n1)
    if [[ -z "$found_index" ]]; then
      die "loop id not found: $target_loop_id"
    fi
    loop_index="$found_index"
    iteration=1
  fi

  for ((i=loop_index; i<loop_count; i++)); do
    local loop_json loop_id spec_file max_iterations completion_promise
    loop_json=$(jq -c ".loops[$i]" "$config_path")
    loop_id=$(jq -r '.id' <<<"$loop_json")

    if [[ -n "$target_loop_id" && "$loop_id" != "$target_loop_id" ]]; then
      continue
    fi

    spec_file=$(jq -r '.spec_file' <<<"$loop_json")
    max_iterations=$(jq -r '.max_iterations // 0' <<<"$loop_json")
    completion_promise=$(jq -r '.completion_promise // ""' <<<"$loop_json")

    if [[ -z "$spec_file" || "$spec_file" == "null" ]]; then
      die "loop '$loop_id' missing spec_file"
    fi
    if [[ ! -f "$repo/$spec_file" ]]; then
      die "spec file not found: $spec_file"
    fi

    local loop_dir="$superloop_dir/loops/$loop_id"
    local role_dir="$superloop_dir/roles"
    local prompt_dir="$loop_dir/prompts"
    local log_dir="$loop_dir/logs/iter-$iteration"
    local last_messages_dir="$loop_dir/last_messages"

    local plan_file="$loop_dir/plan.md"
    local notes_file="$loop_dir/iteration_notes.md"
    local implementer_report="$loop_dir/implementer.md"
    local reviewer_report="$loop_dir/review.md"
    local test_output="$loop_dir/test-output.txt"
    local test_status="$loop_dir/test-status.json"
    local test_report="$loop_dir/test-report.md"
    local validation_status_file="$loop_dir/validation-status.json"
    local validation_results_file="$loop_dir/validation-results.json"
    local checklist_status="$loop_dir/checklist-status.json"
    local checklist_remaining="$loop_dir/checklist-remaining.md"
    local evidence_file="$loop_dir/evidence.json"
    local reviewer_packet="$loop_dir/reviewer-packet.md"
    local summary_file="$loop_dir/gate-summary.txt"
    local events_file="$loop_dir/events.jsonl"
    local run_summary_file="$loop_dir/run-summary.json"
    local timeline_file="$loop_dir/timeline.md"
    local approval_file="$loop_dir/approval.json"
    local decisions_jsonl="$loop_dir/decisions.jsonl"
    local decisions_md="$loop_dir/decisions.md"
    local changed_files_planner="$loop_dir/changed-files-planner.txt"
    local changed_files_implementer="$loop_dir/changed-files-implementer.txt"
    local changed_files_all="$loop_dir/changed-files-all.txt"
    local usage_file="$loop_dir/usage.jsonl"

    local tasks_dir="$loop_dir/tasks"
    mkdir -p "$loop_dir" "$prompt_dir" "$log_dir" "$tasks_dir"
    touch "$plan_file" "$notes_file" "$implementer_report" "$reviewer_report" "$test_report"

    # Parse roles - can be array or object with runner assignments
    local roles_type
    roles_type=$(jq -r '.roles | type' <<<"$loop_json")
    local -a roles=()
    local roles_config_json="{}"

    if [[ "$roles_type" == "array" ]]; then
      # Legacy array format: ["planner", "implementer", "tester", "reviewer"]
      while IFS= read -r line; do
        roles+=("$line")
      done < <(jq -r '.roles[]?' <<<"$loop_json")
    elif [[ "$roles_type" == "object" ]]; then
      # New object format: {"planner": {"runner": "codex"}, ...}
      roles_config_json=$(jq -c '.roles' <<<"$loop_json")
      while IFS= read -r line; do
        roles+=("$line")
      done < <(jq -r '.roles | keys[]' <<<"$loop_json")
    fi

    if [[ ${#roles[@]} -eq 0 ]]; then
      roles=(planner implementer tester reviewer)
    fi

    # Helper to get runner name for a role from roles config
    get_role_runner_name() {
      local role="$1"
      if [[ "$roles_type" == "object" ]]; then
        jq -r --arg role "$role" '.[$role].runner // empty' <<<"$roles_config_json"
      fi
    }

    local -a checklist_patterns=()
    while IFS= read -r line; do
      checklist_patterns+=("$line")
    done < <(jq -r '.checklists[]?' <<<"$loop_json")
    local checklist_patterns_json
    checklist_patterns_json=$(jq -c '.checklists // []' <<<"$loop_json")

    local tests_mode
    tests_mode=$(jq -r '.tests.mode // "disabled"' <<<"$loop_json")
    local -a test_commands=()
    while IFS= read -r line; do
      test_commands+=("$line")
    done < <(jq -r '.tests.commands[]?' <<<"$loop_json")
    local test_commands_json
    test_commands_json=$(jq -c '.tests.commands // []' <<<"$loop_json")

    if [[ ${#test_commands[@]} -eq 0 ]]; then
      tests_mode="disabled"
    fi

    local validation_enabled
    validation_enabled=$(jq -r '.validation.enabled // false' <<<"$loop_json")
    local validation_mode
    validation_mode=$(jq -r '.validation.mode // "every"' <<<"$loop_json")
    local validation_require
    validation_require=$(jq -r '.validation.require_on_completion // false' <<<"$loop_json")

    local evidence_enabled
    evidence_enabled=$(jq -r '.evidence.enabled // false' <<<"$loop_json")
    local evidence_require
    evidence_require=$(jq -r '.evidence.require_on_completion // false' <<<"$loop_json")

    local approval_enabled
    approval_enabled=$(jq -r '.approval.enabled // false' <<<"$loop_json")
    local approval_require
    approval_require=$(jq -r '.approval.require_on_completion // false' <<<"$loop_json")

    local timeouts_enabled
    timeouts_enabled=$(jq -r '.timeouts.enabled // false' <<<"$loop_json")
    local timeout_default
    timeout_default=$(jq -r '.timeouts.default // 0' <<<"$loop_json")
    local timeout_planner
    timeout_planner=$(jq -r '.timeouts.planner // 0' <<<"$loop_json")
    local timeout_implementer
    timeout_implementer=$(jq -r '.timeouts.implementer // 0' <<<"$loop_json")
    local timeout_tester
    timeout_tester=$(jq -r '.timeouts.tester // 0' <<<"$loop_json")
    local timeout_reviewer
    timeout_reviewer=$(jq -r '.timeouts.reviewer // 0' <<<"$loop_json")
    local timeout_inactivity
    timeout_inactivity=$(jq -r '.timeouts.inactivity // 0' <<<"$loop_json")

    # Usage check settings
    local usage_check_enabled
    usage_check_enabled=$(jq -r '.usage_check.enabled // false' <<<"$loop_json")
    local usage_warn_threshold
    usage_warn_threshold=$(jq -r '.usage_check.warn_threshold // 70' <<<"$loop_json")
    local usage_block_threshold
    usage_block_threshold=$(jq -r '.usage_check.block_threshold // 95' <<<"$loop_json")
    local usage_wait_on_limit
    usage_wait_on_limit=$(jq -r '.usage_check.wait_on_limit // false' <<<"$loop_json")
    local usage_wait_max_seconds
    usage_wait_max_seconds=$(jq -r '.usage_check.max_wait_seconds // 7200' <<<"$loop_json")

    local reviewer_packet_enabled
    reviewer_packet_enabled=$(jq -r '.reviewer_packet.enabled // false' <<<"$loop_json")

    local tester_exploration_json
    tester_exploration_json=$(jq -c '.tester_exploration // {}' <<<"$loop_json")

    local stuck_enabled
    stuck_enabled=$(jq -r '.stuck.enabled // false' <<<"$loop_json")
    local stuck_threshold
    stuck_threshold=$(jq -r '.stuck.threshold // 0' <<<"$loop_json")
    local stuck_action
    stuck_action=$(jq -r '.stuck.action // "report_and_stop"' <<<"$loop_json")
    local -a stuck_ignore=()
    while IFS= read -r line; do
      stuck_ignore+=("$line")
    done < <(jq -r '.stuck.ignore[]?' <<<"$loop_json")
    if [[ ${#stuck_ignore[@]} -eq 0 ]]; then
      stuck_ignore=("${DEFAULT_STUCK_IGNORE[@]}")
    fi
    if [[ "$stuck_threshold" -le 0 ]]; then
      stuck_enabled="false"
    fi

    if [[ "$reviewer_packet_enabled" != "true" ]]; then
      reviewer_packet=""
    fi

    if [[ "${dry_run:-0}" -eq 1 ]]; then
      local promise_status="n/a"
      if [[ -n "$completion_promise" ]]; then
        local reviewer_last_message="$loop_dir/last_messages/reviewer.txt"
        if [[ -f "$reviewer_last_message" ]]; then
          local promise_text
          promise_text=$(extract_promise "$reviewer_last_message")
          if [[ -n "$promise_text" ]]; then
            if [[ "$promise_text" == "$completion_promise" ]]; then
              promise_status="true"
            else
              promise_status="false"
            fi
          else
            promise_status="unknown"
          fi
        else
          promise_status="unknown"
        fi
      fi

      local tests_status validation_status checklist_status_text evidence_status stuck_value
      tests_status=$(read_test_status_summary "$test_status")
      validation_status=$(read_validation_status_summary "$validation_status_file")
      checklist_status_text=$(read_checklist_status_summary "$checklist_status")
      if [[ "$evidence_enabled" == "true" ]]; then
        if [[ -f "$evidence_file" ]]; then
          evidence_status="ok"
        else
          evidence_status="missing"
        fi
      else
        evidence_status="skipped"
      fi
      stuck_value="n/a"
      if [[ "$stuck_enabled" == "true" ]]; then
        local stuck_streak_read
        stuck_streak_read=$(read_stuck_streak "$loop_dir/stuck.json")
        stuck_value="${stuck_streak_read}/${stuck_threshold}"
      fi

      local approval_status="none"
      if [[ "$approval_enabled" == "true" && -f "$approval_file" ]]; then
        approval_status=$(read_approval_status "$approval_file")
      fi

      echo "Dry-run summary ($loop_id): promise=$promise_status tests=$tests_status validation=$validation_status checklist=$checklist_status_text evidence=$evidence_status approval=$approval_status stuck=$stuck_value"
      if [[ -n "$target_loop_id" && "$loop_id" == "$target_loop_id" ]]; then
        return 0
      fi
      continue
    fi

    local run_id
    run_id=$(timestamp)
    local loop_start_data
    loop_start_data=$(jq -n \
      --arg spec_file "$spec_file" \
      --argjson max_iterations "$max_iterations" \
      --arg tests_mode "$tests_mode" \
      --argjson test_commands "$test_commands_json" \
      --argjson checklists "$checklist_patterns_json" \
      '{spec_file: $spec_file, max_iterations: $max_iterations, tests_mode: $tests_mode, test_commands: $test_commands, checklists: $checklists}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_start" "$loop_start_data"

    local approval_required=0
    if [[ "$approval_enabled" == "true" && "$approval_require" == "true" ]]; then
      approval_required=1
    fi

    if [[ "$approval_enabled" == "true" ]]; then
      local approval_state
      approval_state=$(read_approval_status "$approval_file")
      if [[ "$approval_state" == "pending" ]]; then
        local approval_wait_data
        approval_wait_data=$(jq -n --arg approval_file "${approval_file#$repo/}" '{status: "pending", approval_file: $approval_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_wait" "$approval_wait_data"
        echo "Approval pending for loop '$loop_id'. Run: superloop.sh approve --repo $repo --loop $loop_id"
        if [[ "${dry_run:-0}" -ne 1 ]]; then
          write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
        fi
        return 0
      elif [[ "$approval_state" == "approved" ]]; then
        local approval_run_id approval_iteration approval_promise_text approval_promise_matched
        local approval_tests approval_validation approval_checklist approval_evidence approval_started_at approval_ended_at
        local approval_decision_by approval_decision_note approval_decision_at
        approval_run_id=$(jq -r '.run_id // ""' "$approval_file")
        approval_iteration=$(jq -r '.iteration // 0' "$approval_file")
        approval_promise_text=$(jq -r '.candidate.promise.text // ""' "$approval_file")
        approval_promise_matched=$(jq -r '.candidate.promise.matched // false' "$approval_file")
        approval_tests=$(jq -r '.candidate.gates.tests // "unknown"' "$approval_file")
        approval_validation=$(jq -r '.candidate.gates.validation // "unknown"' "$approval_file")
        approval_checklist=$(jq -r '.candidate.gates.checklist // "unknown"' "$approval_file")
        approval_evidence=$(jq -r '.candidate.gates.evidence // "unknown"' "$approval_file")
        approval_started_at=$(jq -r '.iteration_started_at // ""' "$approval_file")
        approval_ended_at=$(jq -r '.iteration_ended_at // ""' "$approval_file")
        approval_decision_by=$(jq -r '.decision.by // ""' "$approval_file")
        approval_decision_note=$(jq -r '.decision.note // ""' "$approval_file")
        approval_decision_at=$(jq -r '.decision.at // ""' "$approval_file")

        if [[ -z "$approval_run_id" || "$approval_run_id" == "null" ]]; then
          approval_run_id="$run_id"
        fi
        if [[ "$approval_iteration" -le 0 ]]; then
          approval_iteration="$iteration"
        fi
        if [[ -z "$approval_started_at" || "$approval_started_at" == "null" ]]; then
          approval_started_at=$(timestamp)
        fi
        if [[ -z "$approval_ended_at" || "$approval_ended_at" == "null" ]]; then
          approval_ended_at="$approval_started_at"
        fi

        local promise_matched="$approval_promise_matched"
        if [[ "$promise_matched" != "true" ]]; then
          promise_matched="false"
        fi
        local tests_status="$approval_tests"
        local validation_status="$approval_validation"
        local checklist_status_text="$approval_checklist"
        local evidence_status="$approval_evidence"
        local approval_status="approved"

        local stuck_streak="0"
        if [[ "$stuck_enabled" == "true" ]]; then
          stuck_streak=$(read_stuck_streak "$loop_dir/stuck.json")
        fi
        local stuck_value="n/a"
        if [[ "$stuck_enabled" == "true" ]]; then
          stuck_value="${stuck_streak}/${stuck_threshold}"
        fi

        write_iteration_notes "$notes_file" "$loop_id" "$approval_iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
        write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"

        local approval_consume_data
        approval_consume_data=$(jq -n \
          --arg status "approved" \
          --arg by "$approval_decision_by" \
          --arg note "$approval_decision_note" \
          --arg at "$approval_decision_at" \
          '{status: $status, by: (if ($by | length) > 0 then $by else null end), note: (if ($note | length) > 0 then $note else null end), at: (if ($at | length) > 0 then $at else null end)}')
        log_event "$events_file" "$loop_id" "$approval_iteration" "$approval_run_id" "approval_consumed" "$approval_consume_data"

        local completion_ok=1
        append_run_summary "$run_summary_file" "$repo" "$loop_id" "$approval_run_id" "$approval_iteration" "$approval_started_at" "$approval_ended_at" "$promise_matched" "$completion_promise" "$approval_promise_text" "$tests_mode" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$approval_status" "$stuck_streak" "$stuck_threshold" "$completion_ok" "$loop_dir" "$events_file"
        write_timeline "$run_summary_file" "$timeline_file"

        local loop_complete_data
        loop_complete_data=$(jq -n \
          --argjson iteration "$approval_iteration" \
          --arg run_id "$approval_run_id" \
          '{iteration: $iteration, run_id: $run_id, approval: true}')
        log_event "$events_file" "$loop_id" "$approval_iteration" "$approval_run_id" "loop_complete" "$loop_complete_data"
        echo "Loop '$loop_id' complete at iteration $approval_iteration (approved)."
        rm -f "$approval_file"

        iteration=1
        if [[ -n "$target_loop_id" && "$loop_id" == "$target_loop_id" ]]; then
          write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
          return 0
        fi
        continue
      elif [[ "$approval_state" == "rejected" ]]; then
        local approval_reject_data
        approval_reject_data=$(jq -n --arg approval_file "${approval_file#$repo/}" '{status: "rejected", approval_file: $approval_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_rejected" "$approval_reject_data"
        rm -f "$approval_file"
      fi
    fi

    while true; do
      if [[ $max_iterations -gt 0 && $iteration -gt $max_iterations ]]; then
        echo "Max iterations reached for loop '$loop_id' ($max_iterations). Stopping."
        local loop_stop_data
        loop_stop_data=$(jq -n --arg reason "max_iterations" --argjson max_iterations "$max_iterations" '{reason: $reason, max_iterations: $max_iterations}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_stop" "$loop_stop_data"
        if [[ "${dry_run:-0}" -ne 1 ]]; then
          write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
        fi
        return 1
      fi

      if [[ "${dry_run:-0}" -ne 1 ]]; then
        write_state "$state_file" "$i" "$iteration" "$loop_id" "true"
        log_dir="$loop_dir/logs/iter-$iteration"
        mkdir -p "$log_dir" "$last_messages_dir"
      fi

      local iteration_started_at
      iteration_started_at=$(timestamp)
      local iteration_start_data
      iteration_start_data=$(jq -n --arg started_at "$iteration_started_at" '{started_at: $started_at}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "iteration_start" "$iteration_start_data"

      local last_role=""
      for role in "${roles[@]}"; do
        local role_template="$role_dir/$role.md"
        if [[ ! -f "$role_template" ]]; then
          die "missing role template: $role_template"
        fi

        local prompt_file="$prompt_dir/${role}.md"
        build_role_prompt \
          "$role" \
          "$role_template" \
          "$prompt_file" \
          "$spec_file" \
          "$plan_file" \
          "$notes_file" \
          "$implementer_report" \
          "$reviewer_report" \
          "$test_report" \
          "$test_output" \
          "$test_status" \
          "$validation_status_file" \
          "$validation_results_file" \
          "$checklist_status" \
          "$checklist_remaining" \
          "$evidence_file" \
          "$reviewer_packet" \
          "$changed_files_planner" \
          "$changed_files_implementer" \
          "$changed_files_all" \
          "$tester_exploration_json" \
          "$tasks_dir"

        if [[ "$role" == "reviewer" && "$reviewer_packet_enabled" == "true" && -n "$reviewer_packet" ]]; then
          write_reviewer_packet \
            "$loop_dir" \
            "$loop_id" \
            "$iteration" \
            "$summary_file" \
            "$test_status" \
            "$test_report" \
            "$evidence_file" \
            "$checklist_status" \
            "$checklist_remaining" \
            "$validation_status_file" \
            "$validation_results_file" \
            "$reviewer_packet"
        fi

        local last_message_file="$last_messages_dir/${role}.txt"
        local role_log="$log_dir/${role}.log"
        local report_guard=""
        local report_snapshot=""
        local role_timeout_seconds=0

        case "$role" in
          planner)
            report_guard="$plan_file"
            ;;
          implementer|openprose)
            report_guard="$implementer_report"
            ;;
          tester)
            report_guard="$test_report"
            ;;
          reviewer)
            report_guard="$reviewer_report"
            ;;
        esac
        if [[ -n "$report_guard" ]]; then
          report_snapshot="$log_dir/${role}.report.before"
          snapshot_file "$report_guard" "$report_snapshot"
        fi

        if [[ "$timeouts_enabled" == "true" ]]; then
          case "$role" in
            planner)
              role_timeout_seconds="$timeout_planner"
              ;;
            implementer)
              role_timeout_seconds="$timeout_implementer"
              ;;
            tester)
              role_timeout_seconds="$timeout_tester"
              ;;
            reviewer)
              role_timeout_seconds="$timeout_reviewer"
              ;;
            *)
              role_timeout_seconds="$timeout_default"
              ;;
          esac
          if [[ -z "${role_timeout_seconds:-}" || "$role_timeout_seconds" -le 0 ]]; then
            role_timeout_seconds="$timeout_default"
          fi
        fi

        local role_start_data
        role_start_data=$(jq -n \
          --arg prompt_file "$prompt_file" \
          --arg log_file "$role_log" \
          --arg last_message_file "$last_message_file" \
          '{prompt_file: $prompt_file, log_file: $log_file, last_message_file: $last_message_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_start" "$role_start_data" "$role"

        # Pre-flight usage check (need to know runner first)
        # Get runner for this specific role (early, for usage check)
        local early_role_runner_name
        early_role_runner_name=$(get_role_runner_name "$role")
        local early_runner_cmd=""
        if [[ -n "$early_role_runner_name" && -n "$runners_json" ]]; then
          early_runner_cmd=$(jq -r --arg name "$early_role_runner_name" '.[$name].command[0] // empty' <<<"$runners_json")
        fi
        if [[ -z "$early_runner_cmd" && ${#runner_command[@]} -gt 0 ]]; then
          early_runner_cmd="${runner_command[0]}"
        fi

        if [[ "${usage_check_enabled:-false}" == "true" ]]; then
          local runner_type_for_check=""
          case "$early_runner_cmd" in
            *claude*) runner_type_for_check="claude" ;;
            *codex*) runner_type_for_check="codex" ;;
          esac

          if [[ -n "$runner_type_for_check" ]]; then
            local usage_check_result=0
            check_usage_limits "$runner_type_for_check" "${usage_warn_threshold:-70}" "${usage_block_threshold:-95}" || usage_check_result=$?

            if [[ $usage_check_result -eq 2 ]]; then
              # Blocked by usage limits
              local usage_data
              usage_data=$(jq -n \
                --arg runner "$runner_type_for_check" \
                --arg role "$role" \
                '{runner: $runner, role: $role, action: "blocked"}')
              log_event "$events_file" "$loop_id" "$iteration" "$run_id" "usage_limit_blocked" "$usage_data" "$role" "error"

              if [[ "${usage_wait_on_limit:-false}" == "true" ]]; then
                echo "[superloop] Usage limit reached. Waiting for reset..." >&2
                # Wait up to max_wait_seconds (default 2 hours), checking every 5 minutes
                local wait_interval=300
                local wait_elapsed=0
                while true; do
                  sleep "$wait_interval"
                  wait_elapsed=$((wait_elapsed + wait_interval))
                  check_usage_limits "$runner_type_for_check" "${usage_warn_threshold:-70}" "${usage_block_threshold:-95}" || usage_check_result=$?
                  if [[ $usage_check_result -ne 2 ]]; then
                    echo "[superloop] Usage limits cleared. Resuming..." >&2
                    break
                  fi
                  if [[ "${usage_wait_max_seconds:-7200}" -gt 0 && $wait_elapsed -ge $usage_wait_max_seconds ]]; then
                    echo "[superloop] Timed out waiting for usage reset. Stopping." >&2
                    write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
                    return 1
                  fi
                  if [[ "${usage_wait_max_seconds:-7200}" -gt 0 ]]; then
                    local remaining_wait=$((usage_wait_max_seconds - wait_elapsed))
                    local remaining_text
                    remaining_text=$(format_time_until_reset "$remaining_wait" 2>/dev/null || echo "${remaining_wait}s")
                    echo "[superloop] Still waiting for usage reset... (${remaining_text} remaining)" >&2
                  else
                    echo "[superloop] Still waiting for usage reset..." >&2
                  fi
                done
              else
                echo "[superloop] Usage limit reached. Stopping loop." >&2
                write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
                return 1
              fi
            fi
          fi
        fi

        # Get runner for this specific role
        local role_runner_name
        role_runner_name=$(get_role_runner_name "$role")
        local role_runner_config
        role_runner_config=$(get_runner_for_role "$role" "$role_runner_name")

        # Parse role-specific runner settings
        local -a role_runner_command=()
        local -a role_runner_args=()
        local -a role_runner_fast_args=()
        local role_runner_prompt_mode="stdin"

        if [[ -n "$role_runner_config" ]]; then
          while IFS= read -r line; do
            [[ -n "$line" ]] && role_runner_command+=("$line")
          done < <(jq -r '.command[]?' <<<"$role_runner_config")

          while IFS= read -r line; do
            [[ -n "$line" ]] && role_runner_args+=("$line")
          done < <(jq -r '.args[]?' <<<"$role_runner_config")

          while IFS= read -r line; do
            [[ -n "$line" ]] && role_runner_fast_args+=("$line")
          done < <(jq -r '.fast_args[]?' <<<"$role_runner_config")

          role_runner_prompt_mode=$(jq -r '.prompt_mode // "stdin"' <<<"$role_runner_config")
        fi

        # Fall back to default runner if role-specific failed
        if [[ ${#role_runner_command[@]} -eq 0 ]]; then
          role_runner_command=("${runner_command[@]}")
          role_runner_args=("${runner_args[@]}")
          role_runner_fast_args=("${runner_fast_args[@]}")
          role_runner_prompt_mode="$runner_prompt_mode"
        fi

        # Select args based on fast mode
        local -a role_runner_active_args=("${role_runner_args[@]}")
        if [[ "${fast_mode:-0}" -eq 1 && ${#role_runner_fast_args[@]} -gt 0 ]]; then
          role_runner_active_args=("${role_runner_fast_args[@]}")
        fi

        # Log which runner is being used for this role
        if [[ -n "$role_runner_name" ]]; then
          echo "[superloop] Role '$role' using runner: $role_runner_name (${role_runner_command[0]:-unknown})"
        fi

        local role_status=0
        set +e
        if [[ "$role" == "openprose" ]]; then
          run_openprose_role "$repo" "$loop_dir" "$prompt_dir" "$log_dir" "$last_messages_dir" "$role_log" "$last_message_file" "$implementer_report" "$role_timeout_seconds" "$role_runner_prompt_mode" "${role_runner_command[@]}" -- "${role_runner_active_args[@]}"
          role_status=$?
        else
          run_role "$repo" "$role" "$prompt_file" "$last_message_file" "$role_log" "$role_timeout_seconds" "$role_runner_prompt_mode" "$timeout_inactivity" "$usage_file" "$iteration" "${role_runner_command[@]}" -- "${role_runner_active_args[@]}"
          role_status=$?
        fi
        set -e
        if [[ -n "$report_guard" ]]; then
          if [[ $role_status -eq 124 ]]; then
            rm -f "$report_snapshot"
          else
            restore_if_unchanged "$report_guard" "$report_snapshot"
          fi
        fi
        if [[ $role_status -eq 125 ]]; then
          local rate_limit_info
          rate_limit_info=$(json_or_default "$LAST_RATE_LIMIT_INFO" "{}")
          local rate_limit_data
          rate_limit_data=$(jq -n \
            --arg loop_id "$loop_id" \
            --arg run_id "$run_id" \
            --argjson iteration "$iteration" \
            --arg role "$role" \
            --arg occurred_at "$(timestamp)" \
            --argjson info "$rate_limit_info" \
            '{loop_id: $loop_id, run_id: $run_id, iteration: $iteration, role: $role, occurred_at: $occurred_at, info: $info}')
          local rate_limit_file="$loop_dir/rate-limit.json"
          printf '%s\n' "$rate_limit_data" > "$rate_limit_file"
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "rate_limit_stop" "$rate_limit_data" "$role" "rate_limited"
          echo "[superloop] Rate limit hit for role '$role'. State saved; resume with: superloop.sh run --repo $repo" >&2
          if [[ "${dry_run:-0}" -ne 1 ]]; then
            write_state "$state_file" "$i" "$iteration" "$loop_id" "true"
          fi
          return 1
        fi
        if [[ $role_status -eq 124 ]]; then
          local timeout_data
          timeout_data=$(jq -n \
            --arg role "$role" \
            --argjson timeout "$role_timeout_seconds" \
            '{role: $role, timeout_seconds: $timeout}')
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_timeout" "$timeout_data" "$role" "timeout"
          echo "Role '$role' timed out after ${role_timeout_seconds}s."
          if [[ "${dry_run:-0}" -ne 1 ]]; then
            write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
          fi
          return 1
        fi
        if [[ $role_status -ne 0 ]]; then
          die "role '$role' failed (exit $role_status)"
        fi
        local role_end_data
        role_end_data=$(jq -n \
          --arg log_file "$role_log" \
          --arg last_message_file "$last_message_file" \
          '{log_file: $log_file, last_message_file: $last_message_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_end" "$role_end_data" "$role"

        # Capture git changes after role completes (file tracking)
        if [[ "$role" == "planner" || "$role" == "implementer" ]]; then
          local changed_file="$loop_dir/changed-files-${role}.txt"
          if git -C "$repo" rev-parse --git-dir &>/dev/null; then
            # Capture staged and unstaged changes
            git -C "$repo" diff --name-only > "$changed_file" 2>/dev/null || true
            git -C "$repo" diff --cached --name-only >> "$changed_file" 2>/dev/null || true
            git -C "$repo" status --porcelain | awk '{print $2}' >> "$changed_file" 2>/dev/null || true
            # Deduplicate
            if [[ -f "$changed_file" ]]; then
              sort -u "$changed_file" -o "$changed_file"
            fi
            # Update cumulative file
            if [[ -f "$changed_file" ]]; then
              cat "$changed_file" >> "$changed_files_all" 2>/dev/null || true
              sort -u "$changed_files_all" -o "$changed_files_all" 2>/dev/null || true
            fi
          fi
        fi

        last_role="$role"
      done

      local promise_matched="false"
      local promise_text=""
      if [[ -n "$completion_promise" ]]; then
        local last_message_file="$last_messages_dir/${last_role}.txt"
        promise_text=$(extract_promise "$last_message_file")
        if [[ -n "$promise_text" && "$promise_text" == "$completion_promise" ]]; then
          promise_matched="true"
        fi
      fi
      local promise_matched_json="false"
      if [[ "$promise_matched" == "true" ]]; then
        promise_matched_json="true"
      fi
      local promise_data
      promise_data=$(jq -n \
        --arg expected "$completion_promise" \
        --arg text "$promise_text" \
        --argjson matched "$promise_matched_json" \
        '{expected: $expected, text: $text, matched: $matched}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "promise_checked" "$promise_data"

      local checklist_ok=1
      local checklist_status_text="ok"
      local checklist_start_data
      checklist_start_data=$(jq -n --argjson patterns "$checklist_patterns_json" '{patterns: $patterns}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "checklist_start" "$checklist_start_data"
      if check_checklists "$repo" "$loop_dir" "${checklist_patterns[@]:-}"; then
        checklist_ok=1
        checklist_status_text="ok"
      else
        checklist_ok=0
        checklist_status_text="remaining"
      fi
      local checklist_ok_json="false"
      if [[ $checklist_ok -eq 1 ]]; then
        checklist_ok_json="true"
      fi
      local checklist_status_json="null"
      if [[ -f "$checklist_status" ]]; then
        checklist_status_json=$(cat "$checklist_status")
      fi
      local checklist_end_data
      checklist_end_data=$(jq -n \
        --arg status "$checklist_status_text" \
        --argjson ok "$checklist_ok_json" \
        --argjson details "$checklist_status_json" \
        '{status: $status, ok: $ok, details: $details}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "checklist_end" "$checklist_end_data"

      local tests_status="skipped"
      local tests_ok=1
      local tests_start_data
      tests_start_data=$(jq -n --arg mode "$tests_mode" --argjson commands "$test_commands_json" '{mode: $mode, commands: $commands}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "tests_start" "$tests_start_data"
      if [[ "$tests_mode" == "every" ]]; then
        if run_tests "$repo" "$loop_dir" "${test_commands[@]}"; then
          tests_status="ok"
          tests_ok=1
        else
          tests_status="failed"
          tests_ok=0
        fi
      elif [[ "$tests_mode" == "on_promise" ]]; then
        if [[ "$promise_matched" == "true" || $checklist_ok -eq 1 ]]; then
          if run_tests "$repo" "$loop_dir" "${test_commands[@]}"; then
            tests_status="ok"
            tests_ok=1
          else
            tests_status="failed"
            tests_ok=0
          fi
        else
          run_tests "$repo" "$loop_dir"
          tests_status="skipped"
          tests_ok=1
        fi
      else
        run_tests "$repo" "$loop_dir"
        tests_status="skipped"
        tests_ok=1
      fi
      local test_status_json="null"
      if [[ -f "$test_status" ]]; then
        test_status_json=$(cat "$test_status")
      fi
      local tests_end_data
      tests_end_data=$(jq -n \
        --arg status "$tests_status" \
        --argjson details "$test_status_json" \
        '{status: $status, details: $details}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "tests_end" "$tests_end_data"

      local validation_status="skipped"
      local validation_ok=1
      local validation_gate_ok=1
      local validation_start_data
      validation_start_data=$(jq -n \
        --arg enabled "$validation_enabled" \
        --arg mode "$validation_mode" \
        '{enabled: $enabled, mode: $mode}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "validation_start" "$validation_start_data"

      local validation_should_run=0
      if [[ "$validation_enabled" == "true" ]]; then
        if [[ "$validation_mode" == "every" ]]; then
          validation_should_run=1
        elif [[ "$validation_mode" == "on_promise" ]]; then
          if [[ "$promise_matched" == "true" || $checklist_ok -eq 1 ]]; then
            validation_should_run=1
          fi
        fi
      fi

      if [[ "$validation_enabled" == "true" && $validation_should_run -eq 1 ]]; then
        if run_validation "$repo" "$loop_dir" "$loop_id" "$iteration" "$loop_json"; then
          validation_status="ok"
          validation_ok=1
        else
          validation_status="failed"
          validation_ok=0
        fi
      elif [[ "$validation_enabled" == "true" ]]; then
        write_validation_status "$validation_status_file" "skipped" "true" ""
        validation_status="skipped"
      fi

      local validation_end_data
      local validation_results_rel=""
      if [[ -f "$validation_results_file" ]]; then
        validation_results_rel="${validation_results_file#$repo/}"
      fi
      validation_end_data=$(jq -n \
        --arg status "$validation_status" \
        --arg results_file "$validation_results_rel" \
        '{status: $status, results_file: $results_file}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "validation_end" "$validation_end_data"

      if [[ "$validation_enabled" == "true" && "$validation_require" == "true" ]]; then
        validation_gate_ok=$validation_ok
      fi

      local evidence_status="skipped"
      local evidence_ok=1
      local evidence_gate_ok=1
      local evidence_start_data
      evidence_start_data=$(jq -n --arg enabled "$evidence_enabled" '{enabled: $enabled}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "evidence_start" "$evidence_start_data"
      if [[ "$evidence_enabled" == "true" ]]; then
        if write_evidence_manifest "$repo" "$loop_dir" "$loop_id" "$iteration" "$spec_file" "$loop_json" "$test_status" "$test_output" "$checklist_status" "$evidence_file"; then
          evidence_status="ok"
          evidence_ok=1
        else
          evidence_status="failed"
          evidence_ok=0
        fi
      fi
      local evidence_end_data
      evidence_end_data=$(jq -n \
        --arg status "$evidence_status" \
        --arg evidence_file "${evidence_file#$repo/}" \
        '{status: $status, evidence_file: $evidence_file}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "evidence_end" "$evidence_end_data"
      if [[ "$evidence_enabled" == "true" && "$evidence_require" == "true" ]]; then
        evidence_gate_ok=$evidence_ok
      fi

      local progress_signature_prev=""
      local progress_signature_current=""
      local no_progress="false"
      if [[ "$stuck_enabled" == "true" && "$checklist_status_text" != "ok" ]]; then
        if [[ -f "$loop_dir/stuck.json" ]]; then
          progress_signature_prev=$(jq -r '.signature // ""' "$loop_dir/stuck.json" 2>/dev/null || true)
        fi
        if [[ -n "$progress_signature_prev" ]]; then
          local signature_rc=0
          set +e
          progress_signature_current=$(compute_signature "$repo" "${stuck_ignore[@]}")
          signature_rc=$?
          set -e
          if [[ $signature_rc -ne 0 ]]; then
            die "stuck signature computation failed for loop '$loop_id'"
          fi
          if [[ "$progress_signature_current" == "$progress_signature_prev" ]]; then
            no_progress="true"
          fi
        fi
      fi

      local candidate_ok=0
      if [[ "$promise_matched" == "true" && $tests_ok -eq 1 && $validation_gate_ok -eq 1 && $checklist_ok -eq 1 && $evidence_gate_ok -eq 1 ]]; then
        candidate_ok=1
      fi

      local approval_status="skipped"
      local approval_ok=1
      if [[ $approval_required -eq 1 && $candidate_ok -eq 1 ]]; then
        approval_status="pending"
        approval_ok=0
      fi

      local completion_ok=0
      if [[ $candidate_ok -eq 1 && $approval_ok -eq 1 ]]; then
        completion_ok=1
      fi

      local stuck_streak="0"
      local stuck_triggered="false"
      if [[ $completion_ok -eq 0 && "$stuck_enabled" == "true" && $candidate_ok -eq 0 ]]; then
        local stuck_result
        local stuck_rc=0
        set +e
        stuck_result=$(update_stuck_state "$repo" "$loop_dir" "$stuck_threshold" "${stuck_ignore[@]}")
        stuck_rc=$?
        set -e
        if [[ $stuck_rc -eq 0 ]]; then
          stuck_streak="$stuck_result"
          if [[ "$no_progress" == "true" ]]; then
            write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
            local stuck_value="n/a"
            if [[ "$stuck_enabled" == "true" ]]; then
              stuck_value="${stuck_streak}/${stuck_threshold}"
            fi
            write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
            local no_progress_data
            no_progress_data=$(jq -n \
              --arg reason "checklist_remaining_no_change" \
              --arg signature "$progress_signature_current" \
              --argjson streak "$stuck_streak" \
              --argjson threshold "$stuck_threshold" \
              '{reason: $reason, signature: $signature, streak: $streak, threshold: $threshold}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "no_progress_stop" "$no_progress_data" "" "blocked"
            local loop_stop_data
            loop_stop_data=$(jq -n --arg reason "no_progress" --argjson streak "$stuck_streak" --argjson threshold "$stuck_threshold" '{reason: $reason, streak: $streak, threshold: $threshold}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_stop" "$loop_stop_data"
            if [[ "${dry_run:-0}" -ne 1 ]]; then
              write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
            fi
            return 1
          fi
        elif [[ $stuck_rc -eq 2 ]]; then
          stuck_streak="$stuck_result"
          stuck_triggered="true"
          write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
          local stuck_value="n/a"
          if [[ "$stuck_enabled" == "true" ]]; then
            stuck_value="${stuck_streak}/${stuck_threshold}"
          fi
          write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
          local stuck_data
          stuck_data=$(jq -n \
            --argjson streak "$stuck_streak" \
            --argjson threshold "$stuck_threshold" \
            --argjson triggered true \
            --arg action "$stuck_action" \
            '{streak: $streak, threshold: $threshold, triggered: $triggered, action: $action}')
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "stuck_checked" "$stuck_data"
          if [[ "$stuck_action" == "report_and_stop" ]]; then
            echo "Stuck detection triggered for loop '$loop_id'. Stopping."
            local loop_stop_data
            loop_stop_data=$(jq -n --arg reason "stuck" --argjson streak "$stuck_streak" --argjson threshold "$stuck_threshold" '{reason: $reason, streak: $streak, threshold: $threshold}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_stop" "$loop_stop_data"
            write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
            return 1
          fi
        else
          die "stuck detection failed for loop '$loop_id'"
        fi
      fi
      if [[ "$stuck_enabled" == "true" && "$stuck_triggered" != "true" ]]; then
        local stuck_triggered_json="false"
        local stuck_data
        stuck_data=$(jq -n \
          --argjson streak "$stuck_streak" \
          --argjson threshold "$stuck_threshold" \
          --argjson triggered "$stuck_triggered_json" \
          --arg action "$stuck_action" \
          '{streak: $streak, threshold: $threshold, triggered: $triggered, action: $action}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "stuck_checked" "$stuck_data"
      fi

      write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
      local stuck_value="n/a"
      if [[ "$stuck_enabled" == "true" ]]; then
        stuck_value="${stuck_streak}/${stuck_threshold}"
      fi
      write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
      local gates_data
      gates_data=$(jq -n \
        --argjson promise "$promise_matched_json" \
        --arg tests "$tests_status" \
        --arg validation "$validation_status" \
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        --arg approval "$approval_status" \
        --arg stuck "$stuck_value" \
        '{promise: $promise, tests: $tests, validation: $validation, checklist: $checklist, evidence: $evidence, approval: $approval, stuck: $stuck}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "gates_evaluated" "$gates_data"

      local iteration_ended_at
      iteration_ended_at=$(timestamp)
      local completion_json="false"
      if [[ $completion_ok -eq 1 ]]; then
        completion_json="true"
      fi
      local iteration_end_data
      iteration_end_data=$(jq -n \
        --arg started_at "$iteration_started_at" \
        --arg ended_at "$iteration_ended_at" \
        --argjson completion "$completion_json" \
        --argjson promise "$promise_matched_json" \
        --arg tests "$tests_status" \
        --arg validation "$validation_status" \
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        --arg approval "$approval_status" \
        '{started_at: $started_at, ended_at: $ended_at, completion: $completion, promise: $promise, tests: $tests, validation: $validation, checklist: $checklist, evidence: $evidence, approval: $approval}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "iteration_end" "$iteration_end_data"

      append_run_summary "$run_summary_file" "$repo" "$loop_id" "$run_id" "$iteration" "$iteration_started_at" "$iteration_ended_at" "$promise_matched" "$completion_promise" "$promise_text" "$tests_mode" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$approval_status" "$stuck_streak" "$stuck_threshold" "$completion_ok" "$loop_dir" "$events_file"
      write_timeline "$run_summary_file" "$timeline_file"

      if [[ $approval_required -eq 1 && $candidate_ok -eq 1 ]]; then
        write_approval_request \
          "$approval_file" \
          "$loop_id" \
          "$run_id" \
          "$iteration" \
          "$iteration_started_at" \
          "$iteration_ended_at" \
          "$completion_promise" \
          "$promise_text" \
          "$promise_matched" \
          "$tests_status" \
          "$validation_status" \
          "$checklist_status_text" \
          "$evidence_status" \
          "${summary_file#$repo/}" \
          "${evidence_file#$repo/}" \
          "${reviewer_report#$repo/}" \
          "${test_report#$repo/}" \
          "${plan_file#$repo/}" \
          "${notes_file#$repo/}"

        local approval_request_data
        approval_request_data=$(jq -n \
          --arg approval_file "${approval_file#$repo/}" \
          --argjson promise "$promise_matched_json" \
          --arg tests "$tests_status" \
          --arg validation "$validation_status" \
          --arg checklist "$checklist_status_text" \
          --arg evidence "$evidence_status" \
          '{approval_file: $approval_file, promise: $promise, tests: $tests, validation: $validation, checklist: $checklist, evidence: $evidence}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_requested" "$approval_request_data"

        echo "Approval required for loop '$loop_id'. Run: superloop.sh approve --repo $repo --loop $loop_id"
        write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
        return 0
      fi

      if [[ $completion_ok -eq 1 ]]; then
        local loop_complete_data
        loop_complete_data=$(jq -n \
          --argjson iteration "$iteration" \
          --arg run_id "$run_id" \
          '{iteration: $iteration, run_id: $run_id}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_complete" "$loop_complete_data"
        echo "Loop '$loop_id' complete at iteration $iteration."
        iteration=1
        break
      fi

      iteration=$((iteration + 1))
    done

    if [[ -n "$target_loop_id" && "$loop_id" == "$target_loop_id" ]]; then
      if [[ "${dry_run:-0}" -ne 1 ]]; then
        write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
      fi
      return 0
    fi
  done

  if [[ "${dry_run:-0}" -ne 1 ]]; then
    write_state "$state_file" "$loop_count" 0 "" "false"
    echo "All loops complete."
  else
    echo "Dry-run complete."
  fi
}

status_cmd() {
  local repo="$1"
  local summary="${2:-0}"
  local loop_id="${3:-}"
  local config_path="${4:-}"

  if [[ "${summary:-0}" -eq 1 ]]; then
    need_cmd jq
    local target_loop="$loop_id"
    if [[ -z "$target_loop" && -n "$config_path" && -f "$config_path" ]]; then
      target_loop=$(jq -r '.loops[0].id // ""' "$config_path")
    fi
    if [[ -z "$target_loop" || "$target_loop" == "null" ]]; then
      die "loop id required for status --summary (use --loop or config)"
    fi

    local summary_file="$repo/.superloop/loops/$target_loop/run-summary.json"
    if [[ ! -f "$summary_file" ]]; then
      echo "No run summary found for loop '$target_loop'."
      return 0
    fi

    jq -r --arg loop "$target_loop" '
      .updated_at as $updated |
      .entries[-1] as $e |
      if $e == null then
        "No run summary entries found for loop \($loop)."
      else
        [
          "loop=" + $loop,
          "run_id=" + ($e.run_id // "unknown"),
          "iteration=" + (($e.iteration // 0) | tostring),
          "updated_at=" + ($updated // "unknown"),
          "promise=" + (($e.promise.matched // false) | tostring),
          "tests=" + ($e.gates.tests // "unknown"),
          "validation=" + ($e.gates.validation // "unknown"),
          "checklist=" + ($e.gates.checklist // "unknown"),
          "evidence=" + ($e.gates.evidence // "unknown"),
          "approval=" + ($e.gates.approval // "unknown"),
          "evidence_file=" + ($e.artifacts.evidence.path // "unknown"),
          "evidence_exists=" + (($e.artifacts.evidence.exists // false) | tostring),
          "evidence_sha256=" + ($e.artifacts.evidence.sha256 // "unknown"),
          "evidence_mtime=" + (($e.artifacts.evidence.mtime // "unknown") | tostring)
        ] | join(" ")
      end
    ' "$summary_file"
    return 0
  fi

  local state_file="$repo/.superloop/state.json"

  if [[ ! -f "$state_file" ]]; then
    echo "No state file found."
    return 0
  fi

  cat "$state_file"
}

cancel_cmd() {
  local repo="$1"
  local state_file="$repo/.superloop/state.json"

  if [[ ! -f "$state_file" ]]; then
    echo "No active state file found."
    return 0
  fi

  rm "$state_file"
  echo "Cancelled loop state."
}

approve_cmd() {
  local repo="$1"
  local loop_id="$2"
  local approver="$3"
  local note="$4"
  local reject="$5"

  need_cmd jq

  if [[ -z "$loop_id" ]]; then
    die "--loop is required for approve"
  fi

  local loop_dir="$repo/.superloop/loops/$loop_id"
  local approval_file="$loop_dir/approval.json"
  local events_file="$loop_dir/events.jsonl"

  if [[ ! -f "$approval_file" ]]; then
    die "no approval request found for loop '$loop_id'"
  fi

  local status
  status=$(jq -r '.status // "pending"' "$approval_file")
  if [[ "$status" != "pending" ]]; then
    die "approval request is not pending (status=$status)"
  fi

  local run_id iteration
  run_id=$(jq -r '.run_id // ""' "$approval_file")
  iteration=$(jq -r '.iteration // 0' "$approval_file")
  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    run_id="unknown"
  fi
  if [[ -z "$iteration" || "$iteration" == "null" ]]; then
    iteration=0
  fi

  local decided_by="$approver"
  if [[ -z "$decided_by" ]]; then
    decided_by="${USER:-unknown}"
  fi
  local decision="approved"
  if [[ "${reject:-0}" -eq 1 ]]; then
    decision="rejected"
  fi
  local decided_at
  decided_at=$(timestamp)

  jq \
    --arg status "$decision" \
    --arg decided_by "$decided_by" \
    --arg decided_at "$decided_at" \
    --arg note "$note" \
    '.status = $status
     | .decision = {status: $status, by: $decided_by, note: (if ($note | length) > 0 then $note else null end), at: $decided_at}
     | .decided_at = $decided_at
     | .decided_by = $decided_by
     | .decided_note = (if ($note | length) > 0 then $note else null end)' \
    "$approval_file" > "${approval_file}.tmp"
  mv "${approval_file}.tmp" "$approval_file"

  append_decision_log "$loop_dir" "$loop_id" "$run_id" "$iteration" "$decision" "$decided_by" "$note" "${approval_file#$repo/}" "$decided_at"

  local decision_data
  decision_data=$(jq -n \
    --arg status "$decision" \
    --arg by "$decided_by" \
    --arg note "$note" \
    --arg at "$decided_at" \
    '{status: $status, by: $by, note: (if ($note | length) > 0 then $note else null end), at: $at}')
  log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_decision" "$decision_data" "human" "$decision"

  echo "Recorded approval decision ($decision) for loop '$loop_id'."
}
