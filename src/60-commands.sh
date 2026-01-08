init_cmd() {
  local repo="$1"
  local force="$2"
  local superloop_dir="$repo/.superloop"

  mkdir -p "$superloop_dir/roles" "$superloop_dir/loops" "$superloop_dir/logs"

  if [[ -f "$superloop_dir/config.json" && $force -ne 1 ]]; then
    die "found existing $superloop_dir/config.json (use --force to overwrite)"
  fi

  cat > "$superloop_dir/config.json" <<'EOF'
{
  "runner": {
    "command": ["codex", "exec"],
    "args": ["--full-auto", "-C", "{repo}", "--output-last-message", "{last_message_file}", "-"],
    "fast_args": [],
    "prompt_mode": "stdin"
  },
  "loops": [
    {
      "id": "initiation",
      "spec_file": ".superloop/spec.md",
      "max_iterations": 20,
      "completion_promise": "INITIATION_READY",
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
      "roles": ["planner", "implementer", "tester", "reviewer"]
    }
  ]
}
EOF

  cat > "$superloop_dir/spec.md" <<'EOF'
# Supergent Loop Spec

Replace this file with the actual task specification.

Include:
- Goal and scope
- Requirements and constraints
- Verification steps
- Completion criteria
- Promise tag usage
EOF

  cat > "$superloop_dir/roles/planner.md" <<'EOF'
You are the Planner.

Responsibilities:
- Read the spec and iteration notes.
- Maintain a concise, ordered plan (3-7 steps) aligned with the spec and current status.
- Note blockers or unclear requirements in the plan.
- If you identify files that will need to be created or modified, list them in a "Target Files" section.

Rules:
- Do not modify code or run tests.
- Do not output a promise tag.
- Minimize plan churn: if the current plan still matches the spec/status, do not edit the plan file.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged steps).
- Avoid speculative blockers: keep "None" unless a concrete blocker appears; do not update blockers just to note verification completion.
- Write only to the plan file path listed in context.
EOF

  cat > "$superloop_dir/roles/implementer.md" <<'EOF'
You are the Implementer.

Responsibilities:
- Read the spec and plan.
- Implement the required changes in the codebase.
- Summarize changes in the implementer report.

Rules:
- Do not edit the spec or plan files.
- Do not run tests.
- Do not output a promise tag.
- Minimize report churn: if the report already reflects the current state and no changes were made, do not edit it.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged bullets).
- Write your summary to the implementer report file path listed in context.
- Always include a "Files Touched" section in your report listing every file you created, modified, or deleted. Use this format:
  ## Files Touched
  - CREATED: path/to/new/file.ts
  - MODIFIED: path/to/changed/file.ts
  - DELETED: path/to/removed/file.ts
EOF

  cat > "$superloop_dir/roles/tester.md" <<'EOF'
You are the Tester.

Responsibilities:
- Read test status and test output files.
- Summarize failures or gaps in the test report.

Rules:
- Do not modify code or rerun tests.
- Do not output a promise tag.
- Minimize report churn: if test status/output are unchanged and the report is accurate, do not edit it.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged text).
- Do not update the report just to refresh timestamps (e.g., generated_at); update only when status/output or gaps materially change.
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

  echo "Initialized .superloop in $superloop_dir"
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

  local -a runner_command=()
  while IFS= read -r line; do
    runner_command+=("$line")
  done < <(jq -r '.runner.command[]?' "$config_path")
  if [[ ${#runner_command[@]} -eq 0 ]]; then
    die "runner.command is required"
  fi

  local -a runner_args=()
  while IFS= read -r line; do
    runner_args+=("$line")
  done < <(jq -r '.runner.args[]?' "$config_path")
  if [[ ${#runner_args[@]} -eq 0 ]]; then
    die "runner.args is required"
  fi

  local -a runner_fast_args=()
  while IFS= read -r line; do
    runner_fast_args+=("$line")
  done < <(jq -r '.runner.fast_args[]?' "$config_path")

  local runner_prompt_mode
  runner_prompt_mode=$(jq -r '.runner.prompt_mode // "stdin"' "$config_path")
  if [[ "$runner_prompt_mode" != "stdin" && "$runner_prompt_mode" != "file" ]]; then
    die "runner.prompt_mode must be stdin or file"
  fi

  if [[ "${dry_run:-0}" -ne 1 ]]; then
    need_exec "${runner_command[0]}"
  fi

  local -a runner_active_args=("${runner_args[@]}")
  if [[ "${fast_mode:-0}" -eq 1 ]]; then
    if [[ ${#runner_fast_args[@]} -gt 0 ]]; then
      runner_active_args=("${runner_fast_args[@]}")
    else
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

    mkdir -p "$loop_dir" "$prompt_dir" "$log_dir"
    touch "$plan_file" "$notes_file" "$implementer_report" "$reviewer_report" "$test_report"

    local -a roles=()
    while IFS= read -r line; do
      roles+=("$line")
    done < <(jq -r '.roles[]?' <<<"$loop_json")
    if [[ ${#roles[@]} -eq 0 ]]; then
      roles=(planner implementer tester reviewer)
    fi

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

    local reviewer_packet_enabled
    reviewer_packet_enabled=$(jq -r '.reviewer_packet.enabled // false' <<<"$loop_json")

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

      local tests_status checklist_status_text evidence_status stuck_value
      tests_status=$(read_test_status_summary "$test_status")
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

      echo "Dry-run summary ($loop_id): promise=$promise_status tests=$tests_status checklist=$checklist_status_text evidence=$evidence_status approval=$approval_status stuck=$stuck_value"
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
        local approval_tests approval_checklist approval_evidence approval_started_at approval_ended_at
        local approval_decision_by approval_decision_note approval_decision_at
        approval_run_id=$(jq -r '.run_id // ""' "$approval_file")
        approval_iteration=$(jq -r '.iteration // 0' "$approval_file")
        approval_promise_text=$(jq -r '.candidate.promise.text // ""' "$approval_file")
        approval_promise_matched=$(jq -r '.candidate.promise.matched // false' "$approval_file")
        approval_tests=$(jq -r '.candidate.gates.tests // "unknown"' "$approval_file")
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

        write_iteration_notes "$notes_file" "$loop_id" "$approval_iteration" "$promise_matched" "$tests_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
        write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"

        local approval_consume_data
        approval_consume_data=$(jq -n \
          --arg status "approved" \
          --arg by "$approval_decision_by" \
          --arg note "$approval_decision_note" \
          --arg at "$approval_decision_at" \
          '{status: $status, by: (if ($by | length) > 0 then $by else null end), note: (if ($note | length) > 0 then $note else null end), at: (if ($at | length) > 0 then $at else null end)}')
        log_event "$events_file" "$loop_id" "$approval_iteration" "$approval_run_id" "approval_consumed" "$approval_consume_data"

        local completion_ok=1
        append_run_summary "$run_summary_file" "$repo" "$loop_id" "$approval_run_id" "$approval_iteration" "$approval_started_at" "$approval_ended_at" "$promise_matched" "$completion_promise" "$approval_promise_text" "$tests_mode" "$tests_status" "$checklist_status_text" "$evidence_status" "$approval_status" "$stuck_streak" "$stuck_threshold" "$completion_ok" "$loop_dir" "$events_file"
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
          "$checklist_status" \
          "$checklist_remaining" \
          "$evidence_file" \
          "$reviewer_packet" \
          "$changed_files_planner" \
          "$changed_files_implementer" \
          "$changed_files_all"

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

        local role_status=0
        if [[ "$role" == "openprose" ]]; then
          run_openprose_role "$repo" "$loop_dir" "$prompt_dir" "$log_dir" "$last_messages_dir" "$role_log" "$last_message_file" "$implementer_report" "$role_timeout_seconds" "$runner_prompt_mode" "${runner_command[@]}" -- "${runner_active_args[@]}"
          role_status=$?
        else
          run_role "$repo" "$role" "$prompt_file" "$last_message_file" "$role_log" "$role_timeout_seconds" "$runner_prompt_mode" "$usage_file" "$iteration" "${runner_command[@]}" -- "${runner_active_args[@]}"
          role_status=$?
        fi
        if [[ -n "$report_guard" ]]; then
          if [[ $role_status -eq 124 ]]; then
            rm -f "$report_snapshot"
          else
            restore_if_unchanged "$report_guard" "$report_snapshot"
          fi
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

      local candidate_ok=0
      if [[ "$promise_matched" == "true" && $tests_ok -eq 1 && $checklist_ok -eq 1 && $evidence_gate_ok -eq 1 ]]; then
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
        stuck_result=$(update_stuck_state "$repo" "$loop_dir" "$stuck_threshold" "${stuck_ignore[@]}")
        local stuck_rc=$?
        if [[ $stuck_rc -eq 0 ]]; then
          stuck_streak="$stuck_result"
        elif [[ $stuck_rc -eq 2 ]]; then
          stuck_streak="$stuck_result"
          stuck_triggered="true"
          write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
          local stuck_value="n/a"
          if [[ "$stuck_enabled" == "true" ]]; then
            stuck_value="${stuck_streak}/${stuck_threshold}"
          fi
          write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
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

      write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
      local stuck_value="n/a"
      if [[ "$stuck_enabled" == "true" ]]; then
        stuck_value="${stuck_streak}/${stuck_threshold}"
      fi
      write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
      local gates_data
      gates_data=$(jq -n \
        --argjson promise "$promise_matched_json" \
        --arg tests "$tests_status" \
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        --arg approval "$approval_status" \
        --arg stuck "$stuck_value" \
        '{promise: $promise, tests: $tests, checklist: $checklist, evidence: $evidence, approval: $approval, stuck: $stuck}')
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
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        --arg approval "$approval_status" \
        '{started_at: $started_at, ended_at: $ended_at, completion: $completion, promise: $promise, tests: $tests, checklist: $checklist, evidence: $evidence, approval: $approval}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "iteration_end" "$iteration_end_data"

      append_run_summary "$run_summary_file" "$repo" "$loop_id" "$run_id" "$iteration" "$iteration_started_at" "$iteration_ended_at" "$promise_matched" "$completion_promise" "$promise_text" "$tests_mode" "$tests_status" "$checklist_status_text" "$evidence_status" "$approval_status" "$stuck_streak" "$stuck_threshold" "$completion_ok" "$loop_dir" "$events_file"
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
          --arg checklist "$checklist_status_text" \
          --arg evidence "$evidence_status" \
          '{approval_file: $approval_file, promise: $promise, tests: $tests, checklist: $checklist, evidence: $evidence}')
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
