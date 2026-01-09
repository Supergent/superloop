append_decision_log() {
  local loop_dir="$1"
  local loop_id="$2"
  local run_id="$3"
  local iteration="$4"
  local decision="$5"
  local decided_by="$6"
  local note="$7"
  local approval_file="$8"
  local decided_at="${9:-}"

  local decisions_jsonl="$loop_dir/decisions.jsonl"
  local decisions_md="$loop_dir/decisions.md"
  if [[ -z "$decided_at" ]]; then
    decided_at=$(timestamp)
  fi

  jq -c -n \
    --arg timestamp "$decided_at" \
    --arg loop_id "$loop_id" \
    --arg run_id "$run_id" \
    --argjson iteration "$iteration" \
    --arg decision "$decision" \
    --arg decided_by "$decided_by" \
    --arg note "$note" \
    --arg approval_file "$approval_file" \
    '{
      timestamp: $timestamp,
      loop_id: $loop_id,
      run_id: $run_id,
      iteration: $iteration,
      decision: $decision,
      by: $decided_by,
      note: (if ($note | length) > 0 then $note else null end),
      approval_file: (if ($approval_file | length) > 0 then $approval_file else null end)
    } | with_entries(select(.value != null))' \
    >> "$decisions_jsonl"

  {
    echo "## $decided_at $decision"
    echo ""
    echo "- Loop: $loop_id"
    echo "- Run: $run_id"
    echo "- Iteration: $iteration"
    echo "- Decision: $decision"
    echo "- By: $decided_by"
    if [[ -n "$note" ]]; then
      echo "- Note: $note"
    fi
    if [[ -n "$approval_file" ]]; then
      echo "- Approval file: $approval_file"
    fi
    echo ""
  } >> "$decisions_md"
}

log_event() {
  local events_file="$1"
  local loop_id="$2"
  local iteration="$3"
  local run_id="$4"
  local event="$5"
  local data_json_raw="${6:-}"
  local data_json
  data_json=$(json_or_default "$data_json_raw" "null")
  local role="${7:-}"
  local status="${8:-}"
  local message="${9:-}"

  if [[ -z "$events_file" ]]; then
    return 0
  fi

  jq -c -n \
    --arg timestamp "$(timestamp)" \
    --arg event "$event" \
    --arg loop_id "$loop_id" \
    --arg run_id "$run_id" \
    --argjson iteration "$iteration" \
    --arg role "$role" \
    --arg status "$status" \
    --arg message "$message" \
    --argjson data "$data_json" \
    '{
      timestamp: $timestamp,
      event: $event,
      loop_id: $loop_id,
      run_id: $run_id,
      iteration: $iteration,
      role: (if ($role | length) > 0 then $role else null end),
      status: (if ($status | length) > 0 then $status else null end),
      message: (if ($message | length) > 0 then $message else null end),
      data: $data
    } | with_entries(select(.value != null))' \
    >> "$events_file" || true
}

append_run_summary() {
  local summary_file="$1"
  local repo="$2"
  local loop_id="$3"
  local run_id="$4"
  local iteration="$5"
  local started_at="$6"
  local ended_at="$7"
  local promise_matched="$8"
  local completion_promise="$9"
  local promise_text="${10}"
  local tests_mode="${11}"
  local tests_status="${12}"
  local validation_status="${13}"
  local checklist_status="${14}"
  local evidence_status="${15}"
  local approval_status="${16}"
  local stuck_streak="${17}"
  local stuck_threshold="${18}"
  local completion_ok="${19}"
  local loop_dir="${20}"
  local events_file="${21}"

  local plan_file="$loop_dir/plan.md"
  local implementer_report="$loop_dir/implementer.md"
  local test_report="$loop_dir/test-report.md"
  local reviewer_report="$loop_dir/review.md"
  local test_output="$loop_dir/test-output.txt"
  local test_status="$loop_dir/test-status.json"
  local checklist_status_file="$loop_dir/checklist-status.json"
  local checklist_remaining="$loop_dir/checklist-remaining.md"
  local evidence_file="$loop_dir/evidence.json"
  local summary_file_gate="$loop_dir/gate-summary.txt"
  local notes_file="$loop_dir/iteration_notes.md"
  local reviewer_packet="$loop_dir/reviewer-packet.md"
  local approval_file="$loop_dir/approval.json"
  local decisions_jsonl="$loop_dir/decisions.jsonl"
  local decisions_md="$loop_dir/decisions.md"
  local validation_status_file="$loop_dir/validation-status.json"
  local validation_results_file="$loop_dir/validation-results.json"

  local plan_meta implementer_meta test_report_meta reviewer_meta
  local test_output_meta test_status_meta checklist_status_meta checklist_remaining_meta
  local evidence_meta summary_meta notes_meta events_meta reviewer_packet_meta approval_meta decisions_meta decisions_md_meta
  local validation_status_meta validation_results_meta

  plan_meta=$(file_meta_json "${plan_file#$repo/}" "$plan_file")
  plan_meta=$(json_or_default "$plan_meta" "{}")
  implementer_meta=$(file_meta_json "${implementer_report#$repo/}" "$implementer_report")
  implementer_meta=$(json_or_default "$implementer_meta" "{}")
  test_report_meta=$(file_meta_json "${test_report#$repo/}" "$test_report")
  test_report_meta=$(json_or_default "$test_report_meta" "{}")
  reviewer_meta=$(file_meta_json "${reviewer_report#$repo/}" "$reviewer_report")
  reviewer_meta=$(json_or_default "$reviewer_meta" "{}")
  test_output_meta=$(file_meta_json "${test_output#$repo/}" "$test_output")
  test_output_meta=$(json_or_default "$test_output_meta" "{}")
  test_status_meta=$(file_meta_json "${test_status#$repo/}" "$test_status")
  test_status_meta=$(json_or_default "$test_status_meta" "{}")
  checklist_status_meta=$(file_meta_json "${checklist_status_file#$repo/}" "$checklist_status_file")
  checklist_status_meta=$(json_or_default "$checklist_status_meta" "{}")
  checklist_remaining_meta=$(file_meta_json "${checklist_remaining#$repo/}" "$checklist_remaining")
  checklist_remaining_meta=$(json_or_default "$checklist_remaining_meta" "{}")
  evidence_meta=$(file_meta_json "${evidence_file#$repo/}" "$evidence_file")
  evidence_meta=$(json_or_default "$evidence_meta" "{}")
  validation_status_meta=$(file_meta_json "${validation_status_file#$repo/}" "$validation_status_file")
  validation_status_meta=$(json_or_default "$validation_status_meta" "{}")
  validation_results_meta=$(file_meta_json "${validation_results_file#$repo/}" "$validation_results_file")
  validation_results_meta=$(json_or_default "$validation_results_meta" "{}")
  summary_meta=$(file_meta_json "${summary_file_gate#$repo/}" "$summary_file_gate")
  summary_meta=$(json_or_default "$summary_meta" "{}")
  notes_meta=$(file_meta_json "${notes_file#$repo/}" "$notes_file")
  notes_meta=$(json_or_default "$notes_meta" "{}")
  events_meta=$(file_meta_json "${events_file#$repo/}" "$events_file")
  events_meta=$(json_or_default "$events_meta" "{}")
  reviewer_packet_meta=$(file_meta_json "${reviewer_packet#$repo/}" "$reviewer_packet")
  reviewer_packet_meta=$(json_or_default "$reviewer_packet_meta" "{}")
  approval_meta=$(file_meta_json "${approval_file#$repo/}" "$approval_file" "approval")
  approval_meta=$(json_or_default "$approval_meta" "{}")
  decisions_meta=$(file_meta_json "${decisions_jsonl#$repo/}" "$decisions_jsonl")
  decisions_meta=$(json_or_default "$decisions_meta" "{}")
  decisions_md_meta=$(file_meta_json "${decisions_md#$repo/}" "$decisions_md")
  decisions_md_meta=$(json_or_default "$decisions_md_meta" "{}")

  local artifacts_json
  artifacts_json=$(jq -n \
    --argjson plan "$plan_meta" \
    --argjson implementer "$implementer_meta" \
    --argjson test_report "$test_report_meta" \
    --argjson reviewer "$reviewer_meta" \
    --argjson test_output "$test_output_meta" \
    --argjson test_status "$test_status_meta" \
    --argjson checklist_status "$checklist_status_meta" \
    --argjson checklist_remaining "$checklist_remaining_meta" \
    --argjson evidence "$evidence_meta" \
    --argjson validation_status "$validation_status_meta" \
    --argjson validation_results "$validation_results_meta" \
    --argjson gate_summary "$summary_meta" \
    --argjson iteration_notes "$notes_meta" \
    --argjson events "$events_meta" \
    --argjson reviewer_packet "$reviewer_packet_meta" \
    --argjson approval "$approval_meta" \
    --argjson decisions "$decisions_meta" \
    --argjson decisions_md "$decisions_md_meta" \
    '{
      plan: $plan,
      implementer: $implementer,
      test_report: $test_report,
      reviewer: $reviewer,
      test_output: $test_output,
      test_status: $test_status,
      checklist_status: $checklist_status,
      checklist_remaining: $checklist_remaining,
      evidence: $evidence,
      validation_status: $validation_status,
      validation_results: $validation_results,
      gate_summary: $gate_summary,
      iteration_notes: $iteration_notes,
      events: $events,
      reviewer_packet: $reviewer_packet,
      approval: $approval,
      decisions: $decisions,
      decisions_md: $decisions_md
    }')
  artifacts_json=$(json_or_default "$artifacts_json" "{}")

  local promise_matched_json="false"
  if [[ "$promise_matched" == "true" ]]; then
    promise_matched_json="true"
  fi
  local completion_json="false"
  if [[ "$completion_ok" -eq 1 ]]; then
    completion_json="true"
  fi

  local entry_json
  entry_json=$(jq -n \
    --arg run_id "$run_id" \
    --arg iteration "$iteration" \
    --arg started_at "$started_at" \
    --arg ended_at "$ended_at" \
    --arg promise_expected "$completion_promise" \
    --arg promise_text "$promise_text" \
    --arg promise_matched "$promise_matched_json" \
    --arg tests_mode "$tests_mode" \
    --arg tests_status "$tests_status" \
    --arg validation_status "$validation_status" \
    --arg checklist_status "$checklist_status" \
    --arg evidence_status "$evidence_status" \
    --arg approval_status "$approval_status" \
    --arg stuck_streak "$stuck_streak" \
    --arg stuck_threshold "$stuck_threshold" \
    --arg completion_ok "$completion_json" \
    --arg artifacts "$artifacts_json" \
    '{
      run_id: $run_id,
      iteration: ($iteration | tonumber? // $iteration),
      started_at: $started_at,
      ended_at: $ended_at,
      promise: {
        expected: $promise_expected,
        text: (if ($promise_text | length) > 0 then $promise_text else null end),
        matched: ($promise_matched | fromjson? // false)
      },
      gates: {
        tests: $tests_status,
        validation: $validation_status,
        checklist: $checklist_status,
        evidence: $evidence_status,
        approval: $approval_status
      },
      tests_mode: $tests_mode,
      stuck: {
        streak: ($stuck_streak | tonumber? // 0),
        threshold: ($stuck_threshold | tonumber? // 0)
      },
      completion_ok: ($completion_ok | fromjson? // false),
      artifacts: ($artifacts | fromjson? // {})
    } | with_entries(select(.value != null))')
  entry_json=$(json_or_default "$entry_json" "{}")

  local updated_at
  updated_at=$(timestamp)

  local entry_file="$loop_dir/run-summary-entry.json"
  printf '%s\n' "$entry_json" > "$entry_file"

  if [[ -f "$summary_file" ]]; then
    jq -s --arg updated_at "$updated_at" \
      '.[0] as $entry | .[1] | .entries = (.entries // []) + [$entry] | .updated_at = $updated_at' \
      "$entry_file" "$summary_file" > "${summary_file}.tmp"
  else
    jq -s --arg loop_id "$loop_id" --arg updated_at "$updated_at" \
      '{version: 1, loop_id: $loop_id, updated_at: $updated_at, entries: [.[0]]}' \
      "$entry_file" > "${summary_file}.tmp"
  fi

  mv "${summary_file}.tmp" "$summary_file"
}

write_timeline() {
  local summary_file="$1"
  local timeline_file="$2"

  if [[ ! -f "$summary_file" ]]; then
    return 0
  fi

  local loop_id
  loop_id=$(jq -r '.loop_id // ""' "$summary_file")

  {
    echo "# Timeline"
    if [[ -n "$loop_id" && "$loop_id" != "null" ]]; then
      echo ""
      echo "Loop: $loop_id"
    fi
    echo ""
    jq -r '.entries[]? |
      "- \(.ended_at // .started_at) run=\(.run_id // "unknown") iter=\(.iteration) promise=\(.promise.matched // "unknown") tests=\(.gates.tests // "unknown") validation=\(.gates.validation // "unknown") checklist=\(.gates.checklist // "unknown") evidence=\(.gates.evidence // "unknown") approval=\(.gates.approval // "unknown") stuck=\(.stuck.streak // 0)/\(.stuck.threshold // 0) completion=\(.completion_ok // false)"' \
      "$summary_file"
  } > "$timeline_file"
}

read_test_status_summary() {
  local status_file="$1"

  if [[ ! -f "$status_file" ]]; then
    echo "unknown"
    return 0
  fi

  local ok skipped
  ok=$(jq -r '.ok // empty' "$status_file" 2>/dev/null || true)
  skipped=$(jq -r '.skipped // false' "$status_file" 2>/dev/null || true)

  if [[ "$ok" == "true" ]]; then
    if [[ "$skipped" == "true" ]]; then
      echo "skipped"
    else
      echo "ok"
    fi
    return 0
  fi

  if [[ "$ok" == "false" ]]; then
    echo "failed"
    return 0
  fi

  echo "unknown"
}

read_validation_status_summary() {
  local status_file="$1"

  if [[ ! -f "$status_file" ]]; then
    echo "unknown"
    return 0
  fi

  local status
  status=$(jq -r '.status // empty' "$status_file" 2>/dev/null || true)
  if [[ -n "$status" && "$status" != "null" ]]; then
    echo "$status"
    return 0
  fi

  local ok
  ok=$(jq -r '.ok // empty' "$status_file" 2>/dev/null || true)
  if [[ "$ok" == "true" ]]; then
    echo "ok"
    return 0
  fi
  if [[ "$ok" == "false" ]]; then
    echo "failed"
    return 0
  fi
  echo "unknown"
}

read_checklist_status_summary() {
  local status_file="$1"

  if [[ ! -f "$status_file" ]]; then
    echo "unknown"
    return 0
  fi

  local ok
  ok=$(jq -r '.ok // empty' "$status_file" 2>/dev/null || true)
  if [[ "$ok" == "true" ]]; then
    echo "ok"
    return 0
  fi
  if [[ "$ok" == "false" ]]; then
    echo "remaining"
    return 0
  fi
  echo "unknown"
}

read_stuck_streak() {
  local state_file="$1"

  if [[ ! -f "$state_file" ]]; then
    echo "0"
    return 0
  fi

  local streak
  streak=$(jq -r '.streak // 0' "$state_file" 2>/dev/null || true)
  if [[ -z "$streak" || "$streak" == "null" ]]; then
    streak="0"
  fi
  echo "$streak"
}
