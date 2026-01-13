validation_select_runner() {
  if command -v node >/dev/null 2>&1; then
    echo "node"
    return 0
  fi
  if command -v bun >/dev/null 2>&1; then
    echo "bun"
    return 0
  fi
  return 1
}

expand_validation_path() {
  local raw="$1"
  local repo="$2"
  local loop_id="$3"
  local iteration="$4"
  local loop_dir="$5"

  local resolved="$raw"
  resolved="${resolved//\{repo\}/$repo}"
  resolved="${resolved//\{loop_id\}/$loop_id}"
  resolved="${resolved//\{iteration\}/$iteration}"
  resolved="${resolved//\{loop_dir\}/$loop_dir}"
  printf '%s' "$resolved"
}

run_validation_script() {
  local script="$1"
  local repo="$2"
  local config_json="$3"
  local output_file="$4"
  local label="$5"

  local runner=""
  runner=$(validation_select_runner 2>/dev/null || true)
  if [[ -z "$runner" ]]; then
    jq -n \
      --arg error "missing node or bun" \
      --arg label "$label" \
      '{ok: false, error: $error, label: $label}' \
      > "$output_file"
    return 1
  fi

  mkdir -p "$(dirname "$output_file")"

  set +e
  "$runner" "$script" --repo "$repo" --config "$config_json" > "$output_file"
  local status=$?
  set -e

  if ! jq -e '.' "$output_file" >/dev/null 2>&1; then
    jq -n \
      --arg error "invalid json output" \
      --arg label "$label" \
      '{ok: false, error: $error, label: $label}' \
      > "$output_file"
    status=1
  fi

  return $status
}

write_validation_status() {
  local status_file="$1"
  local status="$2"
  local ok="$3"
  local results_file="$4"

  local ok_json="false"
  if [[ "$ok" == "true" || "$ok" == "1" ]]; then
    ok_json="true"
  fi

  jq -n \
    --argjson ok "$ok_json" \
    --arg status "$status" \
    --arg generated_at "$(timestamp)" \
    --arg results_file "$results_file" \
    '{ok: $ok, status: $status, generated_at: $generated_at, results_file: (if ($results_file | length) > 0 then $results_file else null end)}' \
    > "$status_file"
}

run_agent_browser_tests() {
  local repo="$1"
  local loop_id="$2"
  local iteration="$3"
  local loop_dir="$4"
  local config_json="$5"
  local output_file="$6"

  if ! command -v agent-browser >/dev/null 2>&1; then
    jq -n \
      --arg error "agent-browser not found in PATH" \
      '{ok: false, error: $error, tests: []}' \
      > "$output_file"
    return 1
  fi

  local session
  session=$(jq -r '.session // "superloop-default"' <<<"$config_json")
  session="${session//\{loop_id\}/$loop_id}"
  session="${session//\{iteration\}/$iteration}"

  local headed
  headed=$(jq -r '.headed // false' <<<"$config_json")
  local headed_flag=""
  if [[ "$headed" == "true" ]]; then
    headed_flag="--headed"
  fi

  local screenshot_on_failure
  screenshot_on_failure=$(jq -r '.screenshot_on_failure // false' <<<"$config_json")
  local screenshot_path
  screenshot_path=$(jq -r '.screenshot_path // ""' <<<"$config_json")
  if [[ -n "$screenshot_path" && "$screenshot_path" != "null" ]]; then
    screenshot_path=$(expand_validation_path "$screenshot_path" "$repo" "$loop_id" "$iteration" "$loop_dir")
    if [[ "$screenshot_path" != /* ]]; then
      screenshot_path="$repo/$screenshot_path"
    fi
  fi

  local web_root
  web_root=$(jq -r '.web_root // ""' <<<"$config_json")
  if [[ -n "$web_root" && "$web_root" != "null" && "$web_root" != /* ]]; then
    web_root="$repo/$web_root"
  fi

  local -a test_results=()
  local all_ok=1

  expand_agent_browser_cmd() {
    local cmd="$1"
    cmd="${cmd//\{repo\}/$repo}"
    cmd="${cmd//\{loop_id\}/$loop_id}"
    cmd="${cmd//\{iteration\}/$iteration}"
    cmd="${cmd//\{loop_dir\}/$loop_dir}"
    cmd="${cmd//\{web_root\}/$web_root}"
    printf '%s' "$cmd"
  }

  run_ab_cmd() {
    local cmd="$1"
    local expanded
    expanded=$(expand_agent_browser_cmd "$cmd")
    agent-browser --session "$session" $headed_flag $expanded 2>&1
  }

  # Run setup commands
  local setup_cmds
  setup_cmds=$(jq -r '.setup // [] | .[]' <<<"$config_json")
  if [[ -n "$setup_cmds" ]]; then
    while IFS= read -r cmd; do
      if [[ -n "$cmd" ]]; then
        run_ab_cmd "$cmd" >/dev/null || true
      fi
    done <<<"$setup_cmds"
  fi

  # Run tests
  local tests_json
  tests_json=$(jq -c '.tests // []' <<<"$config_json")
  local test_count
  test_count=$(jq 'length' <<<"$tests_json")

  for ((i = 0; i < test_count; i++)); do
    local test_json
    test_json=$(jq -c ".[$i]" <<<"$tests_json")
    local test_name
    test_name=$(jq -r '.name // "test-'"$i"'"' <<<"$test_json")
    local test_ok=1
    local test_output=""
    local test_error=""

    local cmds
    cmds=$(jq -r '.commands // [] | .[]' <<<"$test_json")
    while IFS= read -r cmd; do
      if [[ -n "$cmd" ]]; then
        local cmd_output
        set +e
        cmd_output=$(run_ab_cmd "$cmd" 2>&1)
        local cmd_status=$?
        set -e
        test_output+="$ agent-browser $cmd"$'\n'"$cmd_output"$'\n'
        if [[ $cmd_status -ne 0 ]]; then
          test_ok=0
          test_error="Command failed: $cmd"
          break
        fi
      fi
    done <<<"$cmds"

    if [[ $test_ok -ne 1 ]]; then
      all_ok=0
      if [[ "$screenshot_on_failure" == "true" && -n "$screenshot_path" ]]; then
        mkdir -p "$(dirname "$screenshot_path")"
        run_ab_cmd "screenshot $screenshot_path" >/dev/null 2>&1 || true
      fi
    fi

    local result_json
    result_json=$(jq -n \
      --arg name "$test_name" \
      --argjson ok "$(if [[ $test_ok -eq 1 ]]; then echo true; else echo false; fi)" \
      --arg output "$test_output" \
      --arg error "$test_error" \
      '{name: $name, ok: $ok, output: $output, error: (if $error == "" then null else $error end)}')
    test_results+=("$result_json")
  done

  # Run cleanup commands
  local cleanup_cmds
  cleanup_cmds=$(jq -r '.cleanup // [] | .[]' <<<"$config_json")
  if [[ -n "$cleanup_cmds" ]]; then
    while IFS= read -r cmd; do
      if [[ -n "$cmd" ]]; then
        run_ab_cmd "$cmd" >/dev/null 2>&1 || true
      fi
    done <<<"$cleanup_cmds"
  fi

  # Build results JSON
  local results_array="[]"
  for result in "${test_results[@]}"; do
    results_array=$(jq --argjson r "$result" '. + [$r]' <<<"$results_array")
  done

  jq -n \
    --argjson ok "$(if [[ $all_ok -eq 1 ]]; then echo true; else echo false; fi)" \
    --arg session "$session" \
    --argjson tests "$results_array" \
    --arg screenshot_path "$screenshot_path" \
    '{ok: $ok, session: $session, tests: $tests, screenshot_path: (if $screenshot_path == "" then null else $screenshot_path end)}' \
    > "$output_file"

  if [[ $all_ok -eq 1 ]]; then
    return 0
  fi
  return 1
}

run_validation() {
  local repo="$1"
  local loop_dir="$2"
  local loop_id="$3"
  local iteration="$4"
  local loop_json="$5"

  local validation_dir="$loop_dir/validation"
  local validation_status_file="$loop_dir/validation-status.json"
  local validation_results_file="$loop_dir/validation-results.json"
  mkdir -p "$validation_dir"

  local preflight_enabled
  preflight_enabled=$(jq -r '.validation.preflight.enabled // false' <<<"$loop_json")
  local preflight_config
  preflight_config=$(jq -c '.validation.preflight // {}' <<<"$loop_json")
  local preflight_file="$validation_dir/preflight.json"
  local preflight_ok=1

  if [[ "$preflight_enabled" == "true" ]]; then
    run_validation_script \
      "$SCRIPT_DIR/scripts/validation/bundle-preflight.js" \
      "$repo" \
      "$preflight_config" \
      "$preflight_file" \
      "preflight"
    local preflight_ok_json="false"
    if [[ -f "$preflight_file" ]]; then
      preflight_ok_json=$(jq -r '.ok // false' "$preflight_file" 2>/dev/null || echo "false")
    fi
    if [[ "$preflight_ok_json" != "true" ]]; then
      preflight_ok=0
    fi
  fi

  local smoke_enabled
  smoke_enabled=$(jq -r '.validation.smoke_tests.enabled // false' <<<"$loop_json")
  local smoke_config
  smoke_config=$(jq -c '.validation.smoke_tests // {}' <<<"$loop_json")
  local smoke_file="$validation_dir/smoke-test.json"
  local smoke_ok=1

  if [[ "$smoke_enabled" == "true" ]]; then
    local screenshot_path
    screenshot_path=$(jq -r '.validation.smoke_tests.screenshot_path // ""' <<<"$loop_json")
    if [[ -n "$screenshot_path" && "$screenshot_path" != "null" ]]; then
      screenshot_path=$(expand_validation_path "$screenshot_path" "$repo" "$loop_id" "$iteration" "$loop_dir")
      if [[ "$screenshot_path" != /* ]]; then
        screenshot_path="$repo/$screenshot_path"
      fi
    else
      screenshot_path="$validation_dir/smoke-screenshot.png"
    fi

    smoke_config=$(jq -c --arg screenshot_path "$screenshot_path" '. + {screenshot_path: $screenshot_path}' <<<"$smoke_config")
    run_validation_script \
      "$SCRIPT_DIR/scripts/validation/web-smoke-test.js" \
      "$repo" \
      "$smoke_config" \
      "$smoke_file" \
      "smoke_test"
    local smoke_ok_json="false"
    if [[ -f "$smoke_file" ]]; then
      smoke_ok_json=$(jq -r '.ok // false' "$smoke_file" 2>/dev/null || echo "false")
    fi
    if [[ "$smoke_ok_json" != "true" ]]; then
      smoke_ok=0
    fi
  fi

  local checklist_enabled
  checklist_enabled=$(jq -r '.validation.automated_checklist.enabled // false' <<<"$loop_json")
  local checklist_config
  checklist_config=$(jq -c '.validation.automated_checklist // {}' <<<"$loop_json")
  local checklist_file="$validation_dir/checklist.json"
  local checklist_ok=1

  if [[ "$checklist_enabled" == "true" ]]; then
    run_validation_script \
      "$SCRIPT_DIR/scripts/validation/checklist-verifier.js" \
      "$repo" \
      "$checklist_config" \
      "$checklist_file" \
      "automated_checklist"
    local checklist_ok_json="false"
    if [[ -f "$checklist_file" ]]; then
      checklist_ok_json=$(jq -r '.ok // false' "$checklist_file" 2>/dev/null || echo "false")
    fi
    if [[ "$checklist_ok_json" != "true" ]]; then
      checklist_ok=0
    fi
  fi

  local agent_browser_enabled
  agent_browser_enabled=$(jq -r '.validation.agent_browser.enabled // false' <<<"$loop_json")
  local agent_browser_optional
  agent_browser_optional=$(jq -r '.validation.agent_browser.optional // false' <<<"$loop_json")
  local agent_browser_config
  agent_browser_config=$(jq -c '.validation.agent_browser // {}' <<<"$loop_json")
  local agent_browser_file="$validation_dir/agent-browser.json"
  local agent_browser_ok=1

  if [[ "$agent_browser_enabled" == "true" ]]; then
    set +e
    run_agent_browser_tests \
      "$repo" \
      "$loop_id" \
      "$iteration" \
      "$loop_dir" \
      "$agent_browser_config" \
      "$agent_browser_file"
    set -e
    local agent_browser_ok_json="false"
    if [[ -f "$agent_browser_file" ]]; then
      agent_browser_ok_json=$(jq -r '.ok // false' "$agent_browser_file" 2>/dev/null || echo "false")
    fi
    if [[ "$agent_browser_ok_json" != "true" ]]; then
      agent_browser_ok=0
    fi
  fi

  local ok=1
  if [[ "$preflight_enabled" == "true" && $preflight_ok -ne 1 ]]; then
    ok=0
  fi
  if [[ "$smoke_enabled" == "true" && $smoke_ok -ne 1 ]]; then
    ok=0
  fi
  if [[ "$checklist_enabled" == "true" && $checklist_ok -ne 1 ]]; then
    ok=0
  fi
  if [[ "$agent_browser_enabled" == "true" && "$agent_browser_optional" != "true" && $agent_browser_ok -ne 1 ]]; then
    ok=0
  fi

  local preflight_json="null"
  if [[ -f "$preflight_file" ]]; then
    preflight_json=$(cat "$preflight_file")
  fi
  preflight_json=$(json_or_default "$preflight_json" "null")

  local smoke_json="null"
  if [[ -f "$smoke_file" ]]; then
    smoke_json=$(cat "$smoke_file")
  fi
  smoke_json=$(json_or_default "$smoke_json" "null")

  local checklist_json="null"
  if [[ -f "$checklist_file" ]]; then
    checklist_json=$(cat "$checklist_file")
  fi
  checklist_json=$(json_or_default "$checklist_json" "null")

  local agent_browser_json="null"
  if [[ -f "$agent_browser_file" ]]; then
    agent_browser_json=$(cat "$agent_browser_file")
  fi
  agent_browser_json=$(json_or_default "$agent_browser_json" "null")

  jq -n \
    --arg generated_at "$(timestamp)" \
    --arg loop_id "$loop_id" \
    --argjson iteration "$iteration" \
    --argjson preflight "$preflight_json" \
    --argjson smoke_tests "$smoke_json" \
    --argjson automated_checklist "$checklist_json" \
    --argjson agent_browser "$agent_browser_json" \
    '{
      generated_at: $generated_at,
      loop_id: $loop_id,
      iteration: $iteration,
      preflight: $preflight,
      smoke_tests: $smoke_tests,
      automated_checklist: $automated_checklist,
      agent_browser: $agent_browser
    }' \
    > "$validation_results_file"

  local status="ok"
  local ok_json="true"
  if [[ $ok -ne 1 ]]; then
    status="failed"
    ok_json="false"
  fi

  write_validation_status "$validation_status_file" "$status" "$ok_json" "${validation_results_file#$repo/}"

  if [[ $ok -eq 1 ]]; then
    return 0
  fi
  return 1
}
