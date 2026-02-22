# Static config validation - catches config errors before the loop starts

# Error codes
STATIC_ERR_SCRIPT_NOT_FOUND="SCRIPT_NOT_FOUND"
STATIC_ERR_COMMAND_NOT_FOUND="COMMAND_NOT_FOUND"
STATIC_ERR_RUNNER_NOT_FOUND="RUNNER_NOT_FOUND"
STATIC_ERR_SPEC_NOT_FOUND="SPEC_NOT_FOUND"
STATIC_ERR_POSSIBLE_TYPO="POSSIBLE_TYPO"
STATIC_ERR_TIMEOUT_SUSPICIOUS="TIMEOUT_SUSPICIOUS"
STATIC_ERR_DUPLICATE_LOOP_ID="DUPLICATE_LOOP_ID"
STATIC_ERR_RLMS_INVALID="RLMS_INVALID"
STATIC_ERR_TESTS_CONFIG_INVALID="TESTS_CONFIG_INVALID"
STATIC_ERR_PREREQUISITES_CONFIG_INVALID="PREREQUISITES_CONFIG_INVALID"
STATIC_ERR_DEV_ENV_CONTRACT_INVALID="DEV_ENV_CONTRACT_INVALID"

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

# Check RLMS configuration semantics
# Usage: check_rlms_config <loop_json> <location_prefix>
check_rlms_config() {
  local loop_json="$1"
  local location_prefix="$2"

  local rlms_enabled
  rlms_enabled=$(echo "$loop_json" | jq -r '.rlms.enabled // false' 2>/dev/null || echo "false")
  if [[ "$rlms_enabled" != "true" ]]; then
    return 0
  fi

  local force_on force_off
  force_on=$(echo "$loop_json" | jq -r '.rlms.policy.force_on // false' 2>/dev/null || echo "false")
  force_off=$(echo "$loop_json" | jq -r '.rlms.policy.force_off // false' 2>/dev/null || echo "false")
  if [[ "$force_on" == "true" && "$force_off" == "true" ]]; then
    static_add_error "$STATIC_ERR_RLMS_INVALID" \
      "rlms.policy.force_on and rlms.policy.force_off cannot both be true" \
      "$location_prefix.rlms.policy"
  fi

  local mode request_keyword
  mode=$(echo "$loop_json" | jq -r '.rlms.mode // "hybrid"' 2>/dev/null || echo "hybrid")
  request_keyword=$(echo "$loop_json" | jq -r '.rlms.request_keyword // "RLMS_REQUEST"' 2>/dev/null || echo "RLMS_REQUEST")
  if [[ "$mode" == "requested" || "$mode" == "hybrid" ]]; then
    if [[ -z "$request_keyword" || "$request_keyword" == "null" ]]; then
      static_add_error "$STATIC_ERR_RLMS_INVALID" \
        "rlms.request_keyword must be set when mode is '$mode'" \
        "$location_prefix.rlms.request_keyword"
    fi
  fi

  local timeout_seconds
  timeout_seconds=$(echo "$loop_json" | jq -r '.rlms.limits.timeout_seconds // 0' 2>/dev/null || echo "0")
  if [[ "$timeout_seconds" != "0" && "$timeout_seconds" != "null" ]]; then
    check_timeout "rlms.timeout_seconds" "$timeout_seconds" "$location_prefix.rlms.limits.timeout_seconds"
  fi

  local max_steps max_depth max_subcalls
  max_steps=$(echo "$loop_json" | jq -r '.rlms.limits.max_steps // 0' 2>/dev/null || echo "0")
  max_depth=$(echo "$loop_json" | jq -r '.rlms.limits.max_depth // 0' 2>/dev/null || echo "0")
  max_subcalls=$(echo "$loop_json" | jq -r '.rlms.limits.max_subcalls // 0' 2>/dev/null || echo "0")

  if [[ "$max_steps" =~ ^[0-9]+$ && "$max_steps" -gt 0 && "$max_steps" -gt 500 ]]; then
    static_add_warning "$STATIC_ERR_TIMEOUT_SUSPICIOUS" \
      "rlms.limits.max_steps is $max_steps which may be expensive; consider lower defaults" \
      "$location_prefix.rlms.limits.max_steps"
  fi

  if [[ "$max_depth" =~ ^[0-9]+$ && "$max_depth" -gt 8 ]]; then
    static_add_warning "$STATIC_ERR_TIMEOUT_SUSPICIOUS" \
      "rlms.limits.max_depth is $max_depth which may cause deep recursion and high cost" \
      "$location_prefix.rlms.limits.max_depth"
  fi

  if [[ "$max_subcalls" =~ ^[0-9]+$ && "$max_subcalls" -gt 0 && "$max_subcalls" -gt 2000 ]]; then
    static_add_warning "$STATIC_ERR_TIMEOUT_SUSPICIOUS" \
      "rlms.limits.max_subcalls is $max_subcalls which may be expensive; consider lower defaults" \
      "$location_prefix.rlms.limits.max_subcalls"
  fi
}

# Ensure tests gate configuration is internally consistent.
# Usage: check_tests_gate_config <loop_json> <location_prefix>
check_tests_gate_config() {
  local loop_json="$1"
  local location_prefix="$2"

  local tests_mode
  tests_mode=$(jq -r '.tests.mode // "disabled"' <<<"$loop_json" 2>/dev/null || echo "disabled")

  local tests_command_count
  tests_command_count=$(jq -r '[.tests.commands[]? | strings | select((gsub("^\\s+|\\s+$"; "") | length) > 0)] | length' <<<"$loop_json" 2>/dev/null || echo 0)

  if [[ "$tests_mode" != "disabled" && "$tests_command_count" == "0" ]]; then
    static_add_error "$STATIC_ERR_TESTS_CONFIG_INVALID" \
      "tests.mode is '$tests_mode' but tests.commands is empty. Add at least one test command or set tests.mode to 'disabled'." \
      "$location_prefix.tests"
    return 1
  fi

  return 0
}

# Ensure prerequisites gate configuration is internally consistent.
# Usage: check_prerequisites_gate_config <repo> <loop_json> <location_prefix>
check_prerequisites_gate_config() {
  local repo="$1"
  local loop_json="$2"
  local location_prefix="$3"

  local enabled
  enabled=$(jq -r '.prerequisites.enabled // false' <<<"$loop_json" 2>/dev/null || echo "false")
  local require_on_completion
  require_on_completion=$(jq -r '.prerequisites.require_on_completion // false' <<<"$loop_json" 2>/dev/null || echo "false")
  local checks_count
  checks_count=$(jq -r '(.prerequisites.checks // []) | length' <<<"$loop_json" 2>/dev/null || echo "0")
  local loop_id
  loop_id=$(jq -r '.id // ""' <<<"$loop_json" 2>/dev/null || echo "")

  if [[ "$enabled" == "true" && "$require_on_completion" == "true" && "$checks_count" == "0" ]]; then
    static_add_error "$STATIC_ERR_PREREQUISITES_CONFIG_INVALID" \
      "prerequisites is enabled and required_on_completion, but no checks are configured." \
      "$location_prefix.prerequisites.checks"
    return 1
  fi

  if [[ "$checks_count" == "0" ]]; then
    return 0
  fi

  local i
  for ((i = 0; i < checks_count; i++)); do
    local check_json
    check_json=$(jq -c ".prerequisites.checks[$i]" <<<"$loop_json")
    local check_type
    check_type=$(jq -r '.type // ""' <<<"$check_json")
    local check_path
    check_path=$(jq -r '.path // ""' <<<"$check_json")

    if [[ -z "$check_type" || "$check_type" == "null" ]]; then
      static_add_error "$STATIC_ERR_PREREQUISITES_CONFIG_INVALID" \
        "prerequisites.checks[$i] is missing required field 'type'." \
        "$location_prefix.prerequisites.checks[$i].type"
      continue
    fi

    if [[ -z "$check_path" || "$check_path" == "null" ]]; then
      static_add_error "$STATIC_ERR_PREREQUISITES_CONFIG_INVALID" \
        "prerequisites.checks[$i] is missing required field 'path'." \
        "$location_prefix.prerequisites.checks[$i].path"
      continue
    fi

    if [[ "$check_type" == "file_regex_present" || "$check_type" == "file_regex_absent" ]]; then
      local pattern
      pattern=$(jq -r '.pattern // ""' <<<"$check_json")
      if [[ -z "$pattern" || "$pattern" == "null" ]]; then
        static_add_error "$STATIC_ERR_PREREQUISITES_CONFIG_INVALID" \
          "prerequisites.checks[$i] type '$check_type' requires a non-empty 'pattern'." \
          "$location_prefix.prerequisites.checks[$i].pattern"
      fi
    fi

    if [[ "$check_type" == "file_contains_all" || "$check_type" == "file_not_contains_any" ]]; then
      local needles_count
      needles_count=$(jq -r '(.needles // []) | length' <<<"$check_json" 2>/dev/null || echo "0")
      if [[ "$needles_count" == "0" ]]; then
        static_add_error "$STATIC_ERR_PREREQUISITES_CONFIG_INVALID" \
          "prerequisites.checks[$i] type '$check_type' requires non-empty 'needles'." \
          "$location_prefix.prerequisites.checks[$i].needles"
      fi
    fi

    local resolved_path="$check_path"
    resolved_path="${resolved_path//\{repo\}/$repo}"
    resolved_path="${resolved_path//\{loop_id\}/$loop_id}"
    if [[ "$resolved_path" != /* ]]; then
      resolved_path="$repo/$resolved_path"
    fi

    # Skip existence checks for dynamic iteration paths.
    if [[ "$resolved_path" == *"{iteration}"* ]]; then
      continue
    fi

    if [[ ! -e "$resolved_path" ]]; then
      static_add_error "$STATIC_ERR_PREREQUISITES_CONFIG_INVALID" \
        "prerequisites.checks[$i] path '$check_path' does not exist." \
        "$location_prefix.prerequisites.checks[$i].path"
    fi
  done

  return 0
}

# Validate target adapter manifest contract when explicitly required by config.
# Usage: check_dev_env_contract_manifest <repo> <config_json>
check_dev_env_contract_manifest() {
  local repo="$1"
  local config_json="$2"

  local require_manifest
  require_manifest=$(jq -r '.dev_env_contract.require_target_adapter_manifest // false' <<<"$config_json" 2>/dev/null || echo "false")
  if [[ "$require_manifest" != "true" ]]; then
    return 0
  fi

  local manifest_path schema_path
  manifest_path=$(jq -r '.dev_env_contract.manifest_path // ".superloop/dev-env/adapter.manifest.json"' <<<"$config_json" 2>/dev/null || echo ".superloop/dev-env/adapter.manifest.json")
  schema_path=$(jq -r '.dev_env_contract.schema_path // ".superloop/dev-env/schema/dev-env-target-adapter.schema.json"' <<<"$config_json" 2>/dev/null || echo ".superloop/dev-env/schema/dev-env-target-adapter.schema.json")

  local manifest_full_path="$manifest_path"
  local schema_full_path="$schema_path"
  if [[ "$manifest_full_path" != /* ]]; then
    manifest_full_path="$repo/$manifest_full_path"
  fi
  if [[ "$schema_full_path" != /* ]]; then
    schema_full_path="$repo/$schema_full_path"
  fi

  if [[ ! -f "$manifest_full_path" ]]; then
    static_add_error "$STATIC_ERR_DEV_ENV_CONTRACT_INVALID" \
      "dev_env_contract requires adapter manifest, but file is missing at '$manifest_path'" \
      "dev_env_contract.manifest_path"
    return 1
  fi

  if [[ ! -f "$schema_full_path" ]]; then
    static_add_error "$STATIC_ERR_DEV_ENV_CONTRACT_INVALID" \
      "dev_env_contract schema file is missing at '$schema_path'" \
      "dev_env_contract.schema_path"
    return 1
  fi

  if ! jq -e . "$manifest_full_path" >/dev/null 2>&1; then
    static_add_error "$STATIC_ERR_DEV_ENV_CONTRACT_INVALID" \
      "adapter manifest '$manifest_path' is not valid JSON" \
      "dev_env_contract.manifest_path"
    return 1
  fi

  if ! declare -f validate_schema_config >/dev/null 2>&1; then
    static_add_error "$STATIC_ERR_DEV_ENV_CONTRACT_INVALID" \
      "internal validator validate_schema_config is unavailable for dev_env_contract enforcement" \
      "dev_env_contract"
    return 1
  fi

  if ! validate_schema_config "$schema_full_path" "$manifest_full_path" >/dev/null 2>&1; then
    static_add_error "$STATIC_ERR_DEV_ENV_CONTRACT_INVALID" \
      "adapter manifest '$manifest_path' does not match schema '$schema_path'" \
      "dev_env_contract.manifest_path"
    return 1
  fi

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

  # Enforce target adapter manifest contract when configured.
  check_dev_env_contract_manifest "$repo" "$config_json"

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

    # Check RLMS semantic config
    check_rlms_config "$loop_json" "loops[$i]"

    # Check tests gate policy
    check_tests_gate_config "$loop_json" "loops[$i]"
    check_prerequisites_gate_config "$repo" "$loop_json" "loops[$i]"

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

# =============================================================================
# PROBE VALIDATION (Phase 2)
# =============================================================================

# Error codes for probes
PROBE_ERR_COMMAND_NOT_FOUND="PROBE_COMMAND_NOT_FOUND"
PROBE_ERR_ENV_ERROR="PROBE_ENV_ERROR"
PROBE_ERR_RUNNER_FAILED="PROBE_RUNNER_FAILED"
PROBE_ERR_TIMEOUT="PROBE_TIMEOUT"
PROBE_ERR_RUNNER_ARGS_INVALID="PROBE_RUNNER_ARGS_INVALID"
PROBE_ERR_RUNNER_SHAPE_INVALID="PROBE_RUNNER_SHAPE_INVALID"
PROBE_ERR_AUTH_REQUIRED="PROBE_AUTH_REQUIRED"
PROBE_WARN_AUTH_CHECK_SKIPPED="PROBE_AUTH_CHECK_SKIPPED"

# Probe results storage
PROBE_RESULTS=""
PROBE_ERROR_COUNT=0
PROBE_WARNING_COUNT=0

probe_add_error() {
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
  if [[ -n "$PROBE_RESULTS" ]]; then
    PROBE_RESULTS="$PROBE_RESULTS"$'\n'"$json"
  else
    PROBE_RESULTS="$json"
  fi
  ((PROBE_ERROR_COUNT++))
}

probe_add_warning() {
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
  if [[ -n "$PROBE_RESULTS" ]]; then
    PROBE_RESULTS="$PROBE_RESULTS"$'\n'"$json"
  else
    PROBE_RESULTS="$json"
  fi
  ((PROBE_WARNING_COUNT++))
}

probe_reset_results() {
  PROBE_RESULTS=""
  PROBE_ERROR_COUNT=0
  PROBE_WARNING_COUNT=0
}

is_native_command_name() {
  local cmd="$1"
  local expected="$2"
  local base="${cmd##*/}"
  [[ "$base" == "$expected" ]]
}

probe_check_claude_args() {
  local runner_name="$1"
  local args_json="$2"
  local location="$3"
  local failed=0

  if echo "$args_json" | jq -e '.[]? | select(. == "-C" or . == "--cd")' >/dev/null 2>&1; then
    probe_add_error "$PROBE_ERR_RUNNER_ARGS_INVALID" \
      "Runner '$runner_name' uses -C/--cd, but native Claude CLI does not support directory flags" \
      "$location"
    failed=1
  fi

  if ! echo "$args_json" | jq -e '.[]? | select(. == "-p" or . == "--print")' >/dev/null 2>&1; then
    probe_add_error "$PROBE_ERR_RUNNER_ARGS_INVALID" \
      "Runner '$runner_name' must include --print (or -p) for non-interactive execution" \
      "$location"
    failed=1
  fi

  return "$failed"
}

probe_check_native_codex_shape() {
  local runner_name="$1"
  local command_json="$2"
  local args_json="$3"
  local prompt_mode="$4"
  local location="$5"
  local failed=0

  if ! echo "$command_json" | jq -e '.[]? | select(. == "exec")' >/dev/null 2>&1; then
    probe_add_error "$PROBE_ERR_RUNNER_SHAPE_INVALID" \
      "Runner '$runner_name' must include 'exec' in command for non-interactive Codex runs" \
      "$location"
    failed=1
  fi

  if [[ "$prompt_mode" == "stdin" ]]; then
    if ! echo "$args_json" | jq -e '.[]? | select(. == "-")' >/dev/null 2>&1; then
      probe_add_error "$PROBE_ERR_RUNNER_SHAPE_INVALID" \
        "Runner '$runner_name' uses prompt_mode=stdin and must include '-' in args to consume stdin prompt" \
        "$location"
      failed=1
    fi
  fi

  return "$failed"
}

probe_check_claude_auth() {
  local runner_name="$1"
  local runner_cmd="$2"
  local location="$3"

  local auth_output=""
  local auth_rc=0
  set +e
  auth_output=$("$runner_cmd" auth status 2>&1)
  auth_rc=$?
  set -e

  if [[ $auth_rc -ne 0 ]]; then
    probe_add_error "$PROBE_ERR_AUTH_REQUIRED" \
      "Runner '$runner_name' is not authenticated with Claude Code. Run 'claude auth login'. (${auth_output:0:200})" \
      "$location"
    return 1
  fi

  if echo "$auth_output" | jq -e '.loggedIn == false' >/dev/null 2>&1; then
    probe_add_error "$PROBE_ERR_AUTH_REQUIRED" \
      "Runner '$runner_name' is not authenticated with Claude Code. Run 'claude auth login'" \
      "$location"
    return 1
  fi

  return 0
}

probe_check_codex_auth() {
  local runner_name="$1"
  local runner_cmd="$2"
  local location="$3"

  local codex_cmd="codex"
  if is_native_command_name "$runner_cmd" "codex"; then
    codex_cmd="$runner_cmd"
  fi

  if ! command -v "$codex_cmd" >/dev/null 2>&1; then
    probe_add_warning "$PROBE_WARN_AUTH_CHECK_SKIPPED" \
      "Runner '$runner_name' appears to use Codex, but 'codex' is not in PATH so login status could not be checked" \
      "$location"
    return 0
  fi

  local auth_output=""
  local auth_rc=0
  set +e
  auth_output=$("$codex_cmd" login status 2>&1)
  auth_rc=$?
  set -e

  if [[ $auth_rc -ne 0 ]]; then
    probe_add_error "$PROBE_ERR_AUTH_REQUIRED" \
      "Runner '$runner_name' is not authenticated with Codex. Run 'codex login'. (${auth_output:0:200})" \
      "$location"
    return 1
  fi

  return 0
}

probe_runner_profile() {
  local runner_name="$1"
  local runner_json="$2"
  local location="$3"

  local command_json
  command_json=$(echo "$runner_json" | jq -c '.command // []')
  local args_json
  args_json=$(echo "$runner_json" | jq -c '.args // []')
  local prompt_mode
  prompt_mode=$(echo "$runner_json" | jq -r '.prompt_mode // "stdin"')

  local runner_cmd
  runner_cmd=$(echo "$command_json" | jq -r '.[0] // ""')

  if [[ -z "$runner_cmd" || "$runner_cmd" == "null" ]]; then
    probe_add_error "$PROBE_ERR_RUNNER_FAILED" \
      "Runner '$runner_name' has no command specified" \
      "$location.command"
    return 1
  fi

  if ! command -v "$runner_cmd" >/dev/null 2>&1; then
    probe_add_error "$PROBE_ERR_COMMAND_NOT_FOUND" \
      "Runner '$runner_name' command '$runner_cmd' is not in PATH" \
      "$location.command"
    return 1
  fi

  local -a detect_tokens=()
  mapfile -t detect_tokens < <(echo "$runner_json" | jq -r '.command[]?, .args[]?')
  local runner_type="unknown"
  if type detect_runner_type &>/dev/null && [[ ${#detect_tokens[@]} -gt 0 ]]; then
    runner_type=$(detect_runner_type "${detect_tokens[@]}")
  elif is_native_command_name "$runner_cmd" "claude"; then
    runner_type="claude"
  elif is_native_command_name "$runner_cmd" "codex"; then
    runner_type="codex"
  fi

  local failed=0

  if is_native_command_name "$runner_cmd" "claude"; then
    probe_check_claude_args "$runner_name" "$args_json" "$location.args" || failed=1
  fi

  if is_native_command_name "$runner_cmd" "codex"; then
    probe_check_native_codex_shape "$runner_name" "$command_json" "$args_json" "$prompt_mode" "$location.command" || failed=1
  fi

  if [[ "$runner_type" == "claude" ]]; then
    probe_check_claude_auth "$runner_name" "$runner_cmd" "$location.auth" || failed=1
  elif [[ "$runner_type" == "codex" ]]; then
    probe_check_codex_auth "$runner_name" "$runner_cmd" "$location.auth" || failed=1
  fi

  return "$failed"
}

# Probe a test command to verify it works
# Usage: probe_test_command <repo> <command> <location> <timeout_seconds>
probe_test_command() {
  local repo="$1"
  local cmd="$2"
  local location="$3"
  local timeout_secs="${4:-30}"

  local original_dir
  original_dir=$(pwd)
  cd "$repo" || return 1

  local test_output
  local test_rc

  # Run the actual command with timeout
  set +e
  if command -v timeout &>/dev/null; then
    test_output=$(timeout "$timeout_secs" bash -c "$cmd" 2>&1)
    test_rc=$?
    # timeout returns 124 when command times out
    if [[ $test_rc -eq 124 ]]; then
      probe_add_warning "$PROBE_ERR_TIMEOUT" \
        "Test command '$cmd' timed out after ${timeout_secs}s (may still be valid)" \
        "$location"
      cd "$original_dir"
      return 0  # Timeout is a warning, not an error
    fi
  else
    # No timeout command available, run directly with shorter approach
    test_output=$(bash -c "$cmd" 2>&1 &
      local pid=$!
      sleep "$timeout_secs" && kill -9 $pid 2>/dev/null &
      wait $pid 2>/dev/null)
    test_rc=$?
  fi
  set -e

  cd "$original_dir"

  # Analyze exit code
  if [[ $test_rc -eq 127 ]]; then
    probe_add_error "$PROBE_ERR_COMMAND_NOT_FOUND" \
      "Test command not found: $cmd" \
      "$location"
    return 1
  fi

  # Analyze output for common errors
  if [[ "$test_output" == *"command not found"* ]]; then
    probe_add_error "$PROBE_ERR_COMMAND_NOT_FOUND" \
      "Test command not found: $cmd" \
      "$location"
    return 1
  fi

  if [[ "$test_output" == *"not found"* && "$test_output" == *"error"* ]]; then
    probe_add_error "$PROBE_ERR_COMMAND_NOT_FOUND" \
      "Test command dependency not found: $cmd (${test_output:0:200})" \
      "$location"
    return 1
  fi

  # Check for ReferenceError (common vitest-in-bun-native issue)
  if [[ "$test_output" == *"ReferenceError"* && "$test_output" == *"is not defined"* ]]; then
    probe_add_error "$PROBE_ERR_ENV_ERROR" \
      "Test command has environment error: ReferenceError detected. Check if you meant 'bun run test' instead of 'bun test'. Output: ${test_output:0:300}" \
      "$location"
    return 1
  fi

  # Check for other common environment issues
  if [[ "$test_output" == *"Cannot find module"* ]]; then
    probe_add_error "$PROBE_ERR_ENV_ERROR" \
      "Test command missing module: $cmd (${test_output:0:200})" \
      "$location"
    return 1
  fi

  # Exit 0 = tests pass (great)
  # Exit 1 = tests fail (but command works, that's fine for validation)
  if [[ $test_rc -le 1 ]]; then
    return 0
  fi

  # Exit 2+ could be various issues
  probe_add_warning "$PROBE_ERR_ENV_ERROR" \
    "Test command exited with code $test_rc: $cmd (${test_output:0:200})" \
    "$location"
  return 0  # Treat as warning, not error
}

# Probe a runner to verify it works
# Usage: probe_runner <runner_name> <runner_json> <location>
probe_runner() {
  local runner_name="$1"
  local runner_json="$2"
  local location="$3"

  local runner_cmd
  runner_cmd=$(echo "$runner_json" | jq -r '.command[0] // ""')

  if [[ -z "$runner_cmd" || "$runner_cmd" == "null" ]]; then
    probe_add_error "$PROBE_ERR_RUNNER_FAILED" \
      "Runner '$runner_name' has no command specified" \
      "$location.command"
    return 1
  fi

  # Profile checks (command existence, CLI compatibility, auth preflight)
  if ! probe_runner_profile "$runner_name" "$runner_json" "$location"; then
    return 1
  fi

  # Lightweight sanity check that command responds to version/help (warning only).
  set +e
  if "$runner_cmd" --version &>/dev/null; then
    set -e
    return 0
  fi
  if "$runner_cmd" --help &>/dev/null; then
    set -e
    return 0
  fi
  set -e

  probe_add_warning "$PROBE_ERR_RUNNER_FAILED" \
    "Runner '$runner_name' command '$runner_cmd' does not respond to --version/--help; continuing" \
    "$location.command"
  return 0
}

collect_smoke_runner_names() {
  local config_path="$1"
  local loop_id="${2:-}"

  if [[ -z "$loop_id" ]]; then
    jq -r '.runners | keys[]?' "$config_path" 2>/dev/null
    return 0
  fi

  local scoped_names
  scoped_names=$(jq -r --arg loop_id "$loop_id" '
    . as $cfg
    | (.loops[]? | select(.id == $loop_id)) as $loop
    | if ($loop.roles | type) == "object" then
        [ "planner", "implementer", "tester", "reviewer" ]
        | map(select($loop.roles[.] != null))
        | map($loop.roles[.].runner // $cfg.role_defaults[.].runner // empty)
        | .[]
      elif ($loop.roles | type) == "array" then
        ($loop.roles[]? | select(type == "string") | ($cfg.role_defaults[.].runner // empty))
      else
        [ "planner", "implementer", "tester", "reviewer" ]
        | map($cfg.role_defaults[.].runner // empty)
        | .[]
      end
    | select(length > 0)
  ' "$config_path" 2>/dev/null || true)

  if [[ -n "$scoped_names" ]]; then
    printf '%s\n' "$scoped_names" | sort -u
    return 0
  fi

  jq -r '.runners | keys[]?' "$config_path" 2>/dev/null
}

validate_runner_smoke() {
  local repo="$1"
  local config_path="$2"
  local loop_id="${3:-}"

  # Reserved for future repo-local checks.
  : "$repo"

  probe_reset_results

  if [[ ! -f "$config_path" ]]; then
    echo "error: config not found: $config_path" >&2
    return 1
  fi

  echo "Probing runner profiles..." >&2

  local runner_names
  runner_names=$(collect_smoke_runner_names "$config_path" "$loop_id")

  if [[ -z "$runner_names" ]]; then
    probe_add_error "$PROBE_ERR_RUNNER_FAILED" \
      "No runners found for smoke validation" \
      "runners"
    output_probe_validation_results
    return 1
  fi

  while IFS= read -r runner_name; do
    if [[ -z "$runner_name" ]]; then
      continue
    fi
    local runner_json
    runner_json=$(jq -c --arg name "$runner_name" '.runners[$name] // empty' "$config_path")
    if [[ -z "$runner_json" || "$runner_json" == "null" ]]; then
      probe_add_error "$PROBE_ERR_RUNNER_FAILED" \
        "Runner '$runner_name' is referenced but not defined in runners" \
        "runners.$runner_name"
      continue
    fi

    echo "  Probing runner: $runner_name" >&2
    probe_runner_profile "$runner_name" "$runner_json" "runners.$runner_name"
  done <<< "$(printf '%s\n' "$runner_names" | sort -u)"

  output_probe_validation_results
}

# Main probe validation function
# Usage: validate_probe <repo> <config_path>
# Returns: 0 if valid, 1 if errors found
validate_probe() {
  local repo="$1"
  local config_path="$2"

  # Reset globals
  probe_reset_results

  if [[ ! -f "$config_path" ]]; then
    echo "error: config not found: $config_path" >&2
    return 1
  fi

  local config_json
  config_json=$(cat "$config_path")

  echo "Probing runners..." >&2

  # Probe runners
  local runner_names
  runner_names=$(echo "$config_json" | jq -r '.runners | keys[]' 2>/dev/null)
  while IFS= read -r runner_name; do
    if [[ -n "$runner_name" ]]; then
      local runner_json
      runner_json=$(echo "$config_json" | jq -c ".runners[\"$runner_name\"] // {}")
      echo "  Probing runner: $runner_name" >&2
      probe_runner "$runner_name" "$runner_json" "runners.$runner_name"
    fi
  done <<< "$runner_names"

  echo "Probing test commands..." >&2

  # Probe test commands for each loop
  local loop_count
  loop_count=$(echo "$config_json" | jq '.loops | length' 2>/dev/null || echo 0)

  for ((i = 0; i < loop_count; i++)); do
    local loop_json
    loop_json=$(echo "$config_json" | jq -c ".loops[$i]")
    local loop_id
    loop_id=$(echo "$loop_json" | jq -r '.id // "unknown"')

    # Probe test commands
    local test_commands
    test_commands=$(echo "$loop_json" | jq -r '.tests.commands[]? // empty' 2>/dev/null)
    local cmd_idx=0
    while IFS= read -r cmd; do
      if [[ -n "$cmd" ]]; then
        echo "  Probing test command ($loop_id): $cmd" >&2
        probe_test_command "$repo" "$cmd" "loops[$i].tests.commands[$cmd_idx]" 30
        ((cmd_idx++))
      fi
    done <<< "$test_commands"

    # Probe validation commands
    local validation_commands
    validation_commands=$(echo "$loop_json" | jq -r '.validation.commands[]? // empty' 2>/dev/null)
    cmd_idx=0
    while IFS= read -r cmd; do
      if [[ -n "$cmd" ]]; then
        echo "  Probing validation command ($loop_id): $cmd" >&2
        probe_test_command "$repo" "$cmd" "loops[$i].validation.commands[$cmd_idx]" 60
        ((cmd_idx++))
      fi
    done <<< "$validation_commands"
  done

  # Output results
  output_probe_validation_results
}

# Output probe validation results
output_probe_validation_results() {
  local results_json="[]"

  if [[ -n "$PROBE_RESULTS" ]]; then
    results_json=$(echo "$PROBE_RESULTS" | jq -s '.')
  fi

  local valid="true"
  if [[ $PROBE_ERROR_COUNT -gt 0 ]]; then
    valid="false"
  fi

  jq -n \
    --argjson valid "$valid" \
    --argjson results "$results_json" \
    --argjson error_count "$PROBE_ERROR_COUNT" \
    --argjson warning_count "$PROBE_WARNING_COUNT" \
    '{
      valid: $valid,
      error_count: $error_count,
      warning_count: $warning_count,
      probes: $results
    }'

  # Print human-readable summary to stderr
  if [[ $PROBE_ERROR_COUNT -gt 0 || $PROBE_WARNING_COUNT -gt 0 ]]; then
    echo "" >&2
    echo "Probe Validation Results:" >&2
    echo "=========================" >&2

    while IFS= read -r result; do
      if [[ -n "$result" ]]; then
        local severity msg loc
        severity=$(echo "$result" | jq -r '.severity')
        msg=$(echo "$result" | jq -r '.message')
        loc=$(echo "$result" | jq -r '.location')
        if [[ "$severity" == "error" ]]; then
          echo "  ✗ [$loc] $msg" >&2
        else
          echo "  ⚠ [$loc] $msg" >&2
        fi
      fi
    done <<< "$PROBE_RESULTS"

    echo "" >&2
  fi

  if [[ $PROBE_ERROR_COUNT -gt 0 ]]; then
    return 1
  fi
  return 0
}
