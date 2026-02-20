#!/usr/bin/env bash
set -euo pipefail
# Generated from src/*.sh by scripts/build.sh. Edit source files, not this output.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION="0.6.1"

usage() {
  cat <<'USAGE'
Supergent Runner Wrapper

Usage:
  superloop.sh init [--repo DIR] [--force]
  superloop.sh list [--repo DIR] [--config FILE]
  superloop.sh run [--repo DIR] [--config FILE] [--loop ID] [--fast] [--dry-run]
  superloop.sh status [--repo DIR] [--summary] [--loop ID]
  superloop.sh usage [--repo DIR] [--loop ID] [--json]
  superloop.sh approve --loop ID [--repo DIR] [--by NAME] [--note TEXT] [--reject]
  superloop.sh cancel [--repo DIR]
  superloop.sh validate [--repo DIR] [--config FILE] [--schema FILE]
  superloop.sh runner-smoke [--repo DIR] [--config FILE] [--schema FILE] [--loop ID]
  superloop.sh report [--repo DIR] [--config FILE] [--loop ID] [--out FILE]
  superloop.sh --version

Options:
  --repo DIR       Repository root (default: current directory)
  --config FILE    Config file path (default: .superloop/config.json)
  --schema FILE    Schema file path (default: schema/config.schema.json)
  --loop ID        Run only the loop with this id (or select loop for status/report/usage)
  --summary        Print latest gate/evidence snapshot from run-summary.json
  --json           Output in JSON format (for usage command)
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
    elif [[ -d "$full" ]]; then
      # For untracked directories, enumerate contents recursively
      # Exclude common large directories that don't indicate meaningful progress
      while IFS= read -r -d '' subfile; do
        local relpath="${subfile#$repo/}"
        if should_ignore "$relpath" "${ignore_patterns[@]}"; then
          continue
        fi
        local subhash
        subhash=$(hash_file "$subfile" 2>/dev/null || true)
        if [[ -z "$subhash" ]]; then
          subhash="unhashed"
        fi
        entries+=("$relpath:$subhash")
      done < <(find "$full" -type f \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/target/*" \
        -not -path "*/dist/*" \
        -not -path "*/__pycache__/*" \
        -not -path "*/.venv/*" \
        -print0 2>/dev/null)
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

compute_test_failure_signature() {
  local loop_dir="$1"
  local test_output_file="$loop_dir/test-output.txt"

  if [[ ! -f "$test_output_file" ]]; then
    echo ""
    return 0
  fi

  # Extract error messages, normalize line numbers/paths, hash
  # Captures TypeScript errors (TS####), test failures (FAIL), and generic errors
  grep -E "^(Error|FAIL|TS[0-9]+|error TS[0-9]+)" "$test_output_file" \
    | sed -E 's/:[0-9]+:[0-9]+/:<line>:<col>/g' \
    | sed -E 's/\([0-9]+,[0-9]+\)/(<line>,<col>)/g' \
    | sed -E 's/line [0-9]+/line <num>/g' \
    | sed -E 's/column [0-9]+/column <num>/g' \
    | sort \
    | hash_stdin || echo ""
}

update_stuck_state() {
  local repo="$1"
  local loop_dir="$2"
  local threshold="$3"
  shift 3
  local ignore_patterns=("$@")

  local state_file="$loop_dir/stuck.json"
  local report_file="$loop_dir/stuck-report.md"

  # Compute code signature (existing)
  local code_signature
  code_signature=$(compute_signature "$repo" "${ignore_patterns[@]}") || return 1

  # Compute test failure signature (new)
  local test_signature
  test_signature=$(compute_test_failure_signature "$loop_dir")

  # Load previous state
  local prev_code_signature=""
  local prev_test_signature=""
  local prev_streak=0
  if [[ -f "$state_file" ]]; then
    # Try new format first (code_signature + test_signature)
    prev_code_signature=$(jq -r '.code_signature // ""' "$state_file")
    prev_test_signature=$(jq -r '.test_signature // ""' "$state_file")

    # Fallback to old format (signature field) for backward compatibility
    if [[ -z "$prev_code_signature" ]]; then
      prev_code_signature=$(jq -r '.signature // ""' "$state_file")
    fi

    prev_streak=$(jq -r '.streak // 0' "$state_file")
  fi

  # Increment streak if: same code changes OR same test failures
  local streak=1
  local stuck_reason=""
  if [[ "$code_signature" == "$prev_code_signature" && -n "$code_signature" ]]; then
    streak=$((prev_streak + 1))
    stuck_reason="no_code_changes"
  elif [[ -n "$test_signature" && "$test_signature" == "$prev_test_signature" && -n "$prev_test_signature" ]]; then
    streak=$((prev_streak + 1))
    stuck_reason="same_test_failures"
  fi

  # Save both signatures
  jq -n \
    --arg code_sig "$code_signature" \
    --arg test_sig "$test_signature" \
    --argjson streak "$streak" \
    --argjson threshold "$threshold" \
    --arg reason "$stuck_reason" \
    --arg updated_at "$(timestamp)" \
    '{code_signature: $code_sig, test_signature: $test_sig, streak: $streak, threshold: $threshold, reason: $reason, updated_at: $updated_at}' \
    > "$state_file"

  # Trigger stuck detection if threshold reached
  if [[ "$streak" -ge "$threshold" ]]; then
    {
      echo "# Stuck Report"
      echo ""
      echo "No meaningful progress detected for $streak consecutive iterations."
      echo ""
      if [[ "$stuck_reason" == "no_code_changes" ]]; then
        echo "**Reason**: No code changes detected"
      elif [[ "$stuck_reason" == "same_test_failures" ]]; then
        echo "**Reason**: Same test failures persist despite code changes (thrashing)"
      fi
      echo ""
      echo "**Code Signature**: \`$code_signature\`"
      echo "**Test Failure Signature**: \`$test_signature\`"
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

  # RLMS evidence: index + latest per-role artifacts
  local rlms_index_file="$loop_dir/rlms/index.json"
  local rlms_index_rel="${rlms_index_file#$repo/}"
  local rlms_index_json="null"
  if [[ -f "$rlms_index_file" ]]; then
    rlms_index_json=$(cat "$rlms_index_file")
  fi
  rlms_index_json=$(json_or_default "$rlms_index_json" "null")

  local rlms_index_sha_json="null"
  local rlms_index_mtime_json="null"
  if [[ -f "$rlms_index_file" ]]; then
    local rlms_index_hash
    rlms_index_hash=$(hash_file "$rlms_index_file" 2>/dev/null || true)
    if [[ -n "$rlms_index_hash" ]]; then
      rlms_index_sha_json="\"$rlms_index_hash\""
    fi
    local rlms_index_mtime
    rlms_index_mtime=$(file_mtime "$rlms_index_file" 2>/dev/null || true)
    if [[ -n "$rlms_index_mtime" ]]; then
      rlms_index_mtime_json="$rlms_index_mtime"
    fi
  fi

  local rlms_latest_jsonl="$loop_dir/evidence-rlms-latest.jsonl"
  : > "$rlms_latest_jsonl"
  local rlms_latest_dir="$loop_dir/rlms/latest"
  if [[ -d "$rlms_latest_dir" ]]; then
    while IFS= read -r latest_file; do
      if [[ -z "$latest_file" ]]; then
        continue
      fi
      local latest_rel="${latest_file#$repo/}"
      local latest_hash
      latest_hash=$(hash_file "$latest_file" 2>/dev/null || true)
      local latest_mtime_json="null"
      local latest_mtime
      latest_mtime=$(file_mtime "$latest_file" 2>/dev/null || true)
      if [[ -n "$latest_mtime" ]]; then
        latest_mtime_json="$latest_mtime"
      fi
      jq -n \
        --arg path "$latest_rel" \
        --arg sha "$latest_hash" \
        --argjson mtime "$latest_mtime_json" \
        '{path: $path, exists: true, sha256: (if ($sha | length) > 0 then $sha else null end), mtime: $mtime}' >> "$rlms_latest_jsonl"
    done < <(find "$rlms_latest_dir" -maxdepth 1 -type f 2>/dev/null | sort)
  fi
  local rlms_latest_json
  rlms_latest_json=$(jq -s '.' "$rlms_latest_jsonl")
  rlms_latest_json=$(json_or_default "$rlms_latest_json" "[]")

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
    --arg rlms_index_file "$rlms_index_rel" \
    --argjson rlms_index "$rlms_index_json" \
    --argjson rlms_index_sha "$rlms_index_sha_json" \
    --argjson rlms_index_mtime "$rlms_index_mtime_json" \
    --argjson rlms_latest "$rlms_latest_json" \
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
      rlms: {
        index_file: $rlms_index_file,
        index: $rlms_index,
        index_sha256: $rlms_index_sha,
        index_mtime: $rlms_index_mtime,
        latest: $rlms_latest
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
  local rlms_result_file="${23:-}"
  local rlms_summary_file="${24:-}"
  local rlms_status_file="${25:-}"
  local delegation_status_file="${26:-}"

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

  # Add lint feedback if it exists
  local loop_dir
  loop_dir=$(dirname "$notes_file")
  local lint_feedback_file="$loop_dir/lint-feedback.txt"
  if [[ -f "$lint_feedback_file" ]]; then
    echo "- Lint feedback: $lint_feedback_file" >> "$prompt_file"
  fi

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

  # Add RLMS context if available
  if [[ -n "$rlms_result_file" && -f "$rlms_result_file" ]]; then
    echo "- RLMS result: $rlms_result_file" >> "$prompt_file"
  fi
  if [[ -n "$rlms_summary_file" && -f "$rlms_summary_file" ]]; then
    echo "- RLMS summary: $rlms_summary_file" >> "$prompt_file"
  fi
  if [[ -n "$rlms_status_file" && -f "$rlms_status_file" ]]; then
    echo "- RLMS status: $rlms_status_file" >> "$prompt_file"
  fi
  if [[ -n "$delegation_status_file" && -f "$delegation_status_file" ]]; then
    echo "- Delegation status: $delegation_status_file" >> "$prompt_file"
    local delegation_summary_from_status
    delegation_summary_from_status=$(jq -r '.summary_file // empty' "$delegation_status_file" 2>/dev/null || echo "")
    if [[ -n "$delegation_summary_from_status" && "$delegation_summary_from_status" != "null" ]]; then
      echo "- Delegation summary: $delegation_summary_from_status" >> "$prompt_file"
    fi
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

  if [[ -n "$rlms_result_file" && -f "$rlms_result_file" ]]; then
    echo "" >> "$prompt_file"
    echo "## RLMS Context" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "RLMS analysis is available as a long-context index. Use it to locate relevant sections quickly, then verify against source files." >> "$prompt_file"
    if [[ -n "$rlms_summary_file" && -f "$rlms_summary_file" ]]; then
      echo "" >> "$prompt_file"
      echo "RLMS summary excerpt:" >> "$prompt_file"
      echo '```' >> "$prompt_file"
      sed -n '1,80p' "$rlms_summary_file" >> "$prompt_file"
      echo '```' >> "$prompt_file"
    fi
  fi

  # Add stuck detection context for planner role
  if [[ "$role" == "planner" ]]; then
    local stuck_file="$loop_dir/stuck.json"
    if [[ -f "$stuck_file" ]]; then
      local stuck_streak
      stuck_streak=$(jq -r '.streak // 0' "$stuck_file" 2>/dev/null || echo "0")

      if [[ "$stuck_streak" -ge 2 ]]; then
        local stuck_reason
        stuck_reason=$(jq -r '.reason // ""' "$stuck_file" 2>/dev/null || echo "")

        echo "" >> "$prompt_file"
        echo "## ⚠️ Stuck Detection Alert" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "You have been stuck for $stuck_streak consecutive iterations." >> "$prompt_file"
        echo "" >> "$prompt_file"

        if [[ "$stuck_reason" == "no_code_changes" ]]; then
          echo "**Reason**: No code changes detected" >> "$prompt_file"
        elif [[ "$stuck_reason" == "same_test_failures" ]]; then
          echo "**Reason**: Same test failures persist despite code changes (thrashing)" >> "$prompt_file"
        else
          echo "**Reason**: $stuck_reason" >> "$prompt_file"
        fi

        # Extract Reviewer's findings - they've seen this issue multiple times
        if [[ -f "$reviewer_report" ]]; then
          echo "" >> "$prompt_file" || return 1
          echo "**⚠️ The Reviewer Has Identified The Same Issue $stuck_streak Times:**" >> "$prompt_file" || return 1
          echo '```' >> "$prompt_file" || return 1
          # Extract High and Medium findings (most critical issues)
          if ! awk '/### High/,/### Low/' "$reviewer_report" 2>/dev/null | head -30 >> "$prompt_file" 2>/dev/null; then
            echo "(No findings in review report)" >> "$prompt_file" || return 1
          fi
          echo '```' >> "$prompt_file" || return 1
        fi

        echo "" >> "$prompt_file" || return 1
        echo "**Test Failures**:" >> "$prompt_file" || return 1
        # Extract TypeScript errors and test failures
        if [[ -f "$test_output" ]]; then
          echo '```' >> "$prompt_file" || return 1
          grep "error TS[0-9]" "$test_output" 2>/dev/null | head -10 >> "$prompt_file" 2>/dev/null || true
          grep -E "^(FAIL|Error:)" "$test_output" 2>/dev/null | head -5 >> "$prompt_file" 2>/dev/null || true
          if ! grep -q "error TS\|FAIL\|Error:" "$test_output" 2>/dev/null; then
            echo "(No test failures found in output)" >> "$prompt_file" || return 1
          fi
          echo '```' >> "$prompt_file" || return 1
        else
          echo "(Test output not available)" >> "$prompt_file" || return 1
        fi

        echo "" >> "$prompt_file"
        echo "---" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "## 🛑 CRITICAL - You Are In A Stuck Loop" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "The same test failures have persisted for **$stuck_streak iterations** despite code changes." >> "$prompt_file"
        echo "This means your **APPROACH is fundamentally wrong**, not just the implementation." >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "**REQUIRED ACTIONS:**" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "1. **Read the Reviewer's finding above** - it tells you what's actually failing" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "2. **Identify what conceptual approach you keep repeating**" >> "$prompt_file"
        echo "   - Look at recent tasks - are they all variations of the same idea?" >> "$prompt_file"
        echo "   - Example: If tasks 59-63 all say \"fix handler typing\" → you're repeating" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "3. **Try a FUNDAMENTALLY DIFFERENT solution** (not a variation):" >> "$prompt_file"
        echo "   - If fixing types keeps failing → use runtime approach with type assertions (\`as any\`)" >> "$prompt_file"
        echo "   - If adding generics keeps failing → use concrete types or \`unknown\`" >> "$prompt_file"
        echo "   - If accessing private properties keeps failing → use different API or remove helper" >> "$prompt_file"
        echo "   - If modifying test infrastructure keeps failing → rewrite tests without helpers" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "4. **If you cannot identify a fundamentally different approach** after reviewing the Reviewer's finding:" >> "$prompt_file"
        echo "   - STOP trying variations of the same approach" >> "$prompt_file"
        echo "   - State in your plan: \"This requires human intervention - recommend manual fix to [specific issue]\"" >> "$prompt_file"
        echo "   - Create a task documenting what was tried and why it can't be automated" >> "$prompt_file"
        echo "" >> "$prompt_file"
        echo "**Do not compromise code quality to pass gates. Better to acknowledge limits than create technical debt.**" >> "$prompt_file"
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

    # Pattern: HTTP 429 / Too Many Requests (strict; avoid matching arbitrary digits)
    if 'Too Many Requests' in line:
        info = {"message": "HTTP 429 Too Many Requests", "type": "http"}
        info.update(parsed_info)
        return True, info
    if re.search(r'\bHTTP(?:/\d+(?:\.\d+)?)?\b[^\n\r]{0,32}\b429\b', line, re.IGNORECASE):
        info = {"message": "HTTP 429 Too Many Requests", "type": "http"}
        info.update(parsed_info)
        return True, info
    if re.search(r'\b(?:status(?:\s+code)?|code)\s*[:=]\s*429\b', line, re.IGNORECASE):
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
  # Optional: thinking env var (e.g., "MAX_THINKING_TOKENS=10000")
  local thinking_env="${1:-}"
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
      # Generate session ID in parent shell (not subshell) so it persists
      USAGE_SESSION_ID=$(generate_session_id)

      # Inject --session-id after the 'claude' command
      local -a tracked_cmd=()
      local session_id_injected=0
      for arg in "${cmd[@]}"; do
        tracked_cmd+=("$arg")
        if [[ $session_id_injected -eq 0 && ("$arg" == "claude" || "$arg" == */claude) ]]; then
          tracked_cmd+=("--session-id" "$USAGE_SESSION_ID")
          session_id_injected=1
        fi
      done
      cmd=("${tracked_cmd[@]}")
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
  local original_prompt_mode="$prompt_mode"
  local codex_resume_on_rate_limit="${SUPERLOOP_CODEX_RESUME_ON_RATE_LIMIT:-0}"
  local codex_resume_enabled=0
  case "$codex_resume_on_rate_limit" in
    1|true|TRUE|True|yes|YES|on|ON)
      codex_resume_enabled=1
      ;;
  esac

  # Build env prefix array for command execution
  local -a env_prefix=()
  if [[ -n "$thinking_env" ]]; then
    env_prefix+=("env" "$thinking_env")
  fi

  while true; do
    status=0
    if [[ "${timeout_seconds:-0}" -gt 0 || "${inactivity_seconds:-0}" -gt 0 ]]; then
      if [[ ${#env_prefix[@]} -gt 0 ]]; then
        RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
          "${env_prefix[@]}" run_command_with_timeout "$prompt_file" "$log_file" "$timeout_seconds" "$prompt_mode" "$inactivity_seconds" "${cmd[@]}"
      else
        RUNNER_RATE_LIMIT_FILE="$rate_limit_file" \
          run_command_with_timeout "$prompt_file" "$log_file" "$timeout_seconds" "$prompt_mode" "$inactivity_seconds" "${cmd[@]}"
      fi
      status=$?
    else
      set +e
      if [[ "$prompt_mode" == "stdin" ]]; then
        if [[ ${#env_prefix[@]} -gt 0 ]]; then
          RUNNER_RATE_LIMIT_FILE="$rate_limit_file" "${env_prefix[@]}" "${cmd[@]}" < "$prompt_file" | tee "$log_file"
        else
          RUNNER_RATE_LIMIT_FILE="$rate_limit_file" "${cmd[@]}" < "$prompt_file" | tee "$log_file"
        fi
      else
        if [[ ${#env_prefix[@]} -gt 0 ]]; then
          RUNNER_RATE_LIMIT_FILE="$rate_limit_file" "${env_prefix[@]}" "${cmd[@]}" | tee "$log_file"
        else
          RUNNER_RATE_LIMIT_FILE="$rate_limit_file" "${cmd[@]}" | tee "$log_file"
        fi
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
        if [[ "$codex_resume_enabled" -eq 1 ]]; then
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
            prompt_mode="$original_prompt_mode"
          fi
        else
          echo "[superloop] Codex resume disabled; retrying from scratch" >&2
          # Rebuild original command
          cmd=()
          for part in "${runner_command[@]}"; do
            cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
          done
          for part in "${runner_args[@]}"; do
            cmd+=("$(expand_runner_arg "$part" "$repo" "$prompt_file" "$last_message_file")")
          done
          prompt_mode="$original_prompt_mode"
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
        prompt_mode="$original_prompt_mode"
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
  elif [[ "${cmd[0]}" == "codex" ]] || [[ "$cmd_str" == *"/codex "* ]] || [[ "$cmd_str" == *"/codex" ]] || [[ "$cmd_str" == *" codex "* ]] || [[ "$cmd_str" == *" codex" ]]; then
    # Also match "orb -m codex2 codex exec" style commands
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

  # Claude uses full absolute path with slashes replaced by dashes
  # e.g., /Users/foo/Work/project -> -Users-foo-Work-project
  local project_name="${repo//\//-}"

  # Claude stores sessions in ~/.claude/projects/<project>/<session-id>.jsonl
  local session_file="$HOME/.claude/projects/${project_name}/${session_id}.jsonl"

  if [[ -f "$session_file" ]]; then
    echo "$session_file"
    return 0
  fi

  # Try alternative: just the basename (for backwards compatibility)
  local basename_name
  basename_name=$(basename "$repo")
  local alt_file="$HOME/.claude/projects/-${basename_name}/${session_id}.jsonl"
  if [[ -f "$alt_file" ]]; then
    echo "$alt_file"
    return 0
  fi

  # Try glob match as last resort
  for alt_file in "$HOME/.claude/projects"/*"$basename_name"*/"${session_id}.jsonl"; do
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
  # Includes thinking_tokens for extended thinking (billed separately from output_tokens)
  jq -s '
    [.[] | select(.type == "assistant" and .message.usage != null) | .message.usage] |
    if length == 0 then
      {"input_tokens": 0, "output_tokens": 0, "thinking_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
    else
      {
        "input_tokens": (map(.input_tokens // 0) | add),
        "output_tokens": (map(.output_tokens // 0) | add),
        "thinking_tokens": (map(.thinking_tokens // 0) | add),
        "cache_read_input_tokens": (map(.cache_read_input_tokens // 0) | add),
        "cache_creation_input_tokens": (map(.cache_creation_input_tokens // 0) | add)
      }
    end
  ' "$session_file" 2>/dev/null || echo '{"error": "failed to parse session file"}'
}

# Extract usage from Codex log output (fallback when session files unavailable)
# Codex prints "tokens used\n{number}" at the end of runs
# Args: $1 = log_file
# Output: JSON object with usage stats
extract_codex_usage_from_log() {
  local log_file="$1"

  if [[ ! -f "$log_file" ]]; then
    echo '{"input_tokens": 0, "output_tokens": 0}'
    return 1
  fi

  # Extract "tokens used\n{number}" pattern from log
  # The number on the line after "tokens used" is the total tokens
  local total_tokens
  total_tokens=$(grep -A1 "^tokens used$" "$log_file" 2>/dev/null | tail -1 | tr -d ',' | tr -d ' ')

  if [[ "$total_tokens" =~ ^[0-9]+$ ]]; then
    # Codex doesn't break down input/output in log, so we report as total
    # Using output_tokens since that's typically what matters for billing
    echo "{\"input_tokens\": 0, \"output_tokens\": $total_tokens, \"total_tokens\": $total_tokens}"
  else
    echo '{"input_tokens": 0, "output_tokens": 0}'
  fi
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
  # Structure: .payload.info.total_token_usage contains the cumulative counts
  # We take the last token_count event which has the final totals
  # Includes reasoning_output_tokens for reasoning effort (similar to Claude thinking_tokens)
  jq -s '
    [.[] | select(.type == "event_msg" and .payload.type == "token_count") | .payload.info.total_token_usage // .payload] |
    if length == 0 then
      {"input_tokens": 0, "output_tokens": 0, "cached_input_tokens": 0, "reasoning_output_tokens": 0}
    else
      # Take the last entry (cumulative totals) rather than summing
      .[-1] |
      {
        "input_tokens": (.input_tokens // 0),
        "output_tokens": (.output_tokens // 0),
        "cached_input_tokens": (.cached_input_tokens // 0),
        "reasoning_output_tokens": (.reasoning_output_tokens // 0)
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
  model=$(jq -s -r '[.[] | select(.type == "assistant" and .message.model != null) | .message.model][0] // empty' "$session_file" 2>/dev/null)

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
  model=$(jq -s -r '[.[] | select(.model != null) | .model][0] // empty' "$session_file" 2>/dev/null)

  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  # Try alternate structure (without -s for single JSON object)
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

  # Calculate cost if pricing functions are available
  local cost_usd="0"
  if type calculate_cost &>/dev/null && [[ -n "${USAGE_MODEL:-}" ]]; then
    cost_usd=$(calculate_cost "$runner_type" "${USAGE_MODEL}" "$usage_json" 2>/dev/null || echo "0")
  fi

  # Build the event JSON - include session/thread IDs, model, and cost
  jq -c -n \
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
    --argjson cost "$cost_usd" \
    '{
      "timestamp": $ts,
      "iteration": $iter,
      "role": $role,
      "duration_ms": $duration,
      "runner": $runner,
      "model": (if $model == "" then null else $model end),
      "cost_usd": $cost,
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
          # Fallback: extract tokens from log output if session file not found or has no tokens
          # This handles cases where Codex runs in a VM (e.g., via orb) and sessions aren't on host
          if [[ -n "$log_file" && -f "$log_file" ]]; then
            local log_usage
            log_usage=$(extract_codex_usage_from_log "$log_file")
            local log_tokens
            log_tokens=$(echo "$log_usage" | jq -r '.total_tokens // 0' 2>/dev/null)
            if [[ "$log_tokens" -gt 0 ]]; then
              usage_json="$log_usage"
            fi
            # Extract model from log if not found from session
            if [[ -z "$USAGE_MODEL" ]]; then
              USAGE_MODEL=$(extract_codex_model_from_log "$log_file" || true)
            fi
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

  # Pattern: HTTP 429 / Too Many Requests (strict; avoid matching arbitrary digits)
  if echo "$line" | grep -qi "Too Many Requests"; then
    RATE_LIMIT_DETECTED=1
    RATE_LIMIT_MESSAGE="HTTP 429 Too Many Requests"
    return 0
  fi
  if echo "$line" | grep -Eqi 'HTTP(/[0-9]+(\.[0-9]+)?)?[^0-9\r\n]{0,32}429|((status( code)?)|code)[[:space:]]*[:=][[:space:]]*429'; then
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

# Generate a usage-limit-local session ID for rate-limit resume bookkeeping.
# Note: do not shadow usage tracking's generate_session_id() from src/35-usage.sh.
generate_usage_limit_session_id() {
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

# Extract thread/session ID from Codex JSON output text.
# Arguments: output_text
extract_codex_thread_id_from_output() {
  local output="$1"
  echo "$output" | grep -oE '"thread_id":\s*"[^"]*"' | sed 's/"thread_id":\s*"//' | sed 's/"$//' | head -1 || true
}

# Pricing data and cost calculation for Claude and Codex models
# Prices are per million tokens (MTok)
# Last updated: 2026-01-14

# -----------------------------------------------------------------------------
# Pricing Tables (USD per Million Tokens)
# -----------------------------------------------------------------------------

# Get pricing for a model
# Args: $1 = model_id (e.g., "claude-sonnet-4-5-20250929", "gpt-5.2-codex")
# Output: JSON object with pricing per MTok
get_model_pricing() {
  local model="$1"

  # Normalize model ID (remove date suffixes for matching)
  local model_base
  model_base=$(echo "$model" | sed -E 's/-[0-9]{8}$//')

  case "$model_base" in
    # Claude 4.5 models
    claude-opus-4-5|claude-opus-4.5)
      echo '{"input": 5, "output": 25, "thinking": 25, "cache_read": 0.50, "cache_write": 6.25}'
      ;;
    claude-sonnet-4-5|claude-sonnet-4.5)
      echo '{"input": 3, "output": 15, "thinking": 15, "cache_read": 0.30, "cache_write": 3.75}'
      ;;
    claude-haiku-4-5|claude-haiku-4.5)
      echo '{"input": 1, "output": 5, "thinking": 5, "cache_read": 0.10, "cache_write": 1.25}'
      ;;

    # Claude 4.x models
    claude-opus-4|claude-opus-4.1)
      echo '{"input": 15, "output": 75, "thinking": 75, "cache_read": 1.50, "cache_write": 18.75}'
      ;;
    claude-sonnet-4)
      echo '{"input": 3, "output": 15, "thinking": 15, "cache_read": 0.30, "cache_write": 3.75}'
      ;;

    # OpenAI/Codex models
    gpt-5.2-codex|gpt-5.2-codex-*)
      echo '{"input": 1.75, "output": 14, "reasoning": 14, "cached_input": 0.18}'
      ;;
    gpt-5.1-codex|gpt-5.1-codex-*|gpt-5.1-codex-max|gpt-5.1-codex-mini)
      echo '{"input": 1.25, "output": 10, "reasoning": 10, "cached_input": 0.125}'
      ;;
    gpt-5-codex|gpt-5-codex-*)
      echo '{"input": 1.25, "output": 10, "reasoning": 10, "cached_input": 0.125}'
      ;;

    # Default fallback (use Sonnet 4.5 pricing as reasonable default)
    *)
      echo '{"input": 3, "output": 15, "thinking": 15, "reasoning": 15, "cache_read": 0.30, "cache_write": 3.75, "cached_input": 0.30}'
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Cost Calculation
# -----------------------------------------------------------------------------

# Calculate cost for Claude usage
# Args: $1 = model, $2 = usage_json (with input_tokens, output_tokens, thinking_tokens, cache_read_input_tokens, cache_creation_input_tokens)
# Output: cost in USD (decimal)
calculate_claude_cost() {
  local model="$1"
  local usage_json="$2"

  local pricing
  pricing=$(get_model_pricing "$model")

  # Extract token counts (default to 0)
  local input_tokens output_tokens thinking_tokens cache_read cache_write
  input_tokens=$(echo "$usage_json" | jq -r '.input_tokens // 0')
  output_tokens=$(echo "$usage_json" | jq -r '.output_tokens // 0')
  thinking_tokens=$(echo "$usage_json" | jq -r '.thinking_tokens // 0')
  cache_read=$(echo "$usage_json" | jq -r '.cache_read_input_tokens // 0')
  cache_write=$(echo "$usage_json" | jq -r '.cache_creation_input_tokens // 0')

  # Extract prices
  local price_input price_output price_thinking price_cache_read price_cache_write
  price_input=$(echo "$pricing" | jq -r '.input')
  price_output=$(echo "$pricing" | jq -r '.output')
  price_thinking=$(echo "$pricing" | jq -r '.thinking // .output')
  price_cache_read=$(echo "$pricing" | jq -r '.cache_read // .input')
  price_cache_write=$(echo "$pricing" | jq -r '.cache_write // .input')

  # Calculate cost (tokens / 1M * price_per_MTok)
  # Using awk for floating point math
  awk -v input="$input_tokens" -v output="$output_tokens" -v thinking="$thinking_tokens" \
      -v cache_read="$cache_read" -v cache_write="$cache_write" \
      -v p_input="$price_input" -v p_output="$price_output" -v p_thinking="$price_thinking" \
      -v p_cache_read="$price_cache_read" -v p_cache_write="$price_cache_write" \
      'BEGIN {
        cost = (input / 1000000 * p_input) + \
               (output / 1000000 * p_output) + \
               (thinking / 1000000 * p_thinking) + \
               (cache_read / 1000000 * p_cache_read) + \
               (cache_write / 1000000 * p_cache_write)
        printf "%.6f\n", cost
      }'
}

# Calculate cost for Codex usage
# Args: $1 = model, $2 = usage_json (with input_tokens, output_tokens, reasoning_output_tokens, cached_input_tokens)
# Output: cost in USD (decimal)
calculate_codex_cost() {
  local model="$1"
  local usage_json="$2"

  local pricing
  pricing=$(get_model_pricing "$model")

  # Extract token counts (default to 0)
  local input_tokens output_tokens reasoning_tokens cached_tokens
  input_tokens=$(echo "$usage_json" | jq -r '.input_tokens // 0')
  output_tokens=$(echo "$usage_json" | jq -r '.output_tokens // 0')
  reasoning_tokens=$(echo "$usage_json" | jq -r '.reasoning_output_tokens // 0')
  cached_tokens=$(echo "$usage_json" | jq -r '.cached_input_tokens // 0')

  # Extract prices
  local price_input price_output price_reasoning price_cached
  price_input=$(echo "$pricing" | jq -r '.input')
  price_output=$(echo "$pricing" | jq -r '.output')
  price_reasoning=$(echo "$pricing" | jq -r '.reasoning // .output')
  price_cached=$(echo "$pricing" | jq -r '.cached_input // (.input * 0.1)')

  # Calculate cost (tokens / 1M * price_per_MTok)
  # Note: input_tokens from Codex is non-cached input, so we add cached separately
  awk -v input="$input_tokens" -v output="$output_tokens" -v reasoning="$reasoning_tokens" \
      -v cached="$cached_tokens" \
      -v p_input="$price_input" -v p_output="$price_output" -v p_reasoning="$price_reasoning" \
      -v p_cached="$price_cached" \
      'BEGIN {
        cost = (input / 1000000 * p_input) + \
               (output / 1000000 * p_output) + \
               (reasoning / 1000000 * p_reasoning) + \
               (cached / 1000000 * p_cached)
        printf "%.6f\n", cost
      }'
}

# Calculate cost based on runner type
# Args: $1 = runner_type (claude|codex), $2 = model, $3 = usage_json
# Output: cost in USD (decimal)
calculate_cost() {
  local runner_type="$1"
  local model="$2"
  local usage_json="$3"

  case "$runner_type" in
    claude)
      calculate_claude_cost "$model" "$usage_json"
      ;;
    codex|openai)
      calculate_codex_cost "$model" "$usage_json"
      ;;
    *)
      # Unknown runner, return 0
      echo "0"
      ;;
  esac
}

# Format cost as human-readable string
# Args: $1 = cost (decimal USD)
# Output: formatted string (e.g., "$0.0042", "$1.23")
format_cost() {
  local cost="$1"

  awk -v cost="$cost" 'BEGIN {
    if (cost < 0.01) {
      printf "$%.4f\n", cost
    } else if (cost < 1) {
      printf "$%.3f\n", cost
    } else {
      printf "$%.2f\n", cost
    }
  }'
}

# -----------------------------------------------------------------------------
# Aggregate Usage Summary
# -----------------------------------------------------------------------------

# Aggregate usage from JSONL file
# Args: $1 = usage_file (path to usage.jsonl)
# Output: JSON summary with totals per runner, per role, and overall
aggregate_usage() {
  local usage_file="$1"

  if [[ ! -f "$usage_file" ]]; then
    echo '{"error": "usage file not found"}'
    return 1
  fi

  jq -s '
    # Group by runner type
    group_by(.runner) |
    map({
      runner: .[0].runner,
      total_duration_ms: (map(.duration_ms) | add),
      total_cost_usd: 0,
      by_role: (group_by(.role) | map({
        role: .[0].role,
        iterations: length,
        duration_ms: (map(.duration_ms) | add),
        usage: (
          if .[0].runner == "claude" then
            {
              input_tokens: (map(.usage.input_tokens // 0) | add),
              output_tokens: (map(.usage.output_tokens // 0) | add),
              thinking_tokens: (map(.usage.thinking_tokens // 0) | add),
              cache_read_input_tokens: (map(.usage.cache_read_input_tokens // 0) | add),
              cache_creation_input_tokens: (map(.usage.cache_creation_input_tokens // 0) | add)
            }
          else
            {
              input_tokens: (map(.usage.input_tokens // 0) | add),
              output_tokens: (map(.usage.output_tokens // 0) | add),
              reasoning_output_tokens: (map(.usage.reasoning_output_tokens // 0) | add),
              cached_input_tokens: (map(.usage.cached_input_tokens // 0) | add)
            }
          end
        )
      })),
      totals: (
        if .[0].runner == "claude" then
          {
            input_tokens: (map(.usage.input_tokens // 0) | add),
            output_tokens: (map(.usage.output_tokens // 0) | add),
            thinking_tokens: (map(.usage.thinking_tokens // 0) | add),
            cache_read_input_tokens: (map(.usage.cache_read_input_tokens // 0) | add),
            cache_creation_input_tokens: (map(.usage.cache_creation_input_tokens // 0) | add)
          }
        else
          {
            input_tokens: (map(.usage.input_tokens // 0) | add),
            output_tokens: (map(.usage.output_tokens // 0) | add),
            reasoning_output_tokens: (map(.usage.reasoning_output_tokens // 0) | add),
            cached_input_tokens: (map(.usage.cached_input_tokens // 0) | add)
          }
        end
      )
    }) |
    {
      by_runner: .,
      total_duration_ms: (map(.total_duration_ms) | add),
      total_iterations: ([.[].by_role[].iterations] | add)
    }
  ' "$usage_file" 2>/dev/null || echo '{"error": "failed to aggregate usage"}'
}

# Calculate total cost from aggregated usage
# Args: $1 = aggregated_json (from aggregate_usage), $2 = default_claude_model, $3 = default_codex_model
# Output: JSON with costs added
calculate_aggregate_costs() {
  local aggregated="$1"
  local claude_model="${2:-claude-sonnet-4-5}"
  local codex_model="${3:-gpt-5.2-codex}"

  local total_cost=0
  local result="$aggregated"

  # Process each runner
  for runner in $(echo "$aggregated" | jq -r '.by_runner[].runner'); do
    local runner_totals model cost
    runner_totals=$(echo "$aggregated" | jq -r ".by_runner[] | select(.runner == \"$runner\") | .totals")

    if [[ "$runner" == "claude" ]]; then
      model="$claude_model"
      cost=$(calculate_claude_cost "$model" "$runner_totals")
    else
      model="$codex_model"
      cost=$(calculate_codex_cost "$model" "$runner_totals")
    fi

    total_cost=$(awk -v t="$total_cost" -v c="$cost" 'BEGIN { printf "%.6f", t + c }')

    # Update runner cost in result
    result=$(echo "$result" | jq --arg runner "$runner" --argjson cost "$cost" '
      .by_runner |= map(if .runner == $runner then .total_cost_usd = $cost else . end)
    ')
  done

  # Add total cost
  echo "$result" | jq --argjson cost "$total_cost" '. + {total_cost_usd: $cost}'
}

# -----------------------------------------------------------------------------
# Usage Command
# -----------------------------------------------------------------------------

# Format duration in human-readable form
format_duration() {
  local ms="$1"
  local seconds=$((ms / 1000))
  local minutes=$((seconds / 60))
  local hours=$((minutes / 60))

  if [[ $hours -gt 0 ]]; then
    printf "%dh %dm %ds" $hours $((minutes % 60)) $((seconds % 60))
  elif [[ $minutes -gt 0 ]]; then
    printf "%dm %ds" $minutes $((seconds % 60))
  else
    printf "%ds" $seconds
  fi
}

# Format token count with K/M suffix
format_tokens() {
  local tokens="$1"
  if [[ $tokens -ge 1000000 ]]; then
    awk -v t="$tokens" 'BEGIN { printf "%.1fM", t/1000000 }'
  elif [[ $tokens -ge 1000 ]]; then
    awk -v t="$tokens" 'BEGIN { printf "%.1fK", t/1000 }'
  else
    echo "$tokens"
  fi
}

# Usage command - display usage summary for a loop
# Args: $1 = repo, $2 = loop_id, $3 = config_path, $4 = json_output (0|1)
usage_cmd() {
  local repo="$1"
  local loop_id="$2"
  local config_path="$3"
  local json_output="${4:-0}"

  # If no loop_id, try to find one
  if [[ -z "$loop_id" ]]; then
    # Get first loop from config
    if [[ -f "$config_path" ]]; then
      loop_id=$(jq -r '.loops[0].id // empty' "$config_path" 2>/dev/null || true)
    fi
    if [[ -z "$loop_id" ]]; then
      echo "error: no loop specified and no loops in config" >&2
      return 1
    fi
  fi

  local loop_dir="$repo/.superloop/loops/$loop_id"
  local usage_file="$loop_dir/usage.jsonl"

  if [[ ! -f "$usage_file" ]]; then
    echo "error: no usage data found for loop '$loop_id'" >&2
    echo "       expected: $usage_file" >&2
    return 1
  fi

  # Aggregate usage
  local aggregated
  aggregated=$(aggregate_usage "$usage_file")

  if echo "$aggregated" | jq -e '.error' >/dev/null 2>&1; then
    echo "error: $(echo "$aggregated" | jq -r '.error')" >&2
    return 1
  fi

  # Calculate costs (try to get models from usage data)
  local claude_model codex_model
  claude_model=$(jq -s -r '[.[] | select(.runner == "claude") | .model][0] // "claude-sonnet-4-5"' "$usage_file" 2>/dev/null)
  codex_model=$(jq -s -r '[.[] | select(.runner == "codex") | .model][0] // "gpt-5.2-codex"' "$usage_file" 2>/dev/null)

  local with_costs
  with_costs=$(calculate_aggregate_costs "$aggregated" "$claude_model" "$codex_model")

  # JSON output mode
  if [[ "$json_output" -eq 1 ]]; then
    echo "$with_costs" | jq --arg loop "$loop_id" '. + {loop_id: $loop}'
    return 0
  fi

  # Human-readable output
  echo "Usage Summary: $loop_id"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  local total_iterations total_duration total_cost
  total_iterations=$(echo "$with_costs" | jq -r '.total_iterations // 0')
  total_duration=$(echo "$with_costs" | jq -r '.total_duration_ms // 0')
  total_cost=$(echo "$with_costs" | jq -r '.total_cost_usd // 0')

  printf "Total: %s iterations, %s, %s\n\n" \
    "$total_iterations" \
    "$(format_duration "$total_duration")" \
    "$(format_cost "$total_cost")"

  # Per-runner breakdown
  local runners
  runners=$(echo "$with_costs" | jq -r '.by_runner[].runner' 2>/dev/null)

  for runner in $runners; do
    local runner_data runner_cost runner_duration
    runner_data=$(echo "$with_costs" | jq ".by_runner[] | select(.runner == \"$runner\")")
    runner_cost=$(echo "$runner_data" | jq -r '.total_cost_usd // 0')
    runner_duration=$(echo "$runner_data" | jq -r '.total_duration_ms // 0')

    echo "[$runner] $(format_cost "$runner_cost"), $(format_duration "$runner_duration")"
    echo "───────────────────────────────────────────────────────────────"

    # Per-role breakdown
    local roles
    roles=$(echo "$runner_data" | jq -r '.by_role[].role')

    for role in $roles; do
      local role_data iters role_dur
      role_data=$(echo "$runner_data" | jq ".by_role[] | select(.role == \"$role\")")
      iters=$(echo "$role_data" | jq -r '.iterations')
      role_dur=$(echo "$role_data" | jq -r '.duration_ms // 0')

      # Token breakdown
      local input output thinking cached
      input=$(echo "$role_data" | jq -r '.usage.input_tokens // 0')
      output=$(echo "$role_data" | jq -r '.usage.output_tokens // 0')

      if [[ "$runner" == "claude" ]]; then
        thinking=$(echo "$role_data" | jq -r '.usage.thinking_tokens // 0')
        cached=$(echo "$role_data" | jq -r '.usage.cache_read_input_tokens // 0')
      else
        thinking=$(echo "$role_data" | jq -r '.usage.reasoning_output_tokens // 0')
        cached=$(echo "$role_data" | jq -r '.usage.cached_input_tokens // 0')
      fi

      printf "  %-12s %dx  %s  in:%-6s out:%-6s" \
        "$role" "$iters" "$(format_duration "$role_dur")" \
        "$(format_tokens "$input")" "$(format_tokens "$output")"

      if [[ "$thinking" -gt 0 ]]; then
        printf " think:%-6s" "$(format_tokens "$thinking")"
      fi
      if [[ "$cached" -gt 0 ]]; then
        printf " cache:%-6s" "$(format_tokens "$cached")"
      fi
      echo ""
    done
    echo ""
  done
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

#!/usr/bin/env bash
# Git operations for superloop
# Handles automatic commits after iterations

# Auto-commit changes after an iteration
# Arguments:
#   $1 - repo path
#   $2 - loop_id
#   $3 - iteration number
#   $4 - tests_status (ok, failed, skipped)
#   $5 - commit_strategy (per_iteration, on_test_pass, never)
#   $6 - events_file for logging
#   $7 - run_id
#   $8 - pre_commit_commands (optional command to run before commit)
# Returns: 0 on success or skip, 1 on failure
auto_commit_iteration() {
  local repo="$1"
  local loop_id="$2"
  local iteration="$3"
  local tests_status="$4"
  local commit_strategy="$5"
  local events_file="$6"
  local run_id="$7"
  local pre_commit_commands="${8:-}"

  # Check if commits are disabled
  if [[ "$commit_strategy" == "never" || -z "$commit_strategy" ]]; then
    return 0
  fi

  # Check if we should skip based on test status
  if [[ "$commit_strategy" == "on_test_pass" && "$tests_status" != "ok" ]]; then
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_skipped" \
      "$(jq -n --arg reason "tests_not_passing" --arg tests_status "$tests_status" '{reason: $reason, tests_status: $tests_status}')"
    return 0
  fi

  # Check if there are any changes to commit
  local has_changes=0
  if ! git -C "$repo" diff --quiet HEAD 2>/dev/null; then
    has_changes=1
  fi
  if [[ $has_changes -eq 0 ]] && [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
    has_changes=1
  fi

  if [[ $has_changes -eq 0 ]]; then
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_skipped" \
      "$(jq -n --arg reason "no_changes" '{reason: $reason}')"
    return 0
  fi

  # Determine what phase we're in by looking at task files
  local loop_dir="$repo/.superloop/loops/$loop_id"
  local current_phase="unknown"
  local latest_phase_file
  latest_phase_file=$(ls -t "$loop_dir/tasks/"PHASE_*.MD 2>/dev/null | head -1)
  if [[ -n "$latest_phase_file" ]]; then
    current_phase=$(basename "$latest_phase_file" .MD | sed 's/PHASE_/Phase /')
  fi

  # Build commit message
  local test_indicator=""
  case "$tests_status" in
    ok) test_indicator="tests: passing" ;;
    failed) test_indicator="tests: failing" ;;
    skipped) test_indicator="tests: skipped" ;;
    *) test_indicator="tests: $tests_status" ;;
  esac

  local commit_msg="[superloop] $loop_id iteration $iteration: $current_phase ($test_indicator)"

  # Stage all changes (including untracked files in the repo, excluding .superloop internal files)
  # We want to commit implementation work, not loop state files
  local staged_count=0

  # Stage tracked file changes
  git -C "$repo" add -u 2>/dev/null || true

  # Stage new files, excluding .superloop directory
  while IFS= read -r file; do
    if [[ -n "$file" && ! "$file" =~ ^\.superloop/ ]]; then
      git -C "$repo" add "$file" 2>/dev/null || true
      ((staged_count++)) || true
    fi
  done < <(git -C "$repo" status --porcelain 2>/dev/null | grep '^??' | cut -c4-)

  # Check if we actually staged anything
  if git -C "$repo" diff --cached --quiet 2>/dev/null; then
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_skipped" \
      "$(jq -n --arg reason "nothing_staged" '{reason: $reason}')"
    return 0
  fi

  # Run pre-commit commands if configured
  if [[ -n "$pre_commit_commands" ]]; then
    echo "[superloop] Running pre-commit commands: $pre_commit_commands" >&2
    local pre_commit_output
    local pre_commit_exit_code
    # Execute exactly once via a shell to avoid eval's double expansion.
    pre_commit_output=$(cd "$repo" && bash -o pipefail -c "$pre_commit_commands" 2>&1)
    pre_commit_exit_code=$?

    # Log pre-commit execution to events (for reviewer visibility)
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "pre_commit_executed" \
      "$(jq -n --arg cmd "$pre_commit_commands" --arg exit_code "$pre_commit_exit_code" --arg output "$pre_commit_output" '{command: $cmd, exit_code: ($exit_code | tonumber), output: $output}')"

    # Write lint feedback to a file for Reviewer to read
    local lint_feedback_file="$loop_dir/lint-feedback.txt"
    cat > "$lint_feedback_file" <<EOF
# Lint Feedback (Iteration $iteration)

Command: $pre_commit_commands
Exit Code: $pre_commit_exit_code
Status: $([ $pre_commit_exit_code -eq 0 ] && echo "SUCCESS" || echo "FAILED")

## Output:
$pre_commit_output
EOF

    if [[ $pre_commit_exit_code -ne 0 ]]; then
      echo "[superloop] Pre-commit commands failed (exit $pre_commit_exit_code), attempting commit anyway..." >&2
      echo "[superloop] Output: $pre_commit_output" >&2
    else
      echo "[superloop] Pre-commit commands succeeded" >&2
    fi

    # Re-stage changes after pre-commit commands (e.g., lint fixes)
    git -C "$repo" add -u 2>/dev/null || true

    # Stage any new files that might have been created, excluding .superloop
    while IFS= read -r file; do
      if [[ -n "$file" && ! "$file" =~ ^\.superloop/ ]]; then
        git -C "$repo" add "$file" 2>/dev/null || true
      fi
    done < <(git -C "$repo" status --porcelain 2>/dev/null | grep '^??' | cut -c4-)
  fi

  # Create the commit
  local commit_output
  local commit_exit_code
  commit_output=$(git -C "$repo" commit -m "$commit_msg

Automated commit by superloop after iteration $iteration.
Strategy: $commit_strategy

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>" 2>&1)
  commit_exit_code=$?

  if [[ $commit_exit_code -eq 0 ]]; then
    local commit_sha
    commit_sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_success" \
      "$(jq -n --arg sha "$commit_sha" --arg message "$commit_msg" --arg strategy "$commit_strategy" '{sha: $sha, message: $message, strategy: $strategy}')"
    echo "[superloop] Auto-committed: $commit_sha - $commit_msg" >&2
    return 0
  else
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "auto_commit_failed" \
      "$(jq -n --arg error "$commit_output" --arg strategy "$commit_strategy" '{error: $error, strategy: $strategy}')"
    echo "[superloop] Auto-commit failed: $commit_output" >&2
    return 1
  fi
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

summarize_delegation_iteration_metrics() {
  local delegation_index_file="$1"
  local run_id="$2"
  local iteration="$3"

  if [[ ! -f "$delegation_index_file" ]]; then
    echo '{}'
    return 0
  fi

  jq -c \
    --arg run_id "$run_id" \
    --argjson iteration "$iteration" \
    '
    (.entries // []) as $all
    | [ $all[] | select((.run_id // "") == $run_id and ((.iteration // -1) == $iteration)) ] as $entries
    | {
        role_entries: ($entries | length),
        enabled_roles: ($entries | map(select(.enabled == true)) | length),
        requested_children: ($entries | map(.requested_children // 0) | add // 0),
        executed_children: ($entries | map(.executed_children // 0) | add // 0),
        succeeded_children: ($entries | map(.succeeded_children // 0) | add // 0),
        failed_children: ($entries | map(.failed_children // 0) | add // 0),
        adaptation_attempted: ($entries | map(.adaptation_attempted // 0) | add // 0),
        adaptation_applied: ($entries | map(.adaptation_applied // 0) | add // 0),
        adaptation_skipped: ($entries | map(.adaptation_skipped // 0) | add // 0),
        fail_role_triggered: ($entries | map(select(.fail_role_triggered == true)) | length),
        recon_violations: ($entries | map(.recon_violations // 0) | add // 0),
        statuses: (
          [ $entries[] | (.status // "unknown") ] as $statuses
          | reduce $statuses[] as $s ({}; .[$s] = ((.[$s] // 0) + 1))
        ),
        by_role: (
          reduce $entries[] as $e ({};
            .[$e.role] = {
              enabled: ($e.enabled // false),
              mode: ($e.mode // "standard"),
              dispatch_mode: ($e.dispatch_mode // "serial"),
              wake_policy: ($e.wake_policy // "on_wave_complete"),
              status: ($e.status // "unknown"),
              reason: ($e.reason // null),
              requested_children: ($e.requested_children // 0),
              executed_children: ($e.executed_children // 0),
              succeeded_children: ($e.succeeded_children // 0),
              failed_children: ($e.failed_children // 0),
              adaptation_attempted: ($e.adaptation_attempted // 0),
              adaptation_applied: ($e.adaptation_applied // 0),
              adaptation_skipped: ($e.adaptation_skipped // 0),
              fail_role_triggered: ($e.fail_role_triggered // false),
              recon_violations: ($e.recon_violations // 0),
              status_file: ($e.status_file // null)
            }
          )
        )
      }
    ' "$delegation_index_file" 2>/dev/null || echo '{}'
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
  local rlms_index_file="$loop_dir/rlms/index.json"
  local delegation_index_file="$loop_dir/delegation/index.json"
  local validation_status_file="$loop_dir/validation-status.json"
  local validation_results_file="$loop_dir/validation-results.json"

  local plan_meta implementer_meta test_report_meta reviewer_meta
  local test_output_meta test_status_meta checklist_status_meta checklist_remaining_meta
  local evidence_meta summary_meta notes_meta events_meta reviewer_packet_meta approval_meta decisions_meta decisions_md_meta
  local rlms_index_meta delegation_index_meta
  local validation_status_meta validation_results_meta
  local delegation_metrics_json

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
  rlms_index_meta=$(file_meta_json "${rlms_index_file#$repo/}" "$rlms_index_file")
  rlms_index_meta=$(json_or_default "$rlms_index_meta" "{}")
  delegation_index_meta=$(file_meta_json "${delegation_index_file#$repo/}" "$delegation_index_file")
  delegation_index_meta=$(json_or_default "$delegation_index_meta" "{}")
  delegation_metrics_json=$(summarize_delegation_iteration_metrics "$delegation_index_file" "$run_id" "$iteration")
  delegation_metrics_json=$(json_or_default "$delegation_metrics_json" "{}")

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
    --argjson rlms_index "$rlms_index_meta" \
    --argjson delegation_index "$delegation_index_meta" \
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
      decisions_md: $decisions_md,
      rlms_index: $rlms_index,
      delegation_index: $delegation_index
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
    --arg delegation "$delegation_metrics_json" \
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
      delegation: ($delegation | fromjson? // {}),
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
      "- \(.ended_at // .started_at) run=\(.run_id // "unknown") iter=\(.iteration) promise=\(.promise.matched // "unknown") tests=\(.gates.tests // "unknown") validation=\(.gates.validation // "unknown") checklist=\(.gates.checklist // "unknown") evidence=\(.gates.evidence // "unknown") approval=\(.gates.approval // "unknown") stuck=\(.stuck.streak // 0)/\(.stuck.threshold // 0) delegation_roles=\(.delegation.role_entries // 0) delegation_enabled=\(.delegation.enabled_roles // 0) delegation_children=\(.delegation.executed_children // 0) delegation_failed=\(.delegation.failed_children // 0) delegation_recon_violations=\(.delegation.recon_violations // 0) completion=\(.completion_ok // false)"' \
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

# Infrastructure Recovery System - Phase 1
# Enables automatic recovery from common infrastructure failures

# Check if a command is in the auto-approve list
# Returns 0 if approved, 1 if not
is_recovery_approved() {
  local command="$1"
  shift
  local auto_approve=("$@")

  for approved in "${auto_approve[@]}"; do
    if [[ "$command" == "$approved" ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a command is in the require-human list (blocked)
# Returns 0 if blocked, 1 if not
is_recovery_blocked() {
  local command="$1"
  shift
  local require_human=("$@")

  for blocked in "${require_human[@]}"; do
    # Support glob patterns with * wildcard
    if [[ "$blocked" == *"*"* ]]; then
      # Convert glob to regex: * -> .*
      local pattern="${blocked//\*/.*}"
      if [[ "$command" =~ ^$pattern$ ]]; then
        return 0
      fi
    elif [[ "$command" == "$blocked" ]]; then
      return 0
    fi
  done
  return 1
}

# Check whether a path is inside the repository root.
# Returns 0 if inside, 1 if outside.
is_path_within_repo() {
  local path_to_check="$1"
  local repo_root="$2"
  [[ "$path_to_check" == "$repo_root" || "$path_to_check" == "$repo_root/"* ]]
}

# Reject recovery commands that rely on shell substitution primitives.
# Returns 0 if safe enough to execute, 1 otherwise.
is_recovery_command_safe() {
  local command="$1"

  if [[ "$command" == *$'\n'* || "$command" == *$'\r'* ]]; then
    return 1
  fi

  if [[ "$command" == *'`'* || "$command" == *'$('* || "$command" == *'${'* ]]; then
    return 1
  fi

  return 0
}

# Resolve working directory and ensure it remains inside the repository.
# Outputs resolved absolute path on success.
resolve_recovery_working_dir() {
  local repo="$1"
  local working_dir="${2:-.}"

  local repo_root
  repo_root=$(cd "$repo" 2>/dev/null && pwd -P) || return 1

  local resolved_dir
  resolved_dir=$(cd "$repo_root" 2>/dev/null && cd "$working_dir" 2>/dev/null && pwd -P) || return 1

  if ! is_path_within_repo "$resolved_dir" "$repo_root"; then
    return 1
  fi

  printf '%s\n' "$resolved_dir"
}

# Execute a recovery command
# Returns exit code of the command
execute_recovery() {
  local repo="$1"
  local command="$2"
  local working_dir="${3:-.}"
  local timeout_seconds="${4:-120}"

  if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$timeout_seconds" -le 0 ]]; then
    echo "Invalid recovery timeout_seconds: $timeout_seconds" >&2
    return 1
  fi

  if ! is_recovery_command_safe "$command"; then
    echo "Recovery command rejected due to unsafe shell substitutions: $command" >&2
    return 1
  fi

  local full_dir
  full_dir=$(resolve_recovery_working_dir "$repo" "$working_dir")
  if [[ -z "$full_dir" ]]; then
    echo "Recovery working directory is invalid or outside repository: $working_dir" >&2
    return 1
  fi

  local start_time
  start_time=$(date +%s)

  # Execute with timeout
  local output
  local exit_code
  set +e
  output=$(cd "$full_dir" && timeout "$timeout_seconds" bash -o pipefail -c "$command" 2>&1)
  exit_code=$?
  set -e

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Return structured result via stdout
  jq -n \
    --arg command "$command" \
    --arg working_dir "$working_dir" \
    --argjson exit_code "$exit_code" \
    --argjson duration_ms "$((duration * 1000))" \
    --arg output "$output" \
    '{command: $command, working_dir: $working_dir, exit_code: $exit_code, duration_ms: $duration_ms, output: $output}'

  return $exit_code
}

# Process recovery.json and attempt recovery if appropriate
# Returns:
#   0 - recovery executed successfully
#   1 - recovery executed but failed
#   2 - recovery skipped (not approved, blocked, or disabled)
#   3 - no recovery.json found
process_recovery() {
  local repo="$1"
  local loop_dir="$2"
  local events_file="$3"
  local loop_id="$4"
  local iteration="$5"
  local run_id="$6"
  local recovery_enabled="$7"
  local max_recoveries="$8"
  local cooldown_seconds="$9"
  local on_unknown="${10}"
  shift 10
  local auto_approve=()
  local require_human=()

  # Parse remaining args: auto_approve items, then "---", then require_human items
  local in_require_human=0
  for arg in "$@"; do
    if [[ "$arg" == "---" ]]; then
      in_require_human=1
      continue
    fi
    if [[ $in_require_human -eq 1 ]]; then
      require_human+=("$arg")
    else
      auto_approve+=("$arg")
    fi
  done

  local recovery_file="$loop_dir/recovery.json"
  local recovery_state_file="$loop_dir/recovery-state.json"

  # Check if recovery is enabled
  if [[ "$recovery_enabled" != "true" ]]; then
    return 2
  fi

  # Check if recovery.json exists
  if [[ ! -f "$recovery_file" ]]; then
    return 3
  fi

  # Read recovery proposal
  local category command working_dir timeout_seconds confidence
  category=$(jq -r '.category // "unknown"' "$recovery_file")
  command=$(jq -r '.recovery.command // ""' "$recovery_file")
  working_dir=$(jq -r '.recovery.working_dir // "."' "$recovery_file")
  timeout_seconds=$(jq -r '.recovery.timeout_seconds // 120' "$recovery_file")
  confidence=$(jq -r '.recovery.confidence // "unknown"' "$recovery_file")

  if [[ -z "$command" ]]; then
    echo "Recovery proposal has no command" >&2
    return 2
  fi

  # Log recovery_proposed event
  local proposed_data
  proposed_data=$(jq -c '.' "$recovery_file")
  log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_proposed" "$proposed_data"

  # Check recovery count limit
  local recovery_count=0
  if [[ -f "$recovery_state_file" ]]; then
    recovery_count=$(jq -r ".recoveries_this_run // 0" "$recovery_state_file")
    local last_recovery_time
    last_recovery_time=$(jq -r ".last_recovery_time // 0" "$recovery_state_file")

    # Check cooldown
    local now
    now=$(date +%s)
    local elapsed=$((now - last_recovery_time))
    if [[ $elapsed -lt $cooldown_seconds ]]; then
      local cooldown_data
      cooldown_data=$(jq -n \
        --arg command "$command" \
        --argjson elapsed "$elapsed" \
        --argjson cooldown "$cooldown_seconds" \
        '{command: $command, reason: "cooldown", elapsed_seconds: $elapsed, cooldown_seconds: $cooldown}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_skipped" "$cooldown_data"
      return 2
    fi
  fi

  if [[ $recovery_count -ge $max_recoveries ]]; then
    local limit_data
    limit_data=$(jq -n \
      --arg command "$command" \
      --argjson count "$recovery_count" \
      --argjson max "$max_recoveries" \
      '{command: $command, reason: "max_recoveries_reached", count: $count, max: $max}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_skipped" "$limit_data"
    return 2
  fi

  # Check if command is blocked
  if is_recovery_blocked "$command" "${require_human[@]}"; then
    local blocked_data
    blocked_data=$(jq -n \
      --arg command "$command" \
      --arg category "$category" \
      '{command: $command, category: $category, reason: "require_human"}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_blocked" "$blocked_data"
    return 2
  fi

  # Check if command is approved
  if ! is_recovery_approved "$command" "${auto_approve[@]}"; then
    # Command not in auto_approve list
    if [[ "$on_unknown" == "deny" ]]; then
      local denied_data
      denied_data=$(jq -n \
        --arg command "$command" \
        --arg category "$category" \
        '{command: $command, category: $category, reason: "not_in_auto_approve"}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_denied" "$denied_data"
      return 2
    elif [[ "$on_unknown" == "escalate" ]]; then
      local escalate_data
      escalate_data=$(jq -n \
        --arg command "$command" \
        --arg category "$category" \
        --arg confidence "$confidence" \
        '{command: $command, category: $category, confidence: $confidence, reason: "not_in_auto_approve"}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_escalated" "$escalate_data"
      # Write escalation file for Phase 2
      jq -n \
        --arg timestamp "$(timestamp)" \
        --arg loop_id "$loop_id" \
        --argjson iteration "$iteration" \
        --arg type "recovery_approval_required" \
        --arg status "pending" \
        --argjson recovery_proposal "$proposed_data" \
        --arg reason "Command not in auto_approve list" \
        '{timestamp: $timestamp, loop_id: $loop_id, iteration: $iteration, type: $type, status: $status, recovery_proposal: $recovery_proposal, reason: $reason}' \
        > "$loop_dir/escalation.json"
      return 2
    fi
    # on_unknown == "allow" falls through to execute
  fi

  # Log approval and execute
  local approved_data
  approved_data=$(jq -n \
    --arg command "$command" \
    --arg category "$category" \
    --arg source "auto" \
    '{command: $command, category: $category, source: $source}')
  log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_approved" "$approved_data"

  echo "Executing recovery: $command"

  local result
  local exec_rc=0
  set +e
  result=$(execute_recovery "$repo" "$command" "$working_dir" "$timeout_seconds")
  exec_rc=$?
  set -e

  # Update recovery state
  local now
  now=$(date +%s)
  jq -n \
    --argjson recoveries_this_run "$((recovery_count + 1))" \
    --argjson last_recovery_time "$now" \
    '{recoveries_this_run: $recoveries_this_run, last_recovery_time: $last_recovery_time}' \
    > "$recovery_state_file"

  if [[ $exec_rc -eq 0 ]]; then
    local success_data
    success_data=$(echo "$result" | jq -c '. + {status: "success"}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_executed" "$success_data"
    echo "Recovery successful"
    # Remove recovery.json after successful execution
    rm -f "$recovery_file"
    return 0
  else
    local failure_data
    failure_data=$(echo "$result" | jq -c '. + {status: "failed"}')
    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "recovery_failed" "$failure_data"
    echo "Recovery failed with exit code $exec_rc"
    return 1
  fi
}

# Parse recovery config from loop JSON
# Outputs space-separated: enabled max_recoveries cooldown on_unknown
parse_recovery_config() {
  local loop_json="$1"

  local enabled max_recoveries cooldown on_unknown
  enabled=$(echo "$loop_json" | jq -r '.recovery.enabled // false')
  max_recoveries=$(echo "$loop_json" | jq -r '.recovery.max_auto_recoveries_per_run // 3')
  cooldown=$(echo "$loop_json" | jq -r '.recovery.cooldown_seconds // 60')
  on_unknown=$(echo "$loop_json" | jq -r '.recovery.on_unknown // "escalate"')

  echo "$enabled $max_recoveries $cooldown $on_unknown"
}

# Parse auto_approve list from loop JSON
# Outputs newline-separated commands
parse_recovery_auto_approve() {
  local loop_json="$1"
  echo "$loop_json" | jq -r '.recovery.auto_approve // [] | .[]'
}

# Parse require_human list from loop JSON
# Outputs newline-separated patterns
parse_recovery_require_human() {
  local loop_json="$1"
  echo "$loop_json" | jq -r '.recovery.require_human // [] | .[]'
}

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

    # Check RLMS semantic config
    check_rlms_config "$loop_json" "loops[$i]"

    # Check tests gate policy
    check_tests_gate_config "$loop_json" "loops[$i]"

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
        "mode": "disabled",
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
        "threshold": 5,
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
      "delegation": {
        "enabled": false,
        "dispatch_mode": "serial",
        "wake_policy": "on_wave_complete",
        "failure_policy": "warn_and_continue",
        "max_children": 1,
        "max_waves": 1,
        "child_timeout_seconds": 300,
        "retry_limit": 0,
        "retry_backoff_seconds": 0,
        "retry_backoff_max_seconds": 30
      },
      "recovery": {
        "enabled": true,
        "auto_approve": [
          "bun install",
          "npm install",
          "yarn install",
          "pnpm install",
          "rm -rf node_modules && bun install",
          "rm -rf node_modules && npm install",
          "rm -rf .next && bun run build",
          "rm -rf dist && bun run build"
        ],
        "require_human": [
          "rm -rf *",
          "git reset --hard",
          "git push *",
          "curl *",
          "wget *"
        ],
        "max_auto_recoveries_per_run": 3,
        "cooldown_seconds": 60,
        "on_unknown": "escalate"
      },
      "roles": {
        "planner": {"runner": "codex"},
        "implementer": {"runner": "codex"},
        "tester": {"runner": "codex"},
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
- Only output <promise>...</promise> if the tests gate is satisfied (test-status.json.ok == true, including intentional skipped status when tests mode is disabled), checklists are complete, and the spec is satisfied.
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

    i=$((i + 1))
  done

  echo ""
  echo "Total: $loop_count loop(s)"
}

rlms_safe_int() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

# Decide whether RLMS should run for a role in this iteration.
# Usage: rlms_evaluate_trigger <enabled> <role_enabled> <mode> <force_on> <force_off> <auto_trigger> <requested_trigger>
# Output: "<true|false>\t<reason>"
rlms_evaluate_trigger() {
  local enabled="$1"
  local role_enabled="$2"
  local mode="$3"
  local force_on="$4"
  local force_off="$5"
  local auto_trigger="$6"
  local requested_trigger="$7"

  if [[ "$enabled" != "true" ]]; then
    printf 'false\tdisabled\n'
    return 0
  fi
  if [[ "$role_enabled" != "true" ]]; then
    printf 'false\trole_disabled\n'
    return 0
  fi
  if [[ "$force_off" == "true" ]]; then
    printf 'false\tforce_off\n'
    return 0
  fi
  if [[ "$force_on" == "true" ]]; then
    printf 'true\tforce_on\n'
    return 0
  fi

  case "$mode" in
    auto)
      if [[ "$auto_trigger" == "true" ]]; then
        printf 'true\tauto_threshold\n'
      else
        printf 'false\tauto_not_met\n'
      fi
      ;;
    requested)
      if [[ "$requested_trigger" == "true" ]]; then
        printf 'true\trequested_keyword\n'
      else
        printf 'false\trequest_not_found\n'
      fi
      ;;
    hybrid|*)
      if [[ "$requested_trigger" == "true" ]]; then
        printf 'true\thybrid_requested\n'
      elif [[ "$auto_trigger" == "true" ]]; then
        printf 'true\thybrid_auto\n'
      else
        printf 'false\thybrid_not_met\n'
      fi
      ;;
  esac
}

# Compute aggregate RLMS context metrics from a newline-delimited file list.
# Usage: rlms_compute_context_metrics <context_file_list> <request_keyword>
# Output JSON: {file_count, line_count, char_count, estimated_tokens, request_detected}
rlms_compute_context_metrics() {
  local context_file_list="$1"
  local request_keyword="$2"

  local file_count=0
  local line_count=0
  local char_count=0
  local request_detected="false"

  if [[ -f "$context_file_list" ]]; then
    while IFS= read -r file; do
      if [[ -z "$file" || ! -f "$file" ]]; then
        continue
      fi
      file_count=$((file_count + 1))
      local file_lines=0
      local file_chars=0
      file_lines=$(wc -l < "$file" 2>/dev/null | tr -d '[:space:]' || echo 0)
      file_chars=$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]' || echo 0)
      file_lines=$(rlms_safe_int "$file_lines" 0)
      file_chars=$(rlms_safe_int "$file_chars" 0)
      line_count=$((line_count + file_lines))
      char_count=$((char_count + file_chars))

      if [[ "$request_detected" != "true" && -n "$request_keyword" ]]; then
        if grep -Fq -- "$request_keyword" "$file" 2>/dev/null; then
          request_detected="true"
        fi
      fi
    done < "$context_file_list"
  fi

  local estimated_tokens=0
  if [[ "$char_count" -gt 0 ]]; then
    estimated_tokens=$(((char_count + 3) / 4))
  fi

  jq -n \
    --argjson file_count "$file_count" \
    --argjson line_count "$line_count" \
    --argjson char_count "$char_count" \
    --argjson estimated_tokens "$estimated_tokens" \
    --argjson request_detected "$(if [[ "$request_detected" == "true" ]]; then echo true; else echo false; fi)" \
    '{
      file_count: $file_count,
      line_count: $line_count,
      char_count: $char_count,
      estimated_tokens: $estimated_tokens,
      request_detected: $request_detected
    }'
}

# Build a newline-delimited context file list for RLMS.
# Usage: rlms_collect_context_files <repo> <output_file> <max_files> <changed_files_all> <tasks_dir> <paths...>
rlms_collect_context_files() {
  local repo="$1"
  local output_file="$2"
  local max_files="$3"
  local changed_files_all="$4"
  local tasks_dir="$5"
  shift 5
  local -a fixed_paths=("$@")

  local tmp_file
  tmp_file=$(mktemp -t "superloop-rlms-context.XXXXXX")
  : > "$tmp_file"

  local path
  for path in "${fixed_paths[@]}"; do
    if [[ -n "$path" && -f "$path" ]]; then
      printf '%s\n' "$path" >> "$tmp_file"
    fi
  done

  if [[ -n "$tasks_dir" && -d "$tasks_dir" ]]; then
    find "$tasks_dir" -maxdepth 1 -type f -name 'PHASE_*.MD' 2>/dev/null | sort >> "$tmp_file" || true
  fi

  if [[ -n "$changed_files_all" && -f "$changed_files_all" ]]; then
    while IFS= read -r rel_path; do
      if [[ -z "$rel_path" ]]; then
        continue
      fi
      local abs_path="$repo/$rel_path"
      if [[ -f "$abs_path" ]]; then
        printf '%s\n' "$abs_path" >> "$tmp_file"
      fi
    done < "$changed_files_all"
  fi

  awk 'NF && !seen[$0]++' "$tmp_file" | head -n "$max_files" > "$output_file"
  rm -f "$tmp_file"
}

append_rlms_index_entry() {
  local index_file="$1"
  local loop_id="$2"
  local entry_json="$3"

  local tmp_file="${index_file}.tmp"
  mkdir -p "$(dirname "$index_file")"

  if [[ -f "$index_file" ]]; then
    jq -n \
      --argjson entry "$entry_json" \
      --arg updated_at "$(timestamp)" \
      --slurpfile existing "$index_file" \
      '($existing[0] // {}) as $root
      | {
          version: ($root.version // 1),
          loop_id: ($root.loop_id // null),
          updated_at: $updated_at,
          entries: (($root.entries // []) + [$entry])
        }' > "$tmp_file"
  else
    jq -n \
      --arg loop_id "$loop_id" \
      --arg updated_at "$(timestamp)" \
      --argjson entry "$entry_json" \
      '{version: 1, loop_id: $loop_id, updated_at: $updated_at, entries: [$entry]}' > "$tmp_file"
  fi

  mv "$tmp_file" "$index_file"
}

append_delegation_index_entry() {
  local index_file="$1"
  local loop_id="$2"
  local entry_json="$3"

  local tmp_file="${index_file}.tmp"
  mkdir -p "$(dirname "$index_file")"

  if [[ -f "$index_file" ]]; then
    jq -n \
      --argjson entry "$entry_json" \
      --arg updated_at "$(timestamp)" \
      --slurpfile existing "$index_file" \
      '($existing[0] // {}) as $root
      | {
          version: ($root.version // 1),
          loop_id: ($root.loop_id // null),
          updated_at: $updated_at,
          entries: (($root.entries // []) + [$entry])
        }' > "$tmp_file"
  else
    jq -n \
      --arg loop_id "$loop_id" \
      --arg updated_at "$(timestamp)" \
      --argjson entry "$entry_json" \
      '{version: 1, loop_id: $loop_id, updated_at: $updated_at, entries: [$entry]}' > "$tmp_file"
  fi

  mv "$tmp_file" "$index_file"
}

normalize_delegation_dispatch_mode() {
  local value="${1:-}"
  case "$value" in
    parallel) echo "parallel" ;;
    serial) echo "serial" ;;
    *) echo "serial" ;;
  esac
}

normalize_delegation_wake_policy() {
  local value="${1:-}"
  case "$value" in
    on_child_complete|immediate) echo "on_child_complete" ;;
    on_wave_complete|after_all) echo "on_wave_complete" ;;
    *) echo "on_wave_complete" ;;
  esac
}

normalize_delegation_failure_policy() {
  local value="${1:-}"
  case "$value" in
    fail_role) echo "fail_role" ;;
    warn_and_continue) echo "warn_and_continue" ;;
    *) echo "warn_and_continue" ;;
  esac
}

normalize_delegation_mode() {
  local value="${1:-}"
  case "$value" in
    reconnaissance|recon) echo "reconnaissance" ;;
    standard|"") echo "standard" ;;
    *) echo "standard" ;;
  esac
}

normalize_delegation_terminal_state() {
  local status_text="${1:-}"
  case "$status_text" in
    ok) echo "completed" ;;
    timeout) echo "timed_out" ;;
    cancelled) echo "cancelled" ;;
    policy_violation) echo "policy_violation" ;;
    skipped) echo "skipped" ;;
    *) echo "failed" ;;
  esac
}

compute_delegation_retry_backoff_seconds() {
  local base_seconds="$1"
  local max_seconds="$2"
  local failed_attempt="$3"

  base_seconds=$(rlms_safe_int "$base_seconds" 0)
  max_seconds=$(rlms_safe_int "$max_seconds" 0)
  failed_attempt=$(rlms_safe_int "$failed_attempt" 1)

  if [[ "$base_seconds" -le 0 ]]; then
    echo "0"
    return 0
  fi
  if [[ "$failed_attempt" -lt 1 ]]; then
    failed_attempt=1
  fi

  local delay="$base_seconds"
  local step=1
  while [[ "$step" -lt "$failed_attempt" ]]; do
    delay=$((delay * 2))
    if [[ "$max_seconds" -gt 0 && "$delay" -ge "$max_seconds" ]]; then
      delay="$max_seconds"
      break
    fi
    step=$((step + 1))
  done

  if [[ "$max_seconds" -gt 0 && "$delay" -gt "$max_seconds" ]]; then
    delay="$max_seconds"
  fi
  if [[ "$delay" -lt 0 ]]; then
    delay=0
  fi
  echo "$delay"
}

collect_dirty_paths() {
  local repo="$1"
  local output_file="$2"
  : > "$output_file"

  if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$repo" diff --name-only >> "$output_file" 2>/dev/null || true
    git -C "$repo" diff --cached --name-only >> "$output_file" 2>/dev/null || true
    git -C "$repo" status --porcelain | awk '{print $2}' >> "$output_file" 2>/dev/null || true
  else
    while IFS= read -r -d '' file; do
      local rel="${file#$repo/}"
      if [[ "$rel" == .superloop/* || "$rel" == .git/* ]]; then
        continue
      fi
      printf '%s\n' "$rel" >> "$output_file"
    done < <(find "$repo" -type f -print0 2>/dev/null)
  fi

  awk 'NF && $0 !~ /^\.superloop\// && $0 !~ /^\.git\// && !seen[$0]++' "$output_file" | LC_ALL=C sort > "${output_file}.tmp"
  mv "${output_file}.tmp" "$output_file"
}

append_usage_records_file() {
  local source_file="$1"
  local target_file="$2"
  if [[ -z "$source_file" || -z "$target_file" ]]; then
    return 0
  fi
  if [[ ! -f "$source_file" ]]; then
    return 0
  fi
  cat "$source_file" >> "$target_file" 2>/dev/null || true
}

sanitize_delegation_id() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    echo "child"
    return 0
  fi
  local sanitized
  sanitized=$(printf '%s' "$raw" | tr -cs 'A-Za-z0-9._-' '-')
  sanitized="${sanitized#-}"
  sanitized="${sanitized%-}"
  if [[ -z "$sanitized" ]]; then
    sanitized="child"
  fi
  echo "$sanitized"
}

run_cmd() {
  local repo="$1"
  local config_path="$2"
  local target_loop_id="$3"
  local fast_mode="$4"
  local dry_run="$5"
  local skip_validate="${6:-0}"

  need_cmd jq

  local superloop_dir="$repo/.superloop"
  local state_file="$superloop_dir/state.json"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi

  # Pre-run validation (Phase 3 of Config Validation)
  if [[ "$skip_validate" != "1" ]]; then
    echo "Validating config before starting loop..."
    if ! validate_static "$repo" "$config_path" >/dev/null; then
      echo ""
      echo "Config validation failed. Fix errors above or use --skip-validate to bypass."
      return 1
    fi
    echo "Config validation passed."
    echo ""
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
  # Use ${array[@]+"${array[@]}"} to safely handle empty arrays with set -u
  local -a runner_command=()
  [[ ${#default_runner_command[@]} -gt 0 ]] && runner_command=("${default_runner_command[@]}")
  local -a runner_args=()
  [[ ${#default_runner_args[@]} -gt 0 ]] && runner_args=("${default_runner_args[@]}")
  local -a runner_fast_args=()
  [[ ${#default_runner_fast_args[@]} -gt 0 ]] && runner_fast_args=("${default_runner_fast_args[@]}")
  local runner_prompt_mode="$default_runner_prompt_mode"

  if [[ "${dry_run:-0}" -ne 1 && ${#runner_command[@]} -gt 0 ]]; then
    need_exec "${runner_command[0]}"
  fi

  local -a runner_active_args=()
  [[ ${#runner_args[@]} -gt 0 ]] && runner_active_args=("${runner_args[@]}")
  if [[ "${fast_mode:-0}" -eq 1 ]]; then
    if [[ ${#runner_fast_args[@]} -gt 0 ]]; then
      runner_active_args=("${runner_fast_args[@]}")
    elif [[ ${#runner_args[@]} -gt 0 ]]; then
      echo "warning: --fast set but runner.fast_args is empty; using runner.args" >&2
    fi
  fi

  local loop_index=0
  local iteration=1
  local was_active="false"
  local active_loop_id=""
  if [[ "${dry_run:-0}" -ne 1 && -f "$state_file" ]]; then
    loop_index=$(jq -r '.loop_index // 0' "$state_file")
    iteration=$(jq -r '.iteration // 1' "$state_file")
    local active
    active=$(jq -r '.active // true' "$state_file")
    if [[ "$active" == "true" ]]; then
      was_active="true"
      active_loop_id=$(jq -r '.current_loop_id // ""' "$state_file")
    fi
    if [[ "$active" != "true" ]]; then
      loop_index=0
      iteration=1
    fi
  fi

  # Check if loop is already active
  if [[ "$was_active" == "true" && -z "$target_loop_id" ]]; then
    echo "Error: A loop is already running (state.json shows active: true)" >&2
    echo "" >&2
    echo "To start a new loop run:" >&2
    echo "  1. Stop the running loop first, OR" >&2
    echo "  2. Reset the state manually:" >&2
    echo "     echo '{\"active\": false, \"loop_index\": 0, \"iteration\": 0}' > $state_file" >&2
    return 1
  fi

  # Block re-entrant execution of the same loop when state already marks it active.
  if [[ "$was_active" == "true" && -n "$target_loop_id" && -n "$active_loop_id" && "$target_loop_id" == "$active_loop_id" ]]; then
    echo "Error: loop '$target_loop_id' is already running (reentrant run blocked)" >&2
    echo "" >&2
    echo "Active loop id from state: $active_loop_id" >&2
    echo "State file: $state_file" >&2
    echo "" >&2
    echo "Wait for the active run to finish, or clear stale state only if you are sure no run is active." >&2
    return 1
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
    local rlms_root_dir="$loop_dir/rlms"
    local rlms_latest_dir="$rlms_root_dir/latest"
    local rlms_index_file="$rlms_root_dir/index.json"
    local delegation_root_dir="$loop_dir/delegation"
    local delegation_latest_dir="$delegation_root_dir/latest"
    local delegation_index_file="$delegation_root_dir/index.json"

    local tasks_dir="$loop_dir/tasks"
    local stuck_file="$loop_dir/stuck.json"
    mkdir -p "$loop_dir" "$prompt_dir" "$log_dir" "$tasks_dir" "$rlms_latest_dir" "$delegation_latest_dir"
    touch "$plan_file" "$notes_file" "$implementer_report" "$reviewer_report" "$test_report"

    # Check if stuck threshold has been reached
    if [[ -f "$stuck_file" ]]; then
      local stuck_streak
      local stuck_threshold
      stuck_streak=$(jq -r '.streak // 0' "$stuck_file" 2>/dev/null || echo "0")
      stuck_threshold=$(jq -r '.threshold // 5' "$stuck_file" 2>/dev/null || echo "5")

      if [[ "$stuck_streak" -ge "$stuck_threshold" && "$stuck_threshold" -gt 0 ]]; then
        local stuck_reason
        stuck_reason=$(jq -r '.reason // "unknown"' "$stuck_file" 2>/dev/null || echo "unknown")

        echo "Error: Loop has reached stuck threshold ($stuck_streak/$stuck_threshold iterations)" >&2
        echo "" >&2
        echo "Reason: $stuck_reason" >&2
        echo "" >&2
        echo "The loop has been making no meaningful progress. To restart:" >&2
        echo "  1. Review the stuck state: cat $stuck_file" >&2
        echo "  2. Review recent iterations: ls -lt $loop_dir/logs/" >&2
        echo "  3. Reset stuck state if you want to retry:" >&2
        echo "     echo '{\"code_signature\": \"\", \"test_signature\": \"\", \"streak\": 0, \"threshold\": 5, \"reason\": \"\"}' > $stuck_file" >&2
        echo "  4. OR fix the underlying issue manually before restarting" >&2
        return 1
      fi
    fi

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
      # Use canonical order, not alphabetical keys
      roles_config_json=$(jq -c '.roles' <<<"$loop_json")
      local canonical_order=(planner implementer tester reviewer)
      for role in "${canonical_order[@]}"; do
        if jq -e --arg role "$role" '.roles | has($role)' <<<"$loop_json" >/dev/null 2>&1; then
          roles+=("$role")
        fi
      done
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
          # Claude Code thinking is controlled via MAX_THINKING_TOKENS env var.
          # Use get_thinking_env() to get the env var prefix for command execution.
          # No CLI flags for thinking.
          ;;
      esac
    }

    # Get environment variables for thinking (returns VAR=value to prefix command)
    # Used for Claude where thinking is controlled via MAX_THINKING_TOKENS env var
    get_thinking_env() {
      local runner_type="$1"  # "codex" or "claude"
      local thinking="$2"     # none|minimal|low|standard|high|max

      if [[ -z "$thinking" || "$thinking" == "null" ]]; then
        return 0
      fi

      case "$runner_type" in
        claude)
          # Map thinking level to MAX_THINKING_TOKENS (per-request budget)
          # - 0 = disabled
          # - 1024 = minimum
          # - 32000 = recommended max for real-time (above this, use batch)
          local tokens=""
          case "$thinking" in
            none)     tokens="0" ;;
            minimal)  tokens="1024" ;;
            low)      tokens="4096" ;;
            standard) tokens="10000" ;;
            high)     tokens="20000" ;;
            max)      tokens="32000" ;;
          esac
          if [[ -n "$tokens" ]]; then
            echo "MAX_THINKING_TOKENS=$tokens"
          fi
          ;;
        # Codex uses CLI flags, not env vars - handled by get_thinking_flags
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

    local test_command_count=0
    for cmd in "${test_commands[@]}"; do
      if [[ -n "${cmd//[[:space:]]/}" ]]; then
        test_command_count=$((test_command_count + 1))
      fi
    done

    if [[ "$tests_mode" != "disabled" && $test_command_count -eq 0 ]]; then
      die "loop '$loop_id': tests.mode is '$tests_mode' but tests.commands is empty. Add at least one test command or set tests.mode to 'disabled'."
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

    # Delegation (role-local nested orchestration) configuration
    local delegation_enabled
    delegation_enabled=$(jq -r '.delegation.enabled // false' <<<"$loop_json")
    local delegation_dispatch_mode_raw
    delegation_dispatch_mode_raw=$(jq -r '.delegation.dispatch_mode // "serial"' <<<"$loop_json")
    local delegation_dispatch_mode
    delegation_dispatch_mode=$(normalize_delegation_dispatch_mode "$delegation_dispatch_mode_raw")
    local delegation_wake_policy_raw
    delegation_wake_policy_raw=$(jq -r '.delegation.wake_policy // "on_wave_complete"' <<<"$loop_json")
    local delegation_wake_policy
    delegation_wake_policy=$(normalize_delegation_wake_policy "$delegation_wake_policy_raw")
    local delegation_failure_policy_raw
    delegation_failure_policy_raw=$(jq -r '.delegation.failure_policy // "warn_and_continue"' <<<"$loop_json")
    local delegation_failure_policy
    delegation_failure_policy=$(normalize_delegation_failure_policy "$delegation_failure_policy_raw")
    local delegation_failure_policy_explicit
    delegation_failure_policy_explicit=$(jq -r 'if ((.delegation // {}) | has("failure_policy")) then "true" else "false" end' <<<"$loop_json")
    local delegation_max_children
    delegation_max_children=$(jq -r '.delegation.max_children // 1' <<<"$loop_json")
    local delegation_max_parallel
    delegation_max_parallel=$(jq -r '
      if ((.delegation // {}) | has("max_parallel")) then
        .delegation.max_parallel
      else
        (.delegation.max_children // 1)
      end' <<<"$loop_json")
    local delegation_max_waves
    delegation_max_waves=$(jq -r '.delegation.max_waves // 1' <<<"$loop_json")
    local delegation_child_timeout_seconds
    delegation_child_timeout_seconds=$(jq -r '.delegation.child_timeout_seconds // 300' <<<"$loop_json")
    local delegation_retry_limit
    delegation_retry_limit=$(jq -r '.delegation.retry_limit // 0' <<<"$loop_json")
    local delegation_retry_backoff_seconds
    delegation_retry_backoff_seconds=$(jq -r '.delegation.retry_backoff_seconds // 0' <<<"$loop_json")
    local delegation_retry_backoff_max_seconds
    delegation_retry_backoff_max_seconds=$(jq -r '.delegation.retry_backoff_max_seconds // 30' <<<"$loop_json")

    delegation_max_children=$(rlms_safe_int "$delegation_max_children" 1)
    delegation_max_parallel=$(rlms_safe_int "$delegation_max_parallel" "$delegation_max_children")
    delegation_max_waves=$(rlms_safe_int "$delegation_max_waves" 1)
    delegation_child_timeout_seconds=$(rlms_safe_int "$delegation_child_timeout_seconds" 300)
    delegation_retry_limit=$(rlms_safe_int "$delegation_retry_limit" 0)
    delegation_retry_backoff_seconds=$(rlms_safe_int "$delegation_retry_backoff_seconds" 0)
    delegation_retry_backoff_max_seconds=$(rlms_safe_int "$delegation_retry_backoff_max_seconds" 30)

    if [[ "$delegation_max_children" -lt 1 ]]; then delegation_max_children=1; fi
    if [[ "$delegation_max_parallel" -lt 1 ]]; then delegation_max_parallel="$delegation_max_children"; fi
    if [[ "$delegation_max_parallel" -gt "$delegation_max_children" ]]; then delegation_max_parallel="$delegation_max_children"; fi
    if [[ "$delegation_max_waves" -lt 1 ]]; then delegation_max_waves=1; fi
    if [[ "$delegation_child_timeout_seconds" -lt 1 ]]; then delegation_child_timeout_seconds=300; fi
    if [[ "$delegation_retry_limit" -lt 0 ]]; then delegation_retry_limit=0; fi
    if [[ "$delegation_retry_backoff_seconds" -lt 0 ]]; then delegation_retry_backoff_seconds=0; fi
    if [[ "$delegation_retry_backoff_max_seconds" -lt 0 ]]; then delegation_retry_backoff_max_seconds=0; fi
    if [[ "$delegation_retry_backoff_max_seconds" -gt 0 && "$delegation_retry_backoff_max_seconds" -lt "$delegation_retry_backoff_seconds" ]]; then
      delegation_retry_backoff_max_seconds="$delegation_retry_backoff_seconds"
    fi

    if [[ "$delegation_dispatch_mode_raw" != "$delegation_dispatch_mode" && "$delegation_enabled" == "true" ]]; then
      echo "warning: delegation.dispatch_mode '$delegation_dispatch_mode_raw' is invalid; using '$delegation_dispatch_mode'" >&2
    fi
    if [[ "$delegation_wake_policy_raw" == "immediate" || "$delegation_wake_policy_raw" == "after_all" ]]; then
      echo "warning: delegation.wake_policy '$delegation_wake_policy_raw' is deprecated; use '$delegation_wake_policy'" >&2
    elif [[ "$delegation_wake_policy_raw" != "$delegation_wake_policy" && "$delegation_enabled" == "true" ]]; then
      echo "warning: delegation.wake_policy '$delegation_wake_policy_raw' is invalid; using '$delegation_wake_policy'" >&2
    fi
    if [[ "$delegation_failure_policy_raw" != "$delegation_failure_policy" && "$delegation_enabled" == "true" ]]; then
      echo "warning: delegation.failure_policy '$delegation_failure_policy_raw' is invalid; using '$delegation_failure_policy'" >&2
    fi

    # RLMS (recursive language model scaffold) configuration
    local rlms_enabled
    rlms_enabled=$(jq -r '.rlms.enabled // false' <<<"$loop_json")
    local rlms_mode
    rlms_mode=$(jq -r '.rlms.mode // "hybrid"' <<<"$loop_json")
    local rlms_request_keyword
    rlms_request_keyword=$(jq -r '.rlms.request_keyword // "RLMS_REQUEST"' <<<"$loop_json")
    local rlms_auto_max_lines
    rlms_auto_max_lines=$(jq -r '.rlms.auto.max_lines // 2500' <<<"$loop_json")
    local rlms_auto_max_estimated_tokens
    rlms_auto_max_estimated_tokens=$(jq -r '.rlms.auto.max_estimated_tokens // 120000' <<<"$loop_json")
    local rlms_auto_max_files
    rlms_auto_max_files=$(jq -r '.rlms.auto.max_files // 40' <<<"$loop_json")
    local rlms_limit_max_steps
    rlms_limit_max_steps=$(jq -r '.rlms.limits.max_steps // 40' <<<"$loop_json")
    local rlms_limit_max_depth
    rlms_limit_max_depth=$(jq -r '.rlms.limits.max_depth // 2' <<<"$loop_json")
    local rlms_limit_timeout_seconds
    rlms_limit_timeout_seconds=$(jq -r '.rlms.limits.timeout_seconds // 240' <<<"$loop_json")
    local rlms_limit_max_subcalls
    rlms_limit_max_subcalls=$(jq -r '.rlms.limits.max_subcalls // 0' <<<"$loop_json")
    local rlms_output_format
    rlms_output_format=$(jq -r '.rlms.output.format // "json"' <<<"$loop_json")
    local rlms_output_require_citations
    rlms_output_require_citations=$(jq -r '.rlms.output.require_citations // true' <<<"$loop_json")
    local rlms_policy_force_on
    rlms_policy_force_on=$(jq -r '.rlms.policy.force_on // false' <<<"$loop_json")
    local rlms_policy_force_off
    rlms_policy_force_off=$(jq -r '.rlms.policy.force_off // false' <<<"$loop_json")
    local rlms_policy_fail_mode
    rlms_policy_fail_mode=$(jq -r '.rlms.policy.fail_mode // "warn_and_continue"' <<<"$loop_json")

    rlms_auto_max_lines=$(rlms_safe_int "$rlms_auto_max_lines" 2500)
    rlms_auto_max_estimated_tokens=$(rlms_safe_int "$rlms_auto_max_estimated_tokens" 120000)
    rlms_auto_max_files=$(rlms_safe_int "$rlms_auto_max_files" 40)
    rlms_limit_max_steps=$(rlms_safe_int "$rlms_limit_max_steps" 40)
    rlms_limit_max_depth=$(rlms_safe_int "$rlms_limit_max_depth" 2)
    rlms_limit_timeout_seconds=$(rlms_safe_int "$rlms_limit_timeout_seconds" 240)
    rlms_limit_max_subcalls=$(rlms_safe_int "$rlms_limit_max_subcalls" 0)
    if [[ "$rlms_limit_max_subcalls" -le 0 ]]; then
      rlms_limit_max_subcalls=$((rlms_limit_max_steps * 2))
    fi
    if [[ "$rlms_limit_max_subcalls" -le 0 ]]; then
      rlms_limit_max_subcalls=1
    fi

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

    # Git auto-commit configuration
    local commit_strategy
    commit_strategy=$(jq -r '.git.commit_strategy // "never"' <<<"$loop_json")
    local pre_commit_commands
    pre_commit_commands=$(jq -r '.git.pre_commit_commands // ""' <<<"$loop_json")

    # Recovery configuration
    local recovery_enabled
    recovery_enabled=$(jq -r '.recovery.enabled // false' <<<"$loop_json")
    local recovery_max_per_run
    recovery_max_per_run=$(jq -r '.recovery.max_auto_recoveries_per_run // 3' <<<"$loop_json")
    local recovery_cooldown
    recovery_cooldown=$(jq -r '.recovery.cooldown_seconds // 60' <<<"$loop_json")
    local recovery_on_unknown
    recovery_on_unknown=$(jq -r '.recovery.on_unknown // "escalate"' <<<"$loop_json")
    local -a recovery_auto_approve=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && recovery_auto_approve+=("$line")
    done < <(jq -r '.recovery.auto_approve[]?' <<<"$loop_json")
    local -a recovery_require_human=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && recovery_require_human+=("$line")
    done < <(jq -r '.recovery.require_human[]?' <<<"$loop_json")

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
      --argjson delegation_enabled "$(if [[ "$delegation_enabled" == "true" ]]; then echo true; else echo false; fi)" \
      --arg delegation_dispatch_mode "$delegation_dispatch_mode" \
      --arg delegation_wake_policy "$delegation_wake_policy" \
      --arg delegation_failure_policy "$delegation_failure_policy" \
      --argjson delegation_max_children "$delegation_max_children" \
      --argjson delegation_max_parallel "$delegation_max_parallel" \
      --argjson delegation_max_waves "$delegation_max_waves" \
      --argjson delegation_child_timeout_seconds "$delegation_child_timeout_seconds" \
      --argjson delegation_retry_limit "$delegation_retry_limit" \
      --argjson delegation_retry_backoff_seconds "$delegation_retry_backoff_seconds" \
      --argjson delegation_retry_backoff_max_seconds "$delegation_retry_backoff_max_seconds" \
      --argjson rlms_enabled "$(if [[ "$rlms_enabled" == "true" ]]; then echo true; else echo false; fi)" \
      --arg rlms_mode "$rlms_mode" \
      '{
        spec_file: $spec_file,
        max_iterations: $max_iterations,
        tests_mode: $tests_mode,
        test_commands: $test_commands,
        checklists: $checklists,
        delegation: {
          enabled: $delegation_enabled,
          dispatch_mode: $delegation_dispatch_mode,
          wake_policy: $delegation_wake_policy,
          failure_policy: $delegation_failure_policy,
          max_children: $delegation_max_children,
          max_parallel: $delegation_max_parallel,
          max_waves: $delegation_max_waves,
          child_timeout_seconds: $delegation_child_timeout_seconds,
          retry_limit: $delegation_retry_limit,
          retry_backoff_seconds: $delegation_retry_backoff_seconds,
          retry_backoff_max_seconds: $delegation_retry_backoff_max_seconds
        },
        rlms: {
          enabled: $rlms_enabled,
          mode: $rlms_mode
        }
      }')
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

      # Setup error logging for this iteration
      local error_log="$log_dir/errors.log"
      touch "$error_log" 2>/dev/null || true

      local last_role=""
      for role in "${roles[@]}"; do
        local role_template="$role_dir/$role.md"
        if [[ ! -f "$role_template" ]]; then
          die "missing role template: $role_template"
        fi

        local rlms_result_for_prompt=""
        local rlms_summary_for_prompt=""
        local rlms_status_for_prompt=""
        local role_delegation_status_for_prompt=""

        local role_delegation_enabled="$delegation_enabled"
        local role_delegation_dispatch_mode="$delegation_dispatch_mode"
        local role_delegation_wake_policy="$delegation_wake_policy"
        local role_delegation_failure_policy="$delegation_failure_policy"
        local role_delegation_max_children="$delegation_max_children"
        local role_delegation_max_parallel="$delegation_max_parallel"
        local role_delegation_max_waves="$delegation_max_waves"
        local role_delegation_child_timeout_seconds="$delegation_child_timeout_seconds"
        local role_delegation_retry_limit="$delegation_retry_limit"
        local role_delegation_retry_backoff_seconds="$delegation_retry_backoff_seconds"
        local role_delegation_retry_backoff_max_seconds="$delegation_retry_backoff_max_seconds"
        local role_delegation_mode="standard"
        local role_delegation_reason="disabled"
        local role_delegation_failure_policy_override_present
        role_delegation_failure_policy_override_present=$(jq -r --arg role "$role" '
          if ((.delegation.roles[$role] // {}) | has("failure_policy")) then
            "true"
          else
            "false"
          end' <<<"$loop_json")

        local role_delegation_enabled_override
        role_delegation_enabled_override=$(jq -r --arg role "$role" '
          if ((.delegation.roles[$role] // {}) | has("enabled")) then
            (.delegation.roles[$role].enabled | tostring)
          else
            empty
          end' <<<"$loop_json")
        if [[ -n "$role_delegation_enabled_override" && "$role_delegation_enabled_override" != "null" ]]; then
          role_delegation_enabled="$role_delegation_enabled_override"
        fi

        local role_delegation_dispatch_mode_override
        role_delegation_dispatch_mode_override=$(jq -r --arg role "$role" '.delegation.roles[$role].dispatch_mode // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_dispatch_mode_override" && "$role_delegation_dispatch_mode_override" != "null" ]]; then
          role_delegation_dispatch_mode=$(normalize_delegation_dispatch_mode "$role_delegation_dispatch_mode_override")
        fi

        local role_delegation_wake_policy_override
        role_delegation_wake_policy_override=$(jq -r --arg role "$role" '.delegation.roles[$role].wake_policy // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_wake_policy_override" && "$role_delegation_wake_policy_override" != "null" ]]; then
          role_delegation_wake_policy=$(normalize_delegation_wake_policy "$role_delegation_wake_policy_override")
          if [[ "$role_delegation_wake_policy_override" == "immediate" || "$role_delegation_wake_policy_override" == "after_all" ]]; then
            echo "warning: delegation.roles.$role.wake_policy '$role_delegation_wake_policy_override' is deprecated; use '$role_delegation_wake_policy'" >&2
          elif [[ "$role_delegation_wake_policy_override" != "$role_delegation_wake_policy" ]]; then
            echo "warning: delegation.roles.$role.wake_policy '$role_delegation_wake_policy_override' is invalid; using '$role_delegation_wake_policy'" >&2
          fi
        fi

        local role_delegation_failure_policy_override
        role_delegation_failure_policy_override=$(jq -r --arg role "$role" '.delegation.roles[$role].failure_policy // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_failure_policy_override" && "$role_delegation_failure_policy_override" != "null" ]]; then
          role_delegation_failure_policy=$(normalize_delegation_failure_policy "$role_delegation_failure_policy_override")
          if [[ "$role_delegation_failure_policy_override" != "$role_delegation_failure_policy" ]]; then
            echo "warning: delegation.roles.$role.failure_policy '$role_delegation_failure_policy_override' is invalid; using '$role_delegation_failure_policy'" >&2
          fi
        fi

        local role_delegation_max_children_override
        role_delegation_max_children_override=$(jq -r --arg role "$role" '.delegation.roles[$role].max_children // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_max_children_override" && "$role_delegation_max_children_override" != "null" ]]; then
          role_delegation_max_children=$(rlms_safe_int "$role_delegation_max_children_override" "$role_delegation_max_children")
        fi

        local role_delegation_max_parallel_override
        role_delegation_max_parallel_override=$(jq -r --arg role "$role" '.delegation.roles[$role].max_parallel // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_max_parallel_override" && "$role_delegation_max_parallel_override" != "null" ]]; then
          role_delegation_max_parallel=$(rlms_safe_int "$role_delegation_max_parallel_override" "$role_delegation_max_children")
        fi

        local role_delegation_max_waves_override
        role_delegation_max_waves_override=$(jq -r --arg role "$role" '.delegation.roles[$role].max_waves // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_max_waves_override" && "$role_delegation_max_waves_override" != "null" ]]; then
          role_delegation_max_waves=$(rlms_safe_int "$role_delegation_max_waves_override" "$role_delegation_max_waves")
        fi

        local role_delegation_child_timeout_override
        role_delegation_child_timeout_override=$(jq -r --arg role "$role" '.delegation.roles[$role].child_timeout_seconds // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_child_timeout_override" && "$role_delegation_child_timeout_override" != "null" ]]; then
          role_delegation_child_timeout_seconds=$(rlms_safe_int "$role_delegation_child_timeout_override" "$role_delegation_child_timeout_seconds")
        fi

        local role_delegation_retry_limit_override
        role_delegation_retry_limit_override=$(jq -r --arg role "$role" '.delegation.roles[$role].retry_limit // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_retry_limit_override" && "$role_delegation_retry_limit_override" != "null" ]]; then
          role_delegation_retry_limit=$(rlms_safe_int "$role_delegation_retry_limit_override" "$role_delegation_retry_limit")
        fi

        local role_delegation_retry_backoff_seconds_override
        role_delegation_retry_backoff_seconds_override=$(jq -r --arg role "$role" '.delegation.roles[$role].retry_backoff_seconds // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_retry_backoff_seconds_override" && "$role_delegation_retry_backoff_seconds_override" != "null" ]]; then
          role_delegation_retry_backoff_seconds=$(rlms_safe_int "$role_delegation_retry_backoff_seconds_override" "$role_delegation_retry_backoff_seconds")
        fi

        local role_delegation_retry_backoff_max_seconds_override
        role_delegation_retry_backoff_max_seconds_override=$(jq -r --arg role "$role" '.delegation.roles[$role].retry_backoff_max_seconds // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_retry_backoff_max_seconds_override" && "$role_delegation_retry_backoff_max_seconds_override" != "null" ]]; then
          role_delegation_retry_backoff_max_seconds=$(rlms_safe_int "$role_delegation_retry_backoff_max_seconds_override" "$role_delegation_retry_backoff_max_seconds")
        fi

        local role_delegation_mode_override
        role_delegation_mode_override=$(jq -r --arg role "$role" '.delegation.roles[$role].mode // empty' <<<"$loop_json")
        if [[ -n "$role_delegation_mode_override" && "$role_delegation_mode_override" != "null" ]]; then
          role_delegation_mode=$(normalize_delegation_mode "$role_delegation_mode_override")
          if [[ "$role_delegation_mode_override" != "$role_delegation_mode" ]]; then
            echo "warning: delegation.roles.$role.mode '$role_delegation_mode_override' is invalid; using '$role_delegation_mode'" >&2
          fi
        fi

        if [[ "$role_delegation_max_children" -lt 1 ]]; then role_delegation_max_children=1; fi
        if [[ "$role_delegation_max_parallel" -lt 1 ]]; then role_delegation_max_parallel="$role_delegation_max_children"; fi
        if [[ "$role_delegation_max_parallel" -gt "$role_delegation_max_children" ]]; then role_delegation_max_parallel="$role_delegation_max_children"; fi
        if [[ "$role_delegation_max_waves" -lt 1 ]]; then role_delegation_max_waves=1; fi
        if [[ "$role_delegation_child_timeout_seconds" -lt 1 ]]; then role_delegation_child_timeout_seconds=300; fi
        if [[ "$role_delegation_retry_limit" -lt 0 ]]; then role_delegation_retry_limit=0; fi
        if [[ "$role_delegation_retry_backoff_seconds" -lt 0 ]]; then role_delegation_retry_backoff_seconds=0; fi
        if [[ "$role_delegation_retry_backoff_max_seconds" -lt 0 ]]; then role_delegation_retry_backoff_max_seconds=0; fi
        if [[ "$role_delegation_retry_backoff_max_seconds" -gt 0 && "$role_delegation_retry_backoff_max_seconds" -lt "$role_delegation_retry_backoff_seconds" ]]; then
          role_delegation_retry_backoff_max_seconds="$role_delegation_retry_backoff_seconds"
        fi

        if [[ "$role_delegation_enabled" == "true" ]]; then
          role_delegation_reason="enabled_by_config"
        fi

        # Phase 4 guardrail: allow implementer and planner reconnaissance only.
        if [[ "$role_delegation_enabled" == "true" && "$role" != "implementer" && "$role" != "planner" ]]; then
          role_delegation_enabled="false"
          role_delegation_reason="phase4_role_guardrail"
        fi

        if [[ "$role_delegation_enabled" == "true" && "$role" == "planner" ]]; then
          role_delegation_mode="reconnaissance"
          if [[ "$role_delegation_reason" == "enabled_by_config" ]]; then
            role_delegation_reason="enabled_by_config,planner_reconnaissance"
          elif [[ -n "$role_delegation_reason" && "$role_delegation_reason" != *"planner_reconnaissance"* ]]; then
            role_delegation_reason="${role_delegation_reason},planner_reconnaissance"
          else
            role_delegation_reason="planner_reconnaissance"
          fi
          if [[ "$role_delegation_failure_policy_override_present" != "true" && "$delegation_failure_policy_explicit" != "true" ]]; then
            role_delegation_failure_policy="fail_role"
            if [[ -n "$role_delegation_reason" && "$role_delegation_reason" != *"planner_recon_default_fail_role"* ]]; then
              role_delegation_reason="${role_delegation_reason},planner_recon_default_fail_role"
            elif [[ -z "$role_delegation_reason" ]]; then
              role_delegation_reason="planner_recon_default_fail_role"
            fi
          fi
        fi

        if [[ "$role_delegation_enabled" != "true" && "$role_delegation_reason" == "disabled" ]]; then
          role_delegation_reason="disabled_by_config"
        fi

        local role_delegation_dir="$delegation_root_dir/iter-$iteration/$role"
        local role_delegation_request_iter_file="$role_delegation_dir/request.json"
        local role_delegation_request_shared_file="$delegation_root_dir/requests/${role}.json"

        # Parent-handshake pass: let the parent role author request.json before child execution.
        if [[ "$role_delegation_enabled" == "true" && ( "$role" == "implementer" || "$role" == "planner" ) && ! -f "$role_delegation_request_iter_file" && ! -f "$role_delegation_request_shared_file" ]]; then
          mkdir -p "$role_delegation_dir"
          local delegation_request_prompt_file="$prompt_dir/${role}.delegation_request.md"
          local delegation_request_log_file="$log_dir/${role}.delegation_request.log"
          local delegation_request_last_message_file="$last_messages_dir/${role}.delegation_request.txt"

          cat > "$delegation_request_prompt_file" <<EOF
You are preparing a delegation request for Superloop role '$role'.

Write delegation request JSON to this exact file path:
$role_delegation_request_iter_file

Required JSON shape:
{
  "waves": [
    {
      "id": "wave-1",
      "children": [
        {
          "id": "task-1",
          "prompt": "Concrete subtask instruction",
          "context_files": ["repo/relative/path"]
        }
      ]
    }
  ]
}

Rules:
- Keep requests concrete and bounded.
- Use repo-relative paths in context_files.
- If no delegation is needed, write: {"waves":[]}
- Do not modify canonical reports or code in this pass.

Context files:
- Spec: $repo/$spec_file
- Plan: $plan_file
- Notes: $notes_file
- Implementer report: $implementer_report
- Tasks dir: $tasks_dir
EOF

          if [[ "$role" == "planner" ]]; then
            cat >> "$delegation_request_prompt_file" <<'EOF'

Planner reconnaissance constraints:
- Child prompts must be read-heavy reconnaissance work (analysis/synthesis only).
- Do not ask children to modify code, PLAN.MD, or PHASE task files.
- Ask children to return concise findings with file references and suggested planner follow-ups.
EOF
          fi

          local delegation_request_start_data
          delegation_request_start_data=$(jq -n \
            --arg role "$role" \
            --arg request_file "${role_delegation_request_iter_file#$repo/}" \
            --arg prompt_file "${delegation_request_prompt_file#$repo/}" \
            '{role: $role, request_file: $request_file, prompt_file: $prompt_file}')
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_request_pass_start" "$delegation_request_start_data" "$role"

          local delegation_request_runner_name
          delegation_request_runner_name=$(get_role_runner_name "$role")
          local delegation_request_runner_config
          delegation_request_runner_config=$(get_runner_for_role "$role" "$delegation_request_runner_name")

          local -a delegation_request_runner_command=()
          local -a delegation_request_runner_args=()
          local -a delegation_request_runner_fast_args=()
          local delegation_request_runner_prompt_mode="stdin"

          if [[ -n "$delegation_request_runner_config" ]]; then
            while IFS= read -r line; do
              [[ -n "$line" ]] && delegation_request_runner_command+=("$line")
            done < <(jq -r '.command[]?' <<<"$delegation_request_runner_config")
            while IFS= read -r line; do
              [[ -n "$line" ]] && delegation_request_runner_args+=("$line")
            done < <(jq -r '.args[]?' <<<"$delegation_request_runner_config")
            while IFS= read -r line; do
              [[ -n "$line" ]] && delegation_request_runner_fast_args+=("$line")
            done < <(jq -r '.fast_args[]?' <<<"$delegation_request_runner_config")
            delegation_request_runner_prompt_mode=$(jq -r '.prompt_mode // "stdin"' <<<"$delegation_request_runner_config")
          fi

          if [[ ${#delegation_request_runner_command[@]} -eq 0 ]]; then
            delegation_request_runner_command=("${runner_command[@]}")
            delegation_request_runner_args=("${runner_args[@]}")
            delegation_request_runner_fast_args=("${runner_fast_args[@]}")
            delegation_request_runner_prompt_mode="$runner_prompt_mode"
          fi

          local -a delegation_request_runner_active_args=("${delegation_request_runner_args[@]}")
          if [[ "${fast_mode:-0}" -eq 1 && ${#delegation_request_runner_fast_args[@]} -gt 0 ]]; then
            delegation_request_runner_active_args=("${delegation_request_runner_fast_args[@]}")
          fi

          local delegation_request_role_model delegation_request_role_thinking delegation_request_runner_type
          delegation_request_role_model=$(get_role_model "$role")
          delegation_request_role_thinking=$(get_role_thinking "$role")
          delegation_request_runner_type=$(detect_runner_type_from_cmd "${delegation_request_runner_command[0]:-}")
          local delegation_request_thinking_env=""

          if [[ -n "$delegation_request_role_model" && "$delegation_request_role_model" != "null" ]]; then
            delegation_request_runner_active_args=("--model" "$delegation_request_role_model" "${delegation_request_runner_active_args[@]}")
          fi
          if [[ -n "$delegation_request_role_thinking" && "$delegation_request_role_thinking" != "null" ]]; then
            local -a delegation_request_thinking_flags=()
            while IFS= read -r flag; do
              [[ -n "$flag" ]] && delegation_request_thinking_flags+=("$flag")
            done < <(get_thinking_flags "$delegation_request_runner_type" "$delegation_request_role_thinking")
            if [[ ${#delegation_request_thinking_flags[@]} -gt 0 ]]; then
              delegation_request_runner_active_args=("${delegation_request_thinking_flags[@]}" "${delegation_request_runner_active_args[@]}")
            fi
            delegation_request_thinking_env=$(get_thinking_env "$delegation_request_runner_type" "$delegation_request_role_thinking")
          fi

          local delegation_request_rc=0
          set +e
          (
            run_role \
              "$repo" \
              "${role}-delegation-request" \
              "$delegation_request_prompt_file" \
              "$delegation_request_last_message_file" \
              "$delegation_request_log_file" \
              "$role_delegation_child_timeout_seconds" \
              "$delegation_request_runner_prompt_mode" \
              "$timeout_inactivity" \
              "$usage_file" \
              "$iteration" \
              "$delegation_request_thinking_env" \
              "${delegation_request_runner_command[@]}" \
              -- \
              "${delegation_request_runner_active_args[@]}"
          )
          delegation_request_rc=$?
          set -e

          if [[ ! -f "$role_delegation_request_iter_file" && -f "$delegation_request_last_message_file" ]]; then
            local extracted_request_json=""
            extracted_request_json=$(sed -n '/```json/,/```/p' "$delegation_request_last_message_file" | sed '1d;$d')
            if [[ -z "$extracted_request_json" ]]; then
              extracted_request_json=$(sed -n '/^{/,$p' "$delegation_request_last_message_file")
            fi
            if [[ -n "$extracted_request_json" ]] && jq -e '.' >/dev/null 2>&1 <<<"$extracted_request_json"; then
              printf '%s\n' "$extracted_request_json" > "$role_delegation_request_iter_file"
            fi
          fi

          local delegation_request_pass_status="failed"
          if [[ -f "$role_delegation_request_iter_file" ]] && jq -e '.' "$role_delegation_request_iter_file" >/dev/null 2>&1; then
            delegation_request_pass_status="ok"
          elif [[ "$delegation_request_rc" -eq 0 ]]; then
            delegation_request_pass_status="no_request"
          fi

          local delegation_request_end_data
          delegation_request_end_data=$(jq -n \
            --arg role "$role" \
            --arg status "$delegation_request_pass_status" \
            --arg request_file "${role_delegation_request_iter_file#$repo/}" \
            --arg last_message_file "${delegation_request_last_message_file#$repo/}" \
            --argjson exit_code "$delegation_request_rc" \
            '{role: $role, status: $status, request_file: $request_file, last_message_file: $last_message_file, exit_code: $exit_code}')
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_request_pass_end" "$delegation_request_end_data" "$role"

          if [[ "$delegation_request_pass_status" == "failed" ]]; then
            echo "warning: delegation request pass failed for role '$role' (continuing without generated request)" >&2
          fi
        fi

        if [[ "$delegation_enabled" == "true" || -n "$role_delegation_enabled_override" ]]; then
          local role_delegation_status_file="$role_delegation_dir/status.json"
          local role_delegation_summary_file="$role_delegation_dir/summary.md"
          local role_delegation_children_dir="$role_delegation_dir/children"
          local role_delegation_waves_dir="$role_delegation_dir/waves"
          mkdir -p "$role_delegation_dir" "$role_delegation_children_dir" "$role_delegation_waves_dir"

          local role_delegation_enabled_json="false"
          if [[ "$role_delegation_enabled" == "true" ]]; then
            role_delegation_enabled_json="true"
          fi

          local role_delegation_status_text="disabled"
          local role_delegation_effective_dispatch_mode="$role_delegation_dispatch_mode"
          local role_delegation_effective_wake_policy="$role_delegation_wake_policy"
          local role_delegation_execution_reason="$role_delegation_reason"
          local role_delegation_request_file=""
          local role_delegation_requested_waves=0
          local role_delegation_executed_waves=0
          local role_delegation_requested_children=0
          local role_delegation_executed_children=0
          local role_delegation_succeeded_children=0
          local role_delegation_failed_children=0
          local role_delegation_skipped_children=0
          local role_delegation_completion_order_json="[]"
          local role_delegation_aggregation_order_json="[]"
          local role_delegation_terminal_completed=0
          local role_delegation_terminal_failed=0
          local role_delegation_terminal_timed_out=0
          local role_delegation_terminal_cancelled=0
          local role_delegation_terminal_policy_violation=0
          local role_delegation_terminal_skipped=0
          local role_delegation_recon_violation_count=0
          local role_delegation_recon_violation_wave_id=""
          local role_delegation_recon_violation_child_id=""
          local role_delegation_fail_role_triggered=0
          local role_delegation_fail_role_wave_id=""
          local role_delegation_fail_role_child_id=""
          local role_delegation_adaptation_dir="$role_delegation_dir/adaptation"
          local role_delegation_adaptation_status="disabled"
          local role_delegation_adaptation_reason="wake_policy_not_on_child_complete"
          local role_delegation_adaptation_max_replans_per_wave=0
          local role_delegation_adaptation_max_replans_per_iteration=0
          local role_delegation_adaptation_attempted=0
          local role_delegation_adaptation_applied=0
          local role_delegation_adaptation_skipped=0
          local role_delegation_stop_after_wave=0
          local role_delegation_stop_reason=""

          {
            echo "# Delegation Summary"
            echo ""
            echo "- loop: $loop_id"
            echo "- run_id: $run_id"
            echo "- iteration: $iteration"
            echo "- role: $role"
            echo ""
          } > "$role_delegation_summary_file"

          if [[ -f "$role_delegation_request_iter_file" ]]; then
            role_delegation_request_file="$role_delegation_request_iter_file"
          elif [[ -f "$role_delegation_request_shared_file" ]]; then
            role_delegation_request_file="$role_delegation_request_shared_file"
          fi

          # Phase 3: bounded serial/parallel dispatch + adaptive wake on child completion.
          if [[ "$role_delegation_enabled" == "true" ]]; then
            role_delegation_status_text="enabled"
            mkdir -p "$role_delegation_adaptation_dir"

            if [[ "$role_delegation_mode" == "reconnaissance" && "$role_delegation_effective_dispatch_mode" == "parallel" ]]; then
              echo "warning: delegation mode=reconnaissance requested for role '$role' with dispatch_mode=parallel; using serial dispatch" >&2
              role_delegation_effective_dispatch_mode="serial"
              if [[ -n "$role_delegation_execution_reason" ]]; then
                role_delegation_execution_reason="${role_delegation_execution_reason},reconnaissance_requires_serial"
              else
                role_delegation_execution_reason="reconnaissance_requires_serial"
              fi
            fi

            if [[ "$role_delegation_effective_wake_policy" == "on_child_complete" ]]; then
              role_delegation_adaptation_status="enabled"
              if [[ "$role_delegation_effective_dispatch_mode" == "parallel" ]]; then
                role_delegation_adaptation_reason="on_child_complete_parallel"
              else
                role_delegation_adaptation_reason="on_child_complete"
              fi
            fi

            if [[ -z "$role_delegation_request_file" ]]; then
              role_delegation_status_text="enabled_no_request"
              echo "- status: enabled but no delegation request file found" >> "$role_delegation_summary_file"
            elif ! jq -e '.' "$role_delegation_request_file" >/dev/null 2>&1; then
              role_delegation_status_text="request_invalid"
              role_delegation_execution_reason="request_invalid_json"
              echo "warning: invalid delegation request JSON for role '$role': ${role_delegation_request_file#$repo/}" >&2
              echo "- status: invalid request JSON (${role_delegation_request_file#$repo/})" >> "$role_delegation_summary_file"
            else
              local role_delegation_waves_json
              role_delegation_waves_json=$(jq -c '
                if (.waves | type) == "array" then .waves
                elif (.children | type) == "array" then [{id: "wave-1", children: .children}]
                else []
                end' "$role_delegation_request_file" 2>/dev/null || echo "[]")

              role_delegation_requested_waves=$(jq -r 'length' <<<"$role_delegation_waves_json" 2>/dev/null || echo "0")
              role_delegation_requested_waves=$(rlms_safe_int "$role_delegation_requested_waves" 0)

              if [[ "$role_delegation_requested_waves" -le 0 ]]; then
                role_delegation_status_text="request_empty"
                echo "- status: request contained no waves/children" >> "$role_delegation_summary_file"
              else
                local role_delegation_waves_to_run="$role_delegation_requested_waves"
                if [[ "$role_delegation_waves_to_run" -gt "$role_delegation_max_waves" ]]; then
                  role_delegation_waves_to_run="$role_delegation_max_waves"
                fi
                if [[ "$role_delegation_requested_waves" -gt "$role_delegation_waves_to_run" ]]; then
                  echo "- waves truncated by max_waves (${role_delegation_waves_to_run}/${role_delegation_requested_waves})" >> "$role_delegation_summary_file"
                fi

                if [[ "$role_delegation_adaptation_status" == "enabled" ]]; then
                  role_delegation_adaptation_max_replans_per_wave="$role_delegation_max_children"
                  role_delegation_adaptation_max_replans_per_iteration=$((role_delegation_waves_to_run * role_delegation_adaptation_max_replans_per_wave))
                  if [[ "$role_delegation_adaptation_max_replans_per_wave" -lt 1 ]]; then
                    role_delegation_adaptation_max_replans_per_wave=1
                  fi
                  if [[ "$role_delegation_adaptation_max_replans_per_iteration" -lt 1 ]]; then
                    role_delegation_adaptation_max_replans_per_iteration="$role_delegation_adaptation_max_replans_per_wave"
                  fi
                fi

                local delegation_runner_name
                delegation_runner_name=$(get_role_runner_name "$role")
                local delegation_runner_config
                delegation_runner_config=$(get_runner_for_role "$role" "$delegation_runner_name")

                local -a delegation_runner_command=()
                local -a delegation_runner_args=()
                local -a delegation_runner_fast_args=()
                local delegation_runner_prompt_mode="stdin"

                if [[ -n "$delegation_runner_config" ]]; then
                  while IFS= read -r line; do
                    [[ -n "$line" ]] && delegation_runner_command+=("$line")
                  done < <(jq -r '.command[]?' <<<"$delegation_runner_config")
                  while IFS= read -r line; do
                    [[ -n "$line" ]] && delegation_runner_args+=("$line")
                  done < <(jq -r '.args[]?' <<<"$delegation_runner_config")
                  while IFS= read -r line; do
                    [[ -n "$line" ]] && delegation_runner_fast_args+=("$line")
                  done < <(jq -r '.fast_args[]?' <<<"$delegation_runner_config")
                  delegation_runner_prompt_mode=$(jq -r '.prompt_mode // "stdin"' <<<"$delegation_runner_config")
                fi

                if [[ ${#delegation_runner_command[@]} -eq 0 ]]; then
                  delegation_runner_command=("${runner_command[@]}")
                  delegation_runner_args=("${runner_args[@]}")
                  delegation_runner_fast_args=("${runner_fast_args[@]}")
                  delegation_runner_prompt_mode="$runner_prompt_mode"
                fi
                if [[ "$delegation_runner_prompt_mode" != "stdin" && "$delegation_runner_prompt_mode" != "file" ]]; then
                  delegation_runner_prompt_mode="stdin"
                fi

                local -a delegation_runner_active_args=("${delegation_runner_args[@]}")
                if [[ "${fast_mode:-0}" -eq 1 && ${#delegation_runner_fast_args[@]} -gt 0 ]]; then
                  delegation_runner_active_args=("${delegation_runner_fast_args[@]}")
                fi

                local delegation_role_model delegation_role_thinking delegation_runner_type delegation_thinking_env
                delegation_role_model=$(get_role_model "$role")
                delegation_role_thinking=$(get_role_thinking "$role")
                delegation_runner_type=$(detect_runner_type_from_cmd "${delegation_runner_command[0]:-}")
                delegation_thinking_env=""

                if [[ -n "$delegation_role_model" && "$delegation_role_model" != "null" ]]; then
                  delegation_runner_active_args=("--model" "$delegation_role_model" "${delegation_runner_active_args[@]}")
                fi
                if [[ -n "$delegation_role_thinking" && "$delegation_role_thinking" != "null" ]]; then
                  local -a delegation_thinking_flags=()
                  while IFS= read -r flag; do
                    [[ -n "$flag" ]] && delegation_thinking_flags+=("$flag")
                  done < <(get_thinking_flags "$delegation_runner_type" "$delegation_role_thinking")
                  if [[ ${#delegation_thinking_flags[@]} -gt 0 ]]; then
                    delegation_runner_active_args=("${delegation_thinking_flags[@]}" "${delegation_runner_active_args[@]}")
                  fi
                  delegation_thinking_env=$(get_thinking_env "$delegation_runner_type" "$delegation_role_thinking")
                fi

                if [[ ${#delegation_runner_command[@]} -eq 0 ]]; then
                  role_delegation_status_text="child_runner_missing"
                  role_delegation_execution_reason="child_runner_missing"
                  echo "warning: delegation is enabled for role '$role' but no runner command is configured" >&2
                  echo "- status: child runner missing" >> "$role_delegation_summary_file"
                else
                  echo "- request file: ${role_delegation_request_file#$repo/}" >> "$role_delegation_summary_file"
                  echo "- executing waves: ${role_delegation_waves_to_run}" >> "$role_delegation_summary_file"
                  echo "- dispatch: ${role_delegation_effective_dispatch_mode}" >> "$role_delegation_summary_file"
                  echo "- wake policy: ${role_delegation_effective_wake_policy}" >> "$role_delegation_summary_file"
                  echo "- mode: ${role_delegation_mode}" >> "$role_delegation_summary_file"
                  echo "- max children per wave: ${role_delegation_max_children}" >> "$role_delegation_summary_file"
                  echo "- max parallel workers: ${role_delegation_max_parallel}" >> "$role_delegation_summary_file"
                  echo "- failure policy: ${role_delegation_failure_policy}" >> "$role_delegation_summary_file"
                  echo "- retry limit: ${role_delegation_retry_limit}" >> "$role_delegation_summary_file"
                  echo "- retry backoff seconds: ${role_delegation_retry_backoff_seconds}" >> "$role_delegation_summary_file"
                  echo "- retry backoff max seconds: ${role_delegation_retry_backoff_max_seconds}" >> "$role_delegation_summary_file"
                  echo "- adaptation status: ${role_delegation_adaptation_status}" >> "$role_delegation_summary_file"
                  if [[ "$role_delegation_adaptation_status" == "enabled" ]]; then
                    echo "- adaptation max replans per wave: ${role_delegation_adaptation_max_replans_per_wave}" >> "$role_delegation_summary_file"
                    echo "- adaptation max replans per iteration: ${role_delegation_adaptation_max_replans_per_iteration}" >> "$role_delegation_summary_file"
                  else
                    echo "- adaptation reason: ${role_delegation_adaptation_reason}" >> "$role_delegation_summary_file"
                  fi
                  echo "" >> "$role_delegation_summary_file"

                  local wave_number
                  for ((wave_number=1; wave_number<=role_delegation_waves_to_run; wave_number++)); do
                    local wave_json
                    wave_json=$(jq -c ".[$((wave_number - 1))]" <<<"$role_delegation_waves_json")
                    local wave_id
                    wave_id=$(jq -r --arg default "wave-$wave_number" '.id // $default' <<<"$wave_json")
                    wave_id=$(sanitize_delegation_id "$wave_id")
                    local wave_dir="$role_delegation_waves_dir/$wave_id"
                    mkdir -p "$wave_dir"

                    local wave_children_json
                    wave_children_json=$(jq -c '.children // []' <<<"$wave_json")
                    local wave_requested_children wave_children_to_run
                    wave_requested_children=$(jq -r 'length' <<<"$wave_children_json" 2>/dev/null || echo "0")
                    wave_requested_children=$(rlms_safe_int "$wave_requested_children" 0)
                    wave_children_to_run="$wave_requested_children"
                    if [[ "$wave_children_to_run" -gt "$role_delegation_max_children" ]]; then
                      wave_children_to_run="$role_delegation_max_children"
                    fi
                    if [[ "$wave_children_to_run" -lt 0 ]]; then
                      wave_children_to_run=0
                    fi
                    local wave_concurrency_cap="$wave_children_to_run"
                    if [[ "$wave_children_to_run" -le 0 ]]; then
                      wave_concurrency_cap=0
                    elif [[ "$role_delegation_effective_dispatch_mode" == "serial" ]]; then
                      wave_concurrency_cap=1
                    elif [[ "$wave_concurrency_cap" -gt "$role_delegation_max_parallel" ]]; then
                      wave_concurrency_cap="$role_delegation_max_parallel"
                    fi

                    role_delegation_requested_children=$((role_delegation_requested_children + wave_requested_children))

                    local delegation_wave_start_data
                    delegation_wave_start_data=$(jq -n \
                      --arg role "$role" \
                      --arg wave_id "$wave_id" \
                      --arg dispatch_mode "$role_delegation_effective_dispatch_mode" \
                      --arg wake_policy "$role_delegation_effective_wake_policy" \
                      --argjson enabled "$role_delegation_enabled_json" \
                      --argjson requested_children "$wave_requested_children" \
                      --argjson children_to_run "$wave_children_to_run" \
                      --argjson concurrency_cap "$wave_concurrency_cap" \
                      --argjson wave "$wave_number" \
                      '{role: $role, wave_id: $wave_id, wave: $wave, dispatch_mode: $dispatch_mode, wake_policy: $wake_policy, enabled: $enabled, requested_children: $requested_children, children_to_run: $children_to_run, concurrency_cap: $concurrency_cap}')
                    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_wave_start" "$delegation_wave_start_data" "$role"

                    local wave_executed_children=0
                    local wave_succeeded_children=0
                    local wave_failed_children=0
                    local wave_terminal_completed=0
                    local wave_terminal_failed=0
                    local wave_terminal_timed_out=0
                    local wave_terminal_cancelled=0
                    local wave_terminal_policy_violation=0
                    local wave_terminal_skipped=0
                    local wave_adaptation_attempted=0
                    local wave_adaptation_stopped=0
                    local wave_stop_launch=0

                    if [[ "$wave_children_to_run" -gt 0 ]]; then
                      local -a wave_parallel_pids=()
                      local -a wave_parallel_reaped=()
                      local -a wave_parallel_child_ids=()
                      local -a wave_parallel_child_numbers=()
                      local -a wave_parallel_child_status_files=()
                      local -a wave_parallel_child_log_files=()
                      local -a wave_parallel_child_last_files=()
                      local -a wave_parallel_child_usage_files=()
                      local wave_parallel_active_workers=0
                      local wave_parallel_launched_workers=0

                      local child_number
                      for ((child_number=1; child_number<=wave_children_to_run; child_number++)); do
                        if [[ "$wave_stop_launch" -eq 1 ]]; then
                          break
                        fi
                        local child_json
                        child_json=$(jq -c ".[$((child_number - 1))]" <<<"$wave_children_json")

                        local child_id
                        child_id=$(jq -r --arg default "child-$child_number" '.id // $default' <<<"$child_json")
                        child_id=$(sanitize_delegation_id "$child_id")

                        local child_prompt_text
                        child_prompt_text=$(jq -r '.prompt // .task // .instruction // empty' <<<"$child_json")
                        if [[ -z "$child_prompt_text" ]]; then
                          child_prompt_text="Summarize relevant code context and propose concrete implementation steps for this delegated subtask."
                        fi

                        local child_dir="$role_delegation_children_dir/$wave_id/$child_id"
                        local child_prompt_file="$child_dir/prompt.md"
                        local child_log_file="$child_dir/output.log"
                        local child_last_message_file="$child_dir/last_message.txt"
                        local child_status_file="$child_dir/status.json"
                        local child_context_file="$child_dir/context-files.txt"
                        local child_usage_file="$child_dir/usage.jsonl"
                        mkdir -p "$child_dir"
                        : > "$child_context_file"
                        : > "$child_usage_file"

                        while IFS= read -r ctx_path; do
                          [[ -z "$ctx_path" || "$ctx_path" == "null" ]] && continue
                          local ctx_abs_path="$ctx_path"
                          if [[ "$ctx_path" != /* ]]; then
                            ctx_abs_path="$repo/$ctx_path"
                          fi
                          if [[ -f "$ctx_abs_path" ]]; then
                            printf '%s\n' "$ctx_abs_path" >> "$child_context_file"
                          fi
                        done < <(jq -r '.context_files[]? // empty' <<<"$child_json")

                        {
                          echo "You are a delegated child agent in Superloop."
                          echo ""
                          echo "Parent role: $role"
                          echo "Loop: $loop_id"
                          echo "Run: $run_id"
                          echo "Iteration: $iteration"
                          echo "Wave: $wave_id"
                          echo "Child: $child_id"
                          echo ""
                          echo "Subtask:"
                          echo "$child_prompt_text"
                          echo ""
                          echo "Constraints:"
                          echo "- Focus only on this subtask."
                          echo "- Do not claim overall loop completion."
                          echo "- Return concise actionable output for the parent role."
                          if [[ "$role_delegation_mode" == "reconnaissance" ]]; then
                            echo "- Reconnaissance-only mode: analyze existing context; do not apply code or file edits."
                            echo "- Do not modify PLAN.MD, PHASE task files, or canonical role reports."
                            echo "- Prefer findings, risks, and suggested planner follow-up tasks with file references."
                          fi
                          if [[ -s "$child_context_file" ]]; then
                            echo ""
                            echo "Context files (read as needed):"
                            sed 's#^#- #' "$child_context_file"
                          fi
                        } > "$child_prompt_file"

                        local child_start_data
                        child_start_data=$(jq -n \
                          --arg role "$role" \
                          --arg wave_id "$wave_id" \
                          --arg child_id "$child_id" \
                          --arg prompt_file "${child_prompt_file#$repo/}" \
                          --argjson max_retries "$role_delegation_retry_limit" \
                          '{role: $role, wave_id: $wave_id, child_id: $child_id, prompt_file: $prompt_file, max_retries: $max_retries}')
                        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_child_start" "$child_start_data" "$role"

                        if [[ "$role_delegation_effective_dispatch_mode" == "parallel" ]]; then
                          (
                            set +e
                            child_attempt=0
                            child_max_attempts=$((role_delegation_retry_limit + 1))
                            child_rc=1
                            while [[ "$child_attempt" -lt "$child_max_attempts" ]]; do
                              child_attempt=$((child_attempt + 1))
                              (
                                run_role \
                                  "$repo" \
                                  "${role}-child-${wave_id}-${child_id}" \
                                  "$child_prompt_file" \
                                  "$child_last_message_file" \
                                  "$child_log_file" \
                                  "$role_delegation_child_timeout_seconds" \
                                  "$delegation_runner_prompt_mode" \
                                  "$timeout_inactivity" \
                                  "$child_usage_file" \
                                  "$iteration" \
                                  "$delegation_thinking_env" \
                                  "${delegation_runner_command[@]}" \
                                  -- \
                                  "${delegation_runner_active_args[@]}"
                              )
                              child_rc=$?
                              if [[ "$child_rc" -eq 0 ]]; then
                                break
                              fi
                              if [[ "$child_attempt" -lt "$child_max_attempts" ]]; then
                                child_backoff_seconds=$(compute_delegation_retry_backoff_seconds "$role_delegation_retry_backoff_seconds" "$role_delegation_retry_backoff_max_seconds" "$child_attempt")
                                if [[ "$child_backoff_seconds" -gt 0 ]]; then
                                  sleep "$child_backoff_seconds"
                                fi
                              fi
                            done

                            child_status_text="failed"
                            if [[ "$child_rc" -eq 0 ]]; then
                              child_status_text="ok"
                            elif [[ "$child_rc" -eq 124 ]]; then
                              child_status_text="timeout"
                            elif [[ "$child_rc" -eq 125 ]]; then
                              child_status_text="rate_limited"
                            fi
                            child_terminal_state=$(normalize_delegation_terminal_state "$child_status_text")

                            jq -n \
                              --arg generated_at "$(timestamp)" \
                              --arg role "$role" \
                              --arg wave_id "$wave_id" \
                              --arg child_id "$child_id" \
                              --arg status "$child_status_text" \
                              --arg terminal_state "$child_terminal_state" \
                              --argjson exit_code "$child_rc" \
                              --argjson attempts "$child_attempt" \
                              --arg prompt_file "${child_prompt_file#$repo/}" \
                              --arg log_file "${child_log_file#$repo/}" \
                              --arg last_message_file "${child_last_message_file#$repo/}" \
                              --arg usage_file "${child_usage_file#$repo/}" \
                              '{
                                generated_at: $generated_at,
                                role: $role,
                                wave_id: $wave_id,
                                child_id: $child_id,
                                status: $status,
                                terminal_state: $terminal_state,
                                exit_code: $exit_code,
                                attempts: $attempts,
                                prompt_file: $prompt_file,
                                log_file: $log_file,
                                last_message_file: $last_message_file,
                                usage_file: $usage_file
                              }' > "$child_status_file"
                          ) &
                          wave_parallel_pids+=("$!")
                          wave_parallel_reaped+=("0")
                          wave_parallel_child_ids+=("$child_id")
                          wave_parallel_child_numbers+=("$child_number")
                          wave_parallel_child_status_files+=("$child_status_file")
                          wave_parallel_child_log_files+=("$child_log_file")
                          wave_parallel_child_last_files+=("$child_last_message_file")
                          wave_parallel_child_usage_files+=("$child_usage_file")
                          wave_parallel_active_workers=$((wave_parallel_active_workers + 1))
                          wave_parallel_launched_workers=$((wave_parallel_launched_workers + 1))

                          local wave_dispatch_data
                          wave_dispatch_data=$(jq -n \
                            --arg role "$role" \
                            --arg wave_id "$wave_id" \
                            --arg child_id "$child_id" \
                            --argjson wave "$wave_number" \
                            --argjson launched_children "$wave_parallel_launched_workers" \
                            --argjson total_children "$wave_children_to_run" \
                            --argjson active_workers "$wave_parallel_active_workers" \
                            --argjson concurrency_cap "$wave_concurrency_cap" \
                            --argjson queued_children "$((wave_children_to_run - wave_parallel_launched_workers))" \
                            '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, launched_children: $launched_children, total_children: $total_children, active_workers: $active_workers, concurrency_cap: $concurrency_cap, queued_children: $queued_children}')
                          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_wave_dispatch" "$wave_dispatch_data" "$role"

                          if [[ "$wave_concurrency_cap" -gt 0 ]]; then
                            while [[ "$wave_parallel_active_workers" -ge "$wave_concurrency_cap" ]]; do
                              local wave_reaped_one=0
                              local scan_index
                              for scan_index in "${!wave_parallel_pids[@]}"; do
                                if [[ "${wave_parallel_reaped[$scan_index]}" == "1" ]]; then
                                  continue
                                fi
                                local scan_pid="${wave_parallel_pids[$scan_index]}"
                                if ! kill -0 "$scan_pid" 2>/dev/null; then
                                  set +e
                                  wait "$scan_pid" >/dev/null 2>&1
                                  set -e
                                  wave_parallel_reaped[$scan_index]="1"
                                  if [[ "$wave_parallel_active_workers" -gt 0 ]]; then
                                    wave_parallel_active_workers=$((wave_parallel_active_workers - 1))
                                  fi
                                  role_delegation_completion_order_json=$(jq -c \
                                    --arg wave_id "$wave_id" \
                                    --arg child_id "${wave_parallel_child_ids[$scan_index]}" \
                                    '. + [{wave_id: $wave_id, child_id: $child_id}]' \
                                    <<<"$role_delegation_completion_order_json")
                                  local wave_queue_data
                                  wave_queue_data=$(jq -n \
                                    --arg role "$role" \
                                    --arg wave_id "$wave_id" \
                                    --arg phase "cap_gate" \
                                    --argjson wave "$wave_number" \
                                    --argjson active_workers "$wave_parallel_active_workers" \
                                    --argjson launched_children "$wave_parallel_launched_workers" \
                                    --argjson total_children "$wave_children_to_run" \
                                    --argjson concurrency_cap "$wave_concurrency_cap" \
                                    '{role: $role, wave_id: $wave_id, wave: $wave, phase: $phase, active_workers: $active_workers, launched_children: $launched_children, total_children: $total_children, concurrency_cap: $concurrency_cap}')
                                  log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_wave_queue_drain" "$wave_queue_data" "$role"

                                  if [[ "$role_delegation_effective_wake_policy" == "on_child_complete" && "$role_delegation_adaptation_status" == "enabled" && "$role_delegation_stop_after_wave" -eq 0 ]]; then
                                    local completed_child_id="${wave_parallel_child_ids[$scan_index]}"
                                    local completed_child_number="${wave_parallel_child_numbers[$scan_index]}"
                                    local completed_child_status_file="${wave_parallel_child_status_files[$scan_index]}"
                                    local completed_child_last_message_file="${wave_parallel_child_last_files[$scan_index]}"
                                    local completed_child_log_file="${wave_parallel_child_log_files[$scan_index]}"
                                    local completed_child_usage_file="${wave_parallel_child_usage_files[$scan_index]}"

                                    if [[ ! -f "$completed_child_status_file" ]]; then
                                      jq -n \
                                        --arg generated_at "$(timestamp)" \
                                        --arg role "$role" \
                                        --arg wave_id "$wave_id" \
                                        --arg child_id "$completed_child_id" \
                                        --arg status "failed" \
                                        --arg terminal_state "failed" \
                                        --argjson exit_code 1 \
                                        --argjson attempts 0 \
                                        --arg prompt_file "" \
                                        --arg log_file "${completed_child_log_file#$repo/}" \
                                        --arg last_message_file "${completed_child_last_message_file#$repo/}" \
                                        --arg usage_file "${completed_child_usage_file#$repo/}" \
                                        '{
                                          generated_at: $generated_at,
                                          role: $role,
                                          wave_id: $wave_id,
                                          child_id: $child_id,
                                          status: $status,
                                          terminal_state: $terminal_state,
                                          exit_code: $exit_code,
                                          attempts: $attempts,
                                          prompt_file: (if ($prompt_file | length) > 0 then $prompt_file else null end),
                                          log_file: $log_file,
                                          last_message_file: $last_message_file,
                                          usage_file: $usage_file
                                        } | with_entries(select(.value != null))' > "$completed_child_status_file"
                                    fi

                                    local completed_child_status_text completed_child_rc completed_child_attempts
                                    completed_child_status_text=$(jq -r '.status // "failed"' "$completed_child_status_file" 2>/dev/null || echo "failed")
                                    completed_child_rc=$(jq -r '.exit_code // 1' "$completed_child_status_file" 2>/dev/null || echo "1")
                                    completed_child_attempts=$(jq -r '.attempts // 0' "$completed_child_status_file" 2>/dev/null || echo "0")
                                    completed_child_rc=$(rlms_safe_int "$completed_child_rc" 1)
                                    completed_child_attempts=$(rlms_safe_int "$completed_child_attempts" 0)

                                    local remaining_unlaunched=$((wave_children_to_run - wave_parallel_launched_workers))
                                    if [[ "$remaining_unlaunched" -lt 0 ]]; then
                                      remaining_unlaunched=0
                                    fi
                                    local remaining_after_completion=$((remaining_unlaunched + wave_parallel_active_workers))
                                    if [[ "$remaining_after_completion" -gt 0 ]]; then
                                      local adaptation_skip_reason=""
                                      if [[ "$wave_adaptation_attempted" -ge "$role_delegation_adaptation_max_replans_per_wave" ]]; then
                                        adaptation_skip_reason="wave_limit_reached"
                                      elif [[ "$role_delegation_adaptation_attempted" -ge "$role_delegation_adaptation_max_replans_per_iteration" ]]; then
                                        adaptation_skip_reason="iteration_limit_reached"
                                      fi

                                      if [[ -n "$adaptation_skip_reason" ]]; then
                                        role_delegation_adaptation_skipped=$((role_delegation_adaptation_skipped + 1))
                                        local adaptation_skip_data
                                        adaptation_skip_data=$(jq -n \
                                          --arg role "$role" \
                                          --arg wave_id "$wave_id" \
                                          --arg child_id "$completed_child_id" \
                                          --arg reason "$adaptation_skip_reason" \
                                          --argjson wave "$wave_number" \
                                          --argjson child "$completed_child_number" \
                                          --argjson attempted_wave "$wave_adaptation_attempted" \
                                          --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                                          '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, reason: $reason, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration}')
                                        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_skipped" "$adaptation_skip_data" "$role"
                                      else
                                        role_delegation_adaptation_attempted=$((role_delegation_adaptation_attempted + 1))
                                        wave_adaptation_attempted=$((wave_adaptation_attempted + 1))

                                        local adaptation_wave_dir="$role_delegation_adaptation_dir/$wave_id"
                                        mkdir -p "$adaptation_wave_dir"
                                        local adaptation_pass_id="after-child-$completed_child_number"
                                        local adaptation_prompt_file="$adaptation_wave_dir/${adaptation_pass_id}.prompt.md"
                                        local adaptation_log_file="$adaptation_wave_dir/${adaptation_pass_id}.log"
                                        local adaptation_last_message_file="$adaptation_wave_dir/${adaptation_pass_id}.last_message.txt"
                                        local adaptation_decision_file="$adaptation_wave_dir/${adaptation_pass_id}.decision.json"
                                        local adaptation_usage_file="$adaptation_wave_dir/${adaptation_pass_id}.usage.jsonl"
                                        : > "$adaptation_usage_file"

                                        {
                                          echo "You are adapting delegation after a child completion."
                                          echo ""
                                          echo "Parent role: $role"
                                          echo "Loop: $loop_id"
                                          echo "Run: $run_id"
                                          echo "Iteration: $iteration"
                                          echo "Wave: $wave_id"
                                          echo "Completed child: $completed_child_id"
                                          echo "Completed child index: $completed_child_number of $wave_children_to_run"
                                          echo "Completed child status: $completed_child_status_text"
                                          echo "Completed child exit code: $completed_child_rc"
                                          echo "Completed child attempts: $completed_child_attempts"
                                          echo "Completed child output: ${completed_child_last_message_file#$repo/}"
                                          echo ""
                                          echo "Write adaptation decision JSON to this exact file path:"
                                          echo "$adaptation_decision_file"
                                          echo ""
                                          echo "JSON shape:"
                                          echo "{"
                                          echo '  "continue_wave": true,'
                                          echo '  "continue_delegation": true,'
                                          echo '  "reason": "short rationale"'
                                          echo "}"
                                          echo ""
                                          echo "Rules:"
                                          echo "- Set continue_wave=false to stop remaining children in this wave."
                                          echo "- Set continue_delegation=false to stop all remaining waves."
                                          echo "- Keep both true if no replanning is needed."
                                          echo "- Do not modify code or canonical role reports in this pass."
                                        } > "$adaptation_prompt_file"

                                        local adaptation_start_data
                                        adaptation_start_data=$(jq -n \
                                          --arg role "$role" \
                                          --arg wave_id "$wave_id" \
                                          --arg child_id "$completed_child_id" \
                                          --arg prompt_file "${adaptation_prompt_file#$repo/}" \
                                          --arg decision_file "${adaptation_decision_file#$repo/}" \
                                          --argjson wave "$wave_number" \
                                          --argjson child "$completed_child_number" \
                                          --argjson attempted_wave "$wave_adaptation_attempted" \
                                          --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                                          --argjson max_replans_per_wave "$role_delegation_adaptation_max_replans_per_wave" \
                                          --argjson max_replans_per_iteration "$role_delegation_adaptation_max_replans_per_iteration" \
                                          '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, prompt_file: $prompt_file, decision_file: $decision_file, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration, max_replans_per_wave: $max_replans_per_wave, max_replans_per_iteration: $max_replans_per_iteration}')
                                        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_start" "$adaptation_start_data" "$role"

                                        local adaptation_rc=0
                                        set +e
                                        (
                                          run_role \
                                            "$repo" \
                                            "${role}-adapt-${wave_id}-${completed_child_id}-${wave_adaptation_attempted}" \
                                            "$adaptation_prompt_file" \
                                            "$adaptation_last_message_file" \
                                            "$adaptation_log_file" \
                                            "$role_delegation_child_timeout_seconds" \
                                            "$delegation_runner_prompt_mode" \
                                            "$timeout_inactivity" \
                                            "$adaptation_usage_file" \
                                            "$iteration" \
                                            "$delegation_thinking_env" \
                                            "${delegation_runner_command[@]}" \
                                            -- \
                                            "${delegation_runner_active_args[@]}"
                                        )
                                        adaptation_rc=$?
                                        set -e

                                        append_usage_records_file "$adaptation_usage_file" "$usage_file"

                                        if [[ ! -f "$adaptation_decision_file" && -f "$adaptation_last_message_file" ]]; then
                                          local extracted_adaptation_json=""
                                          extracted_adaptation_json=$(sed -n '/```json/,/```/p' "$adaptation_last_message_file" | sed '1d;$d')
                                          if [[ -z "$extracted_adaptation_json" ]]; then
                                            extracted_adaptation_json=$(sed -n '/^{/,$p' "$adaptation_last_message_file")
                                          fi
                                          if [[ -n "$extracted_adaptation_json" ]] && jq -e '.' >/dev/null 2>&1 <<<"$extracted_adaptation_json"; then
                                            printf '%s\n' "$extracted_adaptation_json" > "$adaptation_decision_file"
                                          fi
                                        fi

                                        local adaptation_status="failed"
                                        local adaptation_decision_continue_wave="true"
                                        local adaptation_decision_continue_delegation="true"
                                        local adaptation_decision_reason=""
                                        if [[ -f "$adaptation_decision_file" ]] && jq -e '.' "$adaptation_decision_file" >/dev/null 2>&1; then
                                          adaptation_status="ok"
                                          adaptation_decision_continue_wave=$(jq -r '
                                            if (.continue_wave | type) == "boolean" then (.continue_wave | tostring)
                                            elif (.continue | type) == "boolean" then (.continue | tostring)
                                            elif (.stop_wave | type) == "boolean" then (if .stop_wave then "false" else "true" end)
                                            else "true"
                                            end' "$adaptation_decision_file" 2>/dev/null || echo "true")
                                          adaptation_decision_continue_delegation=$(jq -r '
                                            if (.continue_delegation | type) == "boolean" then (.continue_delegation | tostring)
                                            elif (.continue_iteration | type) == "boolean" then (.continue_iteration | tostring)
                                            elif (.stop_delegation | type) == "boolean" then (if .stop_delegation then "false" else "true" end)
                                            else "true"
                                            end' "$adaptation_decision_file" 2>/dev/null || echo "true")
                                          adaptation_decision_reason=$(jq -r '.reason // .rationale // .note // empty' "$adaptation_decision_file" 2>/dev/null || echo "")
                                        elif [[ "$adaptation_rc" -eq 0 ]]; then
                                          adaptation_status="no_decision"
                                        fi

                                        if [[ "$adaptation_decision_continue_wave" != "true" && "$adaptation_decision_continue_wave" != "false" ]]; then
                                          adaptation_decision_continue_wave="true"
                                        fi
                                        if [[ "$adaptation_decision_continue_delegation" != "true" && "$adaptation_decision_continue_delegation" != "false" ]]; then
                                          adaptation_decision_continue_delegation="true"
                                        fi

                                        local adaptation_applied="false"
                                        if [[ "$adaptation_status" == "ok" && ( "$adaptation_decision_continue_wave" == "false" || "$adaptation_decision_continue_delegation" == "false" ) ]]; then
                                          adaptation_applied="true"
                                          role_delegation_adaptation_applied=$((role_delegation_adaptation_applied + 1))
                                          wave_adaptation_stopped=1
                                        fi

                                        local adaptation_end_data
                                        adaptation_end_data=$(jq -n \
                                          --arg role "$role" \
                                          --arg wave_id "$wave_id" \
                                          --arg child_id "$completed_child_id" \
                                          --arg status "$adaptation_status" \
                                          --arg continue_wave "$adaptation_decision_continue_wave" \
                                          --arg continue_delegation "$adaptation_decision_continue_delegation" \
                                          --arg reason "$adaptation_decision_reason" \
                                          --arg decision_file "${adaptation_decision_file#$repo/}" \
                                          --arg last_message_file "${adaptation_last_message_file#$repo/}" \
                                          --argjson exit_code "$adaptation_rc" \
                                          --argjson wave "$wave_number" \
                                          --argjson child "$completed_child_number" \
                                          --argjson attempted_wave "$wave_adaptation_attempted" \
                                          --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                                          --argjson applied "$(if [[ "$adaptation_applied" == "true" ]]; then echo true; else echo false; fi)" \
                                          '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, status: $status, continue_wave: $continue_wave, continue_delegation: $continue_delegation, reason: (if ($reason | length) > 0 then $reason else null end), decision_file: $decision_file, last_message_file: $last_message_file, exit_code: $exit_code, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration, applied: $applied} | with_entries(select(.value != null))')
                                        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_end" "$adaptation_end_data" "$role"

                                        {
                                          echo "- adaptation after child: $completed_child_id"
                                          echo "  status: $adaptation_status"
                                          echo "  continue_wave: $adaptation_decision_continue_wave"
                                          echo "  continue_delegation: $adaptation_decision_continue_delegation"
                                          echo "  decision_file: ${adaptation_decision_file#$repo/}"
                                          echo "  output_file: ${adaptation_last_message_file#$repo/}"
                                          if [[ -n "$adaptation_decision_reason" ]]; then
                                            echo "  reason: $adaptation_decision_reason"
                                          fi
                                        } >> "$role_delegation_summary_file"
                                        echo "" >> "$role_delegation_summary_file"

                                        if [[ "$adaptation_decision_continue_delegation" == "false" ]]; then
                                          role_delegation_stop_after_wave=1
                                          role_delegation_stop_reason="adaptation_decision"
                                        fi
                                        if [[ "$adaptation_decision_continue_wave" == "false" || "$adaptation_decision_continue_delegation" == "false" ]]; then
                                          if [[ -z "$role_delegation_execution_reason" ]]; then
                                            role_delegation_execution_reason="adapted_after_child"
                                          elif [[ "$role_delegation_execution_reason" != *"adapted_after_child"* ]]; then
                                            role_delegation_execution_reason="${role_delegation_execution_reason},adapted_after_child"
                                          fi
                                          wave_stop_launch=1
                                        fi
                                      fi
                                    fi
                                  fi

                                  wave_reaped_one=1
                                  break
                                fi
                              done
                              if [[ "$wave_reaped_one" -eq 0 ]]; then
                                sleep 0.05
                              fi
                            done
                          fi
                          continue
                        fi

                        local recon_before_dirty_file="$child_dir/recon.before.dirty.txt"
                        local recon_after_dirty_file="$child_dir/recon.after.dirty.txt"
                        local recon_violation_file="$child_dir/recon.violation.txt"
                        local recon_before_signature=""
                        local recon_after_signature=""
                        local recon_violation_detected=0
                        : > "$recon_violation_file"
                        if [[ "$role_delegation_mode" == "reconnaissance" ]]; then
                          collect_dirty_paths "$repo" "$recon_before_dirty_file"
                          recon_before_signature=$(compute_signature "$repo" ".superloop/**" ".git/**")
                        fi

                        local child_attempt=0
                        local child_max_attempts=$((role_delegation_retry_limit + 1))
                        local child_rc=1
                        while [[ "$child_attempt" -lt "$child_max_attempts" ]]; do
                          child_attempt=$((child_attempt + 1))
                          set +e
                          (
                            run_role \
                              "$repo" \
                              "${role}-child-${wave_id}-${child_id}" \
                              "$child_prompt_file" \
                              "$child_last_message_file" \
                              "$child_log_file" \
                              "$role_delegation_child_timeout_seconds" \
                              "$delegation_runner_prompt_mode" \
                              "$timeout_inactivity" \
                              "$child_usage_file" \
                              "$iteration" \
                              "$delegation_thinking_env" \
                              "${delegation_runner_command[@]}" \
                              -- \
                              "${delegation_runner_active_args[@]}"
                          )
                          child_rc=$?
                          set -e
                          if [[ "$child_rc" -eq 0 ]]; then
                            break
                          fi
                          if [[ "$child_attempt" -lt "$child_max_attempts" ]]; then
                            local child_backoff_seconds
                            child_backoff_seconds=$(compute_delegation_retry_backoff_seconds "$role_delegation_retry_backoff_seconds" "$role_delegation_retry_backoff_max_seconds" "$child_attempt")
                            if [[ "$child_backoff_seconds" -gt 0 ]]; then
                              sleep "$child_backoff_seconds"
                            fi
                          fi
                        done

                        if [[ "$role_delegation_mode" == "reconnaissance" ]]; then
                          collect_dirty_paths "$repo" "$recon_after_dirty_file"
                          recon_after_signature=$(compute_signature "$repo" ".superloop/**" ".git/**")
                          if [[ "$recon_before_signature" != "$recon_after_signature" ]]; then
                            recon_violation_detected=1
                            awk 'NR==FNR { before[$0]=1; next } !($0 in before) { print }' "$recon_before_dirty_file" "$recon_after_dirty_file" > "$recon_violation_file" || true
                            if [[ ! -s "$recon_violation_file" ]]; then
                              printf '%s\n' "__dirty_signature_changed__" > "$recon_violation_file"
                            fi
                          fi
                        fi

                        local child_status_text="failed"
                        if [[ "$child_rc" -eq 0 ]]; then
                          child_status_text="ok"
                        elif [[ "$child_rc" -eq 124 ]]; then
                          child_status_text="timeout"
                        elif [[ "$child_rc" -eq 125 ]]; then
                          child_status_text="rate_limited"
                        fi

                        if [[ "$recon_violation_detected" -eq 1 ]]; then
                          child_rc=97
                          child_status_text="policy_violation"
                          role_delegation_recon_violation_count=$((role_delegation_recon_violation_count + 1))
                          role_delegation_recon_violation_wave_id="$wave_id"
                          role_delegation_recon_violation_child_id="$child_id"

                          local recon_violation_files_json
                          recon_violation_files_json=$(jq -R . < "$recon_violation_file" | jq -s '.')
                          local recon_violation_data
                          recon_violation_data=$(jq -n \
                            --arg role "$role" \
                            --arg wave_id "$wave_id" \
                            --arg child_id "$child_id" \
                            --arg mode "$role_delegation_mode" \
                            --arg failure_policy "$role_delegation_failure_policy" \
                            --argjson changed_files "$recon_violation_files_json" \
                            '{role: $role, wave_id: $wave_id, child_id: $child_id, mode: $mode, failure_policy: $failure_policy, changed_files: $changed_files}')
                          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_recon_violation" "$recon_violation_data" "$role" "error"
                          echo "warning: reconnaissance delegation child '$child_id' for role '$role' produced repo edits" >&2

                          {
                            echo "  recon_violation: true"
                            echo "  recon_changed_files: |"
                            sed 's/^/    /' "$recon_violation_file"
                          } >> "$role_delegation_summary_file"
                        fi

                        local child_terminal_state
                        child_terminal_state=$(normalize_delegation_terminal_state "$child_status_text")

                        jq -n \
                          --arg generated_at "$(timestamp)" \
                          --arg role "$role" \
                          --arg wave_id "$wave_id" \
                          --arg child_id "$child_id" \
                          --arg status "$child_status_text" \
                          --arg terminal_state "$child_terminal_state" \
                          --argjson exit_code "$child_rc" \
                          --argjson attempts "$child_attempt" \
                          --arg prompt_file "${child_prompt_file#$repo/}" \
                          --arg log_file "${child_log_file#$repo/}" \
                          --arg last_message_file "${child_last_message_file#$repo/}" \
                          --arg usage_file "${child_usage_file#$repo/}" \
                          '{
                            generated_at: $generated_at,
                            role: $role,
                            wave_id: $wave_id,
                            child_id: $child_id,
                            status: $status,
                            terminal_state: $terminal_state,
                            exit_code: $exit_code,
                            attempts: $attempts,
                            prompt_file: $prompt_file,
                            log_file: $log_file,
                            last_message_file: $last_message_file,
                            usage_file: $usage_file
                          }' > "$child_status_file"

                        append_usage_records_file "$child_usage_file" "$usage_file"

                        local child_end_data
                        child_end_data=$(jq -n \
                          --arg role "$role" \
                          --arg wave_id "$wave_id" \
                          --arg child_id "$child_id" \
                          --arg status "$child_status_text" \
                          --arg terminal_state "$child_terminal_state" \
                          --argjson exit_code "$child_rc" \
                          --argjson attempts "$child_attempt" \
                          --arg log_file "${child_log_file#$repo/}" \
                          --arg last_message_file "${child_last_message_file#$repo/}" \
                          '{role: $role, wave_id: $wave_id, child_id: $child_id, status: $status, terminal_state: $terminal_state, exit_code: $exit_code, attempts: $attempts, log_file: $log_file, last_message_file: $last_message_file}')
                        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_child_end" "$child_end_data" "$role"

                        {
                          echo "- child: $child_id"
                          echo "  status: $child_status_text"
                          echo "  terminal_state: $child_terminal_state"
                          echo "  attempts: $child_attempt"
                          echo "  exit_code: $child_rc"
                          echo "  log_file: ${child_log_file#$repo/}"
                          echo "  last_message_file: ${child_last_message_file#$repo/}"
                        } >> "$role_delegation_summary_file"
                        if [[ -f "$child_last_message_file" ]]; then
                          {
                            echo "  output_excerpt: |"
                            sed -n '1,12p' "$child_last_message_file" | sed 's/^/    /'
                          } >> "$role_delegation_summary_file"
                        fi
                        echo "" >> "$role_delegation_summary_file"

                        role_delegation_completion_order_json=$(jq -c \
                          --arg wave_id "$wave_id" \
                          --arg child_id "$child_id" \
                          '. + [{wave_id: $wave_id, child_id: $child_id}]' \
                          <<<"$role_delegation_completion_order_json")
                        role_delegation_aggregation_order_json=$(jq -c \
                          --arg wave_id "$wave_id" \
                          --arg child_id "$child_id" \
                          '. + [{wave_id: $wave_id, child_id: $child_id}]' \
                          <<<"$role_delegation_aggregation_order_json")

                        wave_executed_children=$((wave_executed_children + 1))
                        if [[ "$child_rc" -eq 0 ]]; then
                          wave_succeeded_children=$((wave_succeeded_children + 1))
                        else
                          wave_failed_children=$((wave_failed_children + 1))
                          if [[ "$role_delegation_failure_policy" == "fail_role" ]]; then
                            role_delegation_fail_role_triggered=1
                            role_delegation_fail_role_wave_id="$wave_id"
                            role_delegation_fail_role_child_id="$child_id"
                            role_delegation_stop_after_wave=1
                            if [[ "$child_status_text" == "policy_violation" ]]; then
                              role_delegation_stop_reason="recon_violation_fail_role"
                              if [[ -z "$role_delegation_execution_reason" ]]; then
                                role_delegation_execution_reason="recon_violation_fail_role"
                              elif [[ "$role_delegation_execution_reason" != *"recon_violation_fail_role"* ]]; then
                                role_delegation_execution_reason="${role_delegation_execution_reason},recon_violation_fail_role"
                              fi
                            else
                              role_delegation_stop_reason="failure_policy_fail_role"
                              if [[ -z "$role_delegation_execution_reason" ]]; then
                                role_delegation_execution_reason="child_failure_fail_role"
                              elif [[ "$role_delegation_execution_reason" != *"child_failure_fail_role"* ]]; then
                                role_delegation_execution_reason="${role_delegation_execution_reason},child_failure_fail_role"
                              fi
                            fi
                          fi
                          if [[ "$child_status_text" == "policy_violation" && "$role_delegation_failure_policy" != "fail_role" ]]; then
                            if [[ -z "$role_delegation_execution_reason" ]]; then
                              role_delegation_execution_reason="recon_violation_warned"
                            elif [[ "$role_delegation_execution_reason" != *"recon_violation_warned"* ]]; then
                              role_delegation_execution_reason="${role_delegation_execution_reason},recon_violation_warned"
                            fi
                          fi
                        fi

                        case "$child_terminal_state" in
                          completed) wave_terminal_completed=$((wave_terminal_completed + 1)) ;;
                          timed_out) wave_terminal_timed_out=$((wave_terminal_timed_out + 1)) ;;
                          cancelled) wave_terminal_cancelled=$((wave_terminal_cancelled + 1)) ;;
                          policy_violation) wave_terminal_policy_violation=$((wave_terminal_policy_violation + 1)) ;;
                          skipped) wave_terminal_skipped=$((wave_terminal_skipped + 1)) ;;
                          *) wave_terminal_failed=$((wave_terminal_failed + 1)) ;;
                        esac

                        if [[ "$role_delegation_fail_role_triggered" -eq 1 ]]; then
                          break
                        fi

                        if [[ "$role_delegation_effective_dispatch_mode" == "serial" && "$role_delegation_effective_wake_policy" == "on_child_complete" && "$child_number" -lt "$wave_children_to_run" ]]; then
                          local adaptation_skip_reason=""
                          if [[ "$wave_adaptation_attempted" -ge "$role_delegation_adaptation_max_replans_per_wave" ]]; then
                            adaptation_skip_reason="wave_limit_reached"
                          elif [[ "$role_delegation_adaptation_attempted" -ge "$role_delegation_adaptation_max_replans_per_iteration" ]]; then
                            adaptation_skip_reason="iteration_limit_reached"
                          fi

                          if [[ -n "$adaptation_skip_reason" ]]; then
                            role_delegation_adaptation_skipped=$((role_delegation_adaptation_skipped + 1))
                            local adaptation_skip_data
                            adaptation_skip_data=$(jq -n \
                              --arg role "$role" \
                              --arg wave_id "$wave_id" \
                              --arg child_id "$child_id" \
                              --arg reason "$adaptation_skip_reason" \
                              --argjson wave "$wave_number" \
                              --argjson child "$child_number" \
                              --argjson attempted_wave "$wave_adaptation_attempted" \
                              --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                              '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, reason: $reason, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration}')
                            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_skipped" "$adaptation_skip_data" "$role"
                          else
                            role_delegation_adaptation_attempted=$((role_delegation_adaptation_attempted + 1))
                            wave_adaptation_attempted=$((wave_adaptation_attempted + 1))

                            local adaptation_wave_dir="$role_delegation_adaptation_dir/$wave_id"
                            mkdir -p "$adaptation_wave_dir"
                            local adaptation_pass_id="after-child-$child_number"
                            local adaptation_prompt_file="$adaptation_wave_dir/${adaptation_pass_id}.prompt.md"
                            local adaptation_log_file="$adaptation_wave_dir/${adaptation_pass_id}.log"
                            local adaptation_last_message_file="$adaptation_wave_dir/${adaptation_pass_id}.last_message.txt"
                            local adaptation_decision_file="$adaptation_wave_dir/${adaptation_pass_id}.decision.json"
                            local adaptation_usage_file="$adaptation_wave_dir/${adaptation_pass_id}.usage.jsonl"
                            : > "$adaptation_usage_file"

                            {
                              echo "You are adapting delegation after a child completion."
                              echo ""
                              echo "Parent role: $role"
                              echo "Loop: $loop_id"
                              echo "Run: $run_id"
                              echo "Iteration: $iteration"
                              echo "Wave: $wave_id"
                              echo "Completed child: $child_id"
                              echo "Completed child index: $child_number of $wave_children_to_run"
                              echo "Completed child status: $child_status_text"
                              echo "Completed child exit code: $child_rc"
                              echo "Completed child attempts: $child_attempt"
                              echo "Completed child output: ${child_last_message_file#$repo/}"
                              echo ""
                              echo "Write adaptation decision JSON to this exact file path:"
                              echo "$adaptation_decision_file"
                              echo ""
                              echo "JSON shape:"
                              echo "{"
                              echo '  "continue_wave": true,'
                              echo '  "continue_delegation": true,'
                              echo '  "reason": "short rationale"'
                              echo "}"
                              echo ""
                              echo "Rules:"
                              echo "- Set continue_wave=false to stop remaining children in this wave."
                              echo "- Set continue_delegation=false to stop all remaining waves."
                              echo "- Keep both true if no replanning is needed."
                              echo "- Do not modify code or canonical role reports in this pass."
                            } > "$adaptation_prompt_file"

                            local adaptation_start_data
                            adaptation_start_data=$(jq -n \
                              --arg role "$role" \
                              --arg wave_id "$wave_id" \
                              --arg child_id "$child_id" \
                              --arg prompt_file "${adaptation_prompt_file#$repo/}" \
                              --arg decision_file "${adaptation_decision_file#$repo/}" \
                              --argjson wave "$wave_number" \
                              --argjson child "$child_number" \
                              --argjson attempted_wave "$wave_adaptation_attempted" \
                              --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                              --argjson max_replans_per_wave "$role_delegation_adaptation_max_replans_per_wave" \
                              --argjson max_replans_per_iteration "$role_delegation_adaptation_max_replans_per_iteration" \
                              '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, prompt_file: $prompt_file, decision_file: $decision_file, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration, max_replans_per_wave: $max_replans_per_wave, max_replans_per_iteration: $max_replans_per_iteration}')
                            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_start" "$adaptation_start_data" "$role"

                            local adaptation_rc=0
                            set +e
                            (
                              run_role \
                                "$repo" \
                                "${role}-adapt-${wave_id}-${child_id}-${wave_adaptation_attempted}" \
                                "$adaptation_prompt_file" \
                                "$adaptation_last_message_file" \
                                "$adaptation_log_file" \
                                "$role_delegation_child_timeout_seconds" \
                                "$delegation_runner_prompt_mode" \
                                "$timeout_inactivity" \
                                "$adaptation_usage_file" \
                                "$iteration" \
                                "$delegation_thinking_env" \
                                "${delegation_runner_command[@]}" \
                                -- \
                                "${delegation_runner_active_args[@]}"
                            )
                            adaptation_rc=$?
                            set -e

                            append_usage_records_file "$adaptation_usage_file" "$usage_file"

                            if [[ ! -f "$adaptation_decision_file" && -f "$adaptation_last_message_file" ]]; then
                              local extracted_adaptation_json=""
                              extracted_adaptation_json=$(sed -n '/```json/,/```/p' "$adaptation_last_message_file" | sed '1d;$d')
                              if [[ -z "$extracted_adaptation_json" ]]; then
                                extracted_adaptation_json=$(sed -n '/^{/,$p' "$adaptation_last_message_file")
                              fi
                              if [[ -n "$extracted_adaptation_json" ]] && jq -e '.' >/dev/null 2>&1 <<<"$extracted_adaptation_json"; then
                                printf '%s\n' "$extracted_adaptation_json" > "$adaptation_decision_file"
                              fi
                            fi

                            local adaptation_status="failed"
                            local adaptation_decision_continue_wave="true"
                            local adaptation_decision_continue_delegation="true"
                            local adaptation_decision_reason=""
                            if [[ -f "$adaptation_decision_file" ]] && jq -e '.' "$adaptation_decision_file" >/dev/null 2>&1; then
                              adaptation_status="ok"
                              adaptation_decision_continue_wave=$(jq -r '
                                if (.continue_wave | type) == "boolean" then (.continue_wave | tostring)
                                elif (.continue | type) == "boolean" then (.continue | tostring)
                                elif (.stop_wave | type) == "boolean" then (if .stop_wave then "false" else "true" end)
                                else "true"
                                end' "$adaptation_decision_file" 2>/dev/null || echo "true")
                              adaptation_decision_continue_delegation=$(jq -r '
                                if (.continue_delegation | type) == "boolean" then (.continue_delegation | tostring)
                                elif (.continue_iteration | type) == "boolean" then (.continue_iteration | tostring)
                                elif (.stop_delegation | type) == "boolean" then (if .stop_delegation then "false" else "true" end)
                                else "true"
                                end' "$adaptation_decision_file" 2>/dev/null || echo "true")
                              adaptation_decision_reason=$(jq -r '.reason // .rationale // .note // empty' "$adaptation_decision_file" 2>/dev/null || echo "")
                            elif [[ "$adaptation_rc" -eq 0 ]]; then
                              adaptation_status="no_decision"
                            fi

                            if [[ "$adaptation_decision_continue_wave" != "true" && "$adaptation_decision_continue_wave" != "false" ]]; then
                              adaptation_decision_continue_wave="true"
                            fi
                            if [[ "$adaptation_decision_continue_delegation" != "true" && "$adaptation_decision_continue_delegation" != "false" ]]; then
                              adaptation_decision_continue_delegation="true"
                            fi

                            local adaptation_applied="false"
                            if [[ "$adaptation_status" == "ok" && ( "$adaptation_decision_continue_wave" == "false" || "$adaptation_decision_continue_delegation" == "false" ) ]]; then
                              adaptation_applied="true"
                              role_delegation_adaptation_applied=$((role_delegation_adaptation_applied + 1))
                              wave_adaptation_stopped=1
                            fi

                            local adaptation_end_data
                            adaptation_end_data=$(jq -n \
                              --arg role "$role" \
                              --arg wave_id "$wave_id" \
                              --arg child_id "$child_id" \
                              --arg status "$adaptation_status" \
                              --arg continue_wave "$adaptation_decision_continue_wave" \
                              --arg continue_delegation "$adaptation_decision_continue_delegation" \
                              --arg reason "$adaptation_decision_reason" \
                              --arg decision_file "${adaptation_decision_file#$repo/}" \
                              --arg last_message_file "${adaptation_last_message_file#$repo/}" \
                              --argjson exit_code "$adaptation_rc" \
                              --argjson wave "$wave_number" \
                              --argjson child "$child_number" \
                              --argjson attempted_wave "$wave_adaptation_attempted" \
                              --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                              --argjson applied "$(if [[ "$adaptation_applied" == "true" ]]; then echo true; else echo false; fi)" \
                              '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, status: $status, continue_wave: $continue_wave, continue_delegation: $continue_delegation, reason: (if ($reason | length) > 0 then $reason else null end), decision_file: $decision_file, last_message_file: $last_message_file, exit_code: $exit_code, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration, applied: $applied} | with_entries(select(.value != null))')
                            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_end" "$adaptation_end_data" "$role"

                            {
                              echo "- adaptation after child: $child_id"
                              echo "  status: $adaptation_status"
                              echo "  continue_wave: $adaptation_decision_continue_wave"
                              echo "  continue_delegation: $adaptation_decision_continue_delegation"
                              echo "  decision_file: ${adaptation_decision_file#$repo/}"
                              echo "  output_file: ${adaptation_last_message_file#$repo/}"
                              if [[ -n "$adaptation_decision_reason" ]]; then
                                echo "  reason: $adaptation_decision_reason"
                              fi
                            } >> "$role_delegation_summary_file"
                            echo "" >> "$role_delegation_summary_file"

                            if [[ "$adaptation_decision_continue_delegation" == "false" ]]; then
                              role_delegation_stop_after_wave=1
                              role_delegation_stop_reason="adaptation_decision"
                            fi
                            if [[ "$adaptation_decision_continue_wave" == "false" || "$adaptation_decision_continue_delegation" == "false" ]]; then
                              if [[ -z "$role_delegation_execution_reason" ]]; then
                                role_delegation_execution_reason="adapted_after_child"
                              elif [[ "$role_delegation_execution_reason" != *"adapted_after_child"* ]]; then
                                role_delegation_execution_reason="${role_delegation_execution_reason},adapted_after_child"
                              fi
                              break
                            fi
                          fi
                        fi
                      done

                      if [[ "$role_delegation_effective_dispatch_mode" == "parallel" ]]; then
                        while [[ "$wave_parallel_active_workers" -gt 0 ]]; do
                          local wave_reaped_any=0
                          local scan_index
                          for scan_index in "${!wave_parallel_pids[@]}"; do
                            if [[ "${wave_parallel_reaped[$scan_index]}" == "1" ]]; then
                              continue
                            fi
                            local scan_pid="${wave_parallel_pids[$scan_index]}"
                            if ! kill -0 "$scan_pid" 2>/dev/null; then
                              set +e
                              wait "$scan_pid" >/dev/null 2>&1
                              set -e
                              wave_parallel_reaped[$scan_index]="1"
                              if [[ "$wave_parallel_active_workers" -gt 0 ]]; then
                                wave_parallel_active_workers=$((wave_parallel_active_workers - 1))
                              fi
                              role_delegation_completion_order_json=$(jq -c \
                                --arg wave_id "$wave_id" \
                                --arg child_id "${wave_parallel_child_ids[$scan_index]}" \
                                '. + [{wave_id: $wave_id, child_id: $child_id}]' \
                                <<<"$role_delegation_completion_order_json")
                              local wave_queue_data
                              wave_queue_data=$(jq -n \
                                --arg role "$role" \
                                --arg wave_id "$wave_id" \
                                --arg phase "final_drain" \
                                --argjson wave "$wave_number" \
                                --argjson active_workers "$wave_parallel_active_workers" \
                                --argjson launched_children "$wave_parallel_launched_workers" \
                                --argjson total_children "$wave_children_to_run" \
                                --argjson concurrency_cap "$wave_concurrency_cap" \
                                '{role: $role, wave_id: $wave_id, wave: $wave, phase: $phase, active_workers: $active_workers, launched_children: $launched_children, total_children: $total_children, concurrency_cap: $concurrency_cap}')
                              log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_wave_queue_drain" "$wave_queue_data" "$role"

                              if [[ "$role_delegation_effective_wake_policy" == "on_child_complete" && "$role_delegation_adaptation_status" == "enabled" && "$role_delegation_stop_after_wave" -eq 0 ]]; then
                                local completed_child_id="${wave_parallel_child_ids[$scan_index]}"
                                local completed_child_number="${wave_parallel_child_numbers[$scan_index]}"
                                local completed_child_status_file="${wave_parallel_child_status_files[$scan_index]}"
                                local completed_child_last_message_file="${wave_parallel_child_last_files[$scan_index]}"
                                local completed_child_log_file="${wave_parallel_child_log_files[$scan_index]}"
                                local completed_child_usage_file="${wave_parallel_child_usage_files[$scan_index]}"

                                if [[ ! -f "$completed_child_status_file" ]]; then
                                  jq -n \
                                    --arg generated_at "$(timestamp)" \
                                    --arg role "$role" \
                                    --arg wave_id "$wave_id" \
                                    --arg child_id "$completed_child_id" \
                                    --arg status "failed" \
                                    --arg terminal_state "failed" \
                                    --argjson exit_code 1 \
                                    --argjson attempts 0 \
                                    --arg prompt_file "" \
                                    --arg log_file "${completed_child_log_file#$repo/}" \
                                    --arg last_message_file "${completed_child_last_message_file#$repo/}" \
                                    --arg usage_file "${completed_child_usage_file#$repo/}" \
                                    '{
                                      generated_at: $generated_at,
                                      role: $role,
                                      wave_id: $wave_id,
                                      child_id: $child_id,
                                      status: $status,
                                      terminal_state: $terminal_state,
                                      exit_code: $exit_code,
                                      attempts: $attempts,
                                      prompt_file: (if ($prompt_file | length) > 0 then $prompt_file else null end),
                                      log_file: $log_file,
                                      last_message_file: $last_message_file,
                                      usage_file: $usage_file
                                    } | with_entries(select(.value != null))' > "$completed_child_status_file"
                                fi

                                local completed_child_status_text completed_child_rc completed_child_attempts
                                completed_child_status_text=$(jq -r '.status // "failed"' "$completed_child_status_file" 2>/dev/null || echo "failed")
                                completed_child_rc=$(jq -r '.exit_code // 1' "$completed_child_status_file" 2>/dev/null || echo "1")
                                completed_child_attempts=$(jq -r '.attempts // 0' "$completed_child_status_file" 2>/dev/null || echo "0")
                                completed_child_rc=$(rlms_safe_int "$completed_child_rc" 1)
                                completed_child_attempts=$(rlms_safe_int "$completed_child_attempts" 0)

                                local remaining_unlaunched=$((wave_children_to_run - wave_parallel_launched_workers))
                                if [[ "$remaining_unlaunched" -lt 0 ]]; then
                                  remaining_unlaunched=0
                                fi
                                local remaining_after_completion=$((remaining_unlaunched + wave_parallel_active_workers))
                                if [[ "$remaining_after_completion" -gt 0 ]]; then
                                  local adaptation_skip_reason=""
                                  if [[ "$wave_adaptation_attempted" -ge "$role_delegation_adaptation_max_replans_per_wave" ]]; then
                                    adaptation_skip_reason="wave_limit_reached"
                                  elif [[ "$role_delegation_adaptation_attempted" -ge "$role_delegation_adaptation_max_replans_per_iteration" ]]; then
                                    adaptation_skip_reason="iteration_limit_reached"
                                  fi

                                  if [[ -n "$adaptation_skip_reason" ]]; then
                                    role_delegation_adaptation_skipped=$((role_delegation_adaptation_skipped + 1))
                                    local adaptation_skip_data
                                    adaptation_skip_data=$(jq -n \
                                      --arg role "$role" \
                                      --arg wave_id "$wave_id" \
                                      --arg child_id "$completed_child_id" \
                                      --arg reason "$adaptation_skip_reason" \
                                      --argjson wave "$wave_number" \
                                      --argjson child "$completed_child_number" \
                                      --argjson attempted_wave "$wave_adaptation_attempted" \
                                      --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                                      '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, reason: $reason, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration}')
                                    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_skipped" "$adaptation_skip_data" "$role"
                                  else
                                    role_delegation_adaptation_attempted=$((role_delegation_adaptation_attempted + 1))
                                    wave_adaptation_attempted=$((wave_adaptation_attempted + 1))

                                    local adaptation_wave_dir="$role_delegation_adaptation_dir/$wave_id"
                                    mkdir -p "$adaptation_wave_dir"
                                    local adaptation_pass_id="after-child-$completed_child_number"
                                    local adaptation_prompt_file="$adaptation_wave_dir/${adaptation_pass_id}.prompt.md"
                                    local adaptation_log_file="$adaptation_wave_dir/${adaptation_pass_id}.log"
                                    local adaptation_last_message_file="$adaptation_wave_dir/${adaptation_pass_id}.last_message.txt"
                                    local adaptation_decision_file="$adaptation_wave_dir/${adaptation_pass_id}.decision.json"
                                    local adaptation_usage_file="$adaptation_wave_dir/${adaptation_pass_id}.usage.jsonl"
                                    : > "$adaptation_usage_file"

                                    {
                                      echo "You are adapting delegation after a child completion."
                                      echo ""
                                      echo "Parent role: $role"
                                      echo "Loop: $loop_id"
                                      echo "Run: $run_id"
                                      echo "Iteration: $iteration"
                                      echo "Wave: $wave_id"
                                      echo "Completed child: $completed_child_id"
                                      echo "Completed child index: $completed_child_number of $wave_children_to_run"
                                      echo "Completed child status: $completed_child_status_text"
                                      echo "Completed child exit code: $completed_child_rc"
                                      echo "Completed child attempts: $completed_child_attempts"
                                      echo "Completed child output: ${completed_child_last_message_file#$repo/}"
                                      echo ""
                                      echo "Write adaptation decision JSON to this exact file path:"
                                      echo "$adaptation_decision_file"
                                      echo ""
                                      echo "JSON shape:"
                                      echo "{"
                                      echo '  "continue_wave": true,'
                                      echo '  "continue_delegation": true,'
                                      echo '  "reason": "short rationale"'
                                      echo "}"
                                      echo ""
                                      echo "Rules:"
                                      echo "- Set continue_wave=false to stop remaining children in this wave."
                                      echo "- Set continue_delegation=false to stop all remaining waves."
                                      echo "- Keep both true if no replanning is needed."
                                      echo "- Do not modify code or canonical role reports in this pass."
                                    } > "$adaptation_prompt_file"

                                    local adaptation_start_data
                                    adaptation_start_data=$(jq -n \
                                      --arg role "$role" \
                                      --arg wave_id "$wave_id" \
                                      --arg child_id "$completed_child_id" \
                                      --arg prompt_file "${adaptation_prompt_file#$repo/}" \
                                      --arg decision_file "${adaptation_decision_file#$repo/}" \
                                      --argjson wave "$wave_number" \
                                      --argjson child "$completed_child_number" \
                                      --argjson attempted_wave "$wave_adaptation_attempted" \
                                      --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                                      --argjson max_replans_per_wave "$role_delegation_adaptation_max_replans_per_wave" \
                                      --argjson max_replans_per_iteration "$role_delegation_adaptation_max_replans_per_iteration" \
                                      '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, prompt_file: $prompt_file, decision_file: $decision_file, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration, max_replans_per_wave: $max_replans_per_wave, max_replans_per_iteration: $max_replans_per_iteration}')
                                    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_start" "$adaptation_start_data" "$role"

                                    local adaptation_rc=0
                                    set +e
                                    (
                                      run_role \
                                        "$repo" \
                                        "${role}-adapt-${wave_id}-${completed_child_id}-${wave_adaptation_attempted}" \
                                        "$adaptation_prompt_file" \
                                        "$adaptation_last_message_file" \
                                        "$adaptation_log_file" \
                                        "$role_delegation_child_timeout_seconds" \
                                        "$delegation_runner_prompt_mode" \
                                        "$timeout_inactivity" \
                                        "$adaptation_usage_file" \
                                        "$iteration" \
                                        "$delegation_thinking_env" \
                                        "${delegation_runner_command[@]}" \
                                        -- \
                                        "${delegation_runner_active_args[@]}"
                                    )
                                    adaptation_rc=$?
                                    set -e

                                    append_usage_records_file "$adaptation_usage_file" "$usage_file"

                                    if [[ ! -f "$adaptation_decision_file" && -f "$adaptation_last_message_file" ]]; then
                                      local extracted_adaptation_json=""
                                      extracted_adaptation_json=$(sed -n '/```json/,/```/p' "$adaptation_last_message_file" | sed '1d;$d')
                                      if [[ -z "$extracted_adaptation_json" ]]; then
                                        extracted_adaptation_json=$(sed -n '/^{/,$p' "$adaptation_last_message_file")
                                      fi
                                      if [[ -n "$extracted_adaptation_json" ]] && jq -e '.' >/dev/null 2>&1 <<<"$extracted_adaptation_json"; then
                                        printf '%s\n' "$extracted_adaptation_json" > "$adaptation_decision_file"
                                      fi
                                    fi

                                    local adaptation_status="failed"
                                    local adaptation_decision_continue_wave="true"
                                    local adaptation_decision_continue_delegation="true"
                                    local adaptation_decision_reason=""
                                    if [[ -f "$adaptation_decision_file" ]] && jq -e '.' "$adaptation_decision_file" >/dev/null 2>&1; then
                                      adaptation_status="ok"
                                      adaptation_decision_continue_wave=$(jq -r '
                                        if (.continue_wave | type) == "boolean" then (.continue_wave | tostring)
                                        elif (.continue | type) == "boolean" then (.continue | tostring)
                                        elif (.stop_wave | type) == "boolean" then (if .stop_wave then "false" else "true" end)
                                        else "true"
                                        end' "$adaptation_decision_file" 2>/dev/null || echo "true")
                                      adaptation_decision_continue_delegation=$(jq -r '
                                        if (.continue_delegation | type) == "boolean" then (.continue_delegation | tostring)
                                        elif (.continue_iteration | type) == "boolean" then (.continue_iteration | tostring)
                                        elif (.stop_delegation | type) == "boolean" then (if .stop_delegation then "false" else "true" end)
                                        else "true"
                                        end' "$adaptation_decision_file" 2>/dev/null || echo "true")
                                      adaptation_decision_reason=$(jq -r '.reason // .rationale // .note // empty' "$adaptation_decision_file" 2>/dev/null || echo "")
                                    elif [[ "$adaptation_rc" -eq 0 ]]; then
                                      adaptation_status="no_decision"
                                    fi

                                    if [[ "$adaptation_decision_continue_wave" != "true" && "$adaptation_decision_continue_wave" != "false" ]]; then
                                      adaptation_decision_continue_wave="true"
                                    fi
                                    if [[ "$adaptation_decision_continue_delegation" != "true" && "$adaptation_decision_continue_delegation" != "false" ]]; then
                                      adaptation_decision_continue_delegation="true"
                                    fi

                                    local adaptation_applied="false"
                                    if [[ "$adaptation_status" == "ok" && ( "$adaptation_decision_continue_wave" == "false" || "$adaptation_decision_continue_delegation" == "false" ) ]]; then
                                      adaptation_applied="true"
                                      role_delegation_adaptation_applied=$((role_delegation_adaptation_applied + 1))
                                      wave_adaptation_stopped=1
                                    fi

                                    local adaptation_end_data
                                    adaptation_end_data=$(jq -n \
                                      --arg role "$role" \
                                      --arg wave_id "$wave_id" \
                                      --arg child_id "$completed_child_id" \
                                      --arg status "$adaptation_status" \
                                      --arg continue_wave "$adaptation_decision_continue_wave" \
                                      --arg continue_delegation "$adaptation_decision_continue_delegation" \
                                      --arg reason "$adaptation_decision_reason" \
                                      --arg decision_file "${adaptation_decision_file#$repo/}" \
                                      --arg last_message_file "${adaptation_last_message_file#$repo/}" \
                                      --argjson exit_code "$adaptation_rc" \
                                      --argjson wave "$wave_number" \
                                      --argjson child "$completed_child_number" \
                                      --argjson attempted_wave "$wave_adaptation_attempted" \
                                      --argjson attempted_iteration "$role_delegation_adaptation_attempted" \
                                      --argjson applied "$(if [[ "$adaptation_applied" == "true" ]]; then echo true; else echo false; fi)" \
                                      '{role: $role, wave_id: $wave_id, child_id: $child_id, wave: $wave, child: $child, status: $status, continue_wave: $continue_wave, continue_delegation: $continue_delegation, reason: (if ($reason | length) > 0 then $reason else null end), decision_file: $decision_file, last_message_file: $last_message_file, exit_code: $exit_code, attempted_wave: $attempted_wave, attempted_iteration: $attempted_iteration, applied: $applied} | with_entries(select(.value != null))')
                                    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_adaptation_end" "$adaptation_end_data" "$role"

                                    {
                                      echo "- adaptation after child: $completed_child_id"
                                      echo "  status: $adaptation_status"
                                      echo "  continue_wave: $adaptation_decision_continue_wave"
                                      echo "  continue_delegation: $adaptation_decision_continue_delegation"
                                      echo "  decision_file: ${adaptation_decision_file#$repo/}"
                                      echo "  output_file: ${adaptation_last_message_file#$repo/}"
                                      if [[ -n "$adaptation_decision_reason" ]]; then
                                        echo "  reason: $adaptation_decision_reason"
                                      fi
                                    } >> "$role_delegation_summary_file"
                                    echo "" >> "$role_delegation_summary_file"

                                    if [[ "$adaptation_decision_continue_delegation" == "false" ]]; then
                                      role_delegation_stop_after_wave=1
                                      role_delegation_stop_reason="adaptation_decision"
                                    fi
                                    if [[ "$adaptation_decision_continue_wave" == "false" || "$adaptation_decision_continue_delegation" == "false" ]]; then
                                      if [[ -z "$role_delegation_execution_reason" ]]; then
                                        role_delegation_execution_reason="adapted_after_child"
                                      elif [[ "$role_delegation_execution_reason" != *"adapted_after_child"* ]]; then
                                        role_delegation_execution_reason="${role_delegation_execution_reason},adapted_after_child"
                                      fi
                                      wave_stop_launch=1
                                    fi
                                  fi
                                fi
                              fi
                              wave_reaped_any=1
                            fi
                          done
                          if [[ "$wave_reaped_any" -eq 0 ]]; then
                            sleep 0.05
                          fi
                        done

                        local parallel_index
                        for parallel_index in "${!wave_parallel_pids[@]}"; do
                          local final_child_id="${wave_parallel_child_ids[$parallel_index]}"
                          local final_child_status_file="${wave_parallel_child_status_files[$parallel_index]}"
                          local final_child_log_file="${wave_parallel_child_log_files[$parallel_index]}"
                          local final_child_last_message_file="${wave_parallel_child_last_files[$parallel_index]}"
                          local final_child_usage_file="${wave_parallel_child_usage_files[$parallel_index]}"

                          if [[ ! -f "$final_child_status_file" ]]; then
                            jq -n \
                              --arg generated_at "$(timestamp)" \
                              --arg role "$role" \
                              --arg wave_id "$wave_id" \
                              --arg child_id "$final_child_id" \
                              --arg status "failed" \
                              --arg terminal_state "failed" \
                              --argjson exit_code 1 \
                              --argjson attempts 0 \
                              --arg prompt_file "" \
                              --arg log_file "${final_child_log_file#$repo/}" \
                              --arg last_message_file "${final_child_last_message_file#$repo/}" \
                              --arg usage_file "${final_child_usage_file#$repo/}" \
                              '{
                                generated_at: $generated_at,
                                role: $role,
                                wave_id: $wave_id,
                                child_id: $child_id,
                                status: $status,
                                terminal_state: $terminal_state,
                                exit_code: $exit_code,
                                attempts: $attempts,
                                prompt_file: (if ($prompt_file | length) > 0 then $prompt_file else null end),
                                log_file: $log_file,
                                last_message_file: $last_message_file,
                                usage_file: $usage_file
                              } | with_entries(select(.value != null))' > "$final_child_status_file"
                          fi

                          local final_child_status_text final_child_rc final_child_attempts
                          final_child_status_text=$(jq -r '.status // "failed"' "$final_child_status_file" 2>/dev/null || echo "failed")
                          local final_child_terminal_state
                          final_child_terminal_state=$(jq -r '.terminal_state // empty' "$final_child_status_file" 2>/dev/null || echo "")
                          if [[ -z "$final_child_terminal_state" || "$final_child_terminal_state" == "null" ]]; then
                            final_child_terminal_state=$(normalize_delegation_terminal_state "$final_child_status_text")
                          fi
                          final_child_rc=$(jq -r '.exit_code // 1' "$final_child_status_file" 2>/dev/null || echo "1")
                          final_child_attempts=$(jq -r '.attempts // 0' "$final_child_status_file" 2>/dev/null || echo "0")
                          final_child_rc=$(rlms_safe_int "$final_child_rc" 1)
                          final_child_attempts=$(rlms_safe_int "$final_child_attempts" 0)

                          local final_child_end_data
                          final_child_end_data=$(jq -n \
                            --arg role "$role" \
                            --arg wave_id "$wave_id" \
                            --arg child_id "$final_child_id" \
                            --arg status "$final_child_status_text" \
                            --arg terminal_state "$final_child_terminal_state" \
                            --argjson exit_code "$final_child_rc" \
                            --argjson attempts "$final_child_attempts" \
                            --arg log_file "${final_child_log_file#$repo/}" \
                            --arg last_message_file "${final_child_last_message_file#$repo/}" \
                            '{role: $role, wave_id: $wave_id, child_id: $child_id, status: $status, terminal_state: $terminal_state, exit_code: $exit_code, attempts: $attempts, log_file: $log_file, last_message_file: $last_message_file}')
                          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_child_end" "$final_child_end_data" "$role"

                          {
                            echo "- child: $final_child_id"
                            echo "  status: $final_child_status_text"
                            echo "  terminal_state: $final_child_terminal_state"
                            echo "  attempts: $final_child_attempts"
                            echo "  exit_code: $final_child_rc"
                            echo "  log_file: ${final_child_log_file#$repo/}"
                            echo "  last_message_file: ${final_child_last_message_file#$repo/}"
                          } >> "$role_delegation_summary_file"
                          if [[ -f "$final_child_last_message_file" ]]; then
                            {
                              echo "  output_excerpt: |"
                              sed -n '1,12p' "$final_child_last_message_file" | sed 's/^/    /'
                            } >> "$role_delegation_summary_file"
                          fi
                          echo "" >> "$role_delegation_summary_file"

                          role_delegation_aggregation_order_json=$(jq -c \
                            --arg wave_id "$wave_id" \
                            --arg child_id "$final_child_id" \
                            '. + [{wave_id: $wave_id, child_id: $child_id}]' \
                            <<<"$role_delegation_aggregation_order_json")

                          append_usage_records_file "$final_child_usage_file" "$usage_file"

                          wave_executed_children=$((wave_executed_children + 1))
                          if [[ "$final_child_rc" -eq 0 ]]; then
                            wave_succeeded_children=$((wave_succeeded_children + 1))
                          else
                            wave_failed_children=$((wave_failed_children + 1))
                            if [[ "$role_delegation_failure_policy" == "fail_role" && "$role_delegation_fail_role_triggered" -eq 0 ]]; then
                              role_delegation_fail_role_triggered=1
                              role_delegation_fail_role_wave_id="$wave_id"
                              role_delegation_fail_role_child_id="$final_child_id"
                              role_delegation_stop_after_wave=1
                              role_delegation_stop_reason="failure_policy_fail_role"
                              if [[ -z "$role_delegation_execution_reason" ]]; then
                                role_delegation_execution_reason="child_failure_fail_role"
                              elif [[ "$role_delegation_execution_reason" != *"child_failure_fail_role"* ]]; then
                                role_delegation_execution_reason="${role_delegation_execution_reason},child_failure_fail_role"
                              fi
                            fi
                          fi

                          case "$final_child_terminal_state" in
                            completed) wave_terminal_completed=$((wave_terminal_completed + 1)) ;;
                            timed_out) wave_terminal_timed_out=$((wave_terminal_timed_out + 1)) ;;
                            cancelled) wave_terminal_cancelled=$((wave_terminal_cancelled + 1)) ;;
                            policy_violation) wave_terminal_policy_violation=$((wave_terminal_policy_violation + 1)) ;;
                            skipped) wave_terminal_skipped=$((wave_terminal_skipped + 1)) ;;
                            *) wave_terminal_failed=$((wave_terminal_failed + 1)) ;;
                          esac
                        done
                      fi
                    fi

                    local wave_status_text="ok"
                    if [[ "$wave_executed_children" -eq 0 ]]; then
                      wave_status_text="skipped"
                    elif [[ "$wave_failed_children" -gt 0 && "$wave_succeeded_children" -eq 0 ]]; then
                      wave_status_text="failed"
                    elif [[ "$wave_failed_children" -gt 0 || "$wave_adaptation_stopped" -eq 1 ]]; then
                      wave_status_text="partial"
                    fi

                    role_delegation_executed_waves=$((role_delegation_executed_waves + 1))
                    role_delegation_executed_children=$((role_delegation_executed_children + wave_executed_children))
                    role_delegation_succeeded_children=$((role_delegation_succeeded_children + wave_succeeded_children))
                    role_delegation_failed_children=$((role_delegation_failed_children + wave_failed_children))
                    local wave_skipped_due_unfinished=0
                    if [[ "$wave_children_to_run" -gt "$wave_executed_children" ]]; then
                      wave_skipped_due_unfinished=$((wave_children_to_run - wave_executed_children))
                    fi
                    local wave_skipped_due_limits=0
                    if [[ "$wave_requested_children" -gt "$wave_children_to_run" ]]; then
                      wave_skipped_due_limits=$((wave_requested_children - wave_children_to_run))
                    fi
                    wave_terminal_skipped=$((wave_terminal_skipped + wave_skipped_due_unfinished + wave_skipped_due_limits))
                    role_delegation_skipped_children=$((role_delegation_skipped_children + wave_terminal_skipped))
                    role_delegation_terminal_completed=$((role_delegation_terminal_completed + wave_terminal_completed))
                    role_delegation_terminal_failed=$((role_delegation_terminal_failed + wave_terminal_failed))
                    role_delegation_terminal_timed_out=$((role_delegation_terminal_timed_out + wave_terminal_timed_out))
                    role_delegation_terminal_cancelled=$((role_delegation_terminal_cancelled + wave_terminal_cancelled))
                    role_delegation_terminal_policy_violation=$((role_delegation_terminal_policy_violation + wave_terminal_policy_violation))
                    role_delegation_terminal_skipped=$((role_delegation_terminal_skipped + wave_terminal_skipped))

                    {
                      echo "## $wave_id"
                      echo "- requested children: $wave_requested_children"
                      echo "- executed children: $wave_executed_children"
                      echo "- succeeded children: $wave_succeeded_children"
                      echo "- failed children: $wave_failed_children"
                      echo "- terminal completed: $wave_terminal_completed"
                      echo "- terminal failed: $wave_terminal_failed"
                      echo "- terminal timed_out: $wave_terminal_timed_out"
                      echo "- terminal cancelled: $wave_terminal_cancelled"
                      echo "- terminal policy_violation: $wave_terminal_policy_violation"
                      echo "- terminal skipped: $wave_terminal_skipped"
                      echo "- adaptation replans (wave): $wave_adaptation_attempted"
                      if [[ "$wave_adaptation_stopped" -eq 1 ]]; then
                        echo "- adaptation stopped remaining children: true"
                      fi
                      echo "- status: $wave_status_text"
                      echo ""
                    } >> "$role_delegation_summary_file"

                    local delegation_wave_end_data
                    delegation_wave_end_data=$(jq -n \
                      --arg role "$role" \
                      --arg wave_id "$wave_id" \
                      --arg status "$wave_status_text" \
                      --argjson wave "$wave_number" \
                      --argjson requested_children "$wave_requested_children" \
                      --argjson children_completed "$wave_executed_children" \
                      --argjson children_succeeded "$wave_succeeded_children" \
                      --argjson children_failed "$wave_failed_children" \
                      --argjson concurrency_cap "$wave_concurrency_cap" \
                      --argjson terminal_completed "$wave_terminal_completed" \
                      --argjson terminal_failed "$wave_terminal_failed" \
                      --argjson terminal_timed_out "$wave_terminal_timed_out" \
                      --argjson terminal_cancelled "$wave_terminal_cancelled" \
                      --argjson terminal_policy_violation "$wave_terminal_policy_violation" \
                      --argjson terminal_skipped "$wave_terminal_skipped" \
                      --argjson adaptation_replans "$wave_adaptation_attempted" \
                      --argjson adaptation_stopped "$(if [[ "$wave_adaptation_stopped" -eq 1 ]]; then echo true; else echo false; fi)" \
                      '{role: $role, wave_id: $wave_id, wave: $wave, status: $status, requested_children: $requested_children, children_completed: $children_completed, children_succeeded: $children_succeeded, children_failed: $children_failed, concurrency_cap: $concurrency_cap, terminal_state_counts: {completed: $terminal_completed, failed: $terminal_failed, timed_out: $terminal_timed_out, cancelled: $terminal_cancelled, policy_violation: $terminal_policy_violation, skipped: $terminal_skipped}, adaptation_replans: $adaptation_replans, adaptation_stopped: $adaptation_stopped}')
                    log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_wave_end" "$delegation_wave_end_data" "$role"

                    if [[ "$role_delegation_stop_after_wave" -eq 1 ]]; then
                      local delegation_policy_data
                      delegation_policy_data=$(jq -n \
                        --arg role "$role" \
                        --arg wave_id "$wave_id" \
                        --arg reason "$role_delegation_stop_reason" \
                        --argjson wave "$wave_number" \
                        --argjson fail_role_triggered "$(if [[ "$role_delegation_fail_role_triggered" -eq 1 ]]; then echo true; else echo false; fi)" \
                        '{role: $role, wave_id: $wave_id, wave: $wave, reason: (if ($reason | length) > 0 then $reason else "unspecified" end), fail_role_triggered: $fail_role_triggered}')
                      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_policy_decision" "$delegation_policy_data" "$role"

                      if [[ "$role_delegation_stop_reason" == "failure_policy_fail_role" ]]; then
                        echo "- delegation stopped early by failure policy at wave: $wave_id" >> "$role_delegation_summary_file"
                      else
                        echo "- delegation stopped early by adaptation decision at wave: $wave_id" >> "$role_delegation_summary_file"
                      fi
                      echo "" >> "$role_delegation_summary_file"
                      break
                    fi
                  done

                  if [[ "$role_delegation_executed_children" -eq 0 ]]; then
                    role_delegation_status_text="executed_no_children"
                  elif [[ "$role_delegation_failed_children" -eq 0 ]]; then
                    role_delegation_status_text="executed_ok"
                  elif [[ "$role_delegation_succeeded_children" -eq 0 ]]; then
                    role_delegation_status_text="executed_failed"
                  else
                    role_delegation_status_text="executed_partial"
                  fi
                fi
              fi
            fi
          else
            role_delegation_status_text="disabled"
          fi

          local role_delegation_policy_reason="$role_delegation_stop_reason"
          if [[ -z "$role_delegation_policy_reason" ]]; then
            if [[ "$role_delegation_status_text" == "executed_no_children" ]]; then
              role_delegation_policy_reason="no_children_executed"
            elif [[ "$role_delegation_status_text" == "disabled" ]]; then
              role_delegation_policy_reason="delegation_disabled"
            else
              role_delegation_policy_reason="completed"
            fi
          fi

          jq -n \
            --arg generated_at "$(timestamp)" \
            --arg loop_id "$loop_id" \
            --arg run_id "$run_id" \
            --arg role "$role" \
            --arg mode "$role_delegation_mode" \
            --arg dispatch_mode "$role_delegation_dispatch_mode" \
            --arg dispatch_mode_effective "$role_delegation_effective_dispatch_mode" \
            --arg wake_policy "$role_delegation_wake_policy" \
            --arg wake_policy_effective "$role_delegation_effective_wake_policy" \
            --arg failure_policy "$role_delegation_failure_policy" \
            --arg reason "$role_delegation_execution_reason" \
            --arg status "$role_delegation_status_text" \
            --arg request_file "${role_delegation_request_file#$repo/}" \
            --arg summary_file "${role_delegation_summary_file#$repo/}" \
            --arg adaptation_status "$role_delegation_adaptation_status" \
            --arg adaptation_reason "$role_delegation_adaptation_reason" \
            --arg adaptation_dir "${role_delegation_adaptation_dir#$repo/}" \
            --argjson enabled "$role_delegation_enabled_json" \
            --argjson max_children "$role_delegation_max_children" \
            --argjson max_parallel "$role_delegation_max_parallel" \
            --argjson max_waves "$role_delegation_max_waves" \
            --argjson child_timeout_seconds "$role_delegation_child_timeout_seconds" \
            --argjson retry_limit "$role_delegation_retry_limit" \
            --argjson retry_backoff_seconds "$role_delegation_retry_backoff_seconds" \
            --argjson retry_backoff_max_seconds "$role_delegation_retry_backoff_max_seconds" \
            --argjson adaptation_max_replans_per_wave "$role_delegation_adaptation_max_replans_per_wave" \
            --argjson adaptation_max_replans_per_iteration "$role_delegation_adaptation_max_replans_per_iteration" \
            --argjson adaptation_attempted "$role_delegation_adaptation_attempted" \
            --argjson adaptation_applied "$role_delegation_adaptation_applied" \
            --argjson adaptation_skipped "$role_delegation_adaptation_skipped" \
            --argjson adaptation_stopped_delegation "$(if [[ "$role_delegation_stop_after_wave" -eq 1 ]]; then echo true; else echo false; fi)" \
            --argjson fail_role_triggered "$(if [[ "$role_delegation_fail_role_triggered" -eq 1 ]]; then echo true; else echo false; fi)" \
            --arg fail_role_wave_id "$role_delegation_fail_role_wave_id" \
            --arg fail_role_child_id "$role_delegation_fail_role_child_id" \
            --argjson requested_waves "$role_delegation_requested_waves" \
            --argjson executed_waves "$role_delegation_executed_waves" \
            --argjson requested_children "$role_delegation_requested_children" \
            --argjson executed_children "$role_delegation_executed_children" \
            --argjson succeeded_children "$role_delegation_succeeded_children" \
            --argjson failed_children "$role_delegation_failed_children" \
            --argjson skipped_children "$role_delegation_skipped_children" \
            --argjson completion_order "$role_delegation_completion_order_json" \
            --argjson aggregation_order "$role_delegation_aggregation_order_json" \
            --arg policy_reason "$role_delegation_policy_reason" \
            --argjson terminal_completed "$role_delegation_terminal_completed" \
            --argjson terminal_failed "$role_delegation_terminal_failed" \
            --argjson terminal_timed_out "$role_delegation_terminal_timed_out" \
            --argjson terminal_cancelled "$role_delegation_terminal_cancelled" \
            --argjson terminal_policy_violation "$role_delegation_terminal_policy_violation" \
            --argjson terminal_skipped "$role_delegation_terminal_skipped" \
            --argjson recon_violations "$role_delegation_recon_violation_count" \
            --arg recon_violation_wave_id "$role_delegation_recon_violation_wave_id" \
            --arg recon_violation_child_id "$role_delegation_recon_violation_child_id" \
            '{
              generated_at: $generated_at,
              loop_id: $loop_id,
              run_id: $run_id,
              role: $role,
              enabled: $enabled,
              mode: $mode,
              dispatch_mode: $dispatch_mode,
              dispatch_mode_effective: $dispatch_mode_effective,
              wake_policy: $wake_policy,
              wake_policy_effective: $wake_policy_effective,
              policy: {
                failure_policy: $failure_policy
              },
              limits: {
                max_children: $max_children,
                max_parallel: $max_parallel,
                max_waves: $max_waves,
                child_timeout_seconds: $child_timeout_seconds,
                retry_limit: $retry_limit,
                retry_backoff_seconds: $retry_backoff_seconds,
                retry_backoff_max_seconds: $retry_backoff_max_seconds
              },
              scheduler: {
                state_model: "pending->running->terminal",
                concurrency_cap: $max_parallel,
                terminal_states: ["completed", "failed", "timed_out", "cancelled", "policy_violation", "skipped"],
                invariants: {
                  cap_enforced: true,
                  deterministic_finalization: true,
                  single_finalization_per_child: true
                }
              },
              status: $status,
              implemented: true,
              reason: $reason,
              request_file: (if ($request_file | length) > 0 then $request_file else null end),
              summary_file: $summary_file,
              adaptation: {
                status: $adaptation_status,
                reason: $adaptation_reason,
                dir: $adaptation_dir,
                limits: {
                  max_replans_per_wave: $adaptation_max_replans_per_wave,
                  max_replans_per_iteration: $adaptation_max_replans_per_iteration
                },
                counters: {
                  replans_attempted: $adaptation_attempted,
                  replans_applied: $adaptation_applied,
                  replans_skipped: $adaptation_skipped,
                  stopped_delegation: $adaptation_stopped_delegation
                }
              },
              fail_role: {
                triggered: $fail_role_triggered,
                wave_id: (if ($fail_role_wave_id | length) > 0 then $fail_role_wave_id else null end),
                child_id: (if ($fail_role_child_id | length) > 0 then $fail_role_child_id else null end)
              },
              execution: {
                requested_waves: $requested_waves,
                executed_waves: $executed_waves,
                requested_children: $requested_children,
                executed_children: $executed_children,
                succeeded_children: $succeeded_children,
                failed_children: $failed_children,
                skipped_children: $skipped_children,
                completion_order: $completion_order,
                aggregation_order: $aggregation_order,
                policy_reason: $policy_reason,
                terminal_state_counts: {
                  completed: $terminal_completed,
                  failed: $terminal_failed,
                  timed_out: $terminal_timed_out,
                  cancelled: $terminal_cancelled,
                  policy_violation: $terminal_policy_violation,
                  skipped: $terminal_skipped
                }
              },
              reconnaissance: {
                enabled: ($mode == "reconnaissance"),
                violations: $recon_violations,
                last_violation: {
                  wave_id: (if ($recon_violation_wave_id | length) > 0 then $recon_violation_wave_id else null end),
                  child_id: (if ($recon_violation_child_id | length) > 0 then $recon_violation_child_id else null end)
                }
              }
            } | with_entries(select(.value != null))' > "$role_delegation_status_file"

          cp "$role_delegation_status_file" "$delegation_latest_dir/${role}.status.json"
          role_delegation_status_for_prompt="$role_delegation_status_file"

          local delegation_index_entry
          delegation_index_entry=$(jq -n \
            --arg timestamp "$(timestamp)" \
            --arg role "$role" \
            --arg run_id "$run_id" \
            --argjson iteration "$iteration" \
            --arg mode "$role_delegation_mode" \
            --arg dispatch_mode "$role_delegation_dispatch_mode" \
            --arg wake_policy "$role_delegation_wake_policy" \
            --arg failure_policy "$role_delegation_failure_policy" \
            --argjson max_parallel "$role_delegation_max_parallel" \
            --arg status "$role_delegation_status_text" \
            --arg policy_reason "$role_delegation_policy_reason" \
            --arg reason "$role_delegation_execution_reason" \
            --arg request_file "${role_delegation_request_file#$repo/}" \
            --arg summary_file "${role_delegation_summary_file#$repo/}" \
            --argjson enabled "$role_delegation_enabled_json" \
            --argjson executed_children "$role_delegation_executed_children" \
            --argjson succeeded_children "$role_delegation_succeeded_children" \
            --argjson failed_children "$role_delegation_failed_children" \
            --argjson skipped_children "$role_delegation_skipped_children" \
            --argjson completion_order "$role_delegation_completion_order_json" \
            --argjson aggregation_order "$role_delegation_aggregation_order_json" \
            --argjson terminal_completed "$role_delegation_terminal_completed" \
            --argjson terminal_failed "$role_delegation_terminal_failed" \
            --argjson terminal_timed_out "$role_delegation_terminal_timed_out" \
            --argjson terminal_cancelled "$role_delegation_terminal_cancelled" \
            --argjson terminal_policy_violation "$role_delegation_terminal_policy_violation" \
            --argjson terminal_skipped "$role_delegation_terminal_skipped" \
            --argjson adaptation_attempted "$role_delegation_adaptation_attempted" \
            --argjson adaptation_applied "$role_delegation_adaptation_applied" \
            --argjson adaptation_skipped "$role_delegation_adaptation_skipped" \
            --argjson fail_role_triggered "$(if [[ "$role_delegation_fail_role_triggered" -eq 1 ]]; then echo true; else echo false; fi)" \
            --argjson recon_violations "$role_delegation_recon_violation_count" \
            --arg status_file "${role_delegation_status_file#$repo/}" \
            '{
              timestamp: $timestamp,
              role: $role,
              run_id: $run_id,
              iteration: $iteration,
              enabled: $enabled,
              mode: $mode,
              dispatch_mode: $dispatch_mode,
              wake_policy: $wake_policy,
              failure_policy: $failure_policy,
              max_parallel: $max_parallel,
              status: $status,
              policy_reason: $policy_reason,
              reason: $reason,
              request_file: (if ($request_file | length) > 0 then $request_file else null end),
              summary_file: $summary_file,
              executed_children: $executed_children,
              succeeded_children: $succeeded_children,
              failed_children: $failed_children,
              skipped_children: $skipped_children,
              completion_order: $completion_order,
              aggregation_order: $aggregation_order,
              terminal_state_counts: {
                completed: $terminal_completed,
                failed: $terminal_failed,
                timed_out: $terminal_timed_out,
                cancelled: $terminal_cancelled,
                policy_violation: $terminal_policy_violation,
                skipped: $terminal_skipped
              },
              adaptation_attempted: $adaptation_attempted,
              adaptation_applied: $adaptation_applied,
              adaptation_skipped: $adaptation_skipped,
              fail_role_triggered: $fail_role_triggered,
              recon_violations: $recon_violations,
              status_file: $status_file
            } | with_entries(select(.value != null))')
          append_delegation_index_entry "$delegation_index_file" "$loop_id" "$delegation_index_entry"

          if [[ "$role_delegation_fail_role_triggered" -eq 1 && "$role_delegation_failure_policy" == "fail_role" ]]; then
            local delegation_fail_role_data
            delegation_fail_role_data=$(jq -n \
              --arg role "$role" \
              --arg wave_id "$role_delegation_fail_role_wave_id" \
              --arg child_id "$role_delegation_fail_role_child_id" \
              --arg status_file "${role_delegation_status_file#$repo/}" \
              --arg failure_policy "$role_delegation_failure_policy" \
              --arg stop_reason "$role_delegation_stop_reason" \
              --argjson failed_children "$role_delegation_failed_children" \
              '{role: $role, wave_id: (if ($wave_id | length) > 0 then $wave_id else null end), child_id: (if ($child_id | length) > 0 then $child_id else null end), failed_children: $failed_children, failure_policy: $failure_policy, stop_reason: (if ($stop_reason | length) > 0 then $stop_reason else null end), status_file: $status_file} | with_entries(select(.value != null))')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "delegation_fail_role" "$delegation_fail_role_data" "$role" "error"
            echo "error: delegation child failed for role '$role' and failure_policy is 'fail_role'" >&2
            write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
            return 1
          fi
        fi

        if [[ "$rlms_enabled" == "true" ]]; then
          local role_rlms_enabled
          role_rlms_enabled=$(jq -r --arg role "$role" '.rlms.roles[$role] // true' <<<"$loop_json")
          role_rlms_enabled="${role_rlms_enabled:-true}"

          local role_rlms_dir="$rlms_root_dir/iter-$iteration/$role"
          local role_rlms_context_file="$role_rlms_dir/context-files.txt"
          local role_rlms_metadata_file="$role_rlms_dir/metadata.json"
          local role_rlms_result_file="$role_rlms_dir/result.json"
          local role_rlms_summary_file="$role_rlms_dir/summary.md"
          local role_rlms_status_file="$role_rlms_dir/status.json"
          local rlms_script="${SUPERLOOP_RLMS_SCRIPT:-$SCRIPT_DIR/scripts/rlms}"
          mkdir -p "$role_rlms_dir"

          rlms_collect_context_files \
            "$repo" \
            "$role_rlms_context_file" \
            "$rlms_auto_max_files" \
            "$changed_files_all" \
            "$tasks_dir" \
            "$repo/$spec_file" \
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
            "$evidence_file"

          local rlms_metrics_json
          rlms_metrics_json=$(rlms_compute_context_metrics "$role_rlms_context_file" "$rlms_request_keyword")
          rlms_metrics_json=$(json_or_default "$rlms_metrics_json" '{}')

          local rlms_context_files_count rlms_context_lines rlms_context_tokens rlms_requested_trigger
          rlms_context_files_count=$(jq -r '.file_count // 0' <<<"$rlms_metrics_json")
          rlms_context_lines=$(jq -r '.line_count // 0' <<<"$rlms_metrics_json")
          rlms_context_tokens=$(jq -r '.estimated_tokens // 0' <<<"$rlms_metrics_json")
          rlms_requested_trigger=$(jq -r '.request_detected // false' <<<"$rlms_metrics_json")
          rlms_context_files_count=$(rlms_safe_int "$rlms_context_files_count" 0)
          rlms_context_lines=$(rlms_safe_int "$rlms_context_lines" 0)
          rlms_context_tokens=$(rlms_safe_int "$rlms_context_tokens" 0)

          local rlms_auto_trigger="false"
          if [[ "$rlms_context_lines" -ge "$rlms_auto_max_lines" || "$rlms_context_tokens" -ge "$rlms_auto_max_estimated_tokens" || "$rlms_context_files_count" -ge "$rlms_auto_max_files" ]]; then
            rlms_auto_trigger="true"
          fi

          local rlms_decision
          rlms_decision=$(rlms_evaluate_trigger "$rlms_enabled" "$role_rlms_enabled" "$rlms_mode" "$rlms_policy_force_on" "$rlms_policy_force_off" "$rlms_auto_trigger" "$rlms_requested_trigger")
          local rlms_should_run
          rlms_should_run=$(printf '%s' "$rlms_decision" | awk -F $'\t' '{print $1}')
          local rlms_trigger_reason
          rlms_trigger_reason=$(printf '%s' "$rlms_decision" | awk -F $'\t' '{print $2}')

          local rlms_decision_data
          rlms_decision_data=$(jq -n \
            --arg role "$role" \
            --arg mode "$rlms_mode" \
            --arg reason "$rlms_trigger_reason" \
            --argjson should_run "$(if [[ "$rlms_should_run" == "true" ]]; then echo true; else echo false; fi)" \
            --argjson metrics "$rlms_metrics_json" \
            '{role: $role, mode: $mode, reason: $reason, should_run: $should_run, metrics: $metrics}')
          log_event "$events_file" "$loop_id" "$iteration" "$run_id" "rlms_decision" "$rlms_decision_data" "$role"

          jq -n \
            --arg generated_at "$(timestamp)" \
            --arg loop_id "$loop_id" \
            --arg run_id "$run_id" \
            --arg role "$role" \
            --arg mode "$rlms_mode" \
            --arg trigger_reason "$rlms_trigger_reason" \
            --argjson should_run "$(if [[ "$rlms_should_run" == "true" ]]; then echo true; else echo false; fi)" \
            --argjson metrics "$rlms_metrics_json" \
            --argjson limits "$(jq -n \
              --argjson max_steps "$rlms_limit_max_steps" \
              --argjson max_depth "$rlms_limit_max_depth" \
              --argjson timeout_seconds "$rlms_limit_timeout_seconds" \
              --argjson max_subcalls "$rlms_limit_max_subcalls" \
              '{max_steps: $max_steps, max_depth: $max_depth, timeout_seconds: $timeout_seconds, max_subcalls: $max_subcalls}')" \
            '{generated_at: $generated_at, loop_id: $loop_id, run_id: $run_id, role: $role, mode: $mode, trigger_reason: $trigger_reason, should_run: $should_run, metrics: $metrics, limits: $limits}' \
            > "$role_rlms_metadata_file"

          local rlms_root_command_json='[]'
          local rlms_root_args_json='[]'
          local rlms_root_prompt_mode='stdin'
          local rlms_subcall_command_json='[]'
          local rlms_subcall_args_json='[]'
          local rlms_subcall_prompt_mode='stdin'

          local rlms_runner_name
          rlms_runner_name=$(get_role_runner_name "$role")
          local rlms_runner_config
          rlms_runner_config=$(get_runner_for_role "$role" "$rlms_runner_name")

          local -a rlms_runner_command=()
          local -a rlms_runner_args=()
          local -a rlms_runner_fast_args=()
          local rlms_runner_prompt_mode='stdin'

          if [[ -n "$rlms_runner_config" ]]; then
            while IFS= read -r line; do
              [[ -n "$line" ]] && rlms_runner_command+=("$line")
            done < <(jq -r '.command[]?' <<<"$rlms_runner_config")

            while IFS= read -r line; do
              [[ -n "$line" ]] && rlms_runner_args+=("$line")
            done < <(jq -r '.args[]?' <<<"$rlms_runner_config")

            while IFS= read -r line; do
              [[ -n "$line" ]] && rlms_runner_fast_args+=("$line")
            done < <(jq -r '.fast_args[]?' <<<"$rlms_runner_config")

            rlms_runner_prompt_mode=$(jq -r '.prompt_mode // "stdin"' <<<"$rlms_runner_config")
          fi

          if [[ ${#rlms_runner_command[@]} -eq 0 ]]; then
            rlms_runner_command=("${runner_command[@]}")
            rlms_runner_args=("${runner_args[@]}")
            rlms_runner_fast_args=("${runner_fast_args[@]}")
            rlms_runner_prompt_mode="$runner_prompt_mode"
          fi

          local -a rlms_runner_active_args=("${rlms_runner_args[@]}")
          if [[ "${fast_mode:-0}" -eq 1 && ${#rlms_runner_fast_args[@]} -gt 0 ]]; then
            rlms_runner_active_args=("${rlms_runner_fast_args[@]}")
          fi

          local rlms_role_model rlms_role_thinking rlms_runner_type
          rlms_role_model=$(get_role_model "$role")
          rlms_role_thinking=$(get_role_thinking "$role")
          rlms_runner_type=$(detect_runner_type_from_cmd "${rlms_runner_command[0]:-}")

          if [[ -n "$rlms_role_model" && "$rlms_role_model" != "null" ]]; then
            rlms_runner_active_args=("--model" "$rlms_role_model" "${rlms_runner_active_args[@]}")
          fi

          if [[ -n "$rlms_role_thinking" && "$rlms_role_thinking" != "null" ]]; then
            local -a rlms_thinking_flags=()
            while IFS= read -r flag; do
              [[ -n "$flag" ]] && rlms_thinking_flags+=("$flag")
            done < <(get_thinking_flags "$rlms_runner_type" "$rlms_role_thinking")
            if [[ ${#rlms_thinking_flags[@]} -gt 0 ]]; then
              rlms_runner_active_args=("${rlms_thinking_flags[@]}" "${rlms_runner_active_args[@]}")
            fi
          fi

          rlms_root_command_json=$(printf '%s\n' "${rlms_runner_command[@]}" | jq -R . | jq -s .)
          rlms_root_args_json=$(printf '%s\n' "${rlms_runner_active_args[@]}" | jq -R . | jq -s .)
          rlms_root_prompt_mode="$rlms_runner_prompt_mode"

          if [[ -n "${SUPERLOOP_RLMS_ROOT_COMMAND_JSON:-}" ]]; then
            rlms_root_command_json="$SUPERLOOP_RLMS_ROOT_COMMAND_JSON"
          fi
          if [[ -n "${SUPERLOOP_RLMS_ROOT_ARGS_JSON:-}" ]]; then
            rlms_root_args_json="$SUPERLOOP_RLMS_ROOT_ARGS_JSON"
          fi
          if [[ -n "${SUPERLOOP_RLMS_ROOT_PROMPT_MODE:-}" ]]; then
            rlms_root_prompt_mode="$SUPERLOOP_RLMS_ROOT_PROMPT_MODE"
          fi

          rlms_subcall_command_json="$rlms_root_command_json"
          rlms_subcall_args_json="$rlms_root_args_json"
          rlms_subcall_prompt_mode="$rlms_root_prompt_mode"

          if [[ -n "${SUPERLOOP_RLMS_SUBCALL_COMMAND_JSON:-}" ]]; then
            rlms_subcall_command_json="$SUPERLOOP_RLMS_SUBCALL_COMMAND_JSON"
          fi
          if [[ -n "${SUPERLOOP_RLMS_SUBCALL_ARGS_JSON:-}" ]]; then
            rlms_subcall_args_json="$SUPERLOOP_RLMS_SUBCALL_ARGS_JSON"
          fi
          if [[ -n "${SUPERLOOP_RLMS_SUBCALL_PROMPT_MODE:-}" ]]; then
            rlms_subcall_prompt_mode="$SUPERLOOP_RLMS_SUBCALL_PROMPT_MODE"
          fi

          if [[ "$rlms_root_prompt_mode" != "stdin" && "$rlms_root_prompt_mode" != "file" ]]; then
            rlms_root_prompt_mode="stdin"
          fi
          if [[ "$rlms_subcall_prompt_mode" != "stdin" && "$rlms_subcall_prompt_mode" != "file" ]]; then
            rlms_subcall_prompt_mode="stdin"
          fi

          local rlms_status_text="skipped"
          local rlms_error_message=""
          local rlms_started_at=""
          local rlms_ended_at=""
          local rlms_rc=0

          if [[ "$rlms_should_run" == "true" ]]; then
            rlms_started_at=$(timestamp)
            local rlms_start_data
            rlms_start_data=$(jq -n \
              --arg role "$role" \
              --arg output_dir "${role_rlms_dir#$repo/}" \
              --argjson metrics "$rlms_metrics_json" \
              '{role: $role, output_dir: $output_dir, metrics: $metrics}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "rlms_start" "$rlms_start_data" "$role"

            set +e
            "$rlms_script" \
              --repo "$repo" \
              --loop-id "$loop_id" \
              --role "$role" \
              --iteration "$iteration" \
              --context-file-list "$role_rlms_context_file" \
              --output-dir "$role_rlms_dir" \
              --max-steps "$rlms_limit_max_steps" \
              --max-depth "$rlms_limit_max_depth" \
              --timeout-seconds "$rlms_limit_timeout_seconds" \
              --max-subcalls "$rlms_limit_max_subcalls" \
              --root-command-json "$rlms_root_command_json" \
              --root-args-json "$rlms_root_args_json" \
              --root-prompt-mode "$rlms_root_prompt_mode" \
              --subcall-command-json "$rlms_subcall_command_json" \
              --subcall-args-json "$rlms_subcall_args_json" \
              --subcall-prompt-mode "$rlms_subcall_prompt_mode" \
              --require-citations "$rlms_output_require_citations" \
              --format "$rlms_output_format" \
              --metadata-file "$role_rlms_metadata_file"
            rlms_rc=$?
            set -e

            rlms_ended_at=$(timestamp)
            if [[ $rlms_rc -eq 0 ]]; then
              rlms_status_text="ok"
            else
              rlms_status_text="failed"
              if [[ -f "$role_rlms_result_file" ]]; then
                rlms_error_message=$(jq -r '.error // ""' "$role_rlms_result_file" 2>/dev/null || echo "")
              fi
              if [[ -z "$rlms_error_message" ]]; then
                rlms_error_message="rlms script exited with status $rlms_rc"
              fi
            fi

            local rlms_end_data
            rlms_end_data=$(jq -n \
              --arg role "$role" \
              --arg status "$rlms_status_text" \
              --arg error "$rlms_error_message" \
              --arg result_file "${role_rlms_result_file#$repo/}" \
              --arg summary_file "${role_rlms_summary_file#$repo/}" \
              --arg started_at "$rlms_started_at" \
              --arg ended_at "$rlms_ended_at" \
              '{role: $role, status: $status, error: (if ($error | length) > 0 then $error else null end), result_file: $result_file, summary_file: $summary_file, started_at: $started_at, ended_at: $ended_at}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "rlms_end" "$rlms_end_data" "$role"
          fi

          jq -n \
            --arg generated_at "$(timestamp)" \
            --arg status "$rlms_status_text" \
            --arg reason "$rlms_trigger_reason" \
            --arg mode "$rlms_mode" \
            --arg error "$rlms_error_message" \
            --arg result_file "${role_rlms_result_file#$repo/}" \
            --arg summary_file "${role_rlms_summary_file#$repo/}" \
            --arg metadata_file "${role_rlms_metadata_file#$repo/}" \
            --argjson metrics "$rlms_metrics_json" \
            --argjson should_run "$(if [[ "$rlms_should_run" == "true" ]]; then echo true; else echo false; fi)" \
            '{generated_at: $generated_at, status: $status, reason: $reason, mode: $mode, should_run: $should_run, error: (if ($error | length) > 0 then $error else null end), result_file: $result_file, summary_file: $summary_file, metadata_file: $metadata_file, metrics: $metrics}' \
            > "$role_rlms_status_file"

          if [[ -f "$role_rlms_result_file" ]]; then
            cp "$role_rlms_result_file" "$rlms_latest_dir/${role}.json"
          fi
          if [[ -f "$role_rlms_summary_file" ]]; then
            cp "$role_rlms_summary_file" "$rlms_latest_dir/${role}.md"
          fi
          cp "$role_rlms_status_file" "$rlms_latest_dir/${role}.status.json"

          local rlms_index_entry
          rlms_index_entry=$(jq -n \
            --arg timestamp "$(timestamp)" \
            --arg role "$role" \
            --arg run_id "$run_id" \
            --argjson iteration "$iteration" \
            --arg status "$rlms_status_text" \
            --arg reason "$rlms_trigger_reason" \
            --arg error "$rlms_error_message" \
            --arg result_file "${role_rlms_result_file#$repo/}" \
            --arg summary_file "${role_rlms_summary_file#$repo/}" \
            --arg status_file "${role_rlms_status_file#$repo/}" \
            --argjson metrics "$rlms_metrics_json" \
            '{timestamp: $timestamp, role: $role, run_id: $run_id, iteration: $iteration, status: $status, reason: $reason, error: (if ($error | length) > 0 then $error else null end), result_file: $result_file, summary_file: $summary_file, status_file: $status_file, metrics: $metrics}')
          append_rlms_index_entry "$rlms_index_file" "$loop_id" "$rlms_index_entry"

          if [[ "$rlms_status_text" == "failed" && "$rlms_policy_fail_mode" == "fail_role" ]]; then
            echo "error: RLMS failed for role '$role' and fail_mode is 'fail_role': $rlms_error_message" >&2
            write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
            return 1
          fi
          if [[ "$rlms_status_text" == "failed" && "$rlms_policy_fail_mode" != "fail_role" ]]; then
            echo "warning: RLMS failed for role '$role' (continuing): $rlms_error_message" >&2
          fi

          if [[ -f "$rlms_latest_dir/${role}.json" ]]; then
            rlms_result_for_prompt="$rlms_latest_dir/${role}.json"
          fi
          if [[ -f "$rlms_latest_dir/${role}.md" ]]; then
            rlms_summary_for_prompt="$rlms_latest_dir/${role}.md"
          fi
          if [[ -f "$rlms_latest_dir/${role}.status.json" ]]; then
            rlms_status_for_prompt="$rlms_latest_dir/${role}.status.json"
          fi
        fi

        local prompt_file="$prompt_dir/${role}.md"
        echo "[$(timestamp)] Building prompt for role: $role" >> "$error_log"

        if ! build_role_prompt \
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
          "$tasks_dir" \
          "$rlms_result_for_prompt" \
          "$rlms_summary_for_prompt" \
          "$rlms_status_for_prompt" \
          "$role_delegation_status_for_prompt" 2>> "$error_log"; then
          echo "[$(timestamp)] ERROR: build_role_prompt failed for role: $role" >> "$error_log"
          echo "Error: Failed to build prompt for role '$role' in iteration $iteration" >&2
          echo "See $error_log for details" >&2
          if [[ "${dry_run:-0}" -ne 1 ]]; then
            write_state "$state_file" "$i" "$iteration" "$loop_id" "false"
          fi
          return 1
        fi
        echo "[$(timestamp)] Successfully built prompt for role: $role" >> "$error_log"

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

        # Inject thinking flags based on runner type (for Codex CLI flags)
        local role_thinking_env=""
        if [[ -n "$role_thinking" && "$role_thinking" != "null" ]]; then
          local -a thinking_flags=()
          while IFS= read -r flag; do
            [[ -n "$flag" ]] && thinking_flags+=("$flag")
          done < <(get_thinking_flags "$role_runner_type" "$role_thinking")
          if [[ ${#thinking_flags[@]} -gt 0 ]]; then
            role_runner_active_args=("${thinking_flags[@]}" "${role_runner_active_args[@]}")
          fi
          # Get thinking env vars (for Claude MAX_THINKING_TOKENS)
          role_thinking_env=$(get_thinking_env "$role_runner_type" "$role_thinking")
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
          run_role "$repo" "$role" "$prompt_file" "$last_message_file" "$role_log" "$role_timeout_seconds" "$role_runner_prompt_mode" "$timeout_inactivity" "$usage_file" "$iteration" "$role_thinking_env" "${role_runner_command[@]}" -- "${role_runner_active_args[@]}"
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

      # Infrastructure Recovery: check for recovery.json when tests fail
      if [[ $tests_ok -eq 0 && "$recovery_enabled" == "true" ]]; then
        local recovery_file="$loop_dir/recovery.json"
        if [[ -f "$recovery_file" ]]; then
          local recovery_rc=0
          set +e
          process_recovery "$repo" "$loop_dir" "$events_file" "$loop_id" "$iteration" "$run_id" \
            "$recovery_enabled" "$recovery_max_per_run" "$recovery_cooldown" "$recovery_on_unknown" \
            "${recovery_auto_approve[@]}" "---" "${recovery_require_human[@]}"
          recovery_rc=$?
          set -e

          if [[ $recovery_rc -eq 0 ]]; then
            # Recovery succeeded - re-run tests
            echo "Recovery completed, re-running tests..."
            local retest_start_data
            retest_start_data=$(jq -n --arg reason "post_recovery" '{reason: $reason}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "tests_rerun_start" "$retest_start_data"

            if run_tests "$repo" "$loop_dir" "${test_commands[@]}"; then
              tests_status="ok"
              tests_ok=1
              echo "Tests passed after recovery!"
            else
              tests_status="failed"
              tests_ok=0
              echo "Tests still failing after recovery"
            fi

            # Update test_status_json with new results
            if [[ -f "$test_status" ]]; then
              test_status_json=$(cat "$test_status")
            fi
            local retest_end_data
            retest_end_data=$(jq -n \
              --arg status "$tests_status" \
              --argjson details "$test_status_json" \
              '{status: $status, details: $details}')
            log_event "$events_file" "$loop_id" "$iteration" "$run_id" "tests_rerun_end" "$retest_end_data"
          fi
        fi
      fi

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

      local progress_code_sig_prev=""
      local progress_test_sig_prev=""
      local progress_code_sig_current=""
      local progress_test_sig_current=""
      local no_progress="false"
      if [[ "$stuck_enabled" == "true" && "$checklist_status_text" != "ok" ]]; then
        if [[ -f "$loop_dir/stuck.json" ]]; then
          # Try new format first (code_signature + test_signature)
          progress_code_sig_prev=$(jq -r '.code_signature // ""' "$loop_dir/stuck.json" 2>/dev/null || true)
          progress_test_sig_prev=$(jq -r '.test_signature // ""' "$loop_dir/stuck.json" 2>/dev/null || true)

          # Fallback to old format (signature field) for backward compatibility
          if [[ -z "$progress_code_sig_prev" ]]; then
            progress_code_sig_prev=$(jq -r '.signature // ""' "$loop_dir/stuck.json" 2>/dev/null || true)
          fi
        fi
        if [[ -n "$progress_code_sig_prev" || -n "$progress_test_sig_prev" ]]; then
          local signature_rc=0
          set +e
          progress_code_sig_current=$(compute_signature "$repo" "${stuck_ignore[@]}")
          signature_rc=$?
          set -e
          if [[ $signature_rc -ne 0 ]]; then
            die "stuck signature computation failed for loop '$loop_id'"
          fi

          # Compute test failure signature
          progress_test_sig_current=$(compute_test_failure_signature "$loop_dir")

          # No progress if: same code changes OR same test failures
          if [[ "$progress_code_sig_current" == "$progress_code_sig_prev" && -n "$progress_code_sig_current" ]]; then
            no_progress="true"
          elif [[ -n "$progress_test_sig_current" && "$progress_test_sig_current" == "$progress_test_sig_prev" && -n "$progress_test_sig_prev" ]]; then
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
              --arg code_sig "$progress_code_sig_current" \
              --arg test_sig "$progress_test_sig_current" \
              --argjson streak "$stuck_streak" \
              --argjson threshold "$stuck_threshold" \
              '{reason: $reason, code_signature: $code_sig, test_signature: $test_sig, streak: $streak, threshold: $threshold}')
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

      # Auto-commit iteration changes if configured
      if [[ "$commit_strategy" != "never" ]]; then
        auto_commit_iteration "$repo" "$loop_id" "$iteration" "$tests_status" "$commit_strategy" "$events_file" "$run_id" "$pre_commit_commands" || true
      fi

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
          "delegation_roles=" + (($e.delegation.role_entries // 0) | tostring),
          "delegation_enabled_roles=" + (($e.delegation.enabled_roles // 0) | tostring),
          "delegation_children=" + (($e.delegation.executed_children // 0) | tostring),
          "delegation_failed=" + (($e.delegation.failed_children // 0) | tostring),
          "delegation_recon_violations=" + (($e.delegation.recon_violations // 0) | tostring),
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

validate_schema_config() {
  local schema_path="$1"
  local config_path="$2"

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    die "missing python3/python for schema validation"
  fi

  "$python_bin" - "$schema_path" "$config_path" <<'PY'
import json
import sys


def error(message, path, quiet=False):
    if not quiet:
        sys.stderr.write("schema validation error at {}: {}\n".format(path, message))
    return False


def is_integer(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    return (isinstance(value, int) or isinstance(value, float)) and not isinstance(value, bool)


def validate(instance, schema, path, quiet=False):
    if "allOf" in schema:
        for index, subschema in enumerate(schema["allOf"]):
            if not validate(instance, subschema, "{}.allOf[{}]".format(path, index), quiet):
                return False

    if "anyOf" in schema:
        any_ok = False
        for index, subschema in enumerate(schema["anyOf"]):
            if validate(instance, subschema, "{}.anyOf[{}]".format(path, index), True):
                any_ok = True
                break
        if not any_ok:
            return error("expected to match at least one schema in anyOf", path, quiet)

    if "oneOf" in schema:
        one_matches = 0
        for index, subschema in enumerate(schema["oneOf"]):
            if validate(instance, subschema, "{}.oneOf[{}]".format(path, index), True):
                one_matches += 1
        if one_matches != 1:
            return error("expected to match exactly one schema in oneOf", path, quiet)

    if "if" in schema:
        condition_met = validate(instance, schema["if"], "{}.if".format(path), True)
        if condition_met:
            then_schema = schema.get("then")
            if then_schema is not None and not validate(instance, then_schema, "{}.then".format(path), quiet):
                return False
        else:
            else_schema = schema.get("else")
            if else_schema is not None and not validate(instance, else_schema, "{}.else".format(path), quiet):
                return False

    if "enum" in schema:
        if instance not in schema["enum"]:
            return error("expected one of {}".format(schema["enum"]), path, quiet)

    schema_type = schema.get("type")
    if schema_type == "object":
        if not isinstance(instance, dict):
            return error("expected object", path, quiet)
        props = schema.get("properties", {})
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                return error("missing required property '{}'".format(key), "{}.{}".format(path, key), quiet)
        additional = schema.get("additionalProperties", True)
        for key, value in instance.items():
            if key in props:
                if not validate(value, props[key], "{}.{}".format(path, key), quiet):
                    return False
            else:
                if additional is False:
                    return error("unexpected property '{}'".format(key), "{}.{}".format(path, key), quiet)
                if isinstance(additional, dict):
                    if not validate(value, additional, "{}.{}".format(path, key), quiet):
                        return False
        return True

    if schema_type == "array":
        if not isinstance(instance, list):
            return error("expected array", path, quiet)
        if "minItems" in schema and len(instance) < schema["minItems"]:
            return error("expected at least {} items".format(schema["minItems"]), path, quiet)
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, item in enumerate(instance):
                if not validate(item, item_schema, "{}[{}]".format(path, index), quiet):
                    return False
        return True

    if schema_type == "string":
        if not isinstance(instance, str):
            return error("expected string", path, quiet)
        return True

    if schema_type == "integer":
        if not is_integer(instance):
            return error("expected integer", path, quiet)
        return True

    if schema_type == "number":
        if not is_number(instance):
            return error("expected number", path, quiet)
        return True

    if schema_type == "boolean":
        if not isinstance(instance, bool):
            return error("expected boolean", path, quiet)
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

validate_cmd() {
  local repo="$1"
  local config_path="$2"
  local schema_path="$3"
  local static_only="${4:-0}"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi
  if [[ ! -f "$schema_path" ]]; then
    die "schema not found: $schema_path"
  fi

  if ! validate_schema_config "$schema_path" "$config_path"; then
    return 1
  fi

  local probe_mode="${5:-0}"

  # Run static validation if requested (--static or --probe)
  if [[ "$static_only" == "1" || "$static_only" == "--static" || "$probe_mode" == "1" ]]; then
    echo ""
    echo "Running static analysis..."
    if ! validate_static "$repo" "$config_path"; then
      return 1
    fi
    echo "ok: static analysis passed"
  fi

  # Run probe validation if requested (--probe)
  if [[ "$probe_mode" == "1" ]]; then
    echo ""
    echo "Running probe validation (this may take a moment)..."
    if ! validate_probe "$repo" "$config_path"; then
      return 1
    fi
    echo "ok: probe validation passed"
  fi
}

runner_smoke_cmd() {
  local repo="$1"
  local config_path="$2"
  local schema_path="$3"
  local loop_id="${4:-}"

  need_cmd jq

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi
  if [[ ! -f "$schema_path" ]]; then
    die "schema not found: $schema_path"
  fi

  if [[ -n "$loop_id" ]]; then
    local loop_match
    loop_match=$(jq -r --arg id "$loop_id" '.loops[]? | select(.id == $id) | .id' "$config_path" | head -n1)
    if [[ -z "$loop_match" ]]; then
      die "loop id not found: $loop_id"
    fi
  fi

  if ! validate_schema_config "$schema_path" "$config_path"; then
    return 1
  fi

  echo ""
  echo "Running runner smoke checks..."
  if ! validate_runner_smoke "$repo" "$config_path" "$loop_id"; then
    return 1
  fi
  echo "ok: runner smoke checks passed"
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
  local usage_file="$loop_dir/usage.jsonl"
  local report_file="$out_path"
  if [[ -z "$report_file" ]]; then
    report_file="$loop_dir/report.html"
  fi

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    die "missing python3/python for report generation"
  fi

  "$python_bin" - "$loop_id" "$summary_file" "$timeline_file" "$events_file" "$gate_summary" "$evidence_file" "$reviewer_packet" "$approval_file" "$decisions_md" "$decisions_jsonl" "$usage_file" "$report_file" <<'PY'
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


def read_jsonl(path):
    if not path or not os.path.exists(path):
        return []
    entries = []
    with open(path, "r") as handle:
        for line in handle:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except Exception:
                    pass
    return entries


def aggregate_usage(entries):
    totals = {
        "input_tokens": 0,
        "output_tokens": 0,
        "thinking_tokens": 0,
        "reasoning_output_tokens": 0,
        "cached_input_tokens": 0,
        "cache_read_input_tokens": 0,
        "cache_creation_input_tokens": 0,
        "total_cost_usd": 0.0,
        "total_duration_ms": 0,
    }
    by_role = {}
    by_runner = {}

    for entry in entries:
        usage = entry.get("usage", {})
        cost = entry.get("cost_usd", 0) or 0
        duration = entry.get("duration_ms", 0) or 0
        role = entry.get("role", "unknown")
        runner = entry.get("runner", "unknown")

        totals["input_tokens"] += usage.get("input_tokens", 0) or 0
        totals["output_tokens"] += usage.get("output_tokens", 0) or 0
        totals["thinking_tokens"] += usage.get("thinking_tokens", 0) or 0
        totals["reasoning_output_tokens"] += usage.get("reasoning_output_tokens", 0) or 0
        totals["cached_input_tokens"] += usage.get("cached_input_tokens", 0) or 0
        totals["cache_read_input_tokens"] += usage.get("cache_read_input_tokens", 0) or 0
        totals["cache_creation_input_tokens"] += usage.get("cache_creation_input_tokens", 0) or 0
        totals["total_cost_usd"] += cost
        totals["total_duration_ms"] += duration

        if role not in by_role:
            by_role[role] = {"cost_usd": 0.0, "duration_ms": 0, "count": 0}
        by_role[role]["cost_usd"] += cost
        by_role[role]["duration_ms"] += duration
        by_role[role]["count"] += 1

        if runner not in by_runner:
            by_runner[runner] = {"cost_usd": 0.0, "count": 0}
        by_runner[runner]["cost_usd"] += cost
        by_runner[runner]["count"] += 1

    return totals, by_role, by_runner


def format_duration(ms):
    if ms < 1000:
        return "{}ms".format(ms)
    secs = ms / 1000
    if secs < 60:
        return "{:.1f}s".format(secs)
    mins = secs / 60
    if mins < 60:
        return "{:.1f}m".format(mins)
    hours = mins / 60
    return "{:.1f}h".format(hours)


def format_tokens(n):
    if n >= 1000000:
        return "{:.1f}M".format(n / 1000000)
    if n >= 1000:
        return "{:.1f}K".format(n / 1000)
    return str(n)


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
usage_path = sys.argv[11]
out_path = sys.argv[12]

summary = read_json(summary_path)
timeline = read_text(timeline_path)
gate_summary = read_text(gate_path).strip()
evidence = read_json(evidence_path)
reviewer_packet = read_text(reviewer_packet_path).strip()
approval = read_json(approval_path)
decisions_md = read_text(decisions_md_path).strip()
decisions_jsonl = read_text(decisions_jsonl_path).strip()
usage_entries = read_jsonl(usage_path)
usage_totals, usage_by_role, usage_by_runner = aggregate_usage(usage_entries)

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

# Usage & Cost section
if usage_entries:
    usage_html = ["<div class='usage-grid'>"]

    # Summary row
    usage_html.append("<div class='usage-summary'>")
    usage_html.append("<div class='usage-stat'><span class='label'>Total Cost</span><span class='value'>${:.4f}</span></div>".format(usage_totals["total_cost_usd"]))
    usage_html.append("<div class='usage-stat'><span class='label'>Duration</span><span class='value'>{}</span></div>".format(format_duration(usage_totals["total_duration_ms"])))
    usage_html.append("<div class='usage-stat'><span class='label'>Iterations</span><span class='value'>{}</span></div>".format(len(usage_entries)))
    usage_html.append("</div>")

    # Token breakdown
    usage_html.append("<h3>Token Usage</h3>")
    usage_html.append("<table class='usage-table'>")
    usage_html.append("<tr><th>Type</th><th>Count</th></tr>")
    usage_html.append("<tr><td>Input Tokens</td><td>{}</td></tr>".format(format_tokens(usage_totals["input_tokens"])))
    usage_html.append("<tr><td>Output Tokens</td><td>{}</td></tr>".format(format_tokens(usage_totals["output_tokens"])))
    if usage_totals["thinking_tokens"] > 0:
        usage_html.append("<tr><td>Thinking Tokens (Claude)</td><td>{}</td></tr>".format(format_tokens(usage_totals["thinking_tokens"])))
    if usage_totals["reasoning_output_tokens"] > 0:
        usage_html.append("<tr><td>Reasoning Tokens (Codex)</td><td>{}</td></tr>".format(format_tokens(usage_totals["reasoning_output_tokens"])))
    cache_tokens = usage_totals["cached_input_tokens"] + usage_totals["cache_read_input_tokens"]
    if cache_tokens > 0:
        usage_html.append("<tr><td>Cache Read Tokens</td><td>{}</td></tr>".format(format_tokens(cache_tokens)))
    if usage_totals["cache_creation_input_tokens"] > 0:
        usage_html.append("<tr><td>Cache Write Tokens</td><td>{}</td></tr>".format(format_tokens(usage_totals["cache_creation_input_tokens"])))
    usage_html.append("</table>")

    # Cost by role
    if usage_by_role:
        usage_html.append("<h3>Cost by Role</h3>")
        usage_html.append("<table class='usage-table'>")
        usage_html.append("<tr><th>Role</th><th>Runs</th><th>Duration</th><th>Cost</th></tr>")
        for role in ["planner", "implementer", "tester", "reviewer"]:
            if role in usage_by_role:
                r = usage_by_role[role]
                usage_html.append("<tr><td>{}</td><td>{}</td><td>{}</td><td>${:.4f}</td></tr>".format(
                    role.capitalize(), r["count"], format_duration(r["duration_ms"]), r["cost_usd"]))
        usage_html.append("</table>")

    # Cost by runner
    if usage_by_runner:
        usage_html.append("<h3>Cost by Runner</h3>")
        usage_html.append("<table class='usage-table'>")
        usage_html.append("<tr><th>Runner</th><th>Runs</th><th>Cost</th></tr>")
        for runner, r in sorted(usage_by_runner.items()):
            usage_html.append("<tr><td>{}</td><td>{}</td><td>${:.4f}</td></tr>".format(
                runner.capitalize(), r["count"], r["cost_usd"]))
        usage_html.append("</table>")

    usage_html.append("</div>")
    sections.append("<h2>Usage &amp; Cost</h2>" + "\n".join(usage_html))
else:
    sections.append("<h2>Usage &amp; Cost</h2><p>No usage data found.</p>")

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
    .usage-grid {{
      background: #fff;
      border: 1px solid #e2e2e2;
      padding: 16px;
    }}
    .usage-summary {{
      display: flex;
      gap: 24px;
      margin-bottom: 16px;
      padding-bottom: 16px;
      border-bottom: 1px solid #e2e2e2;
    }}
    .usage-stat {{
      display: flex;
      flex-direction: column;
    }}
    .usage-stat .label {{
      font-size: 12px;
      color: #666;
    }}
    .usage-stat .value {{
      font-size: 20px;
      font-weight: bold;
    }}
    .usage-table {{
      border-collapse: collapse;
      margin: 8px 0 16px 0;
    }}
    .usage-table th,
    .usage-table td {{
      border: 1px solid #e2e2e2;
      padding: 6px 12px;
      text-align: left;
    }}
    .usage-table th {{
      background: #f5f5f5;
    }}
    h3 {{
      margin: 16px 0 8px 0;
      font-size: 14px;
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
  local json_output=0
  local approver=""
  local note=""
  local reject=0
  local static=0
  local probe=0
  local skip_validate=0

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
      --json)
        json_output=1
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
      --static)
        static=1
        shift
        ;;
      --probe)
        probe=1
        shift
        ;;
      --skip-validate)
        skip_validate=1
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
      run_cmd "$repo" "$config_path" "$loop_id" "$fast" "$dry_run" "$skip_validate"
      ;;
    status)
      status_cmd "$repo" "$summary" "$loop_id" "$config_path"
      ;;
    usage)
      usage_cmd "$repo" "$loop_id" "$config_path" "$json_output"
      ;;
    approve)
      approve_cmd "$repo" "$loop_id" "$approver" "$note" "$reject"
      ;;
    cancel)
      cancel_cmd "$repo"
      ;;
    validate)
      validate_cmd "$repo" "$config_path" "$schema_path" "$static" "$probe"
      ;;
    runner-smoke)
      runner_smoke_cmd "$repo" "$config_path" "$schema_path" "$loop_id"
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

