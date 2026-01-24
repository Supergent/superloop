update_stuck_state() {
  local repo="$1"
  local loop_dir="$2"
  local threshold="$3"
  shift 3
  local ignore_patterns=("$@")

  local state_file="$loop_dir/stuck.json"
  local report_file="$loop_dir/stuck-report.md"

  # Compute code signature (existing)
  local code_signature
  code_signature=$(compute_signature "$repo" "${ignore_patterns[@]}") || return 1

  # Compute test failure signature (new)
  local test_signature
  test_signature=$(compute_test_failure_signature "$loop_dir")

  # Load previous state
  local prev_code_signature=""
  local prev_test_signature=""
  local prev_streak=0
  if [[ -f "$state_file" ]]; then
    # Try new format first (code_signature + test_signature)
    prev_code_signature=$(jq -r '.code_signature // ""' "$state_file")
    prev_test_signature=$(jq -r '.test_signature // ""' "$state_file")

    # Fallback to old format (signature field) for backward compatibility
    if [[ -z "$prev_code_signature" ]]; then
      prev_code_signature=$(jq -r '.signature // ""' "$state_file")
    fi

    prev_streak=$(jq -r '.streak // 0' "$state_file")
  fi

  # Increment streak if: same code changes OR same test failures
  local streak=1
  local stuck_reason=""
  if [[ "$code_signature" == "$prev_code_signature" && -n "$code_signature" ]]; then
    streak=$((prev_streak + 1))
    stuck_reason="no_code_changes"
  elif [[ -n "$test_signature" && "$test_signature" == "$prev_test_signature" && -n "$prev_test_signature" ]]; then
    streak=$((prev_streak + 1))
    stuck_reason="same_test_failures"
  fi

  # Save both signatures
  jq -n \
    --arg code_sig "$code_signature" \
    --arg test_sig "$test_signature" \
    --argjson streak "$streak" \
    --argjson threshold "$threshold" \
    --arg reason "$stuck_reason" \
    --arg updated_at "$(timestamp)" \
    '{code_signature: $code_sig, test_signature: $test_sig, streak: $streak, threshold: $threshold, reason: $reason, updated_at: $updated_at}' \
    > "$state_file"

  # Trigger stuck detection if threshold reached
  if [[ "$streak" -ge "$threshold" ]]; then
    {
      echo "# Stuck Report"
      echo ""
      echo "No meaningful progress detected for $streak consecutive iterations."
      echo ""
      if [[ "$stuck_reason" == "no_code_changes" ]]; then
        echo "**Reason**: No code changes detected"
      elif [[ "$stuck_reason" == "same_test_failures" ]]; then
        echo "**Reason**: Same test failures persist despite code changes (thrashing)"
      fi
      echo ""
      echo "**Code Signature**: \`$code_signature\`"
      echo "**Test Failure Signature**: \`$test_signature\`"
      echo ""
      echo "Ignored paths:"
      printf '%s\n' "${ignore_patterns[@]}" | sed 's/^/- /'
      echo ""
      echo "Timestamp: $(timestamp)"
    } > "$report_file"
    echo "$streak"
    return 2
  fi

  echo "$streak"
  return 0
}

write_evidence_manifest() {
  local repo="$1"
  local loop_dir="$2"
  local loop_id="$3"
  local iteration="$4"
  local spec_file="$5"
  local loop_json="$6"
  local test_status_file="$7"
  local test_output_file="$8"
  local checklist_status_file="$9"
  local evidence_file="${10}"

  local tests_mode
  tests_mode=$(jq -r '.tests.mode // "disabled"' <<<"$loop_json")
  local test_commands_json
  test_commands_json=$(jq -c '.tests.commands // []' <<<"$loop_json")

  local test_status_json="null"
  if [[ -f "$test_status_file" ]]; then
    test_status_json=$(cat "$test_status_file")
  fi
  local test_status_sha_json="null"
  local test_status_mtime_json="null"
  if [[ -f "$test_status_file" ]]; then
    local status_hash
    status_hash=$(hash_file "$test_status_file" 2>/dev/null || true)
    if [[ -n "$status_hash" ]]; then
      test_status_sha_json="\"$status_hash\""
    fi
    local status_mtime
    status_mtime=$(file_mtime "$test_status_file" 2>/dev/null || true)
    if [[ -n "$status_mtime" ]]; then
      test_status_mtime_json="$status_mtime"
    fi
  fi

  local test_output_sha_json="null"
  local test_output_mtime_json="null"
  if [[ -f "$test_output_file" ]]; then
    local output_hash
    output_hash=$(hash_file "$test_output_file" 2>/dev/null || true)
    if [[ -n "$output_hash" ]]; then
      test_output_sha_json="\"$output_hash\""
    fi
    local output_mtime
    output_mtime=$(file_mtime "$test_output_file" 2>/dev/null || true)
    if [[ -n "$output_mtime" ]]; then
      test_output_mtime_json="$output_mtime"
    fi
  fi

  local checklist_status_json="null"
  if [[ -f "$checklist_status_file" ]]; then
    checklist_status_json=$(cat "$checklist_status_file")
  fi
  local checklist_status_sha_json="null"
  local checklist_status_mtime_json="null"
  if [[ -f "$checklist_status_file" ]]; then
    local checklist_hash
    checklist_hash=$(hash_file "$checklist_status_file" 2>/dev/null || true)
    if [[ -n "$checklist_hash" ]]; then
      checklist_status_sha_json="\"$checklist_hash\""
    fi
    local checklist_mtime
    checklist_mtime=$(file_mtime "$checklist_status_file" 2>/dev/null || true)
    if [[ -n "$checklist_mtime" ]]; then
      checklist_status_mtime_json="$checklist_mtime"
    fi
  fi
  local checklist_remaining_file="$loop_dir/checklist-remaining.md"
  local checklist_remaining_sha_json="null"
  local checklist_remaining_mtime_json="null"
  if [[ -f "$checklist_remaining_file" ]]; then
    local remaining_hash
    remaining_hash=$(hash_file "$checklist_remaining_file" 2>/dev/null || true)
    if [[ -n "$remaining_hash" ]]; then
      checklist_remaining_sha_json="\"$remaining_hash\""
    fi
    local remaining_mtime
    remaining_mtime=$(file_mtime "$checklist_remaining_file" 2>/dev/null || true)
    if [[ -n "$remaining_mtime" ]]; then
      checklist_remaining_mtime_json="$remaining_mtime"
    fi
  fi
  local checklist_patterns_json
  checklist_patterns_json=$(jq -c '.checklists // []' <<<"$loop_json")

  local validation_enabled
  validation_enabled=$(jq -r '.validation.enabled // false' <<<"$loop_json")
  local validation_status_file="$loop_dir/validation-status.json"
  local validation_results_file="$loop_dir/validation-results.json"
  local validation_status_json="null"
  if [[ "$validation_enabled" == "true" && -f "$validation_status_file" ]]; then
    validation_status_json=$(cat "$validation_status_file")
  fi
  validation_status_json=$(json_or_default "$validation_status_json" "null")
  local validation_results_json="null"
  if [[ "$validation_enabled" == "true" && -f "$validation_results_file" ]]; then
    validation_results_json=$(cat "$validation_results_file")
  fi
  validation_results_json=$(json_or_default "$validation_results_json" "null")

  local artifacts_jsonl="$loop_dir/evidence-artifacts.jsonl"
  : > "$artifacts_jsonl"
  local artifacts_gate="evidence"

  while IFS= read -r pattern; do
    if [[ -z "$pattern" ]]; then
      continue
    fi
    local -a expanded=()
    while IFS= read -r file; do
      expanded+=("$file")
    done < <(expand_pattern "$repo" "$pattern")

    if [[ ${#expanded[@]} -eq 0 ]]; then
      jq -n --arg path "$pattern" --arg gate "$artifacts_gate" \
        '{path: $path, exists: false, sha256: null, mtime: null, gate: $gate}' >> "$artifacts_jsonl"
      continue
    fi

    local file
    for file in "${expanded[@]}"; do
      if [[ -f "$repo/$file" ]]; then
        local hash
        hash=$(hash_file "$repo/$file" 2>/dev/null || true)
        local mtime_json="null"
        local mtime
        mtime=$(file_mtime "$repo/$file" 2>/dev/null || true)
        if [[ -n "$mtime" ]]; then
          mtime_json="$mtime"
        fi
        if [[ -n "$hash" ]]; then
          jq -n --arg path "$file" --arg sha "$hash" --arg gate "$artifacts_gate" --argjson mtime "$mtime_json" \
            '{path: $path, exists: true, sha256: $sha, mtime: $mtime, gate: $gate}' >> "$artifacts_jsonl"
        else
          jq -n --arg path "$file" --arg gate "$artifacts_gate" --argjson mtime "$mtime_json" \
            '{path: $path, exists: true, sha256: null, mtime: $mtime, gate: $gate}' >> "$artifacts_jsonl"
        fi
      else
        jq -n --arg path "$file" --arg gate "$artifacts_gate" \
          '{path: $path, exists: false, sha256: null, mtime: null, gate: $gate}' >> "$artifacts_jsonl"
      fi
    done
  done < <(jq -r '.evidence.artifacts[]?' <<<"$loop_json")

  local artifacts_json
  artifacts_json=$(jq -s '.' "$artifacts_jsonl")

  local test_status_rel="${test_status_file#$repo/}"
  local test_output_rel="${test_output_file#$repo/}"
  local checklist_status_rel="${checklist_status_file#$repo/}"
  local checklist_remaining_rel="${checklist_remaining_file#$repo/}"
  local validation_status_rel="${validation_status_file#$repo/}"
  local validation_results_rel="${validation_results_file#$repo/}"

  jq -n \
    --arg generated_at "$(timestamp)" \
    --arg loop_id "$loop_id" \
    --argjson iteration "$iteration" \
    --arg spec_file "$spec_file" \
    --arg tests_mode "$tests_mode" \
    --argjson test_commands "$test_commands_json" \
    --argjson test_status "$test_status_json" \
    --arg test_status_file "$test_status_rel" \
    --argjson test_status_sha "$test_status_sha_json" \
    --argjson test_status_mtime "$test_status_mtime_json" \
    --arg test_output_file "$test_output_rel" \
    --argjson test_output_sha "$test_output_sha_json" \
    --argjson test_output_mtime "$test_output_mtime_json" \
    --argjson checklist_patterns "$checklist_patterns_json" \
    --argjson checklist_status "$checklist_status_json" \
    --arg checklist_status_file "$checklist_status_rel" \
    --argjson checklist_status_sha "$checklist_status_sha_json" \
    --argjson checklist_status_mtime "$checklist_status_mtime_json" \
    --arg checklist_remaining_file "$checklist_remaining_rel" \
    --argjson checklist_remaining_sha "$checklist_remaining_sha_json" \
    --argjson checklist_remaining_mtime "$checklist_remaining_mtime_json" \
    --arg validation_status_file "$validation_status_rel" \
    --argjson validation_status "$validation_status_json" \
    --arg validation_results_file "$validation_results_rel" \
    --argjson validation_results "$validation_results_json" \
    --argjson artifacts "$artifacts_json" \
    '{
      generated_at: $generated_at,
      loop_id: $loop_id,
      iteration: $iteration,
      spec_file: $spec_file,
      tests: {
        mode: $tests_mode,
        commands: $test_commands,
        status: $test_status,
        status_file: $test_status_file,
        status_sha256: $test_status_sha,
        status_mtime: $test_status_mtime,
        output_file: $test_output_file,
        output_sha256: $test_output_sha,
        output_mtime: $test_output_mtime
      },
      checklists: {
        patterns: $checklist_patterns,
        status: $checklist_status,
        status_file: $checklist_status_file,
        status_sha256: $checklist_status_sha,
        status_mtime: $checklist_status_mtime,
        remaining_file: $checklist_remaining_file,
        remaining_sha256: $checklist_remaining_sha,
        remaining_mtime: $checklist_remaining_mtime
      },
      validation: {
        status: $validation_status,
        status_file: $validation_status_file,
        results: $validation_results,
        results_file: $validation_results_file
      },
      artifacts: $artifacts
    }' \
    > "$evidence_file"
}

check_checklists() {
  local repo="$1"
  local loop_dir="$2"
  shift 2
  local patterns=("$@")

  local remaining_file="$loop_dir/checklist-remaining.md"
  local status_file="$loop_dir/checklist-status.json"
  local missing_file="$loop_dir/checklist-missing.md"

  : > "$remaining_file"
  : > "$missing_file"

  local total_remaining=0
  local missing_count=0

  if [[ ${#patterns[@]} -eq 0 ]]; then
    jq -n --arg generated_at "$(timestamp)" '{ok: true, remaining: 0, generated_at: $generated_at}' > "$status_file"
    return 0
  fi

  for pattern in "${patterns[@]}"; do
    local -a expanded=()
    while IFS= read -r file; do
      expanded+=("$file")
    done < <(expand_pattern "$repo" "$pattern")

    if [[ ${#expanded[@]} -eq 0 ]]; then
      echo "$pattern" >> "$missing_file"
      missing_count=$((missing_count + 1))
      continue
    fi

    for file in "${expanded[@]}"; do
      if [[ -z "$file" ]]; then
        continue
      fi
      if [[ ! -f "$repo/$file" ]]; then
        echo "$file" >> "$missing_file"
        missing_count=$((missing_count + 1))
        continue
      fi

      local lines
      lines=$(awk -v file="$file" '
        BEGIN { in_code = 0 }
        /^\s*```/ { in_code = !in_code; next }
        in_code { next }
        /\[[ ]\]/ { print file ":" NR ":" $0 }
      ' "$repo/$file")

      if [[ -n "$lines" ]]; then
        echo "$lines" >> "$remaining_file"
        local count
        count=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
        total_remaining=$((total_remaining + count))
      fi
    done
  done

  if [[ $missing_count -gt 0 ]]; then
    total_remaining=$((total_remaining + missing_count))
  fi

  local ok="false"
  if [[ $total_remaining -eq 0 ]]; then
    ok="true"
  fi

  jq -n \
    --argjson ok "$ok" \
    --argjson remaining "$total_remaining" \
    --arg generated_at "$(timestamp)" \
    '{ok: $ok, remaining: $remaining, generated_at: $generated_at}' \
    > "$status_file"

  if [[ "$ok" == "true" ]]; then
    return 0
  fi

  return 1
}

run_tests() {
  local repo="$1"
  local loop_dir="$2"
  shift 2
  local commands=("$@")

  local output_file="$loop_dir/test-output.txt"
  local status_file="$loop_dir/test-status.json"

  : > "$output_file"

  if [[ ${#commands[@]} -eq 0 ]]; then
    jq -n --arg generated_at "$(timestamp)" '{ok: true, skipped: true, generated_at: $generated_at}' > "$status_file"
    return 0
  fi

  local ok=1
  local last_exit=0

  for cmd in "${commands[@]}"; do
    echo "$ $cmd" >> "$output_file"
    set +e
    (cd "$repo" && bash -lc "$cmd") >> "$output_file" 2>&1
    last_exit=$?
    set -e
    echo "exit_code: $last_exit" >> "$output_file"
    echo "" >> "$output_file"
    if [[ $last_exit -ne 0 ]]; then
      ok=0
    fi
  done

  local ok_json="false"
  if [[ $ok -eq 1 ]]; then
    ok_json="true"
  fi

  jq -n \
    --argjson ok "$ok_json" \
    --argjson exit_code "$last_exit" \
    --arg generated_at "$(timestamp)" \
    '{ok: $ok, exit_code: $exit_code, generated_at: $generated_at}' \
    > "$status_file"

  if [[ $ok -eq 1 ]]; then
    return 0
  fi

  return 1
}
