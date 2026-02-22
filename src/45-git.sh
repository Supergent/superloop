#!/usr/bin/env bash
# Git operations for superloop
# Handles automatic commits after iterations

LLM_COMMIT_PROMPT_FILE=""
LLM_COMMIT_LOG_FILE=""
LLM_COMMIT_LAST_MESSAGE_FILE=""

sanitize_commit_subject() {
  local subject="$1"
  subject=$(echo "$subject" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//')
  echo "$subject"
}

build_template_commit_message() {
  local loop_id="$1"
  local iteration="$2"
  local current_phase="$3"
  local tests_status="$4"
  local commit_strategy="$5"

  local test_indicator=""
  case "$tests_status" in
    ok) test_indicator="tests: passing" ;;
    failed) test_indicator="tests: failing" ;;
    skipped) test_indicator="tests: skipped" ;;
    *) test_indicator="tests: $tests_status" ;;
  esac

  local subject="[superloop] $loop_id iteration $iteration: $current_phase ($test_indicator)"
  cat <<EOF_MESSAGE
$subject

Automated commit created after iteration $iteration.

Superloop-Loop: $loop_id
Superloop-Iteration: $iteration
Superloop-Commit-Strategy: $commit_strategy
Commit-Message-Author: template
EOF_MESSAGE
}

generate_llm_commit_message() {
  local repo="$1"
  local loop_dir="$2"
  local loop_id="$3"
  local iteration="$4"
  local tests_status="$5"
  local commit_strategy="$6"
  local current_phase="$7"
  local authoring="$8"
  local author_role="$9"
  local timeout_seconds="${10}"
  local max_subject_length="${11}"
  local runner_prompt_mode="${12}"
  local runner_command_json="${13}"
  local runner_args_json="${14}"
  local runner_thinking_env="${15:-}"

  LLM_COMMIT_PROMPT_FILE=""
  LLM_COMMIT_LOG_FILE=""
  LLM_COMMIT_LAST_MESSAGE_FILE=""

  if [[ "$authoring" != "llm" ]]; then
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local -a runner_command=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && runner_command+=("$line")
  done < <(jq -r '.[]? // empty' <<<"$runner_command_json")

  local -a runner_args=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && runner_args+=("$line")
  done < <(jq -r '.[]? // empty' <<<"$runner_args_json")

  if [[ ${#runner_command[@]} -eq 0 ]]; then
    return 1
  fi

  local commit_dir="$loop_dir/commit-message"
  mkdir -p "$commit_dir"
  local prompt_file="$commit_dir/iter-$iteration.llm.prompt.md"
  local log_file="$commit_dir/iter-$iteration.llm.log"
  local last_message_file="$commit_dir/iter-$iteration.llm.last.txt"
  LLM_COMMIT_PROMPT_FILE="$prompt_file"
  LLM_COMMIT_LOG_FILE="$log_file"
  LLM_COMMIT_LAST_MESSAGE_FILE="$last_message_file"

  local changed_files=""
  changed_files=$(git -C "$repo" diff --cached --name-status --no-renames 2>/dev/null | sed 's/^/- /' | head -n 200)
  local diff_stat=""
  diff_stat=$(git -C "$repo" diff --cached --shortstat 2>/dev/null || true)
  local diff_excerpt=""
  diff_excerpt=$(git -C "$repo" diff --cached --no-color --unified=0 2>/dev/null | head -n 1200)

  cat > "$prompt_file" <<EOF_PROMPT
You are writing a git commit message for a Superloop iteration.

Output requirements:
1. Return ONLY valid JSON (no markdown fences, no commentary).
2. JSON object keys:
   - "subject": string, <= ${max_subject_length} characters.
   - "body": array of 1-5 concise lines with concrete changes and why.
   - "footers": array of optional footer lines.
3. Do not invent changes. Use only provided context.
4. Keep subject specific and action-oriented.

Context:
- Loop ID: $loop_id
- Iteration: $iteration
- Author role: $author_role
- Commit strategy: $commit_strategy
- Current phase: $current_phase
- Tests status: $tests_status
- Diff stat: ${diff_stat:-none}

Staged files:
${changed_files:-none}

Diff excerpt:
\`\`\`diff
${diff_excerpt:-# (no diff excerpt available)}
\`\`\`
EOF_PROMPT

  local -a cmd=()
  local part
  for part in "${runner_command[@]}"; do
    cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
  done
  for part in "${runner_args[@]}"; do
    cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
  done

  local status=0
  if [[ "${runner_prompt_mode:-stdin}" != "stdin" && "${runner_prompt_mode:-stdin}" != "file" ]]; then
    runner_prompt_mode="stdin"
  fi

  if [[ "${timeout_seconds:-0}" -gt 0 ]] && declare -f run_command_with_timeout >/dev/null 2>&1; then
    set +e
    if [[ -n "$runner_thinking_env" ]]; then
      env "$runner_thinking_env" run_command_with_timeout "$prompt_file" "$log_file" "$timeout_seconds" "$runner_prompt_mode" 0 "${cmd[@]}"
    else
      run_command_with_timeout "$prompt_file" "$log_file" "$timeout_seconds" "$runner_prompt_mode" 0 "${cmd[@]}"
    fi
    status=$?
    set -e
  else
    set +e
    if [[ "$runner_prompt_mode" == "stdin" ]]; then
      if [[ -n "$runner_thinking_env" ]]; then
        env "$runner_thinking_env" "${cmd[@]}" < "$prompt_file" | tee "$log_file"
      else
        "${cmd[@]}" < "$prompt_file" | tee "$log_file"
      fi
    else
      if [[ -n "$runner_thinking_env" ]]; then
        env "$runner_thinking_env" "${cmd[@]}" | tee "$log_file"
      else
        "${cmd[@]}" | tee "$log_file"
      fi
    fi
    status=${PIPESTATUS[0]}
    set -e
  fi

  if [[ $status -ne 0 ]]; then
    return 1
  fi

  local payload_file="$last_message_file"
  if [[ ! -s "$payload_file" ]]; then
    payload_file="$log_file"
  fi
  if [[ ! -f "$payload_file" ]]; then
    return 1
  fi

  local payload_json=""
  if jq -e . "$payload_file" >/dev/null 2>&1; then
    payload_json=$(cat "$payload_file")
  else
    local fenced_json=""
    fenced_json=$(sed -n '/```json/,/```/p' "$payload_file" | sed '1d;$d')
    if [[ -n "$fenced_json" ]] && jq -e . >/dev/null 2>&1 <<<"$fenced_json"; then
      payload_json="$fenced_json"
    fi
  fi

  if [[ -z "$payload_json" ]]; then
    return 1
  fi

  local subject
  subject=$(jq -r '.subject // empty' <<<"$payload_json" 2>/dev/null || true)
  subject=$(sanitize_commit_subject "$subject")
  if [[ -z "$subject" ]]; then
    return 1
  fi
  if [[ ${#subject} -gt "$max_subject_length" ]]; then
    subject="${subject:0:$max_subject_length}"
    subject=$(sanitize_commit_subject "$subject")
  fi
  if [[ -z "$subject" ]]; then
    return 1
  fi

  local body_text=""
  body_text=$(jq -r '
    if (.body | type) == "array" then
      .body[]
    elif (.body | type) == "string" then
      .body
    else
      empty
    end' <<<"$payload_json" 2>/dev/null | sed -E 's/[[:space:]]+$//' | sed '/^[[:space:]]*$/d')

  local footer_text=""
  footer_text=$(jq -r '
    if (.footers | type) == "array" then
      .footers[]
    elif (.footers | type) == "string" then
      .footers
    else
      empty
    end' <<<"$payload_json" 2>/dev/null | sed -E 's/[[:space:]]+$//' | sed '/^[[:space:]]*$/d')

  local commit_msg="$subject"
  if [[ -n "$body_text" ]]; then
    commit_msg="$commit_msg"$'\n\n'"$body_text"
  fi
  if [[ -n "$footer_text" ]]; then
    commit_msg="$commit_msg"$'\n\n'"$footer_text"
  fi
  commit_msg="$commit_msg"$'\n\n'"Superloop-Loop: $loop_id"$'\n'"Superloop-Iteration: $iteration"$'\n'"Superloop-Commit-Strategy: $commit_strategy"$'\n'"Commit-Message-Author: llm:$author_role"

  printf '%s\n' "$commit_msg"
  return 0
}

# Auto-commit changes after an iteration
# Arguments:
#   $1 - repo path
#   $2 - loop_id
#   $3 - iteration number
#   $4 - tests_status (ok, failed, skipped)
#   $5 - commit_strategy (per_iteration, on_test_pass, never)
#   $6 - events_file for logging
#   $7 - run_id
#   $8 - pre_commit_commands (optional command to run before commit)
#   $9 - commit_message_authoring (llm)
#  $10 - commit_message_author_role
#  $11 - commit_message_timeout_seconds
#  $12 - commit_message_max_subject_length
#  $13 - commit_message_runner_prompt_mode
#  $14 - commit_message_runner_command_json
#  $15 - commit_message_runner_args_json
#  $16 - commit_message_runner_thinking_env
# Returns: 0 on success or skip, 1 on failure
auto_commit_iteration() {
  local repo="$1"
  local loop_id="$2"
  local iteration="$3"
  local tests_status="$4"
  local commit_strategy="$5"
  local events_file="$6"
  local run_id="$7"
  local pre_commit_commands="${8:-}"
  local commit_message_authoring="${9:-llm}"
  local commit_message_author_role="${10:-reviewer}"
  local commit_message_timeout_seconds="${11:-120}"
  local commit_message_max_subject_length="${12:-72}"
  local commit_message_runner_prompt_mode="${13:-stdin}"
  local commit_message_runner_command_json="${14:-[]}"
  local commit_message_runner_args_json="${15:-[]}"
  local commit_message_runner_thinking_env="${16:-}"

  # Check if commits are disabled
  if [[ "$commit_strategy" == "never" || -z "$commit_strategy" ]]; then
    return 0
  fi

  # Check if we should skip based on test status
  if [[ "$commit_strategy" == "on_test_pass" && "$tests_status" != "ok" ]]; then
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_skipped" \
      "$(jq -n --arg reason "tests_not_passing" --arg tests_status "$tests_status" '{reason: $reason, tests_status: $tests_status}')"
    return 0
  fi

  # Check if there are any changes to commit
  local has_changes=0
  if ! git -C "$repo" diff --quiet HEAD 2>/dev/null; then
    has_changes=1
  fi
  if [[ $has_changes -eq 0 ]] && [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
    has_changes=1
  fi

  if [[ $has_changes -eq 0 ]]; then
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_skipped" \
      "$(jq -n --arg reason "no_changes" '{reason: $reason}')"
    return 0
  fi

  # Determine what phase we're in by looking at task files
  local loop_dir="$repo/.superloop/loops/$loop_id"
  local current_phase="unknown"
  local latest_phase_file
  latest_phase_file=$(ls -t "$loop_dir/tasks/"PHASE_*.MD 2>/dev/null | head -1)
  if [[ -n "$latest_phase_file" ]]; then
    current_phase=$(basename "$latest_phase_file" .MD | sed 's/PHASE_/Phase /')
  fi

  # Stage all changes (including untracked files in the repo, excluding .superloop internal files)
  # We want to commit implementation work, not loop state files
  local staged_count=0

  # Stage tracked file changes
  git -C "$repo" add -u 2>/dev/null || true

  # Stage new files, excluding .superloop directory
  while IFS= read -r file; do
    if [[ -n "$file" && ! "$file" =~ ^\.superloop/ ]]; then
      git -C "$repo" add "$file" 2>/dev/null || true
      ((staged_count++)) || true
    fi
  done < <(git -C "$repo" status --porcelain 2>/dev/null | grep '^??' | cut -c4-)

  # Check if we actually staged anything
  if git -C "$repo" diff --cached --quiet 2>/dev/null; then
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_skipped" \
      "$(jq -n --arg reason "nothing_staged" '{reason: $reason}')"
    return 0
  fi

  # Run pre-commit commands if configured
  if [[ -n "$pre_commit_commands" ]]; then
    echo "[superloop] Running pre-commit commands: $pre_commit_commands" >&2
    local pre_commit_output
    local pre_commit_exit_code
    # Execute exactly once via a shell to avoid eval's double expansion.
    pre_commit_output=$(cd "$repo" && bash -o pipefail -c "$pre_commit_commands" 2>&1)
    pre_commit_exit_code=$?

    # Log pre-commit execution to events (for reviewer visibility)
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "pre_commit_executed" \
      "$(jq -n --arg cmd "$pre_commit_commands" --arg exit_code "$pre_commit_exit_code" --arg output "$pre_commit_output" '{command: $cmd, exit_code: ($exit_code | tonumber), output: $output}')"

    # Write lint feedback to a file for Reviewer to read
    local lint_feedback_file="$loop_dir/lint-feedback.txt"
    cat > "$lint_feedback_file" <<EOF_LINT
# Lint Feedback (Iteration $iteration)

Command: $pre_commit_commands
Exit Code: $pre_commit_exit_code
Status: $([ $pre_commit_exit_code -eq 0 ] && echo "SUCCESS" || echo "FAILED")

## Output:
$pre_commit_output
EOF_LINT

    if [[ $pre_commit_exit_code -ne 0 ]]; then
      echo "[superloop] Pre-commit commands failed (exit $pre_commit_exit_code), attempting commit anyway..." >&2
      echo "[superloop] Output: $pre_commit_output" >&2
    else
      echo "[superloop] Pre-commit commands succeeded" >&2
    fi

    # Re-stage changes after pre-commit commands (e.g., lint fixes)
    git -C "$repo" add -u 2>/dev/null || true

    # Stage any new files that might have been created, excluding .superloop
    while IFS= read -r file; do
      if [[ -n "$file" && ! "$file" =~ ^\.superloop/ ]]; then
        git -C "$repo" add "$file" 2>/dev/null || true
      fi
    done < <(git -C "$repo" status --porcelain 2>/dev/null | grep '^??' | cut -c4-)
  fi

  local commit_msg_source="template"
  local commit_msg
  commit_msg=$(build_template_commit_message "$loop_id" "$iteration" "$current_phase" "$tests_status" "$commit_strategy")

  if [[ "$commit_message_authoring" == "llm" ]]; then
    local llm_commit_msg=""
    if llm_commit_msg=$(generate_llm_commit_message \
      "$repo" \
      "$loop_dir" \
      "$loop_id" \
      "$iteration" \
      "$tests_status" \
      "$commit_strategy" \
      "$current_phase" \
      "$commit_message_authoring" \
      "$commit_message_author_role" \
      "$commit_message_timeout_seconds" \
      "$commit_message_max_subject_length" \
      "$commit_message_runner_prompt_mode" \
      "$commit_message_runner_command_json" \
      "$commit_message_runner_args_json" \
      "$commit_message_runner_thinking_env"); then
      commit_msg="$llm_commit_msg"
      commit_msg_source="llm"
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_message_generated" \
        "$(jq -n \
          --arg source "$commit_msg_source" \
          --arg author_role "$commit_message_author_role" \
          --arg prompt_file "${LLM_COMMIT_PROMPT_FILE#$repo/}" \
          --arg log_file "${LLM_COMMIT_LOG_FILE#$repo/}" \
          --arg last_message_file "${LLM_COMMIT_LAST_MESSAGE_FILE#$repo/}" \
          '{source: $source, author_role: $author_role, prompt_file: $prompt_file, log_file: $log_file, last_message_file: $last_message_file}')"
    else
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_message_fallback" \
        "$(jq -n \
          --arg source "template" \
          --arg requested_source "$commit_message_authoring" \
          --arg author_role "$commit_message_author_role" \
          --arg prompt_file "${LLM_COMMIT_PROMPT_FILE#$repo/}" \
          --arg log_file "${LLM_COMMIT_LOG_FILE#$repo/}" \
          --arg last_message_file "${LLM_COMMIT_LAST_MESSAGE_FILE#$repo/}" \
          '{source: $source, requested_source: $requested_source, author_role: $author_role, prompt_file: $prompt_file, log_file: $log_file, last_message_file: $last_message_file}')"
    fi
  fi

  local commit_msg_file="$loop_dir/commit-message/iter-$iteration.final.txt"
  mkdir -p "$(dirname "$commit_msg_file")"
  printf '%s\n' "$commit_msg" > "$commit_msg_file"

  # Create the commit
  local commit_output
  local commit_exit_code
  commit_output=$(git -C "$repo" commit -F "$commit_msg_file" 2>&1)
  commit_exit_code=$?

  local commit_subject
  commit_subject=$(head -n 1 "$commit_msg_file" 2>/dev/null || echo "")

  if [[ $commit_exit_code -eq 0 ]]; then
    local commit_sha
    commit_sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_success" \
      "$(jq -n \
        --arg sha "$commit_sha" \
        --arg subject "$commit_subject" \
        --arg strategy "$commit_strategy" \
        --arg message_source "$commit_msg_source" \
        --arg author_role "$commit_message_author_role" \
        --arg message_file "${commit_msg_file#$repo/}" \
        '{sha: $sha, subject: $subject, strategy: $strategy, message_source: $message_source, author_role: $author_role, message_file: $message_file}')"
    echo "[superloop] Auto-committed: $commit_sha - $commit_subject" >&2
    return 0
  else
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_failed" \
      "$(jq -n \
        --arg error "$commit_output" \
        --arg strategy "$commit_strategy" \
        --arg message_source "$commit_msg_source" \
        --arg author_role "$commit_message_author_role" \
        '{error: $error, strategy: $strategy, message_source: $message_source, author_role: $author_role}')"
    echo "[superloop] Auto-commit failed: $commit_output" >&2
    return 1
  fi
}
