build_role_prompt() {
  local role="$1"
  local role_template="$2"
  local prompt_file="$3"
  local spec_file="$4"
  local plan_file="$5"
  local notes_file="$6"
  local implementer_report="$7"
  local reviewer_report="$8"
  local test_report="$9"
  local test_output="${10}"
  local test_status="${11}"
  local checklist_status="${12}"
  local checklist_remaining="${13}"
  local evidence_file="${14}"
  local reviewer_packet="${15:-}"
  local changed_files_planner="${16:-}"
  local changed_files_implementer="${17:-}"
  local changed_files_all="${18:-}"

  cat "$role_template" > "$prompt_file"
  cat <<EOF >> "$prompt_file"

Context files (read as needed):
- Spec: $spec_file
- Plan: $plan_file
- Iteration notes: $notes_file
- Implementer report: $implementer_report
- Reviewer report: $reviewer_report
- Test report: $test_report
- Test output: $test_output
- Test status: $test_status
- Checklist status: $checklist_status
- Checklist remaining: $checklist_remaining
- Evidence: $evidence_file
EOF

  if [[ -n "$reviewer_packet" ]]; then
    echo "- Reviewer packet: $reviewer_packet" >> "$prompt_file"
  fi

  # Add changed files context if available
  if [[ -n "$changed_files_planner" && -f "$changed_files_planner" ]]; then
    echo "- Files changed by planner: $changed_files_planner" >> "$prompt_file"
  fi
  if [[ -n "$changed_files_implementer" && -f "$changed_files_implementer" ]]; then
    echo "- Files changed by implementer: $changed_files_implementer" >> "$prompt_file"
  fi
  if [[ -n "$changed_files_all" && -f "$changed_files_all" ]]; then
    echo "- All files changed this iteration: $changed_files_all" >> "$prompt_file"
  fi
}

