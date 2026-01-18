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
  local validation_status="${12}"
  local validation_results="${13}"
  local checklist_status="${14}"
  local checklist_remaining="${15}"
  local evidence_file="${16}"
  local reviewer_packet="${17:-}"
  local changed_files_planner="${18:-}"
  local changed_files_implementer="${19:-}"
  local changed_files_all="${20:-}"
  local tester_exploration_json="${21:-}"
  local tasks_dir="${22:-}"

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
- Validation status: $validation_status
- Validation results: $validation_results
- Checklist status: $checklist_status
- Checklist remaining: $checklist_remaining
- Evidence: $evidence_file
- Tasks directory: $tasks_dir
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

  # Add phase files context for planner and implementer
  if [[ -n "$tasks_dir" && -d "$tasks_dir" ]]; then
    local phase_files
    phase_files=$(find "$tasks_dir" -maxdepth 1 -name 'PHASE_*.MD' -type f 2>/dev/null | sort)
    if [[ -n "$phase_files" ]]; then
      echo "" >> "$prompt_file"
      echo "Phase files (task breakdown):" >> "$prompt_file"
      local active_phase=""
      while IFS= read -r phase_file; do
        local phase_name
        phase_name=$(basename "$phase_file")
        # Check if this phase has unchecked tasks
        local unchecked_count=0
        if [[ -f "$phase_file" ]]; then
          unchecked_count=$(grep -c '\[ \]' "$phase_file" 2>/dev/null) || unchecked_count=0
          [[ -z "$unchecked_count" || ! "$unchecked_count" =~ ^[0-9]+$ ]] && unchecked_count=0
        fi
        local checked_count=0
        if [[ -f "$phase_file" ]]; then
          checked_count=$(grep -c '\[x\]' "$phase_file" 2>/dev/null) || checked_count=0
          [[ -z "$checked_count" || ! "$checked_count" =~ ^[0-9]+$ ]] && checked_count=0
        fi
        local status_marker=""
        if [[ $unchecked_count -eq 0 && $checked_count -gt 0 ]]; then
          status_marker=" (complete)"
        elif [[ $unchecked_count -gt 0 ]]; then
          if [[ -z "$active_phase" ]]; then
            active_phase="$phase_file"
            status_marker=" (ACTIVE - $unchecked_count tasks remaining)"
          else
            status_marker=" ($unchecked_count tasks remaining)"
          fi
        fi
        echo "- $phase_file$status_marker" >> "$prompt_file"
      done <<< "$phase_files"
      if [[ -n "$active_phase" ]]; then
        echo "" >> "$prompt_file"
        echo "Active phase file: $active_phase" >> "$prompt_file"
      fi
    else
      echo "" >> "$prompt_file"
      echo "Phase files: (none yet - planner should create tasks/PHASE_1.MD)" >> "$prompt_file"
    fi
  fi

  # Add tester exploration context if enabled for tester role
  if [[ "$role" == "tester" && -n "$tester_exploration_json" ]]; then
    local exploration_enabled
    exploration_enabled=$(jq -r '.enabled // false' <<<"$tester_exploration_json" 2>/dev/null || echo "false")

    if [[ "$exploration_enabled" == "true" ]]; then
      local tool entry_url focus_areas max_steps screenshot_dir
      tool=$(jq -r '.tool // "agent_browser"' <<<"$tester_exploration_json")
      entry_url=$(jq -r '.entry_url // ""' <<<"$tester_exploration_json")
      max_steps=$(jq -r '.max_steps // ""' <<<"$tester_exploration_json")
      screenshot_dir=$(jq -r '.screenshot_dir // ""' <<<"$tester_exploration_json")

      # Inject agent-browser documentation using hybrid approach
      local skill_file="$HOME/.claude/skills/agent-browser/SKILL.md"

      echo "" >> "$prompt_file"
      echo "## Exploration Configuration" >> "$prompt_file"
      echo "" >> "$prompt_file"
      echo "Browser exploration is ENABLED. Use agent-browser to verify the implementation." >> "$prompt_file"
      echo "" >> "$prompt_file"

      # Try to use global SKILL.md first, fallback to --help, then minimal reference
      if [[ -f "$skill_file" ]]; then
        # Global skill exists - use it (single source of truth)
        cat "$skill_file" >> "$prompt_file"
      elif command -v agent-browser &> /dev/null; then
        # Fallback: Generate from agent-browser --help
        echo "### agent-browser Commands" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo '```' >> "$prompt_file"
        agent-browser --help >> "$prompt_file" 2>&1
        echo '```' >> "$prompt_file"
      else
        # Minimal fallback if agent-browser not found
        cat <<'MINIMAL_FALLBACK' >> "$prompt_file"
### agent-browser Quick Reference

**Installation required:**
```
npm install -g agent-browser
```

**Basic workflow:**
1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs
3. `agent-browser click @e1` - Interact using refs
4. `agent-browser close` - Close browser

For full documentation, install agent-browser or see https://github.com/vercel-labs/agent-browser
MINIMAL_FALLBACK
      fi
      echo "" >> "$prompt_file"

      echo "### Session Configuration" >> "$prompt_file"
      echo "" >> "$prompt_file"
      if [[ -n "$entry_url" && "$entry_url" != "null" ]]; then
        echo "- Entry URL: $entry_url" >> "$prompt_file"
      fi
      if [[ -n "$max_steps" && "$max_steps" != "null" ]]; then
        echo "- Max exploration steps: $max_steps" >> "$prompt_file"
      fi
      if [[ -n "$screenshot_dir" && "$screenshot_dir" != "null" ]]; then
        echo "- Screenshot directory: $screenshot_dir" >> "$prompt_file"
      fi

      # Add focus areas if specified
      local focus_count
      focus_count=$(jq -r '.focus_areas // [] | length' <<<"$tester_exploration_json" 2>/dev/null || echo "0")
      if [[ "$focus_count" -gt 0 ]]; then
        echo "" >> "$prompt_file"
        echo "**Focus your exploration on:**" >> "$prompt_file"
        jq -r '.focus_areas // [] | .[]' <<<"$tester_exploration_json" 2>/dev/null | while read -r area; do
          echo "- $area" >> "$prompt_file"
        done
      fi
    fi
  fi
}
