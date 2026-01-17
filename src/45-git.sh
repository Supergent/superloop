#!/usr/bin/env bash
# Git operations for superloop
# Handles automatic commits after iterations

# Auto-commit changes after an iteration
# Arguments:
#   $1 - repo path
#   $2 - loop_id
#   $3 - iteration number
#   $4 - tests_status (ok, failed, skipped)
#   $5 - commit_strategy (per_iteration, on_test_pass, never)
#   $6 - events_file for logging
#   $7 - run_id
# Returns: 0 on success or skip, 1 on failure
auto_commit_iteration() {
  local repo="$1"
  local loop_id="$2"
  local iteration="$3"
  local tests_status="$4"
  local commit_strategy="$5"
  local events_file="$6"
  local run_id="$7"

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

  # Build commit message
  local test_indicator=""
  case "$tests_status" in
    ok) test_indicator="tests: passing" ;;
    failed) test_indicator="tests: failing" ;;
    skipped) test_indicator="tests: skipped" ;;
    *) test_indicator="tests: $tests_status" ;;
  esac

  local commit_msg="[superloop] $loop_id iteration $iteration: $current_phase ($test_indicator)"

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

  # Create the commit
  local commit_output
  local commit_exit_code
  commit_output=$(git -C "$repo" commit -m "$commit_msg

Automated commit by superloop after iteration $iteration.
Strategy: $commit_strategy

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>" 2>&1)
  commit_exit_code=$?

  if [[ $commit_exit_code -eq 0 ]]; then
    local commit_sha
    commit_sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_success" \
      "$(jq -n --arg sha "$commit_sha" --arg message "$commit_msg" --arg strategy "$commit_strategy" '{sha: $sha, message: $message, strategy: $strategy}')"
    echo "[superloop] Auto-committed: $commit_sha - $commit_msg" >&2
    return 0
  else
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_failed" \
      "$(jq -n --arg error "$commit_output" --arg strategy "$commit_strategy" '{error: $error, strategy: $strategy}')"
    echo "[superloop] Auto-commit failed: $commit_output" >&2
    return 1
  fi
}
