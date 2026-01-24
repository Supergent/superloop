# Static config validation - catches config errors before the loop starts

# Error codes
STATIC_ERR_SCRIPT_NOT_FOUND="SCRIPT_NOT_FOUND"
STATIC_ERR_COMMAND_NOT_FOUND="COMMAND_NOT_FOUND"
STATIC_ERR_RUNNER_NOT_FOUND="RUNNER_NOT_FOUND"
STATIC_ERR_SPEC_NOT_FOUND="SPEC_NOT_FOUND"
STATIC_ERR_POSSIBLE_TYPO="POSSIBLE_TYPO"
STATIC_ERR_TIMEOUT_SUSPICIOUS="TIMEOUT_SUSPICIOUS"
STATIC_ERR_DUPLICATE_LOOP_ID="DUPLICATE_LOOP_ID"

# Arrays to collect errors and warnings (initialized in validate_static)
STATIC_ERRORS=""
STATIC_WARNINGS=""
STATIC_ERROR_COUNT=0
STATIC_WARNING_COUNT=0

static_add_error() {
  local code="$1"
  local message="$2"
  local location="$3"
  local json
  json=$(jq -nc \
    --arg code "$code" \
    --arg message "$message" \
    --arg location "$location" \
    --arg severity "error" \
    '{code: $code, message: $message, location: $location, severity: $severity}')
  if [[ -n "$STATIC_ERRORS" ]]; then
    STATIC_ERRORS="$STATIC_ERRORS"$'\n'"$json"
  else
    STATIC_ERRORS="$json"
  fi
  ((STATIC_ERROR_COUNT++))
}

static_add_warning() {
  local code="$1"
  local message="$2"
  local location="$3"
  local json
  json=$(jq -nc \
    --arg code "$code" \
    --arg message "$message" \
    --arg location "$location" \
    --arg severity "warning" \
    '{code: $code, message: $message, location: $location, severity: $severity}')
  if [[ -n "$STATIC_WARNINGS" ]]; then
    STATIC_WARNINGS="$STATIC_WARNINGS"$'\n'"$json"
  else
    STATIC_WARNINGS="$json"
  fi
  ((STATIC_WARNING_COUNT++))
}

# Check if a script exists in package.json
# Usage: check_package_script <repo> <script_name>
# Returns: 0 if exists, 1 if not
check_package_script() {
  local repo="$1"
  local script_name="$2"
  local pkg_json="$repo/package.json"

  if [[ ! -f "$pkg_json" ]]; then
    return 1
  fi

  local script_value
  script_value=$(jq -r --arg name "$script_name" '.scripts[$name] // ""' "$pkg_json" 2>/dev/null)
  if [[ -n "$script_value" && "$script_value" != "null" ]]; then
    return 0
  fi
  return 1
}

# Get the script content from package.json
get_package_script_content() {
  local repo="$1"
  local script_name="$2"
  local pkg_json="$repo/package.json"

  if [[ ! -f "$pkg_json" ]]; then
    echo ""
    return
  fi

  jq -r --arg name "$script_name" '.scripts[$name] // ""' "$pkg_json" 2>/dev/null
}

# Extract script name from commands like "bun run test", "npm run build"
# Usage: extract_script_name <command>
# Outputs: script name or empty string
extract_script_name() {
  local cmd="$1"

  # Match "bun run <script>", "npm run <script>", "yarn <script>", "pnpm <script>", "pnpm run <script>"
  if [[ "$cmd" =~ ^(bun|npm|pnpm)[[:space:]]+run[[:space:]]+([a-zA-Z0-9_:-]+) ]]; then
    echo "${BASH_REMATCH[2]}"
    return
  fi

  if [[ "$cmd" =~ ^yarn[[:space:]]+([a-zA-Z0-9_:-]+) ]]; then
    # Skip yarn built-in commands
    local maybe_script="${BASH_REMATCH[1]}"
    case "$maybe_script" in
      add|remove|install|init|upgrade|info|why|link|unlink|pack|publish|cache|config|global|import|licenses|list|outdated|owner|login|logout|version|versions|workspace|workspaces|run)
        echo ""
        ;;
      *)
        echo "$maybe_script"
        ;;
    esac
    return
  fi

  echo ""
}

# Check for "bun test" vs "bun run test" typo when vitest is configured
# Usage: check_bun_test_typo <repo> <command> <location>
check_bun_test_typo() {
  local repo="$1"
  local cmd="$2"
  local location="$3"

  # Only check if command is exactly "bun test" (without "run")
  if [[ "$cmd" != "bun test" && ! "$cmd" =~ ^bun[[:space:]]+test[[:space:]] ]]; then
    return 0
  fi

  # Check if package.json has a "test" script that uses vitest
  local test_script
  test_script=$(get_package_script_content "$repo" "test")

  if [[ "$test_script" == *"vitest"* ]]; then
    static_add_warning "$STATIC_ERR_POSSIBLE_TYPO" \
      "Command 'bun test' runs Bun's native test runner, not vitest. Did you mean 'bun run test'?" \
      "$location"
    return 1
  fi

  return 0
}

# Check if a command uses a package.json script that exists
# Usage: check_command_script <repo> <command> <location>
check_command_script() {
  local repo="$1"
  local cmd="$2"
  local location="$3"

  local script_name
  script_name=$(extract_script_name "$cmd")

  if [[ -z "$script_name" ]]; then
    # Not a script-based command, skip
    return 0
  fi

  if ! check_package_script "$repo" "$script_name"; then
    static_add_error "$STATIC_ERR_SCRIPT_NOT_FOUND" \
      "Command '$cmd' references script '$script_name' which doesn't exist in package.json" \
      "$location"
    return 1
  fi

  return 0
}

# Check if a runner command is available in PATH
# Usage: check_runner_command <runner_name> <command_array_json> <location>
check_runner_command() {
  local runner_name="$1"
  local command_json="$2"
  local location="$3"

  local runner_cmd
  runner_cmd=$(echo "$command_json" | jq -r '.[0] // ""')

  if [[ -z "$runner_cmd" || "$runner_cmd" == "null" ]]; then
    static_add_error "$STATIC_ERR_RUNNER_NOT_FOUND" \
      "Runner '$runner_name' has no command specified" \
      "$location"
    return 1
  fi

  if ! command -v "$runner_cmd" &>/dev/null; then
    static_add_error "$STATIC_ERR_RUNNER_NOT_FOUND" \
      "Runner '$runner_name' uses command '$runner_cmd' which is not in PATH" \
      "$location"
    return 1
  fi

  return 0
}

# Check if a spec file exists
# Usage: check_spec_file <repo> <spec_path> <location>
check_spec_file() {
  local repo="$1"
  local spec_path="$2"
  local location="$3"

  local full_path="$repo/$spec_path"
  if [[ ! -f "$full_path" ]]; then
    static_add_error "$STATIC_ERR_SPEC_NOT_FOUND" \
      "Spec file '$spec_path' does not exist" \
      "$location"
    return 1
  fi

  return 0
}

# Check timeout sanity
# Usage: check_timeout <name> <value_seconds> <location>
check_timeout() {
  local name="$1"
  local value="$2"
  local location="$3"

  # Skip if not a number
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  # Timeouts in config are in seconds, not milliseconds
  # Less than 5 seconds is suspicious
  if [[ "$value" -gt 0 && "$value" -lt 5 ]]; then
    static_add_warning "$STATIC_ERR_TIMEOUT_SUSPICIOUS" \
      "Timeout '$name' is $value seconds which seems too short. Did you mean ${value}0 or ${value}00?" \
      "$location"
    return 1
  fi

  # More than 24 hours (86400 seconds) is suspicious
  if [[ "$value" -gt 86400 ]]; then
    static_add_warning "$STATIC_ERR_TIMEOUT_SUSPICIOUS" \
      "Timeout '$name' is $value seconds (over 24 hours). Is this intentional?" \
      "$location"
    return 1
  fi

  return 0
}

# Check for duplicate loop IDs
# Usage: check_duplicate_loop_ids <config_path>
check_duplicate_loop_ids() {
  local config_path="$1"

  local loop_ids
  loop_ids=$(jq -r '.loops[]?.id // empty' "$config_path" 2>/dev/null)

  # Use a simple approach: sort and check for adjacent duplicates
  local sorted_ids
  sorted_ids=$(echo "$loop_ids" | sort)
  local prev_id=""
  while IFS= read -r loop_id; do
    if [[ -n "$loop_id" && "$loop_id" == "$prev_id" ]]; then
      static_add_error "$STATIC_ERR_DUPLICATE_LOOP_ID" \
        "Duplicate loop ID '$loop_id'" \
        "loops"
      return 1
    fi
    prev_id="$loop_id"
  done <<< "$sorted_ids"

  return 0
}

# Main static validation function
# Usage: validate_static <repo> <config_path>
# Returns: 0 if valid, 1 if errors found
validate_static() {
  local repo="$1"
  local config_path="$2"

  # Reset globals
  STATIC_ERRORS=""
  STATIC_WARNINGS=""
  STATIC_ERROR_COUNT=0
  STATIC_WARNING_COUNT=0

  if [[ ! -f "$config_path" ]]; then
    echo "error: config not found: $config_path" >&2
    return 1
  fi

  local config_json
  config_json=$(cat "$config_path")

  # Check for duplicate loop IDs
  check_duplicate_loop_ids "$config_path"

  # Check runners
  local runner_names
  runner_names=$(echo "$config_json" | jq -r '.runners | keys[]' 2>/dev/null)
  while IFS= read -r runner_name; do
    if [[ -n "$runner_name" ]]; then
      local command_json
      command_json=$(echo "$config_json" | jq -c ".runners[\"$runner_name\"].command // []")
      check_runner_command "$runner_name" "$command_json" "runners.$runner_name.command"
    fi
  done <<< "$runner_names"

  # Check each loop
  local loop_count
  loop_count=$(echo "$config_json" | jq '.loops | length' 2>/dev/null || echo 0)

  for ((i = 0; i < loop_count; i++)); do
    local loop_json
    loop_json=$(echo "$config_json" | jq -c ".loops[$i]")
    local loop_id
    loop_id=$(echo "$loop_json" | jq -r '.id // ""')

    # Check spec file exists
    local spec_file
    spec_file=$(echo "$loop_json" | jq -r '.spec_file // ""')
    if [[ -n "$spec_file" && "$spec_file" != "null" ]]; then
      check_spec_file "$repo" "$spec_file" "loops[$i].spec_file"
    fi

    # Check test commands
    local test_commands
    test_commands=$(echo "$loop_json" | jq -r '.tests.commands[]? // empty' 2>/dev/null)
    local cmd_idx=0
    while IFS= read -r cmd; do
      if [[ -n "$cmd" ]]; then
        check_bun_test_typo "$repo" "$cmd" "loops[$i].tests.commands[$cmd_idx]"
        check_command_script "$repo" "$cmd" "loops[$i].tests.commands[$cmd_idx]"
        ((cmd_idx++))
      fi
    done <<< "$test_commands"

    # Check validation commands
    local validation_commands
    validation_commands=$(echo "$loop_json" | jq -r '.validation.commands[]? // empty' 2>/dev/null)
    cmd_idx=0
    while IFS= read -r cmd; do
      if [[ -n "$cmd" ]]; then
        check_bun_test_typo "$repo" "$cmd" "loops[$i].validation.commands[$cmd_idx]"
        check_command_script "$repo" "$cmd" "loops[$i].validation.commands[$cmd_idx]"
        ((cmd_idx++))
      fi
    done <<< "$validation_commands"

    # Check timeouts
    local timeouts_json
    timeouts_json=$(echo "$loop_json" | jq -c '.timeouts // {}')
    if [[ "$timeouts_json" != "null" && "$timeouts_json" != "{}" ]]; then
      local default_timeout
      default_timeout=$(echo "$timeouts_json" | jq -r '.default // 0')
      check_timeout "default" "$default_timeout" "loops[$i].timeouts.default"

      for role in planner implementer tester reviewer; do
        local role_timeout
        role_timeout=$(echo "$timeouts_json" | jq -r ".$role // 0")
        if [[ "$role_timeout" != "0" && "$role_timeout" != "null" ]]; then
          check_timeout "$role" "$role_timeout" "loops[$i].timeouts.$role"
        fi
      done
    fi

    # Check that roles reference valid runners
    local roles_json
    roles_json=$(echo "$loop_json" | jq -c '.roles // {}')
    if [[ "$roles_json" != "null" && "$roles_json" != "{}" ]]; then
      for role in planner implementer tester reviewer; do
        local runner_ref
        runner_ref=$(echo "$roles_json" | jq -r ".$role.runner // \"\"")
        if [[ -n "$runner_ref" && "$runner_ref" != "null" ]]; then
          # Check if this runner exists in the config
          local runner_exists
          runner_exists=$(echo "$config_json" | jq -r ".runners[\"$runner_ref\"] // \"missing\"")
          if [[ "$runner_exists" == "missing" || "$runner_exists" == "null" ]]; then
            static_add_error "$STATIC_ERR_RUNNER_NOT_FOUND" \
              "Role '$role' references runner '$runner_ref' which is not defined in runners" \
              "loops[$i].roles.$role.runner"
          fi
        fi
      done
    fi
  done

  # Output results
  output_static_validation_results
}

# Output validation results in JSON format
output_static_validation_results() {
  local errors_json="[]"
  local warnings_json="[]"

  # Convert newline-separated JSONL to JSON array
  if [[ -n "$STATIC_ERRORS" ]]; then
    errors_json=$(echo "$STATIC_ERRORS" | jq -s '.')
  fi

  if [[ -n "$STATIC_WARNINGS" ]]; then
    warnings_json=$(echo "$STATIC_WARNINGS" | jq -s '.')
  fi

  local valid="true"
  if [[ $STATIC_ERROR_COUNT -gt 0 ]]; then
    valid="false"
  fi

  jq -n \
    --argjson valid "$valid" \
    --argjson errors "$errors_json" \
    --argjson warnings "$warnings_json" \
    --argjson error_count "$STATIC_ERROR_COUNT" \
    --argjson warning_count "$STATIC_WARNING_COUNT" \
    '{
      valid: $valid,
      error_count: $error_count,
      warning_count: $warning_count,
      errors: $errors,
      warnings: $warnings
    }'

  # Print human-readable summary to stderr
  if [[ $STATIC_ERROR_COUNT -gt 0 || $STATIC_WARNING_COUNT -gt 0 ]]; then
    echo "" >&2
    echo "Static Validation Results:" >&2
    echo "==========================" >&2

    if [[ $STATIC_ERROR_COUNT -gt 0 ]]; then
      echo "" >&2
      echo "Errors ($STATIC_ERROR_COUNT):" >&2
      while IFS= read -r err; do
        if [[ -n "$err" ]]; then
          local msg loc
          msg=$(echo "$err" | jq -r '.message')
          loc=$(echo "$err" | jq -r '.location')
          echo "  ✗ [$loc] $msg" >&2
        fi
      done <<< "$STATIC_ERRORS"
    fi

    if [[ $STATIC_WARNING_COUNT -gt 0 ]]; then
      echo "" >&2
      echo "Warnings ($STATIC_WARNING_COUNT):" >&2
      while IFS= read -r warn; do
        if [[ -n "$warn" ]]; then
          local msg loc
          msg=$(echo "$warn" | jq -r '.message')
          loc=$(echo "$warn" | jq -r '.location')
          echo "  ⚠ [$loc] $msg" >&2
        fi
      done <<< "$STATIC_WARNINGS"
    fi

    echo "" >&2
  fi

  if [[ $STATIC_ERROR_COUNT -gt 0 ]]; then
    return 1
  fi
  return 0
}
