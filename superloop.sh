#!/usr/bin/env bash
set -euo pipefail
# Generated from src/*.sh by scripts/build.sh. Edit source files, not this output.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION="0.3.0"

usage() {
  cat <<'USAGE'
Supergent Runner Wrapper

Usage:
  superloop.sh init [--repo DIR] [--force]
  superloop.sh list [--repo DIR] [--config FILE]
  superloop.sh run [--repo DIR] [--config FILE] [--loop ID] [--fast] [--dry-run]
  superloop.sh status [--repo DIR] [--summary] [--loop ID]
  superloop.sh approve --loop ID [--repo DIR] [--by NAME] [--note TEXT] [--reject]
  superloop.sh cancel [--repo DIR]
  superloop.sh validate [--repo DIR] [--config FILE] [--schema FILE]
  superloop.sh report [--repo DIR] [--config FILE] [--loop ID] [--out FILE]
  superloop.sh --version

Options:
  --repo DIR       Repository root (default: current directory)
  --config FILE    Config file path (default: .superloop/config.json)
  --schema FILE    Schema file path (default: schema/config.schema.json)
  --loop ID        Run only the loop with this id (or select loop for status/report)
  --summary        Print latest gate/evidence snapshot from run-summary.json
  --force          Overwrite existing .superloop files on init
  --fast           Use runner.fast_args (if set) instead of runner.args
  --dry-run        Read-only status summary from existing artifacts; no runner calls
  --out FILE       Report output path (default: .superloop/loops/<id>/report.html)
  --by NAME        Approver name for approval decisions (default: $USER)
  --note TEXT      Optional decision note for approval/rejection
  --reject         Record a rejection instead of approval
  --version        Print version and exit

Notes:
- This wrapper runs the configured runner in a multi-role loop (planner, implementer, tester, reviewer).
- The loop stops only when the reviewer outputs a matching promise AND gates pass.
- Gates: checklists, tests, validation, evidence, and optional approval (per config).
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

print_version() {
  echo "$VERSION"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_exec() {
  local cmd="$1"

  if [[ -z "$cmd" ]]; then
    die "missing runner command"
  fi
  if [[ "$cmd" == */* ]]; then
    if [[ ! -x "$cmd" ]]; then
      die "command not executable: $cmd"
    fi
    return 0
  fi
  need_cmd "$cmd"
}

timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

DEFAULT_STUCK_IGNORE=(
  ".superloop/**"
  ".git/**"
  "node_modules/**"
  "dist/**"
  "build/**"
  "coverage/**"
  ".next/**"
  ".venv/**"
  ".tox/**"
  ".cache/**"
)

hash_file() {
  local file="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $2}'
    return 0
  fi

  return 1
}

hash_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $2}'
    return 0
  fi

  return 1
}

json_or_default() {
  local raw="$1"
  local fallback="$2"

  if [[ -z "$raw" ]]; then
    echo "$fallback"
    return 0
  fi

  if jq -e -s 'length == 1' >/dev/null 2>&1 <<<"$raw"; then
    echo "$raw"
    return 0
  fi

  echo "$fallback"
}

file_mtime() {
  local file="$1"
  if [[ ! -e "$file" ]]; then
    return 1
  fi

  local mtime=""
  mtime=$(stat -f %m "$file" 2>/dev/null || true)
  if [[ "$mtime" =~ ^[0-9]+$ ]]; then
    echo "$mtime"
    return 0
  fi

  mtime=$(stat -c %Y "$file" 2>/dev/null || true)
  if [[ "$mtime" =~ ^[0-9]+$ ]]; then
    echo "$mtime"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import os
import sys

path = sys.argv[1]
try:
    print(int(os.path.getmtime(path)))
except Exception:
    sys.exit(1)
PY
    return $?
  fi
  if command -v python >/dev/null 2>&1; then
    python - "$file" <<'PY'
import os
import sys

path = sys.argv[1]
try:
    print(int(os.path.getmtime(path)))
except Exception:
    sys.exit(1)
PY
    return $?
  fi

  return 1
}

file_meta_json() {
  local display_path="$1"
  local full_path="$2"
  local gate="${3:-}"

  local exists_json="false"
  local sha_json="null"
  local mtime_json="null"

  if [[ -f "$full_path" ]]; then
    exists_json="true"
    local hash
    hash=$(hash_file "$full_path" 2>/dev/null || true)
    if [[ -n "$hash" ]]; then
      sha_json="\"$hash\""
    fi
    local mtime
    mtime=$(file_mtime "$full_path" 2>/dev/null || true)
    if [[ -n "$mtime" ]]; then
      mtime_json="$mtime"
    fi
  fi

  jq -n \
    --arg path "$display_path" \
    --argjson exists "$exists_json" \
    --argjson sha "$sha_json" \
    --argjson mtime "$mtime_json" \
    --arg gate "$gate" \
    '{path: $path, exists: $exists, sha256: $sha, mtime: $mtime, gate: (if ($gate | length) > 0 then $gate else null end)}' \
    | jq 'with_entries(select(.value != null))'
}

should_ignore() {
  local path="$1"
  shift

  local pattern
  for pattern in "$@"; do
    if [[ -z "$pattern" ]]; then
      continue
    fi
    if [[ "$path" == $pattern ]]; then
      return 0
    fi
  done

  return 1
}

write_state() {
  local state_file="$1"
  local loop_index="$2"
  local iteration="$3"
  local loop_id="$4"
  local active="$5"

  jq -n \
    --argjson loop_index "$loop_index" \
    --argjson iteration "$iteration" \
    --arg loop_id "$loop_id" \
    --arg updated_at "$(timestamp)" \
    --argjson active "$active" \
    '{active: $active, loop_index: $loop_index, iteration: $iteration, current_loop_id: $loop_id, updated_at: $updated_at}' \
    > "$state_file"
}

expand_pattern() {
  local repo="$1"
  local pattern="$2"

  if [[ "$pattern" == *"*"* || "$pattern" == *"?"* || "$pattern" == *"["* ]]; then
    (shopt -s nullglob globstar; for f in "$repo"/$pattern; do printf '%s\n' "${f#$repo/}"; done)
  else
    printf '%s\n' "$pattern"
  fi
}

compute_signature() {
  local repo="$1"
  shift
  local ignore_patterns=("$@")

  local -a files=()

  if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    while IFS= read -r -d '' entry; do
      local status="${entry:0:2}"
      local path="${entry:3}"
      if [[ "$status" == *R* || "$status" == *C* ]]; then
        local newpath=""
        if IFS= read -r -d '' newpath; then
          path="$newpath"
        fi
      fi
      files+=("$path")
    done < <(git -C "$repo" status --porcelain=v1 -z)
  else
    while IFS= read -r -d '' file; do
      files+=("${file#$repo/}")
    done < <(find "$repo" -type f -print0)
  fi

  local -a entries=()
  local file
  for file in "${files[@]:-}"; do
    if [[ -z "$file" ]]; then
      continue
    fi
    if should_ignore "$file" "${ignore_patterns[@]}"; then
      continue
    fi
    local full="$repo/$file"
    if [[ -f "$full" ]]; then
      local hash
      hash=$(hash_file "$full" 2>/dev/null || true)
      if [[ -z "$hash" ]]; then
        hash="unhashed"
      fi
      entries+=("$file:$hash")
    else
      entries+=("$file:missing")
    fi
  done

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "empty"
    return 0
  fi

  printf '%s\n' "${entries[@]}" | LC_ALL=C sort | hash_stdin
}

update_stuck_state() {
  local repo="$1"
  local loop_dir="$2"
  local threshold="$3"
  shift 3
  local ignore_patterns=("$@")

  local state_file="$loop_dir/stuck.json"
  local report_file="$loop_dir/stuck-report.md"

  local signature
  signature=$(compute_signature "$repo" "${ignore_patterns[@]}") || return 1

  local prev_signature=""
  local prev_streak=0
  if [[ -f "$state_file" ]]; then
    prev_signature=$(jq -r '.signature // ""' "$state_file")
    prev_streak=$(jq -r '.streak // 0' "$state_file")
  fi

  local streak=1
  if [[ "$signature" == "$prev_signature" ]]; then
    streak=$((prev_streak + 1))
  fi

  jq -n \
    --arg signature "$signature" \
    --argjson streak "$streak" \
    --argjson threshold "$threshold" \
    --arg updated_at "$(timestamp)" \
    '{signature: $signature, streak: $streak, threshold: $threshold, updated_at: $updated_at}' \
    > "$state_file"

  if [[ "$streak" -ge "$threshold" ]]; then
    {
      echo "# Stuck Report"
      echo ""
      echo "No meaningful progress detected for $streak consecutive iterations."
      echo ""
      echo "Signature: $signature"
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
          unchecked_count=$(grep -c '\[ \]' "$phase_file" 2>/dev/null || echo "0")
        fi
        local checked_count=0
        if [[ -f "$phase_file" ]]; then
          checked_count=$(grep -c '\[x\]' "$phase_file" 2>/dev/null || echo "0")
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

      cat <<'AGENT_BROWSER_SKILL' >> "$prompt_file"

## Exploration Configuration

Browser exploration is ENABLED. Use agent-browser to verify the implementation.

### agent-browser Quick Reference

**Core workflow:**
1. Navigate: `agent-browser open <url>`
2. Snapshot: `agent-browser snapshot -i` (returns elements with refs like `@e1`, `@e2`)
3. Interact using refs from the snapshot
4. Re-snapshot after navigation or significant DOM changes

**Navigation:**
```
agent-browser open <url>      # Navigate to URL
agent-browser back            # Go back
agent-browser forward         # Go forward
agent-browser reload          # Reload page
agent-browser close           # Close browser
```

**Snapshot (page analysis):**
```
agent-browser snapshot        # Full accessibility tree
agent-browser snapshot -i     # Interactive elements only (recommended)
agent-browser snapshot -c     # Compact output
agent-browser snapshot -d 3   # Limit depth to 3
```

**Interactions (use @refs from snapshot):**
```
agent-browser click @e1           # Click
agent-browser dblclick @e1        # Double-click
agent-browser fill @e2 "text"     # Clear and type
agent-browser type @e2 "text"     # Type without clearing
agent-browser press Enter         # Press key
agent-browser press Control+a     # Key combination
agent-browser hover @e1           # Hover
agent-browser check @e1           # Check checkbox
agent-browser uncheck @e1         # Uncheck checkbox
agent-browser select @e1 "value"  # Select dropdown
agent-browser scroll down 500     # Scroll page
agent-browser scrollintoview @e1  # Scroll element into view
```

**Get information:**
```
agent-browser get text @e1        # Get element text
agent-browser get value @e1       # Get input value
agent-browser get title           # Get page title
agent-browser get url             # Get current URL
```

**Screenshots:**
```
agent-browser screenshot          # Screenshot to stdout
agent-browser screenshot path.png # Save to file
agent-browser screenshot --full   # Full page
```

**Wait:**
```
agent-browser wait @e1                     # Wait for element
agent-browser wait 2000                    # Wait milliseconds
agent-browser wait --text "Success"        # Wait for text
agent-browser wait --load networkidle      # Wait for network idle
```

**Semantic locators (alternative to refs):**
```
agent-browser find role button click --name "Submit"
agent-browser find text "Sign In" click
agent-browser find label "Email" fill "user@test.com"
```

**Example exploration flow:**
```
agent-browser open https://example.com/app
agent-browser snapshot -i
# Output shows: textbox "Email" [ref=e1], button "Submit" [ref=e2]

agent-browser fill @e1 "test@example.com"
agent-browser click @e2
agent-browser wait --load networkidle
agent-browser snapshot -i  # Check result
agent-browser screenshot exploration-result.png
```

AGENT_BROWSER_SKILL

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

run_command_with_timeout() {
  local prompt_file="$1"
  local log_file="$2"
  local timeout_seconds="$3"
  local prompt_mode="$4"
  local inactivity_seconds="${5:-0}"
  shift 5 2>/dev/null || shift 4
  local -a cmd=("$@")

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    echo "warning: python not found; running without timeout enforcement" >&2
    set +e
    if [[ "$prompt_mode" == "stdin" ]]; then
      "${cmd[@]}" < "$prompt_file" | tee "$log_file"
    else
      "${cmd[@]}" | tee "$log_file"
    fi
    local status=${PIPESTATUS[0]}
    set -e
    return "$status"
  fi

  RUNNER_PROMPT_FILE="$prompt_file" \
  RUNNER_LOG_FILE="$log_file" \
  RUNNER_TIMEOUT_SECONDS="$timeout_seconds" \
  RUNNER_INACTIVITY_SECONDS="$inactivity_seconds" \
  RUNNER_PROMPT_MODE="$prompt_mode" \
  RUNNER_RATE_LIMIT_FILE="${RUNNER_RATE_LIMIT_FILE:-}" \
  "$python_bin" - "${cmd[@]}" <<'PY'
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
from collections import deque
from datetime import timezone
from email.utils import parsedate_to_datetime

RESET_KEYS = (
    "resets_at",
    "reset_at",
    "resets_in",
    "resets_in_seconds",
    "retry_after",
    "retry_after_seconds",
    "retry_after_ms",
)


def coerce_int(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.isdigit():
            return int(stripped)
    return None


def extract_json_from_line(line):
    stripped = line.strip()
    if not stripped:
        return None
    if stripped.startswith("{") and stripped.endswith("}"):
        try:
            return json.loads(stripped)
        except Exception:
            return None
    start = stripped.find("{")
    end = stripped.rfind("}")
    if start != -1 and end > start:
        snippet = stripped[start : end + 1]
        try:
            return json.loads(snippet)
        except Exception:
            return None
    return None


def extract_error_details(obj):
    if not isinstance(obj, dict):
        return {}
    err = None
    if isinstance(obj.get("error"), dict):
        err = obj["error"]
    elif isinstance(obj.get("errors"), list):
        for item in obj["errors"]:
            if isinstance(item, dict):
                err = item
                break
    if err is None:
        err = obj
    detail = {}
    for key in ("type", "code", "status", "message", "param", "request_id", "requestId"):
        if key in err:
            detail[key] = err[key]
    return detail


def collect_reset_fields(obj, out):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in RESET_KEYS and key not in out and value is not None:
                out[key] = value
            if isinstance(value, (dict, list)):
                collect_reset_fields(value, out)
    elif isinstance(obj, list):
        for item in obj:
            collect_reset_fields(item, out)


def apply_reset_fields(info, reset_fields):
    if "resets_at" not in info:
        for key in ("resets_at", "reset_at"):
            value = coerce_int(reset_fields.get(key))
            if value is not None:
                info["resets_at"] = value
                break
    if "resets_in" not in info:
        for key in ("resets_in", "resets_in_seconds", "retry_after_seconds", "retry_after"):
            value = coerce_int(reset_fields.get(key))
            if value is not None:
                info["resets_in"] = value
                break
    if "resets_in" not in info:
        value = coerce_int(reset_fields.get("retry_after_ms"))
        if value is not None:
            info["resets_in"] = int(round(value / 1000))


def extract_rate_limit_info_from_json(obj):
    info = {}
    if not isinstance(obj, dict):
        return info
    error_detail = extract_error_details(obj)
    if error_detail:
        info["error"] = error_detail
    reset_fields = {}
    collect_reset_fields(obj, reset_fields)
    if reset_fields:
        apply_reset_fields(info, reset_fields)
    return info


def is_rate_limit_json(obj):
    if not isinstance(obj, dict):
        return False
    error_detail = extract_error_details(obj)
    text = " ".join(str(value) for value in error_detail.values()).lower()
    if any(token in text for token in ("rate limit", "rate_limit", "usage limit", "usage_limit", "quota", "too many requests", "overloaded")):
        return True
    status = error_detail.get("status") or error_detail.get("code")
    try:
        if int(status) in (429, 529):  # 429 = rate limit, 529 = overloaded
            return True
    except (TypeError, ValueError):
        pass
    obj_type = obj.get("type")
    if isinstance(obj_type, str) and ("usage_limit" in obj_type or "rate_limit" in obj_type or "overloaded" in obj_type):
        return True
    return False


def parse_http_date(value):
    try:
        parsed = parsedate_to_datetime(value)
    except Exception:
        return None
    if not parsed:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def parse_rate_limit_headers(lines):
    headers = {}
    for line in lines:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if not key:
            continue
        lower = key.lower()
        if lower in ("retry-after", "x-request-id", "request-id") or lower.startswith("x-ratelimit-") or lower.startswith("ratelimit-"):
            headers[lower] = value.strip()
    return headers


def apply_header_resets(info, headers):
    retry_after = headers.get("retry-after")
    if retry_after:
        retry_seconds = coerce_int(retry_after)
        if retry_seconds is not None:
            info.setdefault("resets_in", retry_seconds)
        else:
            retry_at = parse_http_date(retry_after)
            if retry_at is not None:
                info.setdefault("resets_at", retry_at)
    reset_header = headers.get("x-ratelimit-reset") or headers.get("ratelimit-reset")
    if reset_header:
        reset_value = coerce_int(reset_header)
        if reset_value is not None:
            if reset_value >= 1_000_000_000_000:
                reset_value = int(reset_value / 1000)
            if reset_value >= 1_000_000_000:
                info.setdefault("resets_at", reset_value)
            else:
                info.setdefault("resets_in", reset_value)
        else:
            reset_at = parse_http_date(reset_header)
            if reset_at is not None:
                info.setdefault("resets_at", reset_at)


def finalize_rate_limit_info(info, trigger_line, recent_lines):
    final_info = dict(info or {})
    if trigger_line:
        final_info.setdefault("raw_line", trigger_line.rstrip("\n"))
    if recent_lines:
        context = [line.rstrip("\n") for line in recent_lines]
        if context:
            final_info.setdefault("raw_context", context)
        headers = parse_rate_limit_headers(context)
        if headers:
            final_info.setdefault("headers", headers)
            apply_header_resets(final_info, headers)
    return final_info


def detect_rate_limit(line):
    """Detect rate limit patterns in output. Returns (detected, info_dict)."""
    parsed_json = extract_json_from_line(line)
    parsed_info = extract_rate_limit_info_from_json(parsed_json) if parsed_json else {}
    if parsed_json and is_rate_limit_json(parsed_json):
        info = {"message": "Rate limit error detected", "type": "json"}
        info.update(parsed_info)
        error_type = ""
        if isinstance(info.get("error"), dict):
            error_type = str(info["error"].get("type", ""))
        if error_type == "usage_limit_reached":
            info["message"] = "Codex usage limit reached"
            info["type"] = "codex"
        return True, info

    # Pattern: Codex JSON error with usage_limit_reached
    if '"type"' in line and 'usage_limit_reached' in line:
        info = {"message": "Codex usage limit reached", "type": "codex"}
        info.update(parsed_info)
        # Try to extract resets_at
        match = re.search(r'"resets_at":\s*(\d+)', line)
        if match:
            info["resets_at"] = int(match.group(1))
        return True, info

    # Pattern: HTTP 429 or Too Many Requests
    if '429' in line or 'Too Many Requests' in line:
        info = {"message": "HTTP 429 Too Many Requests", "type": "http"}
        info.update(parsed_info)
        return True, info

    # Pattern: usage limit / rate limit errors
    lower = line.lower()
    if ('usage' in lower or 'rate' in lower) and 'limit' in lower:
        if any(word in lower for word in ['reached', 'exceeded', 'error', 'failed', 'hit']):
            info = {"message": "Rate limit error detected", "type": "generic"}
            info.update(parsed_info)
            # Try to extract reset time
            match = re.search(r'resets?_?(at|in)["\s:]+(\d+)', line, re.IGNORECASE)
            if match:
                info["resets_at" if match.group(1).lower() == "at" else "resets_in"] = int(match.group(2))
            return True, info

    return False, {}


def main():
    # Max total timeout (safety ceiling)
    timeout_raw = os.environ.get("RUNNER_TIMEOUT_SECONDS", "0") or "0"
    try:
        timeout_seconds = int(timeout_raw)
    except ValueError:
        timeout_seconds = 0

    # Inactivity timeout (kill if no output for this long)
    inactivity_raw = os.environ.get("RUNNER_INACTIVITY_SECONDS", "0") or "0"
    try:
        inactivity_seconds = int(inactivity_raw)
    except ValueError:
        inactivity_seconds = 0

    prompt_path = os.environ.get("RUNNER_PROMPT_FILE")
    log_path = os.environ.get("RUNNER_LOG_FILE")
    prompt_mode = os.environ.get("RUNNER_PROMPT_MODE", "stdin") or "stdin"
    rate_limit_file = os.environ.get("RUNNER_RATE_LIMIT_FILE", "")
    cmd = sys.argv[1:]
    if not log_path:
        sys.stderr.write("missing RUNNER_LOG_FILE\n")
        return 2
    if prompt_mode == "stdin" and not prompt_path:
        sys.stderr.write("missing RUNNER_PROMPT_FILE\n")
        return 2
    if not cmd:
        sys.stderr.write("missing command args\n")
        return 2
    if prompt_mode == "stdin":
        prompt_handle = open(prompt_path, "rb")
    else:
        prompt_handle = open(os.devnull, "rb")

    with prompt_handle as prompt, open(log_path, "w", buffering=1) as log:
        proc = subprocess.Popen(
            cmd,
            stdin=prompt,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        q = queue.Queue()

        def reader():
            try:
                for line in proc.stdout:
                    q.put(line)
            finally:
                q.put(None)

        thread = threading.Thread(target=reader, daemon=True)
        thread.start()

        # Calculate deadlines
        now = time.time()
        max_deadline = now + timeout_seconds if timeout_seconds > 0 else None
        activity_deadline = now + inactivity_seconds if inactivity_seconds > 0 else None

        timed_out = False
        timeout_reason = None
        rate_limited = False
        rate_limit_info = {}
        rate_limit_trigger_line = None
        rate_limit_deadline = None
        recent_lines = deque(maxlen=40)

        while True:
            current_time = time.time()

            # Check max timeout (safety ceiling)
            if max_deadline and current_time >= max_deadline and proc.poll() is None:
                timed_out = True
                timeout_reason = "max_timeout"
                sys.stderr.write(f"\n[superloop] Max timeout reached ({timeout_seconds}s). Terminating.\n")
                proc.terminate()
                break

            # Check inactivity timeout
            if activity_deadline and current_time >= activity_deadline and proc.poll() is None:
                timed_out = True
                timeout_reason = "inactivity"
                sys.stderr.write(f"\n[superloop] Inactivity timeout ({inactivity_seconds}s without output). Terminating.\n")
                proc.terminate()
                break

            try:
                line = q.get(timeout=0.1)
            except queue.Empty:
                if rate_limited and rate_limit_deadline and time.time() >= rate_limit_deadline:
                    break
                if proc.poll() is not None and q.empty():
                    break
                continue

            if line is None:
                break

            recent_lines.append(line)

            # Got output - reset inactivity deadline
            if inactivity_seconds > 0:
                activity_deadline = time.time() + inactivity_seconds

            # Check for rate limit patterns
            if not rate_limited:
                detected, info = detect_rate_limit(line)
                if detected:
                    rate_limited = True
                    rate_limit_info = info
                    rate_limit_trigger_line = line
                    rate_limit_deadline = time.time() + 1.0
                    sys.stderr.write(f"\n[superloop] Rate limit detected: {info.get('message', 'unknown')}\n")
                    # Terminate the process - we'll resume later
                    proc.terminate()
                    continue

            if rate_limited:
                continue

            sys.stdout.write(line)
            sys.stdout.flush()
            log.write(line)
            log.flush()

        if timed_out and proc.poll() is None:
            time.sleep(2)
            if proc.poll() is None:
                proc.kill()

        if rate_limited and proc.poll() is None:
            time.sleep(2)
            if proc.poll() is None:
                proc.kill()

        rc = proc.wait()
        if rate_limited:
            rate_limit_info = finalize_rate_limit_info(
                rate_limit_info, rate_limit_trigger_line, list(recent_lines)
            )
            if rate_limit_file:
                try:
                    with open(rate_limit_file, "w") as f:
                        json.dump(rate_limit_info, f)
                except Exception as e:
                    sys.stderr.write(f"[superloop] Failed to write rate limit info: {e}\n")

        if timed_out:
            return 124
        if rate_limited:
            return 125  # Special exit code for rate limit
        return rc


if __name__ == "__main__":
    sys.exit(main())
PY
  return $?
}

expand_runner_arg() {
  local arg="$1"
  local repo="$2"
  local prompt_file="$3"
  local last_message_file="$4"

  arg=${arg//\{repo\}/$repo}
  arg=${arg//\{prompt_file\}/$prompt_file}
  arg=${arg//\{last_message_file\}/$last_message_file}
  printf '%s' "$arg"
}

LAST_RATE_LIMIT_INFO=""

run_role() {
  local repo="$1"
  shift
  local role="$1"
  shift
  local prompt_file="$1"
  shift
  local last_message_file="$1"
  shift
  local log_file="$1"
  shift
  local timeout_seconds="${1:-0}"
  shift
  local prompt_mode="${1:-stdin}"
  shift
  local inactivity_seconds="${1:-0}"
  shift
  # Optional: usage tracking parameters
  local usage_file="${1:-}"
  shift || true
  local iteration="${1:-0}"
  shift || true
  local -a runner_command=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    runner_command+=("$1")
    shift
  done
  local -a runner_args=("$@")

  LAST_RATE_LIMIT_INFO=""

  mkdir -p "$(dirname "$last_message_file")" "$(dirname "$log_file")"

  if [[ ${#runner_command[@]} -eq 0 ]]; then
    die "runner.command is empty"
  fi

  local -a cmd=()
  local part
  for part in "${runner_command[@]}"; do
    cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
  done
  for part in "${runner_args[@]}"; do
    cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
  done

  # Detect runner type and prepare tracked command
  local runner_type="unknown"
  USAGE_SESSION_ID=""  # Reset global - will be set by prepare_tracked_command for Claude
  USAGE_THREAD_ID=""   # Reset global - will be extracted from output for Codex
  CURRENT_RUNNER_TYPE="unknown"

  if [[ "${USAGE_TRACKING_ENABLED:-1}" -eq 1 ]] && type detect_runner_type &>/dev/null; then
    runner_type=$(detect_runner_type "${cmd[@]}")
    CURRENT_RUNNER_TYPE="$runner_type"

    if [[ "$runner_type" == "claude" ]]; then
      # prepare_tracked_command generates USAGE_SESSION_ID and injects --session-id
      local -a tracked_cmd=()
      while IFS= read -r line; do
        tracked_cmd+=("$line")
      done < <(prepare_tracked_command "$runner_type" "${cmd[@]}")
      cmd=("${tracked_cmd[@]}")
      # USAGE_SESSION_ID is now set globally by prepare_tracked_command
    fi

    # Start usage tracking
    track_usage "start" "$usage_file" "$iteration" "$role" "$repo" "$runner_type"
  fi

  # Set up rate limit detection
  local rate_limit_file=""
  if type wait_for_rate_limit_reset &>/dev/null; then
    rate_limit_file=$(mktemp -t "superloop-rate-limit.XXXXXX" 2>/dev/null || echo "")
  fi

  local status=0
  local max_retries="${SUPERLOOP_RATE_LIMIT_MAX_RETRIES:-3}"
  local retry_count=0

  while true; do
    status=0
    if [[ "${timeout_seconds:-0}" -gt 0 || "${inactivity_seconds:-0}" -gt 0 ]]; then
      RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
        run_command_with_timeout "$prompt_file" "$log_file" "$timeout_seconds" "$prompt_mode" "$inactivity_seconds" "${cmd[@]}"
      status=$?
    else
      set +e
      if [[ "$prompt_mode" == "stdin" ]]; then
        RUNNER_RATE_LIMIT_FILE="$rate_limit_file" "${cmd[@]}" < "$prompt_file" | tee "$log_file"
      else
        RUNNER_RATE_LIMIT_FILE="$rate_limit_file" "${cmd[@]}" | tee "$log_file"
      fi
      status=${PIPESTATUS[0]}
      set -e
    fi

    # Handle rate limit (exit code 125)
    if [[ $status -eq 125 ]]; then
      retry_count=$((retry_count + 1))
      if [[ $retry_count -gt $max_retries ]]; then
        echo "[superloop] Rate limit: max retries ($max_retries) exceeded, aborting" >&2
        break
      fi

      echo "[superloop] Rate limit hit (attempt $retry_count/$max_retries), will wait and resume" >&2

      # Read rate limit info from file
      local resets_at=""
      if [[ -n "$rate_limit_file" && -f "$rate_limit_file" ]]; then
        resets_at=$(jq -r '.resets_at // empty' "$rate_limit_file" 2>/dev/null || true)
        local resets_in
        resets_in=$(jq -r '.resets_in // empty' "$rate_limit_file" 2>/dev/null || true)
        if [[ -z "$resets_at" && -n "$resets_in" ]]; then
          resets_at=$(($(date +%s) + resets_in))
        fi
      fi

      # Wait for rate limit to reset
      if type wait_for_rate_limit_reset &>/dev/null; then
        if ! wait_for_rate_limit_reset "$resets_at" "${SUPERLOOP_RATE_LIMIT_MAX_WAIT:-7200}"; then
          echo "[superloop] Rate limit: wait exceeded max time, aborting" >&2
          break
        fi
      else
        # Fallback: wait 5 minutes
        echo "[superloop] Waiting 5 minutes before retry..." >&2
        sleep 300
      fi

      # Build resume command based on runner type
      if [[ "$runner_type" == "claude" && -n "$USAGE_SESSION_ID" ]]; then
        # Resume Claude session using the actual session ID that was passed to Claude
        echo "[superloop] Resuming Claude session: $USAGE_SESSION_ID" >&2
        cmd=("claude" "--resume" "$USAGE_SESSION_ID" "-p" "continue from where you left off")
        prompt_mode="arg"  # Resume uses prompt as argument
      elif [[ "$runner_type" == "codex" ]]; then
        # For Codex, try multiple methods to get thread_id for resume
        if [[ -z "$USAGE_THREAD_ID" ]]; then
          # Method 1: Extract from log output
          if [[ -f "$log_file" ]]; then
            USAGE_THREAD_ID=$(grep -o '"thread_id":\s*"[^"]*"' "$log_file" | sed 's/"thread_id":\s*"//' | sed 's/"$//' | tail -1 || true)
          fi
          # Method 2: Extract from session filename (most reliable)
          if [[ -z "$USAGE_THREAD_ID" && -n "$USAGE_START_TIME" ]]; then
            local codex_start_ts=$((USAGE_START_TIME / 1000))
            find_and_set_codex_thread_id "$codex_start_ts" 2>/dev/null || true
          fi
        fi
        if [[ -n "$USAGE_THREAD_ID" ]]; then
          echo "[superloop] Resuming Codex thread: $USAGE_THREAD_ID" >&2
          cmd=("codex" "exec" "resume" "$USAGE_THREAD_ID" "continue from where you left off")
          prompt_mode="arg"  # Resume uses prompt as argument
        else
          echo "[superloop] No Codex thread_id found, retrying from scratch" >&2
          # Rebuild original command
          cmd=()
          for part in "${runner_command[@]}"; do
            cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
          done
          for part in "${runner_args[@]}"; do
            cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
          done
        fi
      else
        echo "[superloop] Retrying from scratch" >&2
        # Rebuild original command
        cmd=()
        for part in "${runner_command[@]}"; do
          cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
        done
        for part in "${runner_args[@]}"; do
          cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
        done
      fi

      # Clear rate limit file for next attempt
      if [[ -n "$rate_limit_file" && -f "$rate_limit_file" ]]; then
        : > "$rate_limit_file"
      fi

      continue  # Retry the loop
    fi

    break  # Success or other error, exit retry loop
  done

  if [[ $status -eq 125 ]]; then
    if [[ -n "$rate_limit_file" && -f "$rate_limit_file" ]]; then
      LAST_RATE_LIMIT_INFO=$(cat "$rate_limit_file")
    else
      LAST_RATE_LIMIT_INFO=""
    fi
  fi

  # Clean up rate limit file
  if [[ -n "$rate_limit_file" && -f "$rate_limit_file" ]]; then
    rm -f "$rate_limit_file"
  fi

  # End usage tracking
  if [[ "${USAGE_TRACKING_ENABLED:-1}" -eq 1 ]] && type track_usage &>/dev/null; then
    track_usage "end" "$usage_file" "$iteration" "$role" "$repo" "$runner_type" "$log_file"
  fi

  if [[ $status -eq 124 ]]; then
    return 124
  fi
  if [[ $status -eq 125 ]]; then
    return 125
  fi
  if [[ $status -ne 0 ]]; then
    die "runner command failed for role '$role' (exit $status)"
  fi
}

OPENPROSE_CONTEXT_MAX_CHARS=4000
OPENPROSE_AGENT_KEYS=()
OPENPROSE_AGENT_PROMPTS=()
OPENPROSE_CONTEXT_KEYS=()
OPENPROSE_CONTEXT_PATHS=()
OPENPROSE_SESSION_IDS=()
OPENPROSE_SESSION_NAMES=()
OPENPROSE_SESSION_LOGS=()
OPENPROSE_SESSION_LASTS=()
OPENPROSE_SESSION_INDEX=0
OPENPROSE_RUNNER_COMMAND=()
OPENPROSE_RUNNER_ARGS=()
OPENPROSE_REPO=""
OPENPROSE_PROMPT_DIR=""
OPENPROSE_LOG_DIR=""
OPENPROSE_LAST_MESSAGES_DIR=""
OPENPROSE_ROLE_LOG=""
OPENPROSE_IMPLEMENTER_REPORT=""
OPENPROSE_TIMEOUT=""
OPENPROSE_PROMPT_MODE=""
OPENPROSE_PROGRAM_FILE=""
OPENPROSE_AGENT_ACTIVE=0
OPENPROSE_AGENT_INDENT=-1
OPENPROSE_CURRENT_AGENT=""
OPENPROSE_SESSION_ACTIVE=0
OPENPROSE_SESSION_INDENT=-1
OPENPROSE_SESSION_IN_PARALLEL=0
OPENPROSE_SESSION_NAME=""
OPENPROSE_SESSION_AGENT=""
OPENPROSE_SESSION_PROMPT=""
OPENPROSE_SESSION_CONTEXT=""
OPENPROSE_PARALLEL_ACTIVE=0
OPENPROSE_PARALLEL_INDENT=-1
OPENPROSE_PARALLEL_IDS=()
OPENPROSE_PARALLEL_NAMES=()
OPENPROSE_PARALLEL_AGENTS=()
OPENPROSE_PARALLEL_PROMPTS=()
OPENPROSE_PARALLEL_CONTEXTS=()
OPENPROSE_PARALLEL_PROMPT_FILES=()
OPENPROSE_PARALLEL_LOG_FILES=()
OPENPROSE_PARALLEL_LAST_FILES=()

openprose_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

openprose_indent() {
  local s="$1"
  local trimmed="${s#"${s%%[![:space:]]*}"}"
  printf '%s' $(( ${#s} - ${#trimmed} ))
}

openprose_strip_quotes() {
  local s="$1"
  if [[ ${#s} -ge 2 ]]; then
    if [[ "$s" == \"*\" && "$s" == *\" ]]; then
      s="${s:1:${#s}-2}"
    elif [[ "$s" == \'*\' && "$s" == *\' ]]; then
      s="${s:1:${#s}-2}"
    fi
  fi
  printf '%s' "$s"
}

openprose_agent_set() {
  local key="$1"
  local value="$2"
  local i
  for i in "${!OPENPROSE_AGENT_KEYS[@]}"; do
    if [[ "${OPENPROSE_AGENT_KEYS[$i]}" == "$key" ]]; then
      OPENPROSE_AGENT_PROMPTS[$i]="$value"
      return 0
    fi
  done
  OPENPROSE_AGENT_KEYS+=("$key")
  OPENPROSE_AGENT_PROMPTS+=("$value")
}

openprose_agent_get() {
  local key="$1"
  local i
  for i in "${!OPENPROSE_AGENT_KEYS[@]}"; do
    if [[ "${OPENPROSE_AGENT_KEYS[$i]}" == "$key" ]]; then
      printf '%s' "${OPENPROSE_AGENT_PROMPTS[$i]}"
      return 0
    fi
  done
  return 1
}

openprose_context_set() {
  local key="$1"
  local path="$2"
  local i
  for i in "${!OPENPROSE_CONTEXT_KEYS[@]}"; do
    if [[ "${OPENPROSE_CONTEXT_KEYS[$i]}" == "$key" ]]; then
      OPENPROSE_CONTEXT_PATHS[$i]="$path"
      return 0
    fi
  done
  OPENPROSE_CONTEXT_KEYS+=("$key")
  OPENPROSE_CONTEXT_PATHS+=("$path")
}

openprose_context_get() {
  local key="$1"
  local i
  for i in "${!OPENPROSE_CONTEXT_KEYS[@]}"; do
    if [[ "${OPENPROSE_CONTEXT_KEYS[$i]}" == "$key" ]]; then
      printf '%s' "${OPENPROSE_CONTEXT_PATHS[$i]}"
      return 0
    fi
  done
  return 1
}

openprose_parse_context_names() {
  local raw="$1"
  raw="${raw#context:}"
  raw=$(openprose_trim "$raw")
  raw="${raw//\{}"
  raw="${raw//\}}"
  raw="${raw//\[}"
  raw="${raw//\]}"
  raw="${raw//,/ }"
  raw=$(printf '%s' "$raw" | tr -s ' ')
  raw=$(openprose_trim "$raw")
  printf '%s' "$raw"
}

openprose_log() {
  printf '%s\n' "$*" >> "$OPENPROSE_ROLE_LOG"
}

openprose_fail() {
  local message="$1"
  openprose_log "error: $message"
  cat <<EOF > "$OPENPROSE_IMPLEMENTER_REPORT"
OpenProse execution failed.
Program: $OPENPROSE_PROGRAM_FILE
Error: $message
EOF
  return 1
}

openprose_write_prompt() {
  local prompt_file="$1"
  local session_prompt="$2"
  local agent_prompt="$3"
  local context_names="$4"
  local context_max="$5"

  : > "$prompt_file"
  if [[ -n "$session_prompt" ]]; then
    printf '%s\n' "$session_prompt" >> "$prompt_file"
  fi
  if [[ -n "$agent_prompt" ]]; then
    if [[ -n "$session_prompt" ]]; then
      printf '\nSystem: %s\n' "$agent_prompt" >> "$prompt_file"
    else
      printf '%s\n' "$agent_prompt" >> "$prompt_file"
    fi
  fi
  if [[ -n "$context_names" ]]; then
    printf '\nContext:\n' >> "$prompt_file"
    local name
    for name in $context_names; do
      local path=""
      local value="(missing)"
      local size=0
      if path=$(openprose_context_get "$name"); then
        if [[ -n "$path" && -f "$path" ]]; then
          value=$(head -c "$context_max" "$path")
          size=$(wc -c < "$path" | tr -d ' ')
          if [[ "$size" -gt "$context_max" ]]; then
            value="${value}...[truncated]"
          fi
        fi
      fi
      printf -- '- %s: %s\n' "$name" "$value" >> "$prompt_file"
    done
  fi
}

openprose_record_session() {
  OPENPROSE_SESSION_IDS+=("$1")
  OPENPROSE_SESSION_NAMES+=("$2")
  OPENPROSE_SESSION_LOGS+=("$3")
  OPENPROSE_SESSION_LASTS+=("$4")
}

openprose_run_session() {
  local session_id="$1"
  local session_name="$2"
  local session_agent="$3"
  local session_prompt="$4"
  local session_context="$5"
  local prompt_file="$6"
  local log_file="$7"
  local last_message_file="$8"

  local agent_prompt=""
  if [[ -n "$session_agent" ]]; then
    if ! agent_prompt=$(openprose_agent_get "$session_agent"); then
      openprose_fail "unknown agent '$session_agent'"
      return 1
    fi
  fi

  openprose_write_prompt "$prompt_file" "$session_prompt" "$agent_prompt" "$session_context" "${OPENPROSE_CONTEXT_MAX_CHARS}"
  openprose_log "session $session_id${session_name:+ ($session_name)} log=${log_file#$OPENPROSE_REPO/} last_message=${last_message_file#$OPENPROSE_REPO/}"

  run_role "$OPENPROSE_REPO" "openprose-session-$session_id" "$prompt_file" "$last_message_file" "$log_file" "$OPENPROSE_TIMEOUT" "$OPENPROSE_PROMPT_MODE" "${OPENPROSE_RUNNER_COMMAND[@]}" -- "${OPENPROSE_RUNNER_ARGS[@]}"
}

openprose_run_parallel() {
  local count=${#OPENPROSE_PARALLEL_IDS[@]}
  if [[ $count -eq 0 ]]; then
    OPENPROSE_PARALLEL_ACTIVE=0
    return 0
  fi

  local -a pids=()
  local i
  for i in "${!OPENPROSE_PARALLEL_IDS[@]}"; do
    openprose_run_session \
      "${OPENPROSE_PARALLEL_IDS[$i]}" \
      "${OPENPROSE_PARALLEL_NAMES[$i]}" \
      "${OPENPROSE_PARALLEL_AGENTS[$i]}" \
      "${OPENPROSE_PARALLEL_PROMPTS[$i]}" \
      "${OPENPROSE_PARALLEL_CONTEXTS[$i]}" \
      "${OPENPROSE_PARALLEL_PROMPT_FILES[$i]}" \
      "${OPENPROSE_PARALLEL_LOG_FILES[$i]}" \
      "${OPENPROSE_PARALLEL_LAST_FILES[$i]}" &
    pids+=("$!")
  done

  local rc=0
  set +e
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}"
    local status=$?
    if [[ $status -eq 124 ]]; then
      rc=124
    elif [[ $status -ne 0 && $rc -eq 0 ]]; then
      rc=$status
    fi
  done
  set -e

  if [[ $rc -ne 0 ]]; then
    return "$rc"
  fi

  for i in "${!OPENPROSE_PARALLEL_IDS[@]}"; do
    local name="${OPENPROSE_PARALLEL_NAMES[$i]}"
    local last_message_file="${OPENPROSE_PARALLEL_LAST_FILES[$i]}"
    if [[ -n "$name" ]]; then
      openprose_context_set "$name" "$last_message_file"
    fi
  done

  OPENPROSE_PARALLEL_ACTIVE=0
  OPENPROSE_PARALLEL_IDS=()
  OPENPROSE_PARALLEL_NAMES=()
  OPENPROSE_PARALLEL_AGENTS=()
  OPENPROSE_PARALLEL_PROMPTS=()
  OPENPROSE_PARALLEL_CONTEXTS=()
  OPENPROSE_PARALLEL_PROMPT_FILES=()
  OPENPROSE_PARALLEL_LOG_FILES=()
  OPENPROSE_PARALLEL_LAST_FILES=()
  return 0
}

openprose_finalize_session() {
  if [[ $OPENPROSE_SESSION_ACTIVE -ne 1 ]]; then
    return 0
  fi

  OPENPROSE_SESSION_INDEX=$((OPENPROSE_SESSION_INDEX + 1))
  local session_id="$OPENPROSE_SESSION_INDEX"
  local prompt_file="$OPENPROSE_PROMPT_DIR/openprose-session-${session_id}.md"
  local log_file="$OPENPROSE_LOG_DIR/openprose-session-${session_id}.log"
  local last_message_file="$OPENPROSE_LAST_MESSAGES_DIR/openprose-session-${session_id}.txt"

  openprose_record_session "$session_id" "$OPENPROSE_SESSION_NAME" "$log_file" "$last_message_file"

  if [[ $OPENPROSE_SESSION_IN_PARALLEL -eq 1 ]]; then
    OPENPROSE_PARALLEL_IDS+=("$session_id")
    OPENPROSE_PARALLEL_NAMES+=("$OPENPROSE_SESSION_NAME")
    OPENPROSE_PARALLEL_AGENTS+=("$OPENPROSE_SESSION_AGENT")
    OPENPROSE_PARALLEL_PROMPTS+=("$OPENPROSE_SESSION_PROMPT")
    OPENPROSE_PARALLEL_CONTEXTS+=("$OPENPROSE_SESSION_CONTEXT")
    OPENPROSE_PARALLEL_PROMPT_FILES+=("$prompt_file")
    OPENPROSE_PARALLEL_LOG_FILES+=("$log_file")
    OPENPROSE_PARALLEL_LAST_FILES+=("$last_message_file")
  else
    if ! openprose_run_session "$session_id" "$OPENPROSE_SESSION_NAME" "$OPENPROSE_SESSION_AGENT" "$OPENPROSE_SESSION_PROMPT" "$OPENPROSE_SESSION_CONTEXT" "$prompt_file" "$log_file" "$last_message_file"; then
      return $?
    fi
    if [[ -n "$OPENPROSE_SESSION_NAME" ]]; then
      openprose_context_set "$OPENPROSE_SESSION_NAME" "$last_message_file"
    fi
  fi

  OPENPROSE_SESSION_ACTIVE=0
  OPENPROSE_SESSION_INDENT=-1
  OPENPROSE_SESSION_IN_PARALLEL=0
  OPENPROSE_SESSION_NAME=""
  OPENPROSE_SESSION_AGENT=""
  OPENPROSE_SESSION_PROMPT=""
  OPENPROSE_SESSION_CONTEXT=""
  return 0
}

openprose_finalize_parallel() {
  if [[ $OPENPROSE_PARALLEL_ACTIVE -ne 1 ]]; then
    return 0
  fi
  if ! openprose_run_parallel; then
    return $?
  fi
  OPENPROSE_PARALLEL_INDENT=-1
  return 0
}

openprose_write_report() {
  {
    echo "OpenProse execution summary"
    echo "Program: $OPENPROSE_PROGRAM_FILE"
    echo "Sessions executed: $OPENPROSE_SESSION_INDEX"
    echo ""
    echo "Sessions:"
    local i
    for i in "${!OPENPROSE_SESSION_IDS[@]}"; do
      local name="${OPENPROSE_SESSION_NAMES[$i]}"
      local label="session ${OPENPROSE_SESSION_IDS[$i]}"
      if [[ -n "$name" ]]; then
        label="$label ($name)"
      fi
      echo "- $label"
      echo "  log: ${OPENPROSE_SESSION_LOGS[$i]#$OPENPROSE_REPO/}"
      echo "  last_message: ${OPENPROSE_SESSION_LASTS[$i]#$OPENPROSE_REPO/}"
    done
    if [[ ${#OPENPROSE_CONTEXT_KEYS[@]} -gt 0 ]]; then
      echo ""
      echo "Outputs:"
      for i in "${!OPENPROSE_CONTEXT_KEYS[@]}"; do
        echo "- ${OPENPROSE_CONTEXT_KEYS[$i]}: ${OPENPROSE_CONTEXT_PATHS[$i]#$OPENPROSE_REPO/}"
      done
    fi
  } > "$OPENPROSE_IMPLEMENTER_REPORT"

  printf 'OpenProse ran %s session(s).\n' "$OPENPROSE_SESSION_INDEX" > "$OPENPROSE_LAST_MESSAGE_FILE"
}

run_openprose_role() {
  local repo="$1"
  local loop_dir="$2"
  local prompt_dir="$3"
  local log_dir="$4"
  local last_messages_dir="$5"
  local role_log="$6"
  local role_last_message_file="$7"
  local implementer_report="$8"
  local timeout_seconds="$9"
  local prompt_mode="${10}"
  shift 10

  local -a runner_command=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    runner_command+=("$1")
    shift
  done
  local -a runner_args=("$@")

  OPENPROSE_REPO="$repo"
  OPENPROSE_PROMPT_DIR="$prompt_dir"
  OPENPROSE_LOG_DIR="$log_dir"
  OPENPROSE_LAST_MESSAGES_DIR="$last_messages_dir"
  OPENPROSE_ROLE_LOG="$role_log"
  OPENPROSE_IMPLEMENTER_REPORT="$implementer_report"
  OPENPROSE_TIMEOUT="$timeout_seconds"
  OPENPROSE_PROMPT_MODE="$prompt_mode"
  OPENPROSE_PROGRAM_FILE="$repo/.superloop/workflows/openprose.prose"
  OPENPROSE_RUNNER_COMMAND=("${runner_command[@]}")
  OPENPROSE_RUNNER_ARGS=("${runner_args[@]}")
  OPENPROSE_SESSION_INDEX=0
  OPENPROSE_AGENT_KEYS=()
  OPENPROSE_AGENT_PROMPTS=()
  OPENPROSE_CONTEXT_KEYS=()
  OPENPROSE_CONTEXT_PATHS=()
  OPENPROSE_SESSION_IDS=()
  OPENPROSE_SESSION_NAMES=()
  OPENPROSE_SESSION_LOGS=()
  OPENPROSE_SESSION_LASTS=()
  OPENPROSE_AGENT_ACTIVE=0
  OPENPROSE_AGENT_INDENT=-1
  OPENPROSE_CURRENT_AGENT=""
  OPENPROSE_SESSION_ACTIVE=0
  OPENPROSE_SESSION_INDENT=-1
  OPENPROSE_SESSION_IN_PARALLEL=0
  OPENPROSE_SESSION_NAME=""
  OPENPROSE_SESSION_AGENT=""
  OPENPROSE_SESSION_PROMPT=""
  OPENPROSE_SESSION_CONTEXT=""
  OPENPROSE_PARALLEL_ACTIVE=0
  OPENPROSE_PARALLEL_INDENT=-1
  OPENPROSE_PARALLEL_IDS=()
  OPENPROSE_PARALLEL_NAMES=()
  OPENPROSE_PARALLEL_AGENTS=()
  OPENPROSE_PARALLEL_PROMPTS=()
  OPENPROSE_PARALLEL_CONTEXTS=()
  OPENPROSE_PARALLEL_PROMPT_FILES=()
  OPENPROSE_PARALLEL_LOG_FILES=()
  OPENPROSE_PARALLEL_LAST_FILES=()

  OPENPROSE_LAST_MESSAGE_FILE="$role_last_message_file"

  mkdir -p "$OPENPROSE_PROMPT_DIR" "$OPENPROSE_LOG_DIR" "$OPENPROSE_LAST_MESSAGES_DIR"
  : > "$OPENPROSE_ROLE_LOG"

  if [[ ! -f "$OPENPROSE_PROGRAM_FILE" ]]; then
    openprose_fail "missing program file: $OPENPROSE_PROGRAM_FILE"
    return 1
  fi

  local line
  local line_no=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    local indent
    indent=$(openprose_indent "$line")
    local trimmed
    trimmed=$(openprose_trim "$line")

    if [[ -z "$trimmed" || "${trimmed#\#}" != "$trimmed" ]]; then
      continue
    fi

    if [[ $OPENPROSE_SESSION_ACTIVE -eq 1 && $indent -le $OPENPROSE_SESSION_INDENT ]]; then
      if ! openprose_finalize_session; then
        return $?
      fi
    fi
    if [[ $OPENPROSE_PARALLEL_ACTIVE -eq 1 && $indent -le $OPENPROSE_PARALLEL_INDENT ]]; then
      if ! openprose_finalize_parallel; then
        return $?
      fi
    fi
    if [[ $OPENPROSE_AGENT_ACTIVE -eq 1 && $indent -le $OPENPROSE_AGENT_INDENT ]]; then
      OPENPROSE_AGENT_ACTIVE=0
      OPENPROSE_CURRENT_AGENT=""
    fi

    if [[ $OPENPROSE_SESSION_ACTIVE -eq 1 && $indent -gt $OPENPROSE_SESSION_INDENT ]]; then
      if [[ "$trimmed" == prompt:* ]]; then
        local value="${trimmed#prompt:}"
        value=$(openprose_trim "$value")
        if [[ "$value" == '"""'* || "$value" == "'''"* ]]; then
          openprose_fail "multi-line prompt not supported (line $line_no)"
          return 1
        fi
        OPENPROSE_SESSION_PROMPT=$(openprose_strip_quotes "$value")
        continue
      fi
      if [[ "$trimmed" == context:* ]]; then
        OPENPROSE_SESSION_CONTEXT=$(openprose_parse_context_names "$trimmed")
        continue
      fi
      continue
    fi

    if [[ $OPENPROSE_AGENT_ACTIVE -eq 1 && $indent -gt $OPENPROSE_AGENT_INDENT ]]; then
      if [[ "$trimmed" == prompt:* ]]; then
        local value="${trimmed#prompt:}"
        value=$(openprose_trim "$value")
        if [[ "$value" == '"""'* || "$value" == "'''"* ]]; then
          openprose_fail "multi-line agent prompt not supported (line $line_no)"
          return 1
        fi
        openprose_agent_set "$OPENPROSE_CURRENT_AGENT" "$(openprose_strip_quotes "$value")"
      fi
      continue
    fi

    if [[ "$trimmed" =~ ^agent[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*:$ ]]; then
      OPENPROSE_CURRENT_AGENT="${BASH_REMATCH[1]}"
      OPENPROSE_AGENT_ACTIVE=1
      OPENPROSE_AGENT_INDENT=$indent
      openprose_agent_set "$OPENPROSE_CURRENT_AGENT" ""
      continue
    fi

    if [[ "$trimmed" == "parallel:" ]]; then
      OPENPROSE_PARALLEL_ACTIVE=1
      OPENPROSE_PARALLEL_INDENT=$indent
      OPENPROSE_PARALLEL_IDS=()
      OPENPROSE_PARALLEL_NAMES=()
      OPENPROSE_PARALLEL_AGENTS=()
      OPENPROSE_PARALLEL_PROMPTS=()
      OPENPROSE_PARALLEL_CONTEXTS=()
      OPENPROSE_PARALLEL_PROMPT_FILES=()
      OPENPROSE_PARALLEL_LOG_FILES=()
      OPENPROSE_PARALLEL_LAST_FILES=()
      continue
    fi

    local session_name=""
    local session_line=""
    if [[ "$trimmed" =~ ^(let|const)[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*=[[:space:]]*session(.*)$ ]]; then
      session_name="${BASH_REMATCH[2]}"
      session_line="session${BASH_REMATCH[3]}"
    elif [[ "$trimmed" =~ ^([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*=[[:space:]]*session(.*)$ ]]; then
      session_name="${BASH_REMATCH[1]}"
      session_line="session${BASH_REMATCH[2]}"
    elif [[ "$trimmed" =~ ^session(.*)$ ]]; then
      session_line="session${BASH_REMATCH[1]}"
    fi

    if [[ -n "$session_line" ]]; then
      local rest="${session_line#session}"
      rest=$(openprose_trim "$rest")
      if [[ "$rest" == *: ]]; then
        rest="${rest%:}"
        rest=$(openprose_trim "$rest")
      fi
      local session_agent=""
      local session_prompt=""
      if [[ "$rest" == :* ]]; then
        rest="${rest#:}"
        rest=$(openprose_trim "$rest")
        session_agent="${rest%%[[:space:]]*}"
        local remainder="${rest#"$session_agent"}"
        if [[ -n "$(openprose_trim "$remainder")" ]]; then
          openprose_fail "inline prompt after session agent not supported (line $line_no)"
          return 1
        fi
      else
        if [[ "$rest" == '"""'* || "$rest" == "'''"* ]]; then
          openprose_fail "multi-line session prompt not supported (line $line_no)"
          return 1
        fi
        session_prompt=$(openprose_strip_quotes "$rest")
      fi

      OPENPROSE_SESSION_ACTIVE=1
      OPENPROSE_SESSION_INDENT=$indent
      OPENPROSE_SESSION_IN_PARALLEL=0
      if [[ $OPENPROSE_PARALLEL_ACTIVE -eq 1 ]]; then
        OPENPROSE_SESSION_IN_PARALLEL=1
      fi
      OPENPROSE_SESSION_NAME="$session_name"
      OPENPROSE_SESSION_AGENT="$session_agent"
      OPENPROSE_SESSION_PROMPT="$session_prompt"
      OPENPROSE_SESSION_CONTEXT=""
      continue
    fi

    openprose_fail "unsupported statement on line $line_no: $trimmed"
    return 1
  done < "$OPENPROSE_PROGRAM_FILE"

  if ! openprose_finalize_session; then
    return $?
  fi
  if ! openprose_finalize_parallel; then
    return $?
  fi

  openprose_write_report
  return 0
}

# Usage tracking functions for Claude Code and Codex
# Extracts token counts and timing from session files

# Global variables for usage tracking
USAGE_TRACKING_ENABLED=1
USAGE_SESSION_ID=""
USAGE_THREAD_ID=""
USAGE_MODEL=""
USAGE_START_TIME=""
USAGE_END_TIME=""
USAGE_FILE=""

# Detect runner type from command array
# Returns: "claude", "codex", or "unknown"
detect_runner_type() {
  local -a cmd=("$@")
  local cmd_str="${cmd[*]}"

  if [[ "${cmd[0]}" == "claude" ]] || [[ "$cmd_str" == *"/claude "* ]] || [[ "$cmd_str" == *"/claude" ]]; then
    echo "claude"
  elif [[ "${cmd[0]}" == "codex" ]] || [[ "$cmd_str" == *"/codex "* ]] || [[ "$cmd_str" == *"/codex" ]]; then
    echo "codex"
  else
    echo "unknown"
  fi
}

# Generate a UUID for Claude session tracking
generate_session_id() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    # Fallback: generate pseudo-UUID from timestamp and random
    printf '%08x-%04x-%04x-%04x-%012x' \
      $((RANDOM * RANDOM)) \
      $((RANDOM)) \
      $((RANDOM)) \
      $((RANDOM)) \
      $((RANDOM * RANDOM * RANDOM))
  fi
}

# Get milliseconds timestamp
get_timestamp_ms() {
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: use python or perl for milliseconds
    python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || \
    perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000' 2>/dev/null || \
    echo "$(($(date +%s) * 1000))"
  else
    # Linux: date supports %N for nanoseconds
    echo "$(($(date +%s%N) / 1000000))"
  fi
}

# Find Claude session file by session ID
# Args: $1 = repo path, $2 = session_id
find_claude_session_file() {
  local repo="$1"
  local session_id="$2"
  local project_name
  project_name=$(basename "$repo")

  # Claude stores sessions in ~/.claude/projects/<project>/<session-id>.jsonl
  local session_file="$HOME/.claude/projects/-${project_name//\//-}/${session_id}.jsonl"

  if [[ -f "$session_file" ]]; then
    echo "$session_file"
    return 0
  fi

  # Try alternative path formats
  local alt_file
  for alt_file in "$HOME/.claude/projects"/*"$project_name"*/"${session_id}.jsonl"; do
    if [[ -f "$alt_file" ]]; then
      echo "$alt_file"
      return 0
    fi
  done

  return 1
}

# Find Codex session file by thread ID
# Args: $1 = thread_id
find_codex_session_file() {
  local thread_id="$1"

  # Codex stores sessions in ~/.codex/sessions/YYYY/MM/DD/rollout-*-<thread_id>.jsonl
  local session_file
  session_file=$(find "$HOME/.codex/sessions" -name "*${thread_id}.jsonl" -type f 2>/dev/null | head -n1)

  if [[ -n "$session_file" && -f "$session_file" ]]; then
    echo "$session_file"
    return 0
  fi

  return 1
}

# Extract usage from Claude session file
# Args: $1 = session_file
# Output: JSON object with usage stats
extract_claude_usage() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    echo '{"error": "session file not found"}'
    return 1
  fi

  # Extract usage from assistant messages
  jq -s '
    [.[] | select(.type == "assistant" and .message.usage != null) | .message.usage] |
    if length == 0 then
      {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
    else
      {
        "input_tokens": (map(.input_tokens // 0) | add),
        "output_tokens": (map(.output_tokens // 0) | add),
        "cache_read_input_tokens": (map(.cache_read_input_tokens // 0) | add),
        "cache_creation_input_tokens": (map(.cache_creation_input_tokens // 0) | add)
      }
    end
  ' "$session_file" 2>/dev/null || echo '{"error": "failed to parse session file"}'
}

# Extract usage from Codex session file
# Args: $1 = session_file
# Output: JSON object with usage stats
extract_codex_usage() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    echo '{"error": "session file not found"}'
    return 1
  fi

  # Extract token_count events from Codex JSONL
  jq -s '
    [.[] | select(.type == "event_msg" and .payload.type == "token_count") | .payload] |
    if length == 0 then
      {"input_tokens": 0, "output_tokens": 0}
    else
      {
        "input_tokens": (map(.input_tokens // 0) | add),
        "output_tokens": (map(.output_tokens // 0) | add)
      }
    end
  ' "$session_file" 2>/dev/null || echo '{"error": "failed to parse session file"}'
}

# Extract thread_id from Codex JSON output
# Args: $1 = log_file containing JSON output
extract_codex_thread_id() {
  local log_file="$1"

  if [[ ! -f "$log_file" ]]; then
    return 1
  fi

  # Look for thread.started event with thread_id
  local thread_id
  thread_id=$(grep -m1 '"thread_id"' "$log_file" 2>/dev/null | jq -r '.thread_id // empty' 2>/dev/null)

  if [[ -n "$thread_id" ]]; then
    echo "$thread_id"
    return 0
  fi

  return 1
}

# Extract thread_id from Codex session filename
# Session files are named: rollout-<timestamp>-<thread_id>.jsonl
# Args: $1 = session_file path
extract_thread_id_from_filename() {
  local session_file="$1"
  local filename
  filename=$(basename "$session_file")

  # Pattern: rollout-YYYYMMDD_HHMMSS_mmm-<thread_id>.jsonl
  # or: rollout-<number>-<thread_id>.jsonl
  if [[ "$filename" =~ ^rollout-.*-([a-zA-Z0-9_-]+)\.jsonl$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

# Find Codex session file by start time and extract thread_id
# Args: $1 = start_timestamp_seconds
# Sets: USAGE_THREAD_ID global
# Returns: 0 if found, 1 otherwise
find_and_set_codex_thread_id() {
  local start_ts="$1"
  local session_file thread_id

  # Find session file created after start time
  session_file=$(find "$HOME/.codex/sessions" -name "rollout-*.jsonl" -type f -newermt "@$start_ts" 2>/dev/null | head -n1 || true)

  if [[ -z "$session_file" ]]; then
    return 1
  fi

  # Extract thread_id from filename
  thread_id=$(extract_thread_id_from_filename "$session_file" || true)

  if [[ -n "$thread_id" ]]; then
    USAGE_THREAD_ID="$thread_id"
    return 0
  fi

  return 1
}

# Extract model from Claude session file
# Args: $1 = session_file
# Output: model name (e.g., "claude-sonnet-4-20250514")
extract_claude_model() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    return 1
  fi

  # Extract model from first assistant message
  local model
  model=$(jq -r '[.[] | select(.type == "assistant" and .message.model != null) | .message.model][0] // empty' "$session_file" 2>/dev/null)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  return 1
}

# Extract model from Codex log output
# Args: $1 = log_file
# Output: model name (e.g., "gpt-5.2-codex")
extract_codex_model_from_log() {
  local log_file="$1"

  if [[ ! -f "$log_file" ]]; then
    return 1
  fi

  # Look for "model: xxx" line in the header
  local model
  model=$(grep -m1 '^model:' "$log_file" 2>/dev/null | sed 's/^model:[[:space:]]*//' || true)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  return 1
}

# Extract model from Codex session file
# Args: $1 = session_file
# Output: model name
extract_codex_model() {
  local session_file="$1"

  if [[ ! -f "$session_file" ]]; then
    return 1
  fi

  # Try to find model in session metadata or messages
  local model
  model=$(jq -r '[.[] | select(.model != null) | .model][0] // empty' "$session_file" 2>/dev/null)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  # Try alternate structure
  model=$(jq -r '.model // empty' "$session_file" 2>/dev/null | head -1)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  return 1
}

# Write usage event to JSONL file
# Args: $1 = usage_file, $2 = iteration, $3 = role, $4 = duration_ms, $5 = usage_json, $6 = runner_type, $7 = session_file
write_usage_event() {
  local usage_file="$1"
  local iteration="$2"
  local role="$3"
  local duration_ms="$4"
  local usage_json="$5"
  local runner_type="$6"
  local session_file="${7:-}"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build the event JSON - include session/thread IDs and model from globals
  jq -n \
    --arg ts "$timestamp" \
    --argjson iter "$iteration" \
    --arg role "$role" \
    --argjson duration "$duration_ms" \
    --argjson usage "$usage_json" \
    --arg runner "$runner_type" \
    --arg session "$session_file" \
    --arg session_id "${USAGE_SESSION_ID:-}" \
    --arg thread_id "${USAGE_THREAD_ID:-}" \
    --arg model "${USAGE_MODEL:-}" \
    '{
      "timestamp": $ts,
      "iteration": $iter,
      "role": $role,
      "duration_ms": $duration,
      "runner": $runner,
      "model": (if $model == "" then null else $model end),
      "session_id": (if $session_id == "" then null else $session_id end),
      "thread_id": (if $thread_id == "" then null else $thread_id end),
      "usage": $usage,
      "session_file": (if $session == "" then null else $session end)
    }' >> "$usage_file"
}

# Write session entry to sessions manifest
# Args: $1 = sessions_file, $2 = iteration, $3 = role, $4 = runner_type, $5 = status, $6 = started_at, $7 = ended_at
write_session_entry() {
  local sessions_file="$1"
  local iteration="$2"
  local role="$3"
  local runner_type="$4"
  local status="$5"
  local started_at="$6"
  local ended_at="${7:-}"

  if [[ -z "$sessions_file" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$sessions_file")"

  jq -c -n \
    --argjson iter "$iteration" \
    --arg role "$role" \
    --arg runner "$runner_type" \
    --arg session_id "${USAGE_SESSION_ID:-}" \
    --arg thread_id "${USAGE_THREAD_ID:-}" \
    --arg model "${USAGE_MODEL:-}" \
    --arg status "$status" \
    --arg started_at "$started_at" \
    --arg ended_at "$ended_at" \
    '{
      iteration: $iter,
      role: $role,
      runner: $runner,
      model: (if $model == "" then null else $model end),
      session_id: (if $session_id == "" then null else $session_id end),
      thread_id: (if $thread_id == "" then null else $thread_id end),
      status: $status,
      started_at: $started_at,
      ended_at: (if $ended_at == "" then null else $ended_at end)
    }' >> "$sessions_file"
}

# Get the current session info as JSON (for state tracking)
get_current_session_json() {
  jq -c -n \
    --arg session_id "${USAGE_SESSION_ID:-}" \
    --arg thread_id "${USAGE_THREAD_ID:-}" \
    --arg runner "${CURRENT_RUNNER_TYPE:-unknown}" \
    '{
      session_id: (if $session_id == "" then null else $session_id end),
      thread_id: (if $thread_id == "" then null else $thread_id end),
      runner: $runner
    }'
}

# Prepare command with session tracking args
# Args: $1 = runner_type, rest = original command
# Sets: USAGE_SESSION_ID for claude
# Output: Modified command array elements (one per line)
prepare_tracked_command() {
  local runner_type="$1"
  shift
  local -a cmd=("$@")

  USAGE_SESSION_ID=""

  case "$runner_type" in
    claude)
      # Generate session ID and inject --session-id flag
      USAGE_SESSION_ID=$(generate_session_id)

      # Find where to insert --session-id (after 'claude' command)
      local inserted=0
      for i in "${!cmd[@]}"; do
        echo "${cmd[$i]}"
        if [[ $inserted -eq 0 && ("${cmd[$i]}" == "claude" || "${cmd[$i]}" == */claude) ]]; then
          echo "--session-id"
          echo "$USAGE_SESSION_ID"
          inserted=1
        fi
      done
      ;;

    codex)
      # For codex, we need --json flag to capture thread_id
      # But this changes output format, so we'll use timestamp-based matching instead
      # Just pass through the command unchanged
      for arg in "${cmd[@]}"; do
        echo "$arg"
      done
      ;;

    *)
      # Unknown runner, pass through unchanged
      for arg in "${cmd[@]}"; do
        echo "$arg"
      done
      ;;
  esac
}

# Main usage tracking wrapper
# Call this before and after running the command
# Args: $1 = action (start|end), $2 = usage_file, $3 = iteration, $4 = role, $5 = repo, $6 = runner_type, $7 = log_file (optional, for model extraction)
track_usage() {
  local action="$1"
  local usage_file="$2"
  local iteration="$3"
  local role="$4"
  local repo="$5"
  local runner_type="$6"
  local log_file="${7:-}"

  case "$action" in
    start)
      USAGE_START_TIME=$(get_timestamp_ms)
      USAGE_MODEL=""  # Reset model for new run
      ;;

    end)
      USAGE_END_TIME=$(get_timestamp_ms)
      local duration_ms=$((USAGE_END_TIME - USAGE_START_TIME))

      # Find and parse session file based on runner type
      local session_file=""
      local usage_json='{"input_tokens": 0, "output_tokens": 0}'

      case "$runner_type" in
        claude)
          if [[ -n "$USAGE_SESSION_ID" ]]; then
            session_file=$(find_claude_session_file "$repo" "$USAGE_SESSION_ID" || true)
            if [[ -n "$session_file" ]]; then
              usage_json=$(extract_claude_usage "$session_file")
              # Extract model from session file
              USAGE_MODEL=$(extract_claude_model "$session_file" || true)
            fi
          fi
          ;;

        codex)
          # For Codex, find the most recent session file modified after start time
          local start_ts=$((USAGE_START_TIME / 1000))
          session_file=$(find "$HOME/.codex/sessions" -name "rollout-*.jsonl" -type f -newermt "@$start_ts" 2>/dev/null | head -n1 || true)
          if [[ -n "$session_file" ]]; then
            usage_json=$(extract_codex_usage "$session_file")
            # Try to extract model from session file first
            USAGE_MODEL=$(extract_codex_model "$session_file" || true)
          fi
          # If no model from session, try log file
          if [[ -z "$USAGE_MODEL" && -n "$log_file" && -f "$log_file" ]]; then
            USAGE_MODEL=$(extract_codex_model_from_log "$log_file" || true)
          fi
          ;;
      esac

      # Write usage event
      if [[ -n "$usage_file" ]]; then
        mkdir -p "$(dirname "$usage_file")"
        write_usage_event "$usage_file" "$iteration" "$role" "$duration_ms" "$usage_json" "$runner_type" "$session_file"
      fi
      ;;
  esac
}

#!/usr/bin/env bash
# 36-usage-limits.sh - Pre-flight usage limit checking for runners
# Checks API usage limits before starting roles to avoid mid-run failures

# -----------------------------------------------------------------------------
# Claude Code Credential Retrieval (multi-method)
# -----------------------------------------------------------------------------

# Get Claude Code OAuth token from available sources
# Priority: 1) Environment variable, 2) Keychain (macOS), 3) Credentials file
get_claude_token() {
  local token=""

  # Method 1: Environment variable
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "$CLAUDE_CODE_OAUTH_TOKEN"
    return 0
  fi

  # Method 2: macOS Keychain
  if command -v security &>/dev/null; then
    token=$(security find-generic-password -s "Claude Code-credentials" -a "Claude Code" -w 2>/dev/null || true)
    if [[ -n "$token" ]]; then
      # Token is JSON, extract accessToken
      local access_token
      access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null || true)
      if [[ -n "$access_token" ]]; then
        echo "$access_token"
        return 0
      fi
    fi
  fi

  # Method 3: Credentials file
  local creds_file="$HOME/.claude/.credentials.json"
  if [[ -f "$creds_file" ]]; then
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
      echo "$token"
      return 0
    fi
  fi

  return 1
}

# Get Claude organization ID from config
get_claude_org_id() {
  local config_file="$HOME/.claude.json"
  if [[ -f "$config_file" ]]; then
    jq -r '.oauthAccount.organizationUuid // empty' "$config_file" 2>/dev/null || true
  fi
}

# -----------------------------------------------------------------------------
# Codex Credential Retrieval
# -----------------------------------------------------------------------------

# Get Codex access token and account ID
get_codex_credentials() {
  local auth_file="$HOME/.codex/auth.json"
  if [[ -f "$auth_file" ]]; then
    local access_token account_id
    access_token=$(jq -r '.tokens.access_token // empty' "$auth_file" 2>/dev/null || true)
    account_id=$(jq -r '.tokens.account_id // empty' "$auth_file" 2>/dev/null || true)
    if [[ -n "$access_token" ]]; then
      echo "$access_token"
      echo "$account_id"
      return 0
    fi
  fi
  return 1
}

# -----------------------------------------------------------------------------
# Usage API Queries
# -----------------------------------------------------------------------------

# Query Claude usage API
# Tries multiple methods: 1) Session key env var, 2) OAuth endpoint
# Returns JSON with usage data or empty on failure
query_claude_usage() {
  local result=""

  # Method 1: Session key from environment (most reliable)
  if [[ -n "${CLAUDE_SESSION_KEY:-}" ]]; then
    local org_id
    org_id=$(get_claude_org_id)
    if [[ -n "$org_id" ]]; then
      # Use browser-like headers to avoid Cloudflare blocking
      result=$(curl -s --max-time 10 \
        "https://claude.ai/api/organizations/${org_id}/usage" \
        -H "accept: application/json, text/plain, */*" \
        -H "accept-language: en-US,en;q=0.9" \
        -H "content-type: application/json" \
        -H "Cookie: sessionKey=${CLAUDE_SESSION_KEY}" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        -H "Origin: https://claude.ai" \
        -H "Referer: https://claude.ai/" \
        2>/dev/null || true)

      # Check if we got a valid response (not an error)
      if [[ -n "$result" ]] && ! echo "$result" | jq -e '.error' &>/dev/null; then
        echo "$result"
        return 0
      fi
    fi
  fi

  # Method 2: OAuth token from keychain (may have limited scope)
  local token
  token=$(get_claude_token 2>/dev/null) || true

  if [[ -n "$token" ]]; then
    result=$(curl -s --max-time 10 \
      "https://api.anthropic.com/api/oauth/usage" \
      -H "Authorization: Bearer ${token}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      2>/dev/null || true)

    # Check if we got a valid response
    if [[ -n "$result" ]] && ! echo "$result" | jq -e '.error' &>/dev/null; then
      echo "$result"
      return 0
    fi
  fi

  # Both methods failed
  return 1
}

# Query OpenAI/Codex usage API
# Returns JSON with usage data or empty on failure
query_codex_usage() {
  local creds access_token account_id
  creds=$(get_codex_credentials) || return 1

  access_token=$(echo "$creds" | head -1)
  account_id=$(echo "$creds" | tail -1)

  if [[ -z "$access_token" ]]; then
    return 1
  fi

  local headers=(-H "accept: */*" -H "authorization: Bearer ${access_token}")
  if [[ -n "$account_id" ]]; then
    headers+=(-H "chatgpt-account-id: ${account_id}")
  fi

  curl -s --max-time 10 \
    "https://chatgpt.com/backend-api/wham/usage" \
    "${headers[@]}" \
    2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Usage Parsing
# -----------------------------------------------------------------------------

# Parse Claude usage response
# Returns: utilization_percent reset_timestamp
parse_claude_usage() {
  local json="$1"
  local window="${2:-five_hour}"  # five_hour, seven_day, etc.

  if [[ -z "$json" ]]; then
    return 1
  fi

  local utilization resets_at
  utilization=$(echo "$json" | jq -r ".${window}.utilization // 0" 2>/dev/null || echo "0")
  resets_at=$(echo "$json" | jq -r ".${window}.resets_at // empty" 2>/dev/null || true)

  echo "$utilization"
  echo "$resets_at"
}

# Parse Codex usage response
# Returns: used_percent reset_timestamp error_message
parse_codex_usage() {
  local json="$1"

  if [[ -z "$json" ]]; then
    return 1
  fi

  # Check for error response (like usage_limit_reached)
  local error_type error_message resets_at limit_reached
  error_type=$(echo "$json" | jq -r '.error.type // empty' 2>/dev/null || true)

  if [[ "$error_type" == "usage_limit_reached" ]]; then
    error_message=$(echo "$json" | jq -r '.error.message // "Usage limit reached"' 2>/dev/null)
    resets_at=$(echo "$json" | jq -r '.error.resets_at // empty' 2>/dev/null || true)
    echo "100"  # 100% used
    echo "$resets_at"
    echo "$error_message"
    return 0
  fi

  # Check if limit is reached via flag
  limit_reached=$(echo "$json" | jq -r '.rate_limit.limit_reached // false' 2>/dev/null || echo "false")
  if [[ "$limit_reached" == "true" ]]; then
    resets_at=$(echo "$json" | jq -r '.rate_limit.primary_window.reset_at // .rate_limit.reset_at // empty' 2>/dev/null || true)
    echo "100"  # 100% used
    echo "$resets_at"
    echo "Usage limit reached"
    return 0
  fi

  # Normal response - try primary_window first, fall back to top-level
  local used_percent
  used_percent=$(echo "$json" | jq -r '.rate_limit.primary_window.used_percent // .rate_limit.used_percent // 0' 2>/dev/null || echo "0")
  resets_at=$(echo "$json" | jq -r '.rate_limit.primary_window.reset_at // .rate_limit.reset_at // empty' 2>/dev/null || true)

  echo "$used_percent"
  echo "$resets_at"
  echo ""
}

# -----------------------------------------------------------------------------
# Pre-flight Check
# -----------------------------------------------------------------------------

# Check usage limits before starting a role
# Arguments: runner_type (claude|codex), warn_threshold (default 70), block_threshold (default 95)
# Returns: 0 = OK, 1 = warning (proceed), 2 = blocked (should not proceed)
# Outputs status info to stderr
check_usage_limits() {
  local runner_type="${1:-}"
  local warn_threshold="${2:-70}"
  local block_threshold="${3:-95}"

  local usage_json used_percent resets_at error_msg
  local result=0

  case "$runner_type" in
    claude)
      usage_json=$(query_claude_usage 2>/dev/null || true)
      if [[ -z "$usage_json" ]]; then
        echo "[usage] Could not query Claude usage (no credentials or API error)" >&2
        return 0  # Don't block on query failure
      fi

      local parsed
      parsed=$(parse_claude_usage "$usage_json" "five_hour")
      used_percent=$(echo "$parsed" | head -1)
      resets_at=$(echo "$parsed" | tail -1)
      ;;

    codex|openai)
      usage_json=$(query_codex_usage 2>/dev/null || true)
      if [[ -z "$usage_json" ]]; then
        echo "[usage] Could not query Codex usage (no credentials or API error)" >&2
        return 0  # Don't block on query failure
      fi

      local parsed
      parsed=$(parse_codex_usage "$usage_json")
      used_percent=$(echo "$parsed" | head -1)
      resets_at=$(echo "$parsed" | sed -n '2p')
      error_msg=$(echo "$parsed" | tail -1)

      if [[ -n "$error_msg" ]]; then
        echo "[usage] Codex API reports: $error_msg" >&2
      fi
      ;;

    *)
      # Unknown runner type, skip check
      return 0
      ;;
  esac

  # Convert to integer for comparison
  used_percent=${used_percent%.*}  # Remove decimal
  used_percent=${used_percent:-0}

  # Format reset time if available
  local reset_info=""
  if [[ -n "$resets_at" ]]; then
    if [[ "$resets_at" =~ ^[0-9]+$ ]]; then
      # Unix timestamp
      reset_info=" (resets at $(date -r "$resets_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$resets_at"))"
    else
      # ISO string
      reset_info=" (resets at $resets_at)"
    fi
  fi

  if [[ "$used_percent" -ge "$block_threshold" ]]; then
    echo "[usage] BLOCKED: $runner_type usage at ${used_percent}% (threshold: ${block_threshold}%)${reset_info}" >&2
    result=2
  elif [[ "$used_percent" -ge "$warn_threshold" ]]; then
    echo "[usage] WARNING: $runner_type usage at ${used_percent}% (threshold: ${warn_threshold}%)${reset_info}" >&2
    result=1
  else
    echo "[usage] OK: $runner_type usage at ${used_percent}%${reset_info}" >&2
    result=0
  fi

  return $result
}

# Calculate seconds until usage resets
# Arguments: resets_at (timestamp or ISO string)
get_seconds_until_reset() {
  local resets_at="$1"
  local now reset_epoch

  now=$(date +%s)

  if [[ "$resets_at" =~ ^[0-9]+$ ]]; then
    reset_epoch="$resets_at"
  else
    # Try to parse ISO string
    reset_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" +%s 2>/dev/null || echo "0")
  fi

  if [[ "$reset_epoch" -gt "$now" ]]; then
    echo $((reset_epoch - now))
  else
    echo "0"
  fi
}

# Human-readable time until reset
format_time_until_reset() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))

  if [[ "$hours" -gt 0 ]]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# -----------------------------------------------------------------------------
# Event Logging
# -----------------------------------------------------------------------------

# Log usage check event
log_usage_event() {
  local events_file="$1"
  local runner_type="$2"
  local used_percent="$3"
  local status="$4"  # ok, warning, blocked
  local resets_at="${5:-}"

  if [[ -z "$events_file" ]]; then
    return
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local event
  event=$(jq -n \
    --arg ts "$timestamp" \
    --arg type "usage_check" \
    --arg runner "$runner_type" \
    --arg percent "$used_percent" \
    --arg status "$status" \
    --arg resets "$resets_at" \
    '{
      timestamp: $ts,
      event: $type,
      runner: $runner,
      used_percent: ($percent | tonumber),
      status: $status,
      resets_at: (if $resets == "" then null else $resets end)
    }')

  echo "$event" >> "$events_file"
}

# -----------------------------------------------------------------------------
# Reactive Rate Limit Detection (during execution)
# -----------------------------------------------------------------------------

# Detect rate limit errors in runner output
# Returns 0 if rate limit detected, 1 otherwise
# Sets global variables: RATE_LIMIT_DETECTED, RATE_LIMIT_RESETS_AT, RATE_LIMIT_MESSAGE
detect_rate_limit_in_line() {
  local line="$1"

  RATE_LIMIT_DETECTED=0
  RATE_LIMIT_RESETS_AT=""
  RATE_LIMIT_MESSAGE=""

  # Pattern: Codex JSON error
  if echo "$line" | grep -q '"type":\s*"usage_limit_reached"'; then
    RATE_LIMIT_DETECTED=1
    RATE_LIMIT_MESSAGE="Codex usage limit reached"
    # Try to extract resets_at
    RATE_LIMIT_RESETS_AT=$(echo "$line" | grep -o '"resets_at":\s*[0-9]*' | grep -o '[0-9]*' || true)
    return 0
  fi

  # Pattern: Codex error message
  if echo "$line" | grep -qi "usage.limit.*reached\|rate.limit.*exceeded"; then
    RATE_LIMIT_DETECTED=1
    RATE_LIMIT_MESSAGE="Rate limit detected in output"
    # Try to extract reset time
    RATE_LIMIT_RESETS_AT=$(echo "$line" | grep -oE 'resets?_?(at|in)["\s:]+[0-9]+' | grep -o '[0-9]*' | head -1 || true)
    return 0
  fi

  # Pattern: HTTP 429
  if echo "$line" | grep -q "429\|Too Many Requests"; then
    RATE_LIMIT_DETECTED=1
    RATE_LIMIT_MESSAGE="HTTP 429 Too Many Requests"
    return 0
  fi

  # Pattern: Claude rate limit
  if echo "$line" | grep -qi "rate.limit\|usage.limit\|limit.*reached"; then
    # Avoid false positives from normal usage discussions
    if echo "$line" | grep -qiE "error|failed|exceeded|hit|reached"; then
      RATE_LIMIT_DETECTED=1
      RATE_LIMIT_MESSAGE="Rate limit error detected"
      return 0
    fi
  fi

  return 1
}

# Parse rate limit info from a block of output
# Arguments: output_text
# Returns: JSON with rate limit info or empty
parse_rate_limit_info() {
  local output="$1"
  local resets_at="" resets_in="" message=""

  # Try to find resets_at (unix timestamp)
  resets_at=$(echo "$output" | grep -oE '"resets_at":\s*[0-9]+' | grep -o '[0-9]*' | head -1 || true)

  # Try to find resets_in_seconds
  resets_in=$(echo "$output" | grep -oE '"resets_in_seconds":\s*[0-9]+' | grep -o '[0-9]*' | head -1 || true)

  # Try to find message
  message=$(echo "$output" | grep -oE '"message":\s*"[^"]*"' | sed 's/"message":\s*"//' | sed 's/"$//' | head -1 || true)

  # Calculate resets_at from resets_in if needed
  if [[ -z "$resets_at" && -n "$resets_in" ]]; then
    resets_at=$(($(date +%s) + resets_in))
  fi

  if [[ -n "$resets_at" || -n "$message" ]]; then
    jq -n \
      --arg resets_at "$resets_at" \
      --arg resets_in "$resets_in" \
      --arg message "$message" \
      '{
        resets_at: (if $resets_at != "" then ($resets_at | tonumber) else null end),
        resets_in_seconds: (if $resets_in != "" then ($resets_in | tonumber) else null end),
        message: (if $message != "" then $message else null end)
      }'
  fi
}

# Wait for rate limit to reset
# Arguments: resets_at (unix timestamp), max_wait_seconds (default: 7200)
# Returns: 0 on success, 1 on timeout
wait_for_rate_limit_reset() {
  local resets_at="$1"
  local max_wait="${2:-7200}"  # Default 2 hours max
  local check_interval=60      # Check every minute

  if [[ -z "$resets_at" ]]; then
    echo "[rate-limit] No reset time provided, waiting 5 minutes..." >&2
    sleep 300
    return 0
  fi

  local now wait_seconds
  now=$(date +%s)

  # Handle if resets_at is already a timestamp or needs parsing
  if [[ ! "$resets_at" =~ ^[0-9]+$ ]]; then
    resets_at=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" +%s 2>/dev/null || echo "$now")
  fi

  wait_seconds=$((resets_at - now))

  if [[ "$wait_seconds" -le 0 ]]; then
    echo "[rate-limit] Reset time already passed, continuing..." >&2
    return 0
  fi

  if [[ "$wait_seconds" -gt "$max_wait" ]]; then
    echo "[rate-limit] Wait time (${wait_seconds}s) exceeds max (${max_wait}s), aborting" >&2
    return 1
  fi

  local formatted_wait
  formatted_wait=$(format_time_until_reset "$wait_seconds")
  echo "[rate-limit] Waiting ${formatted_wait} until $(date -r "$resets_at" '+%Y-%m-%d %H:%M:%S')..." >&2

  # Wait with periodic status updates
  local waited=0
  while [[ "$waited" -lt "$wait_seconds" ]]; do
    local remaining=$((wait_seconds - waited))
    if [[ "$remaining" -gt "$check_interval" ]]; then
      sleep "$check_interval"
      waited=$((waited + check_interval))
      formatted_wait=$(format_time_until_reset "$remaining")
      echo "[rate-limit] Still waiting... ${formatted_wait} remaining" >&2
    else
      sleep "$remaining"
      waited=$((waited + remaining))
    fi
  done

  echo "[rate-limit] Wait complete, resuming..." >&2
  return 0
}

# -----------------------------------------------------------------------------
# Session Management for Resume
# -----------------------------------------------------------------------------

# Generate a session ID for tracking
generate_session_id() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    # Fallback: use date + random
    echo "session-$(date +%s)-$RANDOM"
  fi
}

# Build resume command for Claude Code
# Arguments: session_id, resume_message (optional)
build_claude_resume_command() {
  local session_id="$1"
  local message="${2:-continue from where you left off}"

  echo "claude" "--resume" "$session_id" "-p" "$message"
}

# Build resume command for Codex
# Arguments: thread_id, resume_message (optional)
build_codex_resume_command() {
  local thread_id="$1"
  local message="${2:-continue from where you left off}"

  echo "codex" "exec" "resume" "$thread_id" "$message"
}

# Extract thread/session ID from Codex JSON output
# Arguments: output_text
extract_codex_thread_id() {
  local output="$1"
  echo "$output" | grep -oE '"thread_id":\s*"[^"]*"' | sed 's/"thread_id":\s*"//' | sed 's/"$//' | head -1 || true
}

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

init_cmd() {
  local repo="$1"
  local force="$2"
  local superloop_dir="$repo/.superloop"

  mkdir -p "$superloop_dir/roles" "$superloop_dir/loops" "$superloop_dir/logs" "$superloop_dir/specs"

  if [[ -f "$superloop_dir/config.json" && $force -ne 1 ]]; then
    die "found existing $superloop_dir/config.json (use --force to overwrite)"
  fi

  cat > "$superloop_dir/config.json" <<'EOF'
{
  "runners": {
    "codex": {
      "command": ["codex", "exec"],
      "args": ["--full-auto", "-C", "{repo}", "--output-last-message", "{last_message_file}", "-"],
      "prompt_mode": "stdin"
    },
    "claude-vanilla": {
      "command": ["claude-vanilla"],
      "args": ["--dangerously-skip-permissions", "--print", "-C", "{repo}", "-"],
      "prompt_mode": "stdin"
    },
    "claude-glm-mantic": {
      "command": ["claude-glm-mantic"],
      "args": ["--dangerously-skip-permissions", "--print", "-C", "{repo}", "-"],
      "prompt_mode": "stdin"
    }
  },
  "loops": [
    {
      "id": "initiation",
      "spec_file": ".superloop/specs/initiation.md",
      "max_iterations": 20,
      "completion_promise": "SUPERLOOP_COMPLETE",
      "checklists": [],
      "tests": {
        "mode": "on_promise",
        "commands": []
      },
      "evidence": {
        "enabled": true,
        "require_on_completion": true,
        "artifacts": []
      },
      "approval": {
        "enabled": false,
        "require_on_completion": true
      },
      "reviewer_packet": {
        "enabled": true
      },
      "timeouts": {
        "enabled": true,
        "default": 900,
        "planner": 300,
        "implementer": 900,
        "tester": 300,
        "reviewer": 1200
      },
      "stuck": {
        "enabled": true,
        "threshold": 3,
        "action": "report_and_stop",
        "ignore": [
          ".superloop/**",
          ".git/**",
          "node_modules/**",
          "dist/**",
          "build/**",
          "coverage/**",
          ".next/**",
          ".venv/**",
          ".tox/**",
          ".cache/**"
        ]
      },
      "roles": {
        "planner": {"runner": "codex"},
        "implementer": {"runner": "claude-vanilla"},
        "tester": {"runner": "claude-glm-mantic"},
        "reviewer": {"runner": "codex"}
      }
    }
  ]
}
EOF

  cat > "$superloop_dir/specs/initiation.md" <<'EOF'
# Feature: [Your Feature Name]

## Overview

Replace this with a description of what you're building and why.

Use `/construct-superloop` in Claude Code for guided spec creation.

## Requirements

- [ ] REQ-1: [First requirement]
- [ ] REQ-2: [Second requirement]

## Technical Approach

[Describe the implementation approach]

## Acceptance Criteria

- [ ] AC-1: When [action], then [expected result]
- [ ] AC-2: When [action], then [expected result]

## Constraints

- **Performance**: [requirements]
- **Security**: [requirements]
- **Compatibility**: [requirements]

## Out of Scope

- [What's not included]
EOF

  cat > "$superloop_dir/roles/planner.md" <<'EOF'
You are the Planner.

## Responsibilities

### First Iteration (Initiation)

If PLAN.MD does not exist or is empty, create the full feature plan:

**Create PLAN.MD** with this structure:
```markdown
# {Feature Name}

## Goal
{Main objective - one clear sentence}

## Scope
- {What's included}
- {What's included}

## Non-Goals (this iteration)
- {Explicitly out of scope}

## Primary References
- {Key file}: {purpose}

## Architecture
{High-level description of components and their interactions}

## Decisions
- {Key decision and rationale}

## Risks / Constraints
- {Known risk or constraint}

## Phases
- **Phase 1**: {Brief description}
- **Phase 2**: {Brief description} (if applicable)
```

**Create tasks/PHASE_1.MD** with atomic tasks:
```markdown
# Phase 1 - {Phase Title}

## P1.1 {Task Group Name}
1. [ ] {Atomic task with file path}
2. [ ] {Atomic task with file path}
   1. [ ] {Sub-task}
   2. [ ] {Sub-task}

## P1.2 {Task Group Name}
1. [ ] {Atomic task}
2. [ ] {Atomic task}

## P1.V Validation
1. [ ] {Validation criterion}
```

### Subsequent Iterations

1. Read the current PLAN.MD and active PHASE file.
2. Review iteration notes for blockers or test failures.
3. If current phase has unchecked tasks, no changes needed.
4. If current phase is complete (all `[x]`), create the next PHASE file.
5. Update PLAN.MD only if scope, decisions, or architecture must change.

## Atomic Task Format

Tasks use hierarchical numbering for deep referenceability:
- `P1.1` = Phase 1, Task Group 1
- `P1.1.3` = Phase 1, Task Group 1, Task 3
- `P1.1.3.2` = Sub-task 2 of Task 3

Each task MUST:
- Be a single, verifiable unit of work
- Include the target file path when modifying code
- Use `[ ]` checkbox format for tracking
- Be completable by the implementer in one pass

Example:
```markdown
## P1.2 API Endpoint Setup
1. [ ] Create `src/api/users.ts` with GET /users endpoint
2. [ ] Add authentication middleware to `src/middleware/auth.ts`
   1. [ ] Implement JWT validation
   2. [ ] Add role-based access check
3. [ ] Wire endpoint in `src/routes/index.ts`
```

## Rules

- Do NOT modify code or run tests.
- Do NOT output a promise tag.
- Create the `tasks/` directory and PHASE files as needed.
- Minimize churn: do not rewrite completed tasks or unchanged sections.
- Keep tasks atomic: if a task feels too big, break it into sub-tasks.
- Write PLAN.MD to the plan file path listed in context.
- Write PHASE files to the tasks/ directory under the loop directory.
EOF

  cat > "$superloop_dir/roles/implementer.md" <<'EOF'
You are the Implementer.

## Responsibilities

1. Read PLAN.MD for context, architecture, and decisions.
2. Read the active PHASE file (in tasks/ directory) for current tasks.
3. Work through unchecked tasks (`[ ]`) in order.
4. Check off tasks as you complete them: change `[ ]` to `[x]`.
5. Write implementation notes to the implementer report.

## Workflow

1. Find the first unchecked task in the active PHASE file.
2. Implement that task completely.
3. Mark it `[x]` in the PHASE file.
4. Repeat until all tasks are checked or you hit a blocker.

## Task Completion

When you complete a task, update the PHASE file:

Before:
```markdown
1. [ ] Create `src/api/users.ts` with GET /users endpoint
```

After:
```markdown
1. [x] Create `src/api/users.ts` with GET /users endpoint
```

## Rules

- Do NOT edit the spec or PLAN.MD (only the planner modifies those).
- Do NOT run tests (the wrapper handles that).
- Do NOT output a promise tag.
- DO update PHASE files to check off completed tasks.
- Work through tasks in order unless blocked.
- If blocked, note the blocker and move to the next unblocked task.
- Write your summary to the implementer report file path listed in context.

## Implementer Report Format

Always include these sections:

```markdown
## Tasks Completed
- P1.2.1: Created src/api/users.ts
- P1.2.2: Added auth middleware

## Files Touched
- CREATED: src/api/users.ts
- MODIFIED: src/middleware/auth.ts

## Blockers (if any)
- P1.2.3: Blocked on missing database schema

## Notes
- Additional context for the next iteration
```
EOF

  cat > "$superloop_dir/roles/tester.md" <<'EOF'
You are the Quality Engineer.

## Responsibilities

### Analysis (always)
- Read automated test results from test-status.json and test-output.txt.
- Read validation results (preflight, smoke tests, agent-browser) if present.
- Summarize failures, identify patterns, and note gaps in test coverage.

### Exploration (when browser tools are available)
- Use agent-browser to verify the implementation works correctly.
- Focus on areas NOT covered by automated tests.
- Check user-facing flows from a fresh perspective.
- Look for issues the implementer may have missed:
  - Broken interactions
  - Missing error handling
  - Incorrect behavior
  - Visual/layout problems
- Document findings with screenshots when useful.

## Browser Testing Workflow

When agent-browser is available:

1. `agent-browser open <url>` - Navigate to the application
2. `agent-browser snapshot -i` - Get interactive elements with refs
3. Interact using refs: `click @e1`, `fill @e2 "text"`, `select @e3 "option"`
4. `agent-browser screenshot <path>` - Capture state when needed
5. Re-snapshot after page changes to get new refs.

## Rules
- Do NOT modify code.
- Do NOT run automated test suites (the wrapper handles that).
- Do NOT re-verify things automated tests already cover well.
- Focus exploration on gaps and user-facing behavior.
- Report issues with clear reproduction steps.
- Do not output a promise tag.
- Minimize report churn: if findings are unchanged, do not edit the report.
- Write your report to the test report file path listed in context.
EOF

  cat > "$superloop_dir/roles/reviewer.md" <<'EOF'
You are the Reviewer.

Responsibilities:
- Read the reviewer packet first (if present), then verify against the spec as needed.
- Read the checklist status, test status, and reports.
- Validate that requirements are met and gates are green.
- Write a short review report.

Rules:
- Do not modify code.
- Only output <promise>...</promise> if tests pass, checklists are complete, and the spec is satisfied.
- Minimize report churn: if the review report already reflects the current state and no gates changed, do not edit it.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged text).
- Write your review to the reviewer report file path listed in context.
EOF

  # Install Claude Code skill for agent-browser
  local claude_skills_dir="$repo/.claude/skills/agent-browser"
  mkdir -p "$claude_skills_dir"
  cat > "$claude_skills_dir/SKILL.md" <<'EOF'
---
name: agent-browser
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when you need to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
---

# Browser Automation with agent-browser

## Quick start

```bash
agent-browser open <url>        # Navigate to page
agent-browser snapshot -i       # Get interactive elements with refs
agent-browser click @e1         # Click element by ref
agent-browser fill @e2 "text"   # Fill input by ref
agent-browser close             # Close browser
```

## Core workflow

1. Navigate: `agent-browser open <url>`
2. Snapshot: `agent-browser snapshot -i` (returns elements with refs like `@e1`, `@e2`)
3. Interact using refs from the snapshot
4. Re-snapshot after navigation or significant DOM changes

## Commands

### Navigation
```bash
agent-browser open <url>      # Navigate to URL
agent-browser back            # Go back
agent-browser forward         # Go forward
agent-browser reload          # Reload page
agent-browser close           # Close browser
```

### Snapshot (page analysis)
```bash
agent-browser snapshot        # Full accessibility tree
agent-browser snapshot -i     # Interactive elements only (recommended)
agent-browser snapshot -c     # Compact output
agent-browser snapshot -d 3   # Limit depth to 3
```

### Interactions (use @refs from snapshot)
```bash
agent-browser click @e1           # Click
agent-browser dblclick @e1        # Double-click
agent-browser fill @e2 "text"     # Clear and type
agent-browser type @e2 "text"     # Type without clearing
agent-browser press Enter         # Press key
agent-browser press Control+a     # Key combination
agent-browser hover @e1           # Hover
agent-browser check @e1           # Check checkbox
agent-browser uncheck @e1         # Uncheck checkbox
agent-browser select @e1 "value"  # Select dropdown
agent-browser scroll down 500     # Scroll page
agent-browser scrollintoview @e1  # Scroll element into view
```

### Get information
```bash
agent-browser get text @e1        # Get element text
agent-browser get value @e1       # Get input value
agent-browser get title           # Get page title
agent-browser get url             # Get current URL
```

### Screenshots
```bash
agent-browser screenshot          # Screenshot to stdout
agent-browser screenshot path.png # Save to file
agent-browser screenshot --full   # Full page
```

### Wait
```bash
agent-browser wait @e1                     # Wait for element
agent-browser wait 2000                    # Wait milliseconds
agent-browser wait --text "Success"        # Wait for text
agent-browser wait --load networkidle      # Wait for network idle
```

### Semantic locators (alternative to refs)
```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign In" click
agent-browser find label "Email" fill "user@test.com"
```

## Example: Form submission

```bash
agent-browser open https://example.com/form
agent-browser snapshot -i
# Output shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Submit" [ref=e3]

agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait --load networkidle
agent-browser snapshot -i  # Check result
```

## Example: Authentication with saved state

```bash
# Login once
agent-browser open https://app.example.com/login
agent-browser snapshot -i
agent-browser fill @e1 "username"
agent-browser fill @e2 "password"
agent-browser click @e3
agent-browser wait --url "**/dashboard"
agent-browser state save auth.json

# Later sessions: load saved state
agent-browser state load auth.json
agent-browser open https://app.example.com/dashboard
```

## Sessions (parallel browsers)

```bash
agent-browser --session test1 open site-a.com
agent-browser --session test2 open site-b.com
agent-browser session list
```

## JSON output (for parsing)

Add `--json` for machine-readable output:
```bash
agent-browser snapshot -i --json
agent-browser get text @e1 --json
```

## Debugging

```bash
agent-browser open example.com --headed  # Show browser window
agent-browser console                    # View console messages
agent-browser errors                     # View page errors
```
EOF

  echo "Initialized .superloop in $superloop_dir"
  echo "Installed agent-browser skill in $claude_skills_dir"
}

list_cmd() {
  local repo="$1"
  local config_path="$2"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path (run 'superloop init' first)"
  fi

  local superloop_dir="$repo/.superloop"
  local state_file="$superloop_dir/state.json"
  local current_loop_id=""
  local is_active="false"

  # Read current state if exists
  if [[ -f "$state_file" ]]; then
    current_loop_id=$(jq -r '.current_loop_id // ""' "$state_file")
    is_active=$(jq -r '.active // false' "$state_file")
  fi

  # Get loop count
  local loop_count
  loop_count=$(jq '.loops | length' "$config_path")

  if [[ "$loop_count" -eq 0 ]]; then
    echo "No loops configured."
    return 0
  fi

  echo "Loops in $config_path:"
  echo ""
  printf "%-20s %-12s %-40s %s\n" "ID" "STATUS" "SPEC" "LAST RUN"
  printf "%-20s %-12s %-40s %s\n" "--------------------" "------------" "----------------------------------------" "-------------------"

  local i=0
  while [[ $i -lt $loop_count ]]; do
    local loop_json loop_id spec_file status last_run
    loop_json=$(jq -c ".loops[$i]" "$config_path")
    loop_id=$(jq -r '.id' <<<"$loop_json")
    spec_file=$(jq -r '.spec_file' <<<"$loop_json")

    # Determine status
    local loop_dir="$superloop_dir/loops/$loop_id"
    local run_summary="$loop_dir/run-summary.json"

    if [[ "$is_active" == "true" && "$current_loop_id" == "$loop_id" ]]; then
      status="RUNNING"
    elif [[ -f "$run_summary" ]]; then
      # Check if completed
      local last_completion
      last_completion=$(jq -r '.[-1].completion_ok // false' "$run_summary" 2>/dev/null || echo "false")
      if [[ "$last_completion" == "true" ]]; then
        status="COMPLETED"
      else
        status="STOPPED"
      fi
    elif [[ -d "$loop_dir" ]]; then
      status="STARTED"
    else
      status="NOT STARTED"
    fi

    # Get last run time
    if [[ -f "$run_summary" ]]; then
      last_run=$(jq -r '.[-1].ended_at // .[-1].started_at // "unknown"' "$run_summary" 2>/dev/null || echo "-")
      # Truncate to just date and time
      last_run="${last_run:0:19}"
    else
      last_run="-"
    fi

    # Truncate long values for display
    local display_id="${loop_id:0:20}"
    local display_spec="${spec_file:0:40}"

    printf "%-20s %-12s %-40s %s\n" "$display_id" "$status" "$display_spec" "$last_run"

    ((i++))
  done

  echo ""
  echo "Total: $loop_count loop(s)"
}

run_cmd() {
  local repo="$1"
  local config_path="$2"
  local target_loop_id="$3"
  local fast_mode="$4"
  local dry_run="$5"

  need_cmd jq

  local superloop_dir="$repo/.superloop"
  local state_file="$superloop_dir/state.json"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi

  local loop_count
  loop_count=$(jq '.loops | length' "$config_path")
  if [[ "$loop_count" == "0" ]]; then
    die "config has no loops"
  fi

  # Check if using runners registry (per-role) or single runner (legacy)
  local has_runners_registry
  has_runners_registry=$(jq -r 'if .runners then "true" else "false" end' "$config_path")
  local runners_json=""
  if [[ "$has_runners_registry" == "true" ]]; then
    runners_json=$(jq -c '.runners // {}' "$config_path")
  fi

  # Parse default runner (legacy mode or fallback)
  local -a default_runner_command=()
  while IFS= read -r line; do
    default_runner_command+=("$line")
  done < <(jq -r '.runner.command[]?' "$config_path")

  local -a default_runner_args=()
  while IFS= read -r line; do
    default_runner_args+=("$line")
  done < <(jq -r '.runner.args[]?' "$config_path")

  local -a default_runner_fast_args=()
  while IFS= read -r line; do
    default_runner_fast_args+=("$line")
  done < <(jq -r '.runner.fast_args[]?' "$config_path")

  local default_runner_prompt_mode
  default_runner_prompt_mode=$(jq -r '.runner.prompt_mode // "stdin"' "$config_path")

  # Validate: must have either runner or runners
  if [[ ${#default_runner_command[@]} -eq 0 && "$has_runners_registry" != "true" ]]; then
    die "either runner.command or runners registry is required"
  fi

  if [[ "$default_runner_prompt_mode" != "stdin" && "$default_runner_prompt_mode" != "file" ]]; then
    default_runner_prompt_mode="stdin"
  fi

  # Helper function to get runner config for a role
  get_runner_for_role() {
    local role="$1"
    local role_runner_name="$2"  # From roles config, may be empty
    local runner_name=""

    # If role has explicit runner assignment, use it
    if [[ -n "$role_runner_name" ]]; then
      runner_name="$role_runner_name"
    fi

    # If we have a runner name and runners registry, look it up
    if [[ -n "$runner_name" && -n "$runners_json" ]]; then
      local runner_config
      runner_config=$(jq -c --arg name "$runner_name" '.[$name] // empty' <<<"$runners_json")
      if [[ -n "$runner_config" ]]; then
        echo "$runner_config"
        return 0
      else
        echo "warning: runner '$runner_name' not found in registry, using default" >&2
      fi
    fi

    # Fall back to default runner
    if [[ ${#default_runner_command[@]} -gt 0 ]]; then
      jq -n \
        --argjson cmd "$(printf '%s\n' "${default_runner_command[@]}" | jq -R . | jq -s .)" \
        --argjson args "$(printf '%s\n' "${default_runner_args[@]}" | jq -R . | jq -s .)" \
        --argjson fast_args "$(printf '%s\n' "${default_runner_fast_args[@]}" | jq -R . | jq -s .)" \
        --arg prompt_mode "$default_runner_prompt_mode" \
        '{command: $cmd, args: $args, fast_args: $fast_args, prompt_mode: $prompt_mode}'
      return 0
    fi

    return 1
  }

  # For backward compatibility, set up default runner variables
  local -a runner_command=("${default_runner_command[@]}")
  local -a runner_args=("${default_runner_args[@]}")
  local -a runner_fast_args=("${default_runner_fast_args[@]}")
  local runner_prompt_mode="$default_runner_prompt_mode"

  if [[ "${dry_run:-0}" -ne 1 && ${#runner_command[@]} -gt 0 ]]; then
    need_exec "${runner_command[0]}"
  fi

  local -a runner_active_args=("${runner_args[@]}")
  if [[ "${fast_mode:-0}" -eq 1 ]]; then
    if [[ ${#runner_fast_args[@]} -gt 0 ]]; then
      runner_active_args=("${runner_fast_args[@]}")
    elif [[ ${#runner_args[@]} -gt 0 ]]; then
      echo "warning: --fast set but runner.fast_args is empty; using runner.args" >&2
    fi
  fi

  local loop_index=0
  local iteration=1
  if [[ "${dry_run:-0}" -ne 1 && -f "$state_file" ]]; then
    loop_index=$(jq -r '.loop_index // 0' "$state_file")
    iteration=$(jq -r '.iteration // 1' "$state_file")
    local active
    active=$(jq -r '.active // true' "$state_file")
    if [[ "$active" != "true" ]]; then
      loop_index=0
      iteration=1
    fi
  fi

  if [[ -n "$target_loop_id" ]]; then
    local found_index
    found_index=$(jq -r --arg id "$target_loop_id" '.loops | to_entries[] | select(.value.id == $id) | .key' "$config_path" | head -n1)
    if [[ -z "$found_index" ]]; then
      die "loop id not found: $target_loop_id"
    fi
    loop_index="$found_index"
    iteration=1
  fi

  for ((i=loop_index; i<loop_count; i++)); do
    local loop_json loop_id spec_file max_iterations completion_promise
    loop_json=$(jq -c ".loops[$i]" "$config_path")
    loop_id=$(jq -r '.id' <<<"$loop_json")

    if [[ -n "$target_loop_id" && "$loop_id" != "$target_loop_id" ]]; then
      continue
    fi

    spec_file=$(jq -r '.spec_file' <<<"$loop_json")
    max_iterations=$(jq -r '.max_iterations // 0' <<<"$loop_json")
    completion_promise=$(jq -r '.completion_promise // ""' <<<"$loop_json")

    if [[ -z "$spec_file" || "$spec_file" == "null" ]]; then
      die "loop '$loop_id' missing spec_file"
    fi
    if [[ ! -f "$repo/$spec_file" ]]; then
      die "spec file not found: $spec_file"
    fi

    local loop_dir="$superloop_dir/loops/$loop_id"
    local role_dir="$superloop_dir/roles"
    local prompt_dir="$loop_dir/prompts"
    local log_dir="$loop_dir/logs/iter-$iteration"
    local last_messages_dir="$loop_dir/last_messages"

    local plan_file="$loop_dir/plan.md"
    local notes_file="$loop_dir/iteration_notes.md"
    local implementer_report="$loop_dir/implementer.md"
    local reviewer_report="$loop_dir/review.md"
    local test_output="$loop_dir/test-output.txt"
    local test_status="$loop_dir/test-status.json"
    local test_report="$loop_dir/test-report.md"
    local validation_status_file="$loop_dir/validation-status.json"
    local validation_results_file="$loop_dir/validation-results.json"
    local checklist_status="$loop_dir/checklist-status.json"
    local checklist_remaining="$loop_dir/checklist-remaining.md"
    local evidence_file="$loop_dir/evidence.json"
    local reviewer_packet="$loop_dir/reviewer-packet.md"
    local summary_file="$loop_dir/gate-summary.txt"
    local events_file="$loop_dir/events.jsonl"
    local run_summary_file="$loop_dir/run-summary.json"
    local timeline_file="$loop_dir/timeline.md"
    local approval_file="$loop_dir/approval.json"
    local decisions_jsonl="$loop_dir/decisions.jsonl"
    local decisions_md="$loop_dir/decisions.md"
    local changed_files_planner="$loop_dir/changed-files-planner.txt"
    local changed_files_implementer="$loop_dir/changed-files-implementer.txt"
    local changed_files_all="$loop_dir/changed-files-all.txt"
    local usage_file="$loop_dir/usage.jsonl"

    local tasks_dir="$loop_dir/tasks"
    mkdir -p "$loop_dir" "$prompt_dir" "$log_dir" "$tasks_dir"
    touch "$plan_file" "$notes_file" "$implementer_report" "$reviewer_report" "$test_report"

    # Parse roles - can be array or object with runner assignments
    local roles_type
    roles_type=$(jq -r '.roles | type' <<<"$loop_json")
    local -a roles=()
    local roles_config_json="{}"

    if [[ "$roles_type" == "array" ]]; then
      # Legacy array format: ["planner", "implementer", "tester", "reviewer"]
      while IFS= read -r line; do
        roles+=("$line")
      done < <(jq -r '.roles[]?' <<<"$loop_json")
    elif [[ "$roles_type" == "object" ]]; then
      # New object format: {"planner": {"runner": "codex"}, ...}
      roles_config_json=$(jq -c '.roles' <<<"$loop_json")
      while IFS= read -r line; do
        roles+=("$line")
      done < <(jq -r '.roles | keys[]' <<<"$loop_json")
    fi

    if [[ ${#roles[@]} -eq 0 ]]; then
      roles=(planner implementer tester reviewer)
    fi

    # Helper to get runner name for a role from roles config
    get_role_runner_name() {
      local role="$1"
      if [[ "$roles_type" == "object" ]]; then
        jq -r --arg role "$role" '.[$role].runner // empty' <<<"$roles_config_json"
      fi
    }

    # Helper to get model for a role (from role config, then role_defaults)
    get_role_model() {
      local role="$1"
      local model=""
      if [[ "$roles_type" == "object" ]]; then
        model=$(jq -r --arg role "$role" '.[$role].model // empty' <<<"$roles_config_json")
      fi
      if [[ -z "$model" ]]; then
        model=$(jq -r --arg role "$role" '.role_defaults[$role].model // empty' "$config_path")
      fi
      echo "$model"
    }

    # Helper to get thinking level for a role (from role config, then role_defaults)
    get_role_thinking() {
      local role="$1"
      local thinking=""
      if [[ "$roles_type" == "object" ]]; then
        thinking=$(jq -r --arg role "$role" '.[$role].thinking // empty' <<<"$roles_config_json")
      fi
      if [[ -z "$thinking" ]]; then
        thinking=$(jq -r --arg role "$role" '.role_defaults[$role].thinking // empty' "$config_path")
      fi
      echo "$thinking"
    }

    # Map thinking level to runner-specific flags
    # Returns flags to append to command args
    get_thinking_flags() {
      local runner_type="$1"  # "codex" or "claude"
      local thinking="$2"     # none|minimal|low|standard|high|max

      if [[ -z "$thinking" || "$thinking" == "null" ]]; then
        return 0
      fi

      case "$runner_type" in
        codex)
          # Map to Codex reasoning_effort
          local effort=""
          case "$thinking" in
            none)     effort="none" ;;
            minimal)  effort="minimal" ;;
            low)      effort="low" ;;
            standard) effort="medium" ;;
            high)     effort="high" ;;
            max)      effort="xhigh" ;;
          esac
          if [[ -n "$effort" ]]; then
            echo "-c"
            echo "model_reasoning_effort=\"$effort\""
          fi
          ;;
        claude)
          # Map to Claude thinking_mode and thinking_budget
          local mode="" budget=""
          case "$thinking" in
            none)     mode="quick" ;;
            minimal)  mode="quick" ;;
            low)      mode="extended"; budget="4096" ;;
            standard) mode="extended"; budget="8192" ;;
            high)     mode="extended"; budget="16384" ;;
            max)      mode="extended"; budget="32768" ;;
          esac
          if [[ -n "$mode" ]]; then
            echo "--thinking-mode"
            echo "$mode"
          fi
          if [[ -n "$budget" ]]; then
            echo "--thinking-budget"
            echo "$budget"
          fi
          ;;
      esac
    }

    # Detect runner type from command
    detect_runner_type_from_cmd() {
      local cmd="$1"
      case "$cmd" in
        codex*) echo "codex" ;;
        claude*) echo "claude" ;;
        *) echo "unknown" ;;
      esac
    }

    local -a checklist_patterns=()
    while IFS= read -r line; do
      checklist_patterns+=("$line")
    done < <(jq -r '.checklists[]?' <<<"$loop_json")
    local checklist_patterns_json
    checklist_patterns_json=$(jq -c '.checklists // []' <<<"$loop_json")

    local tests_mode
    tests_mode=$(jq -r '.tests.mode // "disabled"' <<<"$loop_json")
    local -a test_commands=()
    while IFS= read -r line; do
      test_commands+=("$line")
    done < <(jq -r '.tests.commands[]?' <<<"$loop_json")
    local test_commands_json
    test_commands_json=$(jq -c '.tests.commands // []' <<<"$loop_json")

    if [[ ${#test_commands[@]} -eq 0 ]]; then
      tests_mode="disabled"
    fi

    local validation_enabled
    validation_enabled=$(jq -r '.validation.enabled // false' <<<"$loop_json")
    local validation_mode
    validation_mode=$(jq -r '.validation.mode // "every"' <<<"$loop_json")
    local validation_require
    validation_require=$(jq -r '.validation.require_on_completion // false' <<<"$loop_json")

    local evidence_enabled
    evidence_enabled=$(jq -r '.evidence.enabled // false' <<<"$loop_json")
    local evidence_require
    evidence_require=$(jq -r '.evidence.require_on_completion // false' <<<"$loop_json")

    local approval_enabled
    approval_enabled=$(jq -r '.approval.enabled // false' <<<"$loop_json")
    local approval_require
    approval_require=$(jq -r '.approval.require_on_completion // false' <<<"$loop_json")

    local timeouts_enabled
    timeouts_enabled=$(jq -r '.timeouts.enabled // false' <<<"$loop_json")
    local timeout_default
    timeout_default=$(jq -r '.timeouts.default // 0' <<<"$loop_json")
    local timeout_planner
    timeout_planner=$(jq -r '.timeouts.planner // 0' <<<"$loop_json")
    local timeout_implementer
    timeout_implementer=$(jq -r '.timeouts.implementer // 0' <<<"$loop_json")
    local timeout_tester
    timeout_tester=$(jq -r '.timeouts.tester // 0' <<<"$loop_json")
    local timeout_reviewer
    timeout_reviewer=$(jq -r '.timeouts.reviewer // 0' <<<"$loop_json")
    local timeout_inactivity
    timeout_inactivity=$(jq -r '.timeouts.inactivity // 0' <<<"$loop_json")

    # Usage check settings (enabled by default - gracefully degrades if no credentials)
    local usage_check_enabled
    usage_check_enabled=$(jq -r '.usage_check.enabled // true' <<<"$loop_json")
    local usage_warn_threshold
    usage_warn_threshold=$(jq -r '.usage_check.warn_threshold // 70' <<<"$loop_json")
    local usage_block_threshold
    usage_block_threshold=$(jq -r '.usage_check.block_threshold // 95' <<<"$loop_json")
    local usage_wait_on_limit
    usage_wait_on_limit=$(jq -r '.usage_check.wait_on_limit // false' <<<"$loop_json")
    local usage_wait_max_seconds
    usage_wait_max_seconds=$(jq -r '.usage_check.max_wait_seconds // 7200' <<<"$loop_json")

    local reviewer_packet_enabled
    reviewer_packet_enabled=$(jq -r '.reviewer_packet.enabled // false' <<<"$loop_json")

    local tester_exploration_json
    tester_exploration_json=$(jq -c '.tester_exploration // {}' <<<"$loop_json")

    local stuck_enabled
    stuck_enabled=$(jq -r '.stuck.enabled // false' <<<"$loop_json")
    local stuck_threshold
    stuck_threshold=$(jq -r '.stuck.threshold // 0' <<<"$loop_json")
    local stuck_action
    stuck_action=$(jq -r '.stuck.action // "report_and_stop"' <<<"$loop_json")
    local -a stuck_ignore=()
    while IFS= read -r line; do
      stuck_ignore+=("$line")
    done < <(jq -r '.stuck.ignore[]?' <<<"$loop_json")
    if [[ ${#stuck_ignore[@]} -eq 0 ]]; then
      stuck_ignore=("${DEFAULT_STUCK_IGNORE[@]}")
    fi
    if [[ "$stuck_threshold" -le 0 ]]; then
      stuck_enabled="false"
    fi

    if [[ "$reviewer_packet_enabled" != "true" ]]; then
      reviewer_packet=""
    fi

    if [[ "${dry_run:-0}" -eq 1 ]]; then
      local promise_status="n/a"
      if [[ -n "$completion_promise" ]]; then
        local reviewer_last_message="$loop_dir/last_messages/reviewer.txt"
        if [[ -f "$reviewer_last_message" ]]; then
          local promise_text
          promise_text=$(extract_promise "$reviewer_last_message")
          if [[ -n "$promise_text" ]]; then
            if [[ "$promise_text" == "$completion_promise" ]]; then
              promise_status="true"
            else
              promise_status="false"
            fi
          else
            promise_status="unknown"
          fi
        else
          promise_status="unknown"
        fi
      fi

      local tests_status validation_status checklist_status_text evidence_status stuck_value
      tests_status=$(read_test_status_summary "$test_status")
      validation_status=$(read_validation_status_summary "$validation_status_file")
      checklist_status_text=$(read_checklist_status_summary "$checklist_status")
      if [[ "$evidence_enabled" == "true" ]]; then
        if [[ -f "$evidence_file" ]]; then
          evidence_status="ok"
        else
          evidence_status="missing"
        fi
      else
        evidence_status="skipped"
      fi
      stuck_value="n/a"
      if [[ "$stuck_enabled" == "true" ]]; then
        local stuck_streak_read
        stuck_streak_read=$(read_stuck_streak "$loop_dir/stuck.json")
        stuck_value="${stuck_streak_read}/${stuck_threshold}"
      fi

      local approval_status="none"
      if [[ "$approval_enabled" == "true" && -f "$approval_file" ]]; then
        approval_status=$(read_approval_status "$approval_file")
      fi

      echo "Dry-run summary ($loop_id): promise=$promise_status tests=$tests_status validation=$validation_status checklist=$checklist_status_text evidence=$evidence_status approval=$approval_status stuck=$stuck_value"
      if [[ -n "$target_loop_id" && "$loop_id" == "$target_loop_id" ]]; then
        return 0
      fi
      continue
    fi

    local run_id
    run_id=$(timestamp)
    local loop_start_data
    loop_start_data=$(jq -n \
      --arg spec_file "$spec_file" \
      --argjson max_iterations "$max_iterations" \
      --arg tests_mode "$tests_mode" \
      --argjson test_commands "$test_commands_json" \
      --argjson checklists "$checklist_patterns_json" \
      '{spec_file: $spec_file, max_iterations: $max_iterations, tests_mode: $tests_mode, test_commands: $test_commands, checklists: $checklists}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_start" "$loop_start_data"

    local approval_required=0
    if [[ "$approval_enabled" == "true" && "$approval_require" == "true" ]]; then
      approval_required=1
    fi

    if [[ "$approval_enabled" == "true" ]]; then
      local approval_state
      approval_state=$(read_approval_status "$approval_file")
      if [[ "$approval_state" == "pending" ]]; then
        local approval_wait_data
        approval_wait_data=$(jq -n --arg approval_file "${approval_file#$repo/}" '{status: "pending", approval_file: $approval_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_wait" "$approval_wait_data"
        echo "Approval pending for loop '$loop_id'. Run: superloop.sh approve --repo $repo --loop $loop_id"
        if [[ "${dry_run:-0}" -ne 1 ]]; then
          write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
        fi
        return 0
      elif [[ "$approval_state" == "approved" ]]; then
        local approval_run_id approval_iteration approval_promise_text approval_promise_matched
        local approval_tests approval_validation approval_checklist approval_evidence approval_started_at approval_ended_at
        local approval_decision_by approval_decision_note approval_decision_at
        approval_run_id=$(jq -r '.run_id // ""' "$approval_file")
        approval_iteration=$(jq -r '.iteration // 0' "$approval_file")
        approval_promise_text=$(jq -r '.candidate.promise.text // ""' "$approval_file")
        approval_promise_matched=$(jq -r '.candidate.promise.matched // false' "$approval_file")
        approval_tests=$(jq -r '.candidate.gates.tests // "unknown"' "$approval_file")
        approval_validation=$(jq -r '.candidate.gates.validation // "unknown"' "$approval_file")
        approval_checklist=$(jq -r '.candidate.gates.checklist // "unknown"' "$approval_file")
        approval_evidence=$(jq -r '.candidate.gates.evidence // "unknown"' "$approval_file")
        approval_started_at=$(jq -r '.iteration_started_at // ""' "$approval_file")
        approval_ended_at=$(jq -r '.iteration_ended_at // ""' "$approval_file")
        approval_decision_by=$(jq -r '.decision.by // ""' "$approval_file")
        approval_decision_note=$(jq -r '.decision.note // ""' "$approval_file")
        approval_decision_at=$(jq -r '.decision.at // ""' "$approval_file")

        if [[ -z "$approval_run_id" || "$approval_run_id" == "null" ]]; then
          approval_run_id="$run_id"
        fi
        if [[ "$approval_iteration" -le 0 ]]; then
          approval_iteration="$iteration"
        fi
        if [[ -z "$approval_started_at" || "$approval_started_at" == "null" ]]; then
          approval_started_at=$(timestamp)
        fi
        if [[ -z "$approval_ended_at" || "$approval_ended_at" == "null" ]]; then
          approval_ended_at="$approval_started_at"
        fi

        local promise_matched="$approval_promise_matched"
        if [[ "$promise_matched" != "true" ]]; then
          promise_matched="false"
        fi
        local tests_status="$approval_tests"
        local validation_status="$approval_validation"
        local checklist_status_text="$approval_checklist"
        local evidence_status="$approval_evidence"
        local approval_status="approved"

        local stuck_streak="0"
        if [[ "$stuck_enabled" == "true" ]]; then
          stuck_streak=$(read_stuck_streak "$loop_dir/stuck.json")
        fi
        local stuck_value="n/a"
        if [[ "$stuck_enabled" == "true" ]]; then
          stuck_value="${stuck_streak}/${stuck_threshold}"
        fi

        write_iteration_notes "$notes_file" "$loop_id" "$approval_iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
        write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"

        local approval_consume_data
        approval_consume_data=$(jq -n \
          --arg status "approved" \
          --arg by "$approval_decision_by" \
          --arg note "$approval_decision_note" \
          --arg at "$approval_decision_at" \
          '{status: $status, by: (if ($by | length) > 0 then $by else null end), note: (if ($note | length) > 0 then $note else null end), at: (if ($at | length) > 0 then $at else null end)}')
        log_event "$events_file" "$loop_id" "$approval_iteration" "$approval_run_id" "approval_consumed" "$approval_consume_data"

        local completion_ok=1
        append_run_summary "$run_summary_file" "$repo" "$loop_id" "$approval_run_id" "$approval_iteration" "$approval_started_at" "$approval_ended_at" "$promise_matched" "$completion_promise" "$approval_promise_text" "$tests_mode" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$approval_status" "$stuck_streak" "$stuck_threshold" "$completion_ok" "$loop_dir" "$events_file"
        write_timeline "$run_summary_file" "$timeline_file"

        local loop_complete_data
        loop_complete_data=$(jq -n \
          --argjson iteration "$approval_iteration" \
          --arg run_id "$approval_run_id" \
          '{iteration: $iteration, run_id: $run_id, approval: true}')
        log_event "$events_file" "$loop_id" "$approval_iteration" "$approval_run_id" "loop_complete" "$loop_complete_data"
        echo "Loop '$loop_id' complete at iteration $approval_iteration (approved)."
        rm -f "$approval_file"

        iteration=1
        if [[ -n "$target_loop_id" && "$loop_id" == "$target_loop_id" ]]; then
          write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
          return 0
        fi
        continue
      elif [[ "$approval_state" == "rejected" ]]; then
        local approval_reject_data
        approval_reject_data=$(jq -n --arg approval_file "${approval_file#$repo/}" '{status: "rejected", approval_file: $approval_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_rejected" "$approval_reject_data"
        rm -f "$approval_file"
      fi
    fi

    while true; do
      if [[ $max_iterations -gt 0 && $iteration -gt $max_iterations ]]; then
        echo "Max iterations reached for loop '$loop_id' ($max_iterations). Stopping."
        local loop_stop_data
        loop_stop_data=$(jq -n --arg reason "max_iterations" --argjson max_iterations "$max_iterations" '{reason: $reason, max_iterations: $max_iterations}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_stop" "$loop_stop_data"
        if [[ "${dry_run:-0}" -ne 1 ]]; then
          write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
        fi
        return 1
      fi

      if [[ "${dry_run:-0}" -ne 1 ]]; then
        write_state "$state_file" "$i" "$iteration" "$loop_id" "true"
        log_dir="$loop_dir/logs/iter-$iteration"
        mkdir -p "$log_dir" "$last_messages_dir"
      fi

      local iteration_started_at
      iteration_started_at=$(timestamp)
      local iteration_start_data
      iteration_start_data=$(jq -n --arg started_at "$iteration_started_at" '{started_at: $started_at}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "iteration_start" "$iteration_start_data"

      local last_role=""
      for role in "${roles[@]}"; do
        local role_template="$role_dir/$role.md"
        if [[ ! -f "$role_template" ]]; then
          die "missing role template: $role_template"
        fi

        local prompt_file="$prompt_dir/${role}.md"
        build_role_prompt \
          "$role" \
          "$role_template" \
          "$prompt_file" \
          "$spec_file" \
          "$plan_file" \
          "$notes_file" \
          "$implementer_report" \
          "$reviewer_report" \
          "$test_report" \
          "$test_output" \
          "$test_status" \
          "$validation_status_file" \
          "$validation_results_file" \
          "$checklist_status" \
          "$checklist_remaining" \
          "$evidence_file" \
          "$reviewer_packet" \
          "$changed_files_planner" \
          "$changed_files_implementer" \
          "$changed_files_all" \
          "$tester_exploration_json" \
          "$tasks_dir"

        if [[ "$role" == "reviewer" && "$reviewer_packet_enabled" == "true" && -n "$reviewer_packet" ]]; then
          write_reviewer_packet \
            "$loop_dir" \
            "$loop_id" \
            "$iteration" \
            "$summary_file" \
            "$test_status" \
            "$test_report" \
            "$evidence_file" \
            "$checklist_status" \
            "$checklist_remaining" \
            "$validation_status_file" \
            "$validation_results_file" \
            "$reviewer_packet"
        fi

        local last_message_file="$last_messages_dir/${role}.txt"
        local role_log="$log_dir/${role}.log"
        local report_guard=""
        local report_snapshot=""
        local role_timeout_seconds=0

        case "$role" in
          planner)
            report_guard="$plan_file"
            ;;
          implementer|openprose)
            report_guard="$implementer_report"
            ;;
          tester)
            report_guard="$test_report"
            ;;
          reviewer)
            report_guard="$reviewer_report"
            ;;
        esac
        if [[ -n "$report_guard" ]]; then
          report_snapshot="$log_dir/${role}.report.before"
          snapshot_file "$report_guard" "$report_snapshot"
        fi

        if [[ "$timeouts_enabled" == "true" ]]; then
          case "$role" in
            planner)
              role_timeout_seconds="$timeout_planner"
              ;;
            implementer)
              role_timeout_seconds="$timeout_implementer"
              ;;
            tester)
              role_timeout_seconds="$timeout_tester"
              ;;
            reviewer)
              role_timeout_seconds="$timeout_reviewer"
              ;;
            *)
              role_timeout_seconds="$timeout_default"
              ;;
          esac
          if [[ -z "${role_timeout_seconds:-}" || "$role_timeout_seconds" -le 0 ]]; then
            role_timeout_seconds="$timeout_default"
          fi
        fi

        local role_start_data
        role_start_data=$(jq -n \
          --arg prompt_file "$prompt_file" \
          --arg log_file "$role_log" \
          --arg last_message_file "$last_message_file" \
          '{prompt_file: $prompt_file, log_file: $log_file, last_message_file: $last_message_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_start" "$role_start_data" "$role"

        # Pre-flight usage check (need to know runner first)
        # Get runner for this specific role (early, for usage check)
        local early_role_runner_name
        early_role_runner_name=$(get_role_runner_name "$role")
        local early_runner_cmd=""
        if [[ -n "$early_role_runner_name" && -n "$runners_json" ]]; then
          early_runner_cmd=$(jq -r --arg name "$early_role_runner_name" '.[$name].command[0] // empty' <<<"$runners_json")
        fi
        if [[ -z "$early_runner_cmd" && ${#runner_command[@]} -gt 0 ]]; then
          early_runner_cmd="${runner_command[0]}"
        fi

        if [[ "${usage_check_enabled:-false}" == "true" ]]; then
          local runner_type_for_check=""
          case "$early_runner_cmd" in
            *claude*) runner_type_for_check="claude" ;;
            *codex*) runner_type_for_check="codex" ;;
          esac

          if [[ -n "$runner_type_for_check" ]]; then
            local usage_check_result=0
            check_usage_limits "$runner_type_for_check" "${usage_warn_threshold:-70}" "${usage_block_threshold:-95}" || usage_check_result=$?

            if [[ $usage_check_result -eq 2 ]]; then
              # Blocked by usage limits
              local usage_data
              usage_data=$(jq -n \
                --arg runner "$runner_type_for_check" \
                --arg role "$role" \
                '{runner: $runner, role: $role, action: "blocked"}')
              log_event "$events_file" "$loop_id" "$iteration" "$run_id" "usage_limit_blocked" "$usage_data" "$role" "error"

              if [[ "${usage_wait_on_limit:-false}" == "true" ]]; then
                echo "[superloop] Usage limit reached. Waiting for reset..." >&2
                # Wait up to max_wait_seconds (default 2 hours), checking every 5 minutes
                local wait_interval=300
                local wait_elapsed=0
                while true; do
                  sleep "$wait_interval"
                  wait_elapsed=$((wait_elapsed + wait_interval))
                  check_usage_limits "$runner_type_for_check" "${usage_warn_threshold:-70}" "${usage_block_threshold:-95}" || usage_check_result=$?
                  if [[ $usage_check_result -ne 2 ]]; then
                    echo "[superloop] Usage limits cleared. Resuming..." >&2
                    break
                  fi
                  if [[ "${usage_wait_max_seconds:-7200}" -gt 0 && $wait_elapsed -ge $usage_wait_max_seconds ]]; then
                    echo "[superloop] Timed out waiting for usage reset. Stopping." >&2
                    write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
                    return 1
                  fi
                  if [[ "${usage_wait_max_seconds:-7200}" -gt 0 ]]; then
                    local remaining_wait=$((usage_wait_max_seconds - wait_elapsed))
                    local remaining_text
                    remaining_text=$(format_time_until_reset "$remaining_wait" 2>/dev/null || echo "${remaining_wait}s")
                    echo "[superloop] Still waiting for usage reset... (${remaining_text} remaining)" >&2
                  else
                    echo "[superloop] Still waiting for usage reset..." >&2
                  fi
                done
              else
                echo "[superloop] Usage limit reached. Stopping loop." >&2
                write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
                return 1
              fi
            fi
          fi
        fi

        # Get runner for this specific role
        local role_runner_name
        role_runner_name=$(get_role_runner_name "$role")
        local role_runner_config
        role_runner_config=$(get_runner_for_role "$role" "$role_runner_name")

        # Parse role-specific runner settings
        local -a role_runner_command=()
        local -a role_runner_args=()
        local -a role_runner_fast_args=()
        local role_runner_prompt_mode="stdin"

        if [[ -n "$role_runner_config" ]]; then
          while IFS= read -r line; do
            [[ -n "$line" ]] && role_runner_command+=("$line")
          done < <(jq -r '.command[]?' <<<"$role_runner_config")

          while IFS= read -r line; do
            [[ -n "$line" ]] && role_runner_args+=("$line")
          done < <(jq -r '.args[]?' <<<"$role_runner_config")

          while IFS= read -r line; do
            [[ -n "$line" ]] && role_runner_fast_args+=("$line")
          done < <(jq -r '.fast_args[]?' <<<"$role_runner_config")

          role_runner_prompt_mode=$(jq -r '.prompt_mode // "stdin"' <<<"$role_runner_config")
        fi

        # Fall back to default runner if role-specific failed
        if [[ ${#role_runner_command[@]} -eq 0 ]]; then
          role_runner_command=("${runner_command[@]}")
          role_runner_args=("${runner_args[@]}")
          role_runner_fast_args=("${runner_fast_args[@]}")
          role_runner_prompt_mode="$runner_prompt_mode"
        fi

        # Select args based on fast mode
        local -a role_runner_active_args=("${role_runner_args[@]}")
        if [[ "${fast_mode:-0}" -eq 1 && ${#role_runner_fast_args[@]} -gt 0 ]]; then
          role_runner_active_args=("${role_runner_fast_args[@]}")
        fi

        # Inject model and thinking flags based on role config
        local role_model role_thinking role_runner_type
        role_model=$(get_role_model "$role")
        role_thinking=$(get_role_thinking "$role")
        role_runner_type=$(detect_runner_type_from_cmd "${role_runner_command[0]:-}")

        # Inject --model flag
        if [[ -n "$role_model" && "$role_model" != "null" ]]; then
          role_runner_active_args=("--model" "$role_model" "${role_runner_active_args[@]}")
        fi

        # Inject thinking flags based on runner type
        if [[ -n "$role_thinking" && "$role_thinking" != "null" ]]; then
          local -a thinking_flags=()
          while IFS= read -r flag; do
            [[ -n "$flag" ]] && thinking_flags+=("$flag")
          done < <(get_thinking_flags "$role_runner_type" "$role_thinking")
          if [[ ${#thinking_flags[@]} -gt 0 ]]; then
            role_runner_active_args=("${thinking_flags[@]}" "${role_runner_active_args[@]}")
          fi
        fi

        # Log which runner is being used for this role
        if [[ -n "$role_runner_name" || -n "$role_model" || -n "$role_thinking" ]]; then
          local runner_info="${role_runner_command[0]:-unknown}"
          [[ -n "$role_model" && "$role_model" != "null" ]] && runner_info="$runner_info, model=$role_model"
          [[ -n "$role_thinking" && "$role_thinking" != "null" ]] && runner_info="$runner_info, thinking=$role_thinking"
          echo "[superloop] Role '$role' using: $runner_info"
        fi

        local role_status=0
        set +e
        if [[ "$role" == "openprose" ]]; then
          run_openprose_role "$repo" "$loop_dir" "$prompt_dir" "$log_dir" "$last_messages_dir" "$role_log" "$last_message_file" "$implementer_report" "$role_timeout_seconds" "$role_runner_prompt_mode" "${role_runner_command[@]}" -- "${role_runner_active_args[@]}"
          role_status=$?
        else
          run_role "$repo" "$role" "$prompt_file" "$last_message_file" "$role_log" "$role_timeout_seconds" "$role_runner_prompt_mode" "$timeout_inactivity" "$usage_file" "$iteration" "${role_runner_command[@]}" -- "${role_runner_active_args[@]}"
          role_status=$?
        fi
        set -e
        if [[ -n "$report_guard" ]]; then
          if [[ $role_status -eq 124 ]]; then
            rm -f "$report_snapshot"
          else
            restore_if_unchanged "$report_guard" "$report_snapshot"
          fi
        fi
        if [[ $role_status -eq 125 ]]; then
          local rate_limit_info
          rate_limit_info=$(json_or_default "$LAST_RATE_LIMIT_INFO" "{}")
          local rate_limit_data
          rate_limit_data=$(jq -n \
            --arg loop_id "$loop_id" \
            --arg run_id "$run_id" \
            --argjson iteration "$iteration" \
            --arg role "$role" \
            --arg occurred_at "$(timestamp)" \
            --argjson info "$rate_limit_info" \
            '{loop_id: $loop_id, run_id: $run_id, iteration: $iteration, role: $role, occurred_at: $occurred_at, info: $info}')
          local rate_limit_file="$loop_dir/rate-limit.json"
          printf '%s\n' "$rate_limit_data" > "$rate_limit_file"
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "rate_limit_stop" "$rate_limit_data" "$role" "rate_limited"
          echo "[superloop] Rate limit hit for role '$role'. State saved; resume with: superloop.sh run --repo $repo" >&2
          if [[ "${dry_run:-0}" -ne 1 ]]; then
            write_state "$state_file" "$i" "$iteration" "$loop_id" "true"
          fi
          return 1
        fi
        if [[ $role_status -eq 124 ]]; then
          local timeout_data
          timeout_data=$(jq -n \
            --arg role "$role" \
            --argjson timeout "$role_timeout_seconds" \
            '{role: $role, timeout_seconds: $timeout}')
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_timeout" "$timeout_data" "$role" "timeout"
          echo "Role '$role' timed out after ${role_timeout_seconds}s."
          if [[ "${dry_run:-0}" -ne 1 ]]; then
            write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
          fi
          return 1
        fi
        if [[ $role_status -ne 0 ]]; then
          die "role '$role' failed (exit $role_status)"
        fi
        local role_end_data
        role_end_data=$(jq -n \
          --arg log_file "$role_log" \
          --arg last_message_file "$last_message_file" \
          '{log_file: $log_file, last_message_file: $last_message_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_end" "$role_end_data" "$role"

        # Capture git changes after role completes (file tracking)
        if [[ "$role" == "planner" || "$role" == "implementer" ]]; then
          local changed_file="$loop_dir/changed-files-${role}.txt"
          if git -C "$repo" rev-parse --git-dir &>/dev/null; then
            # Capture staged and unstaged changes
            git -C "$repo" diff --name-only > "$changed_file" 2>/dev/null || true
            git -C "$repo" diff --cached --name-only >> "$changed_file" 2>/dev/null || true
            git -C "$repo" status --porcelain | awk '{print $2}' >> "$changed_file" 2>/dev/null || true
            # Deduplicate
            if [[ -f "$changed_file" ]]; then
              sort -u "$changed_file" -o "$changed_file"
            fi
            # Update cumulative file
            if [[ -f "$changed_file" ]]; then
              cat "$changed_file" >> "$changed_files_all" 2>/dev/null || true
              sort -u "$changed_files_all" -o "$changed_files_all" 2>/dev/null || true
            fi
          fi
        fi

        last_role="$role"
      done

      local promise_matched="false"
      local promise_text=""
      if [[ -n "$completion_promise" ]]; then
        local last_message_file="$last_messages_dir/${last_role}.txt"
        promise_text=$(extract_promise "$last_message_file")
        if [[ -n "$promise_text" && "$promise_text" == "$completion_promise" ]]; then
          promise_matched="true"
        fi
      fi
      local promise_matched_json="false"
      if [[ "$promise_matched" == "true" ]]; then
        promise_matched_json="true"
      fi
      local promise_data
      promise_data=$(jq -n \
        --arg expected "$completion_promise" \
        --arg text "$promise_text" \
        --argjson matched "$promise_matched_json" \
        '{expected: $expected, text: $text, matched: $matched}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "promise_checked" "$promise_data"

      local checklist_ok=1
      local checklist_status_text="ok"
      local checklist_start_data
      checklist_start_data=$(jq -n --argjson patterns "$checklist_patterns_json" '{patterns: $patterns}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "checklist_start" "$checklist_start_data"
      if check_checklists "$repo" "$loop_dir" "${checklist_patterns[@]:-}"; then
        checklist_ok=1
        checklist_status_text="ok"
      else
        checklist_ok=0
        checklist_status_text="remaining"
      fi
      local checklist_ok_json="false"
      if [[ $checklist_ok -eq 1 ]]; then
        checklist_ok_json="true"
      fi
      local checklist_status_json="null"
      if [[ -f "$checklist_status" ]]; then
        checklist_status_json=$(cat "$checklist_status")
      fi
      local checklist_end_data
      checklist_end_data=$(jq -n \
        --arg status "$checklist_status_text" \
        --argjson ok "$checklist_ok_json" \
        --argjson details "$checklist_status_json" \
        '{status: $status, ok: $ok, details: $details}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "checklist_end" "$checklist_end_data"

      local tests_status="skipped"
      local tests_ok=1
      local tests_start_data
      tests_start_data=$(jq -n --arg mode "$tests_mode" --argjson commands "$test_commands_json" '{mode: $mode, commands: $commands}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "tests_start" "$tests_start_data"
      if [[ "$tests_mode" == "every" ]]; then
        if run_tests "$repo" "$loop_dir" "${test_commands[@]}"; then
          tests_status="ok"
          tests_ok=1
        else
          tests_status="failed"
          tests_ok=0
        fi
      elif [[ "$tests_mode" == "on_promise" ]]; then
        if [[ "$promise_matched" == "true" || $checklist_ok -eq 1 ]]; then
          if run_tests "$repo" "$loop_dir" "${test_commands[@]}"; then
            tests_status="ok"
            tests_ok=1
          else
            tests_status="failed"
            tests_ok=0
          fi
        else
          run_tests "$repo" "$loop_dir"
          tests_status="skipped"
          tests_ok=1
        fi
      else
        run_tests "$repo" "$loop_dir"
        tests_status="skipped"
        tests_ok=1
      fi
      local test_status_json="null"
      if [[ -f "$test_status" ]]; then
        test_status_json=$(cat "$test_status")
      fi
      local tests_end_data
      tests_end_data=$(jq -n \
        --arg status "$tests_status" \
        --argjson details "$test_status_json" \
        '{status: $status, details: $details}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "tests_end" "$tests_end_data"

      local validation_status="skipped"
      local validation_ok=1
      local validation_gate_ok=1
      local validation_start_data
      validation_start_data=$(jq -n \
        --arg enabled "$validation_enabled" \
        --arg mode "$validation_mode" \
        '{enabled: $enabled, mode: $mode}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "validation_start" "$validation_start_data"

      local validation_should_run=0
      if [[ "$validation_enabled" == "true" ]]; then
        if [[ "$validation_mode" == "every" ]]; then
          validation_should_run=1
        elif [[ "$validation_mode" == "on_promise" ]]; then
          if [[ "$promise_matched" == "true" || $checklist_ok -eq 1 ]]; then
            validation_should_run=1
          fi
        fi
      fi

      if [[ "$validation_enabled" == "true" && $validation_should_run -eq 1 ]]; then
        if run_validation "$repo" "$loop_dir" "$loop_id" "$iteration" "$loop_json"; then
          validation_status="ok"
          validation_ok=1
        else
          validation_status="failed"
          validation_ok=0
        fi
      elif [[ "$validation_enabled" == "true" ]]; then
        write_validation_status "$validation_status_file" "skipped" "true" ""
        validation_status="skipped"
      fi

      local validation_end_data
      local validation_results_rel=""
      if [[ -f "$validation_results_file" ]]; then
        validation_results_rel="${validation_results_file#$repo/}"
      fi
      validation_end_data=$(jq -n \
        --arg status "$validation_status" \
        --arg results_file "$validation_results_rel" \
        '{status: $status, results_file: $results_file}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "validation_end" "$validation_end_data"

      if [[ "$validation_enabled" == "true" && "$validation_require" == "true" ]]; then
        validation_gate_ok=$validation_ok
      fi

      local evidence_status="skipped"
      local evidence_ok=1
      local evidence_gate_ok=1
      local evidence_start_data
      evidence_start_data=$(jq -n --arg enabled "$evidence_enabled" '{enabled: $enabled}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "evidence_start" "$evidence_start_data"
      if [[ "$evidence_enabled" == "true" ]]; then
        if write_evidence_manifest "$repo" "$loop_dir" "$loop_id" "$iteration" "$spec_file" "$loop_json" "$test_status" "$test_output" "$checklist_status" "$evidence_file"; then
          evidence_status="ok"
          evidence_ok=1
        else
          evidence_status="failed"
          evidence_ok=0
        fi
      fi
      local evidence_end_data
      evidence_end_data=$(jq -n \
        --arg status "$evidence_status" \
        --arg evidence_file "${evidence_file#$repo/}" \
        '{status: $status, evidence_file: $evidence_file}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "evidence_end" "$evidence_end_data"
      if [[ "$evidence_enabled" == "true" && "$evidence_require" == "true" ]]; then
        evidence_gate_ok=$evidence_ok
      fi

      local progress_signature_prev=""
      local progress_signature_current=""
      local no_progress="false"
      if [[ "$stuck_enabled" == "true" && "$checklist_status_text" != "ok" ]]; then
        if [[ -f "$loop_dir/stuck.json" ]]; then
          progress_signature_prev=$(jq -r '.signature // ""' "$loop_dir/stuck.json" 2>/dev/null || true)
        fi
        if [[ -n "$progress_signature_prev" ]]; then
          local signature_rc=0
          set +e
          progress_signature_current=$(compute_signature "$repo" "${stuck_ignore[@]}")
          signature_rc=$?
          set -e
          if [[ $signature_rc -ne 0 ]]; then
            die "stuck signature computation failed for loop '$loop_id'"
          fi
          if [[ "$progress_signature_current" == "$progress_signature_prev" ]]; then
            no_progress="true"
          fi
        fi
      fi

      local candidate_ok=0
      if [[ "$promise_matched" == "true" && $tests_ok -eq 1 && $validation_gate_ok -eq 1 && $checklist_ok -eq 1 && $evidence_gate_ok -eq 1 ]]; then
        candidate_ok=1
      fi

      local approval_status="skipped"
      local approval_ok=1
      if [[ $approval_required -eq 1 && $candidate_ok -eq 1 ]]; then
        approval_status="pending"
        approval_ok=0
      fi

      local completion_ok=0
      if [[ $candidate_ok -eq 1 && $approval_ok -eq 1 ]]; then
        completion_ok=1
      fi

      local stuck_streak="0"
      local stuck_triggered="false"
      if [[ $completion_ok -eq 0 && "$stuck_enabled" == "true" && $candidate_ok -eq 0 ]]; then
        local stuck_result
        local stuck_rc=0
        set +e
        stuck_result=$(update_stuck_state "$repo" "$loop_dir" "$stuck_threshold" "${stuck_ignore[@]}")
        stuck_rc=$?
        set -e
        if [[ $stuck_rc -eq 0 ]]; then
          stuck_streak="$stuck_result"
          if [[ "$no_progress" == "true" ]]; then
            write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
            local stuck_value="n/a"
            if [[ "$stuck_enabled" == "true" ]]; then
              stuck_value="${stuck_streak}/${stuck_threshold}"
            fi
            write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
            local no_progress_data
            no_progress_data=$(jq -n \
              --arg reason "checklist_remaining_no_change" \
              --arg signature "$progress_signature_current" \
              --argjson streak "$stuck_streak" \
              --argjson threshold "$stuck_threshold" \
              '{reason: $reason, signature: $signature, streak: $streak, threshold: $threshold}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "no_progress_stop" "$no_progress_data" "" "blocked"
            local loop_stop_data
            loop_stop_data=$(jq -n --arg reason "no_progress" --argjson streak "$stuck_streak" --argjson threshold "$stuck_threshold" '{reason: $reason, streak: $streak, threshold: $threshold}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_stop" "$loop_stop_data"
            if [[ "${dry_run:-0}" -ne 1 ]]; then
              write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
            fi
            return 1
          fi
        elif [[ $stuck_rc -eq 2 ]]; then
          stuck_streak="$stuck_result"
          stuck_triggered="true"
          write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
          local stuck_value="n/a"
          if [[ "$stuck_enabled" == "true" ]]; then
            stuck_value="${stuck_streak}/${stuck_threshold}"
          fi
          write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
          local stuck_data
          stuck_data=$(jq -n \
            --argjson streak "$stuck_streak" \
            --argjson threshold "$stuck_threshold" \
            --argjson triggered true \
            --arg action "$stuck_action" \
            '{streak: $streak, threshold: $threshold, triggered: $triggered, action: $action}')
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "stuck_checked" "$stuck_data"
          if [[ "$stuck_action" == "report_and_stop" ]]; then
            echo "Stuck detection triggered for loop '$loop_id'. Stopping."
            local loop_stop_data
            loop_stop_data=$(jq -n --arg reason "stuck" --argjson streak "$stuck_streak" --argjson threshold "$stuck_threshold" '{reason: $reason, streak: $streak, threshold: $threshold}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_stop" "$loop_stop_data"
            write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
            return 1
          fi
        else
          die "stuck detection failed for loop '$loop_id'"
        fi
      fi
      if [[ "$stuck_enabled" == "true" && "$stuck_triggered" != "true" ]]; then
        local stuck_triggered_json="false"
        local stuck_data
        stuck_data=$(jq -n \
          --argjson streak "$stuck_streak" \
          --argjson threshold "$stuck_threshold" \
          --argjson triggered "$stuck_triggered_json" \
          --arg action "$stuck_action" \
          '{streak: $streak, threshold: $threshold, triggered: $triggered, action: $action}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "stuck_checked" "$stuck_data"
      fi

      write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$approval_status"
      local stuck_value="n/a"
      if [[ "$stuck_enabled" == "true" ]]; then
        stuck_value="${stuck_streak}/${stuck_threshold}"
      fi
      write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$stuck_value" "$approval_status"
      local gates_data
      gates_data=$(jq -n \
        --argjson promise "$promise_matched_json" \
        --arg tests "$tests_status" \
        --arg validation "$validation_status" \
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        --arg approval "$approval_status" \
        --arg stuck "$stuck_value" \
        '{promise: $promise, tests: $tests, validation: $validation, checklist: $checklist, evidence: $evidence, approval: $approval, stuck: $stuck}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "gates_evaluated" "$gates_data"

      local iteration_ended_at
      iteration_ended_at=$(timestamp)
      local completion_json="false"
      if [[ $completion_ok -eq 1 ]]; then
        completion_json="true"
      fi
      local iteration_end_data
      iteration_end_data=$(jq -n \
        --arg started_at "$iteration_started_at" \
        --arg ended_at "$iteration_ended_at" \
        --argjson completion "$completion_json" \
        --argjson promise "$promise_matched_json" \
        --arg tests "$tests_status" \
        --arg validation "$validation_status" \
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        --arg approval "$approval_status" \
        '{started_at: $started_at, ended_at: $ended_at, completion: $completion, promise: $promise, tests: $tests, validation: $validation, checklist: $checklist, evidence: $evidence, approval: $approval}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "iteration_end" "$iteration_end_data"

      append_run_summary "$run_summary_file" "$repo" "$loop_id" "$run_id" "$iteration" "$iteration_started_at" "$iteration_ended_at" "$promise_matched" "$completion_promise" "$promise_text" "$tests_mode" "$tests_status" "$validation_status" "$checklist_status_text" "$evidence_status" "$approval_status" "$stuck_streak" "$stuck_threshold" "$completion_ok" "$loop_dir" "$events_file"
      write_timeline "$run_summary_file" "$timeline_file"

      if [[ $approval_required -eq 1 && $candidate_ok -eq 1 ]]; then
        write_approval_request \
          "$approval_file" \
          "$loop_id" \
          "$run_id" \
          "$iteration" \
          "$iteration_started_at" \
          "$iteration_ended_at" \
          "$completion_promise" \
          "$promise_text" \
          "$promise_matched" \
          "$tests_status" \
          "$validation_status" \
          "$checklist_status_text" \
          "$evidence_status" \
          "${summary_file#$repo/}" \
          "${evidence_file#$repo/}" \
          "${reviewer_report#$repo/}" \
          "${test_report#$repo/}" \
          "${plan_file#$repo/}" \
          "${notes_file#$repo/}"

        local approval_request_data
        approval_request_data=$(jq -n \
          --arg approval_file "${approval_file#$repo/}" \
          --argjson promise "$promise_matched_json" \
          --arg tests "$tests_status" \
          --arg validation "$validation_status" \
          --arg checklist "$checklist_status_text" \
          --arg evidence "$evidence_status" \
          '{approval_file: $approval_file, promise: $promise, tests: $tests, validation: $validation, checklist: $checklist, evidence: $evidence}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_requested" "$approval_request_data"

        echo "Approval required for loop '$loop_id'. Run: superloop.sh approve --repo $repo --loop $loop_id"
        write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
        return 0
      fi

      if [[ $completion_ok -eq 1 ]]; then
        local loop_complete_data
        loop_complete_data=$(jq -n \
          --argjson iteration "$iteration" \
          --arg run_id "$run_id" \
          '{iteration: $iteration, run_id: $run_id}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "loop_complete" "$loop_complete_data"
        echo "Loop '$loop_id' complete at iteration $iteration."
        iteration=1
        break
      fi

      iteration=$((iteration + 1))
    done

    if [[ -n "$target_loop_id" && "$loop_id" == "$target_loop_id" ]]; then
      if [[ "${dry_run:-0}" -ne 1 ]]; then
        write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
      fi
      return 0
    fi
  done

  if [[ "${dry_run:-0}" -ne 1 ]]; then
    write_state "$state_file" "$loop_count" 0 "" "false"
    echo "All loops complete."
  else
    echo "Dry-run complete."
  fi
}

status_cmd() {
  local repo="$1"
  local summary="${2:-0}"
  local loop_id="${3:-}"
  local config_path="${4:-}"

  if [[ "${summary:-0}" -eq 1 ]]; then
    need_cmd jq
    local target_loop="$loop_id"
    if [[ -z "$target_loop" && -n "$config_path" && -f "$config_path" ]]; then
      target_loop=$(jq -r '.loops[0].id // ""' "$config_path")
    fi
    if [[ -z "$target_loop" || "$target_loop" == "null" ]]; then
      die "loop id required for status --summary (use --loop or config)"
    fi

    local summary_file="$repo/.superloop/loops/$target_loop/run-summary.json"
    if [[ ! -f "$summary_file" ]]; then
      echo "No run summary found for loop '$target_loop'."
      return 0
    fi

    jq -r --arg loop "$target_loop" '
      .updated_at as $updated |
      .entries[-1] as $e |
      if $e == null then
        "No run summary entries found for loop \($loop)."
      else
        [
          "loop=" + $loop,
          "run_id=" + ($e.run_id // "unknown"),
          "iteration=" + (($e.iteration // 0) | tostring),
          "updated_at=" + ($updated // "unknown"),
          "promise=" + (($e.promise.matched // false) | tostring),
          "tests=" + ($e.gates.tests // "unknown"),
          "validation=" + ($e.gates.validation // "unknown"),
          "checklist=" + ($e.gates.checklist // "unknown"),
          "evidence=" + ($e.gates.evidence // "unknown"),
          "approval=" + ($e.gates.approval // "unknown"),
          "evidence_file=" + ($e.artifacts.evidence.path // "unknown"),
          "evidence_exists=" + (($e.artifacts.evidence.exists // false) | tostring),
          "evidence_sha256=" + ($e.artifacts.evidence.sha256 // "unknown"),
          "evidence_mtime=" + (($e.artifacts.evidence.mtime // "unknown") | tostring)
        ] | join(" ")
      end
    ' "$summary_file"
    return 0
  fi

  local state_file="$repo/.superloop/state.json"

  if [[ ! -f "$state_file" ]]; then
    echo "No state file found."
    return 0
  fi

  cat "$state_file"
}

cancel_cmd() {
  local repo="$1"
  local state_file="$repo/.superloop/state.json"

  if [[ ! -f "$state_file" ]]; then
    echo "No active state file found."
    return 0
  fi

  rm "$state_file"
  echo "Cancelled loop state."
}

approve_cmd() {
  local repo="$1"
  local loop_id="$2"
  local approver="$3"
  local note="$4"
  local reject="$5"

  need_cmd jq

  if [[ -z "$loop_id" ]]; then
    die "--loop is required for approve"
  fi

  local loop_dir="$repo/.superloop/loops/$loop_id"
  local approval_file="$loop_dir/approval.json"
  local events_file="$loop_dir/events.jsonl"

  if [[ ! -f "$approval_file" ]]; then
    die "no approval request found for loop '$loop_id'"
  fi

  local status
  status=$(jq -r '.status // "pending"' "$approval_file")
  if [[ "$status" != "pending" ]]; then
    die "approval request is not pending (status=$status)"
  fi

  local run_id iteration
  run_id=$(jq -r '.run_id // ""' "$approval_file")
  iteration=$(jq -r '.iteration // 0' "$approval_file")
  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    run_id="unknown"
  fi
  if [[ -z "$iteration" || "$iteration" == "null" ]]; then
    iteration=0
  fi

  local decided_by="$approver"
  if [[ -z "$decided_by" ]]; then
    decided_by="${USER:-unknown}"
  fi
  local decision="approved"
  if [[ "${reject:-0}" -eq 1 ]]; then
    decision="rejected"
  fi
  local decided_at
  decided_at=$(timestamp)

  jq \
    --arg status "$decision" \
    --arg decided_by "$decided_by" \
    --arg decided_at "$decided_at" \
    --arg note "$note" \
    '.status = $status
     | .decision = {status: $status, by: $decided_by, note: (if ($note | length) > 0 then $note else null end), at: $decided_at}
     | .decided_at = $decided_at
     | .decided_by = $decided_by
     | .decided_note = (if ($note | length) > 0 then $note else null end)' \
    "$approval_file" > "${approval_file}.tmp"
  mv "${approval_file}.tmp" "$approval_file"

  append_decision_log "$loop_dir" "$loop_id" "$run_id" "$iteration" "$decision" "$decided_by" "$note" "${approval_file#$repo/}" "$decided_at"

  local decision_data
  decision_data=$(jq -n \
    --arg status "$decision" \
    --arg by "$decided_by" \
    --arg note "$note" \
    --arg at "$decided_at" \
    '{status: $status, by: $by, note: (if ($note | length) > 0 then $note else null end), at: $at}')
  log_event "$events_file" "$loop_id" "$iteration" "$run_id" "approval_decision" "$decision_data" "human" "$decision"

  echo "Recorded approval decision ($decision) for loop '$loop_id'."
}

select_python() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    echo "python"
    return 0
  fi
  return 1
}

validate_cmd() {
  local repo="$1"
  local config_path="$2"
  local schema_path="$3"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi
  if [[ ! -f "$schema_path" ]]; then
    die "schema not found: $schema_path"
  fi

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    die "missing python3/python for schema validation"
  fi

  "$python_bin" - "$schema_path" "$config_path" <<'PY'
import json
import sys


def error(message, path):
    sys.stderr.write("schema validation error at {}: {}\n".format(path, message))
    return False


def is_integer(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    return (isinstance(value, int) or isinstance(value, float)) and not isinstance(value, bool)


def validate(instance, schema, path):
    if "enum" in schema:
        if instance not in schema["enum"]:
            return error("expected one of {}".format(schema["enum"]), path)

    schema_type = schema.get("type")
    if schema_type == "object":
        if not isinstance(instance, dict):
            return error("expected object", path)
        props = schema.get("properties", {})
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                return error("missing required property '{}'".format(key), "{}.{}".format(path, key))
        additional = schema.get("additionalProperties", True)
        for key, value in instance.items():
            if key in props:
                if not validate(value, props[key], "{}.{}".format(path, key)):
                    return False
            else:
                if additional is False:
                    return error("unexpected property '{}'".format(key), "{}.{}".format(path, key))
                if isinstance(additional, dict):
                    if not validate(value, additional, "{}.{}".format(path, key)):
                        return False
        return True

    if schema_type == "array":
        if not isinstance(instance, list):
            return error("expected array", path)
        if "minItems" in schema and len(instance) < schema["minItems"]:
            return error("expected at least {} items".format(schema["minItems"]), path)
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, item in enumerate(instance):
                if not validate(item, item_schema, "{}[{}]".format(path, index)):
                    return False
        return True

    if schema_type == "string":
        if not isinstance(instance, str):
            return error("expected string", path)
        return True

    if schema_type == "integer":
        if not is_integer(instance):
            return error("expected integer", path)
        return True

    if schema_type == "number":
        if not is_number(instance):
            return error("expected number", path)
        return True

    if schema_type == "boolean":
        if not isinstance(instance, bool):
            return error("expected boolean", path)
        return True

    return True


def load_json(path):
    with open(path, "r") as handle:
        return json.load(handle)


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: validate <schema> <config>\n")
        return 2
    schema_path = sys.argv[1]
    config_path = sys.argv[2]
    try:
        schema = load_json(schema_path)
    except Exception as exc:
        sys.stderr.write("error: failed to read schema {}: {}\n".format(schema_path, exc))
        return 1
    try:
        config = load_json(config_path)
    except Exception as exc:
        sys.stderr.write("error: failed to read config {}: {}\n".format(config_path, exc))
        return 1

    if not validate(config, schema, "$"):
        return 1
    print("ok: config matches schema")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
}

report_cmd() {
  local repo="$1"
  local config_path="$2"
  local loop_id="$3"
  local out_path="$4"

  need_cmd jq

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi

  if [[ -z "$loop_id" ]]; then
    loop_id=$(jq -r '.loops[0].id // ""' "$config_path")
    if [[ -z "$loop_id" || "$loop_id" == "null" ]]; then
      die "loop id not found in config"
    fi
  else
    local match
    match=$(jq -r --arg id "$loop_id" '.loops[]? | select(.id == $id) | .id' "$config_path" | head -n1)
    if [[ -z "$match" ]]; then
      die "loop id not found: $loop_id"
    fi
  fi

  local loop_dir="$repo/.superloop/loops/$loop_id"
  local summary_file="$loop_dir/run-summary.json"
  local timeline_file="$loop_dir/timeline.md"
  local events_file="$loop_dir/events.jsonl"
  local gate_summary="$loop_dir/gate-summary.txt"
  local evidence_file="$loop_dir/evidence.json"
  local reviewer_packet="$loop_dir/reviewer-packet.md"
  local approval_file="$loop_dir/approval.json"
  local decisions_md="$loop_dir/decisions.md"
  local decisions_jsonl="$loop_dir/decisions.jsonl"
  local report_file="$out_path"
  if [[ -z "$report_file" ]]; then
    report_file="$loop_dir/report.html"
  fi

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    die "missing python3/python for report generation"
  fi

  "$python_bin" - "$loop_id" "$summary_file" "$timeline_file" "$events_file" "$gate_summary" "$evidence_file" "$reviewer_packet" "$approval_file" "$decisions_md" "$decisions_jsonl" "$report_file" <<'PY'
import datetime
import html
import json
import os
import sys


def read_text(path):
    if not path or not os.path.exists(path):
        return ""
    with open(path, "r") as handle:
        return handle.read()


def read_json(path):
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r") as handle:
            return json.load(handle)
    except Exception as exc:
        return {"_error": str(exc)}


def escape_block(text):
    return html.escape(text or "")


def json_block(value):
    if value is None:
        return ""
    try:
        return json.dumps(value, indent=2, sort_keys=True)
    except Exception:
        return str(value)


loop_id = sys.argv[1]
summary_path = sys.argv[2]
timeline_path = sys.argv[3]
events_path = sys.argv[4]
gate_path = sys.argv[5]
evidence_path = sys.argv[6]
reviewer_packet_path = sys.argv[7]
approval_path = sys.argv[8]
decisions_md_path = sys.argv[9]
decisions_jsonl_path = sys.argv[10]
out_path = sys.argv[11]

summary = read_json(summary_path)
timeline = read_text(timeline_path)
gate_summary = read_text(gate_path).strip()
evidence = read_json(evidence_path)
reviewer_packet = read_text(reviewer_packet_path).strip()
approval = read_json(approval_path)
decisions_md = read_text(decisions_md_path).strip()
decisions_jsonl = read_text(decisions_jsonl_path).strip()

events_lines = []
if os.path.exists(events_path):
    with open(events_path, "r") as handle:
        events_lines = handle.read().splitlines()

latest_entry = None
if isinstance(summary, dict):
    entries = summary.get("entries") or []
    if entries:
        latest_entry = entries[-1]

generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

sections = []

overview = [
    "<div class='meta'>",
    "<div><strong>Loop:</strong> {}</div>".format(html.escape(loop_id)),
    "<div><strong>Generated:</strong> {}</div>".format(html.escape(generated_at)),
    "<div><strong>Summary file:</strong> {}</div>".format(html.escape(summary_path)),
    "</div>",
]
sections.append("<h2>Overview</h2>" + "".join(overview))

if gate_summary:
    sections.append("<h2>Gate Summary</h2><pre>{}</pre>".format(escape_block(gate_summary)))
else:
    sections.append("<h2>Gate Summary</h2><p>No gate summary found.</p>")

if latest_entry is not None:
    sections.append("<h2>Latest Iteration</h2><pre>{}</pre>".format(escape_block(json_block(latest_entry))))
else:
    sections.append("<h2>Latest Iteration</h2><p>No run summary entries found.</p>")

if timeline:
    sections.append("<h2>Timeline</h2><pre>{}</pre>".format(escape_block(timeline)))
else:
    sections.append("<h2>Timeline</h2><p>No timeline found.</p>")

if events_lines:
    tail = events_lines[-40:]
    sections.append("<h2>Recent Events</h2><pre>{}</pre>".format(escape_block("\n".join(tail))))
else:
    sections.append("<h2>Recent Events</h2><p>No events found.</p>")

if evidence is not None:
    sections.append("<h2>Evidence Manifest</h2><pre>{}</pre>".format(escape_block(json_block(evidence))))
else:
    sections.append("<h2>Evidence Manifest</h2><p>No evidence manifest found.</p>")

if reviewer_packet:
    sections.append("<h2>Reviewer Packet</h2><pre>{}</pre>".format(escape_block(reviewer_packet)))
else:
    sections.append("<h2>Reviewer Packet</h2><p>No reviewer packet found.</p>")

if approval is not None:
    sections.append("<h2>Approval Request</h2><pre>{}</pre>".format(escape_block(json_block(approval))))
else:
    sections.append("<h2>Approval Request</h2><p>No approval request found.</p>")

if decisions_md:
    sections.append("<h2>Decisions</h2><pre>{}</pre>".format(escape_block(decisions_md)))
elif decisions_jsonl:
    sections.append("<h2>Decisions</h2><pre>{}</pre>".format(escape_block(decisions_jsonl)))
else:
    sections.append("<h2>Decisions</h2><p>No decisions found.</p>")

html_doc = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Supergent Report - {loop_id}</title>
  <style>
    body {{
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      margin: 24px;
      color: #111;
      background: #f8f6f2;
    }}
    h1 {{
      font-size: 22px;
      margin-bottom: 8px;
    }}
    h2 {{
      margin-top: 24px;
      border-bottom: 1px solid #ddd;
      padding-bottom: 6px;
    }}
    pre {{
      background: #fff;
      border: 1px solid #e2e2e2;
      padding: 12px;
      overflow: auto;
      white-space: pre-wrap;
    }}
    .meta {{
      background: #fff;
      border: 1px solid #e2e2e2;
      padding: 12px;
      margin-bottom: 12px;
    }}
  </style>
</head>
<body>
  <h1>Supergent Report</h1>
  {sections}
</body>
</html>
""".format(loop_id=html.escape(loop_id), sections="\n".join(sections))

with open(out_path, "w") as handle:
    handle.write(html_doc)
PY

  echo "Wrote report to $report_file"
}

main() {
  local cmd="${1:-}"
  if [[ "$cmd" == "--version" || "$cmd" == "-v" ]]; then
    print_version
    return 0
  fi
  shift || true

  local repo="."
  local config_path=""
  local schema_path=""
  local loop_id=""
  local out_path=""
  local summary=0
  local force=0
  local fast=0
  local dry_run=0
  local approver=""
  local note=""
  local reject=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo="$2"
        shift 2
        ;;
      --config)
        config_path="$2"
        shift 2
        ;;
      --schema)
        schema_path="$2"
        shift 2
        ;;
      --loop)
        loop_id="$2"
        shift 2
        ;;
      --summary)
        summary=1
        shift
        ;;
      --out)
        out_path="$2"
        shift 2
        ;;
      --by)
        approver="$2"
        shift 2
        ;;
      --note)
        note="$2"
        shift 2
        ;;
      --reject)
        reject=1
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      --fast)
        fast=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  : "${repo:=.}"
  repo=$(cd "$repo" && pwd)

  if [[ -z "$config_path" ]]; then
    config_path="$repo/.superloop/config.json"
  fi
  if [[ -z "$schema_path" ]]; then
    schema_path="$repo/schema/config.schema.json"
  fi

  case "$cmd" in
    init)
      init_cmd "$repo" "$force"
      ;;
    list)
      list_cmd "$repo" "$config_path"
      ;;
    run)
      run_cmd "$repo" "$config_path" "$loop_id" "$fast" "$dry_run"
      ;;
    status)
      status_cmd "$repo" "$summary" "$loop_id" "$config_path"
      ;;
    approve)
      approve_cmd "$repo" "$loop_id" "$approver" "$note" "$reject"
      ;;
    cancel)
      cancel_cmd "$repo"
      ;;
    validate)
      validate_cmd "$repo" "$config_path" "$schema_path"
      ;;
    report)
      report_cmd "$repo" "$config_path" "$loop_id" "$out_path"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

