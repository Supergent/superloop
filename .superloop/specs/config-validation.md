# Config Validation System

## Problem Statement

Superloop can waste many iterations on configuration errors that could be caught before the loop starts. Real example from pinpoint-v1:

```
Config: "commands": ["bun test"]
Expected: Runs vitest via package.json script
Actual: Runs Bun's native test runner (no vitest)
Result: 4+ iterations with "window is not defined" errors
```

This wasn't a dependency issue - it was a config typo. The Infrastructure Recovery system can't help because the command *runs* successfully, it just runs the wrong thing.

## Goals

1. Catch config errors before the loop starts (fail fast)
2. Validate test/validation commands actually work
3. Warn about common misconfigurations
4. Zero false positives - don't block valid configs

## Non-Goals

- Runtime config validation (that's Phase 3 of Infrastructure Recovery)
- Validating spec file content (separate concern)
- Enforcing coding standards

---

## Validation Layers

### Layer 1: Schema Validation (Existing)

Already implemented via `superloop.sh validate`. Checks:
- Required fields present
- Types correct
- Runner references valid

**Gap**: Doesn't validate that commands actually work.

### Layer 2: Static Analysis (New)

Analyze config without executing anything:

```bash
superloop.sh validate --static
```

**Checks:**

| Check | Example | Severity |
|-------|---------|----------|
| Test command exists in package.json | `bun run test` but no `test` script | Error |
| Command spelling | `bun tset` | Error |
| Runner command exists | `codex` not in PATH | Error |
| Timeout sanity | `timeout: 5` (5ms, probably meant 5000) | Warning |
| Duplicate loop IDs | Two loops named "main" | Error |
| Spec file exists | `.superloop/specs/foo.md` missing | Error |
| Evidence paths exist | `artifacts: ["dist/"]` but no dist/ | Warning |

### Layer 3: Probe Validation (New)

Actually run commands in safe mode to verify they work:

```bash
superloop.sh validate --probe
```

**Probes:**

| Probe | What It Does | Pass Criteria |
|-------|--------------|---------------|
| Test command probe | Run test command with `--help` or dry-run flag | Exit 0 or recognizable output |
| Test command execution | Run actual test command | Exit 0, or exit 1 with test output (not "command not found") |
| Runner probe | Run runner with `--version` | Exit 0 |
| Validation command probe | Run validation commands | Exit 0 or expected output |

---

## Specification

### 1. Static Analysis Checks

#### 1.1 Package.json Script Validation

For commands like `bun run X`, `npm run X`, `yarn X`, `pnpm X`:

```bash
# Extract script name from command
command="bun run test"
script_name="test"  # extracted

# Check package.json
if ! jq -e ".scripts[\"$script_name\"]" package.json >/dev/null 2>&1; then
  error "Test command 'bun run test' references script 'test' which doesn't exist in package.json"
fi
```

#### 1.2 Common Typo Detection

Known typo patterns:

| Typo | Correction |
|------|------------|
| `bun test` (when vitest configured) | `bun run test` |
| `npm test` (no test script) | `npm run test` |
| `pytest` (not installed) | `pip install pytest` or `poetry run pytest` |
| `vitest` (not globally installed) | `bun run test` or `npx vitest` |

Detection heuristic for `bun test` vs `bun run test`:

```bash
# If command is "bun test" (not "bun run test")
# AND package.json has a "test" script that runs vitest
# THEN warn

if [[ "$command" == "bun test" ]]; then
  test_script=$(jq -r '.scripts.test // ""' package.json)
  if [[ "$test_script" == *"vitest"* ]]; then
    warn "Command 'bun test' runs Bun's native runner, not vitest. Did you mean 'bun run test'?"
  fi
fi
```

#### 1.3 Runner Availability

```bash
# For each runner in config
runner_command=$(echo "$runner_json" | jq -r '.command[0]')
if ! command -v "$runner_command" &>/dev/null; then
  error "Runner '$runner_name' uses command '$runner_command' which is not in PATH"
fi
```

#### 1.4 Timeout Sanity

```bash
# Timeouts less than 1000ms are probably mistakes (meant seconds, not ms)
if [[ "$timeout" -gt 0 && "$timeout" -lt 1000 ]]; then
  warn "Timeout $timeout looks like seconds but config expects milliseconds. Did you mean ${timeout}000?"
fi

# Timeouts over 24 hours are suspicious
if [[ "$timeout" -gt 86400000 ]]; then
  warn "Timeout $timeout ms is over 24 hours. Is this intentional?"
fi
```

### 2. Probe Validation

#### 2.1 Test Command Probe

```bash
probe_test_command() {
  local repo="$1"
  local command="$2"

  cd "$repo"

  # Strategy 1: Try --help flag
  local help_output
  if help_output=$($command --help 2>&1); then
    # Command exists and responds to --help
    return 0
  fi

  # Strategy 2: Run the actual command with timeout
  local test_output
  local test_rc
  set +e
  test_output=$(timeout 60 bash -c "$command" 2>&1)
  test_rc=$?
  set -e

  # Analyze output
  if [[ $test_rc -eq 127 ]]; then
    error "Test command not found: $command"
    return 1
  fi

  if [[ "$test_output" == *"command not found"* ]]; then
    error "Test command not found: $command"
    return 1
  fi

  if [[ "$test_output" == *"is not defined"* && "$test_output" == *"ReferenceError"* ]]; then
    # This is the vitest-in-bun-native-runner error
    warn "Test command may be misconfigured. Got ReferenceError - check if you meant 'bun run test' instead of 'bun test'"
    return 1
  fi

  # Exit 0 = tests pass (great)
  # Exit 1 = tests fail (but command works, that's fine for validation)
  # Exit 2+ = something else wrong
  if [[ $test_rc -le 1 ]]; then
    return 0
  fi

  warn "Test command exited with code $test_rc. Output: ${test_output:0:500}"
  return 1
}
```

#### 2.2 Runner Probe

```bash
probe_runner() {
  local runner_name="$1"
  local runner_json="$2"

  local command
  command=$(echo "$runner_json" | jq -r '.command | join(" ")')

  # Try --version
  if $command --version &>/dev/null; then
    return 0
  fi

  # Try --help
  if $command --help &>/dev/null; then
    return 0
  fi

  error "Runner '$runner_name' command '$command' doesn't respond to --version or --help"
  return 1
}
```

### 3. Validation Output Format

```json
{
  "valid": false,
  "errors": [
    {
      "code": "SCRIPT_NOT_FOUND",
      "message": "Test command 'bun run test' references script 'test' which doesn't exist in package.json",
      "location": "loops[0].tests.commands[0]",
      "severity": "error"
    }
  ],
  "warnings": [
    {
      "code": "POSSIBLE_TYPO",
      "message": "Command 'bun test' runs Bun's native runner, not vitest. Did you mean 'bun run test'?",
      "location": "loops[0].tests.commands[0]",
      "severity": "warning"
    }
  ],
  "probes": {
    "test_commands": {"status": "failed", "message": "ReferenceError: window is not defined"},
    "runners": {"status": "ok"}
  }
}
```

### 4. CLI Integration

```bash
# Schema only (fast, existing)
superloop.sh validate

# Schema + static analysis (fast, new)
superloop.sh validate --static

# Schema + static + probes (slower, new)
superloop.sh validate --probe

# Auto-run before loop starts (new flag)
superloop.sh run --validate
```

### 5. Pre-Run Validation

Add to `run_cmd()` in `src/60-commands.sh`:

```bash
if [[ "${validate_before_run:-1}" -eq 1 ]]; then
  echo "Validating config before starting loop..."
  if ! validate_config "$config_path" "$repo" --static; then
    die "Config validation failed. Fix errors above or use --skip-validate to bypass."
  fi
fi
```

---

## Implementation Phases

### Phase 1: Static Analysis (MVP)

1. [ ] Add `validate_static()` function to `src/60-commands.sh`
2. [ ] Implement package.json script check
3. [ ] Implement common typo detection (bun test vs bun run test)
4. [ ] Implement runner availability check
5. [ ] Add `--static` flag to validate command
6. [ ] Output JSON validation report

**Acceptance Criteria:**
- AC-1: `superloop.sh validate --static` catches missing scripts
- AC-2: Warns about `bun test` when vitest is configured
- AC-3: Errors on missing runner commands
- AC-4: JSON output for programmatic use

### Phase 2: Probe Validation

1. [ ] Add `probe_test_command()` function
2. [ ] Add `probe_runner()` function
3. [ ] Implement output analysis (detect ReferenceError, command not found)
4. [ ] Add `--probe` flag to validate command
5. [ ] Add timeout for probes (60s default)

**Acceptance Criteria:**
- AC-5: `superloop.sh validate --probe` runs test commands
- AC-6: Detects "command not found" errors
- AC-7: Detects environment errors (window not defined)
- AC-8: Doesn't fail on test assertion failures (exit 1 is ok)

### Phase 3: Pre-Run Integration

1. [ ] Add `--validate` flag to run command
2. [ ] Add `--skip-validate` flag to bypass
3. [ ] Run static validation by default before loop starts
4. [ ] Add config option `validation.pre_run: true|false`

**Acceptance Criteria:**
- AC-9: `superloop.sh run` validates config by default
- AC-10: Validation errors prevent loop from starting
- AC-11: `--skip-validate` bypasses pre-run checks
- AC-12: Probe validation opt-in via `--validate=probe`

---

## Common Misconfigurations Catalog

| Config | Problem | Detection | Suggestion |
|--------|---------|-----------|------------|
| `bun test` | Runs Bun native, not vitest | Script contains "vitest" | Use `bun run test` |
| `npm test` | No test script | Script missing | Add script or use `npx` |
| `vitest` | Not installed globally | Command not found | Use `bun run test` |
| `pytest` | Not in venv | Command not found | Use `poetry run pytest` |
| `jest` | Not installed globally | Command not found | Use `npm run test` |
| `go test` | Wrong directory | No go.mod | Add `./...` or cd |
| `cargo test` | Wrong directory | No Cargo.toml | Check working_dir |

---

## Error Codes

| Code | Meaning |
|------|---------|
| `SCRIPT_NOT_FOUND` | package.json script doesn't exist |
| `COMMAND_NOT_FOUND` | Binary not in PATH |
| `RUNNER_NOT_FOUND` | Runner command not available |
| `SPEC_NOT_FOUND` | Spec file doesn't exist |
| `POSSIBLE_TYPO` | Command looks like common mistake |
| `TIMEOUT_SUSPICIOUS` | Timeout value looks wrong |
| `DUPLICATE_LOOP_ID` | Multiple loops with same ID |
| `PROBE_FAILED` | Command probe returned error |
| `ENV_ERROR` | Runtime environment issue (window not defined) |

---

*Spec version: 1.0*
*Author: Claude + Human*
*Date: 2026-01-24*
