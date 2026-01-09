snapshot_file() {
  local file="$1"
  local snapshot="$2"

  if [[ -f "$file" ]]; then
    cp -p "$file" "$snapshot"
  else
    : > "$snapshot"
  fi
}

restore_if_unchanged() {
  local file="$1"
  local snapshot="$2"

  if [[ -z "$snapshot" || ! -f "$snapshot" ]]; then
    return 0
  fi

  if [[ -f "$file" ]]; then
    if cmp -s "$snapshot" "$file"; then
      mv "$snapshot" "$file"
    else
      rm -f "$snapshot"
    fi
    return 0
  fi

  mv "$snapshot" "$file"
}

extract_promise() {
  local message_file="$1"

  if [[ ! -f "$message_file" ]]; then
    echo ""
    return 0
  fi

  perl -0777 -ne 'if (/<promise>(.*?)<\/promise>/s) { $p=$1; $p=~s/^\s+|\s+$//g; $p=~s/\s+/ /g; print $p }' "$message_file" 2>/dev/null || true
}

write_reviewer_packet() {
  local loop_dir="$1"
  local loop_id="$2"
  local iteration="$3"
  local gate_summary="$4"
  local test_status="$5"
  local test_report="$6"
  local evidence_file="$7"
  local checklist_status="$8"
  local checklist_remaining="$9"
  local validation_status="${10}"
  local validation_results="${11}"
  local packet_file="${12}"

  {
    echo "# Reviewer Packet"
    echo ""
    echo "Loop: $loop_id"
    echo "Iteration: $iteration"
    echo "Generated at: $(timestamp)"
    echo ""
    echo "## Gate Summary"
    if [[ -f "$gate_summary" ]]; then
      cat "$gate_summary"
    else
      echo "Missing gate summary."
    fi
    echo ""
    echo "## Test Status"
    if [[ -f "$test_status" ]]; then
      cat "$test_status"
    else
      echo "Missing test status."
    fi
    echo ""
    echo "## Test Report"
    if [[ -f "$test_report" ]]; then
      cat "$test_report"
    else
      echo "Missing test report."
    fi
    echo ""
    echo "## Checklist Status"
    if [[ -f "$checklist_status" ]]; then
      cat "$checklist_status"
    else
      echo "Missing checklist status."
    fi
    echo ""
    echo "## Checklist Remaining"
    if [[ -f "$checklist_remaining" ]]; then
      cat "$checklist_remaining"
    else
      echo "Missing checklist remaining list."
    fi
    echo ""
    echo "## Evidence"
    if [[ -f "$evidence_file" ]]; then
      cat "$evidence_file"
    else
      echo "Missing evidence manifest."
    fi
    echo ""
    echo "## Validation"
    if [[ -f "$validation_status" ]]; then
      cat "$validation_status"
    else
      echo "Missing validation status."
    fi
    if [[ -f "$validation_results" ]]; then
      echo ""
      cat "$validation_results"
    fi
  } > "$packet_file"
}

write_iteration_notes() {
  local notes_file="$1"
  local loop_id="$2"
  local iteration="$3"
  local promise_matched="$4"
  local tests_status="$5"
  local validation_status="$6"
  local checklist_status="$7"
  local tests_mode="$8"
  local evidence_status="${9:-}"
  local stuck_streak="${10:-}"
  local stuck_threshold="${11:-}"
  local approval_status="${12:-}"

  cat <<EOF > "$notes_file"
Iteration: $iteration
Loop: $loop_id
Promise matched: $promise_matched
Tests: $tests_status (mode: $tests_mode)
Validation: ${validation_status:-skipped}
Checklist: $checklist_status
Evidence: ${evidence_status:-skipped}
Approval: ${approval_status:-skipped}
Stuck streak: ${stuck_streak:-0}/${stuck_threshold:-0}
Generated at: $(timestamp)

Next steps:
- Review test output and checklist remaining items.
- Update plan or code to address failures.
EOF
}

write_gate_summary() {
  local summary_file="$1"
  local promise_matched="$2"
  local tests_status="$3"
  local validation_status="$4"
  local checklist_status="$5"
  local evidence_status="$6"
  local stuck_status="$7"
  local approval_status="${8:-skipped}"

  printf 'promise=%s tests=%s validation=%s checklist=%s evidence=%s stuck=%s approval=%s\n' \
    "$promise_matched" "$tests_status" "$validation_status" "$checklist_status" "$evidence_status" "$stuck_status" "$approval_status" \
    > "$summary_file"
}

read_approval_status() {
  local approval_file="$1"

  if [[ ! -f "$approval_file" ]]; then
    echo "none"
    return 0
  fi

  local status
  status=$(jq -r '.status // "pending"' "$approval_file" 2>/dev/null || true)
  if [[ -z "$status" || "$status" == "null" ]]; then
    status="pending"
  fi
  echo "$status"
}

write_approval_request() {
  local approval_file="$1"
  local loop_id="$2"
  local run_id="$3"
  local iteration="$4"
  local iteration_started_at="$5"
  local iteration_ended_at="$6"
  local promise_expected="$7"
  local promise_text="$8"
  local promise_matched="$9"
  local tests_status="${10}"
  local validation_status="${11}"
  local checklist_status="${12}"
  local evidence_status="${13}"
  local gate_summary_file="${14}"
  local evidence_file="${15}"
  local reviewer_report="${16}"
  local test_report="${17}"
  local plan_file="${18}"
  local notes_file="${19}"

  local promise_matched_json="false"
  if [[ "$promise_matched" == "true" ]]; then
    promise_matched_json="true"
  fi

  jq -n \
    --arg status "pending" \
    --arg loop_id "$loop_id" \
    --arg run_id "$run_id" \
    --argjson iteration "$iteration" \
    --arg requested_at "$(timestamp)" \
    --arg iteration_started_at "$iteration_started_at" \
    --arg iteration_ended_at "$iteration_ended_at" \
    --arg promise_expected "$promise_expected" \
    --arg promise_text "$promise_text" \
    --argjson promise_matched "$promise_matched_json" \
    --arg tests_status "$tests_status" \
    --arg validation_status "$validation_status" \
    --arg checklist_status "$checklist_status" \
    --arg evidence_status "$evidence_status" \
    --arg gate_summary_file "$gate_summary_file" \
    --arg evidence_file "$evidence_file" \
    --arg reviewer_report "$reviewer_report" \
    --arg test_report "$test_report" \
    --arg plan_file "$plan_file" \
    --arg notes_file "$notes_file" \
    '{
      status: $status,
      loop_id: $loop_id,
      run_id: $run_id,
      iteration: $iteration,
      requested_at: $requested_at,
      iteration_started_at: $iteration_started_at,
      iteration_ended_at: $iteration_ended_at,
      candidate: {
        promise: {
          expected: $promise_expected,
          text: (if ($promise_text | length) > 0 then $promise_text else null end),
          matched: $promise_matched
        },
        gates: {
          tests: $tests_status,
          validation: $validation_status,
          checklist: $checklist_status,
          evidence: $evidence_status
        }
      },
      files: {
        gate_summary: $gate_summary_file,
        evidence: $evidence_file,
        reviewer_report: $reviewer_report,
        test_report: $test_report,
        plan: $plan_file,
        iteration_notes: $notes_file
      }
    } | with_entries(select(.value != null))' \
    > "$approval_file"
}
