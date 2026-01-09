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

  jq -n \
    --arg generated_at "$(timestamp)" \
    --arg loop_id "$loop_id" \
    --argjson iteration "$iteration" \
    --argjson preflight "$preflight_json" \
    --argjson smoke_tests "$smoke_json" \
    --argjson automated_checklist "$checklist_json" \
    '{
      generated_at: $generated_at,
      loop_id: $loop_id,
      iteration: $iteration,
      preflight: $preflight,
      smoke_tests: $smoke_tests,
      automated_checklist: $automated_checklist
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
