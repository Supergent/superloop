#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION="0.1.1"

usage() {
  cat <<'USAGE'
Ralph++ Codex Wrapper

Usage:
  ralph-codex.sh init [--repo DIR] [--force]
  ralph-codex.sh run [--repo DIR] [--config FILE] [--loop ID] [--fast] [--dry-run]
  ralph-codex.sh status [--repo DIR]
  ralph-codex.sh cancel [--repo DIR]
  ralph-codex.sh validate [--repo DIR] [--config FILE] [--schema FILE]
  ralph-codex.sh report [--repo DIR] [--config FILE] [--loop ID] [--out FILE]
  ralph-codex.sh --version

Options:
  --repo DIR       Repository root (default: current directory)
  --config FILE    Config file path (default: .ralph/config.json)
  --schema FILE    Schema file path (default: schema/config.schema.json)
  --loop ID        Run only the loop with this id
  --force          Overwrite existing .ralph files on init
  --fast           Use codex.fast_args (if set) instead of codex.args
  --dry-run        Read-only status summary from existing artifacts; no Codex calls
  --out FILE       Report output path (default: .ralph/loops/<id>/report.html)
  --version        Print version and exit

Notes:
- This wrapper runs Codex in a multi-role loop (planner, implementer, tester, reviewer).
- The loop stops only when the reviewer outputs a matching promise AND gates pass.
- Gates: checklist validation + optional tests (per config).
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

timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

DEFAULT_STUCK_IGNORE=(
  ".ralph/**"
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
  for file in "${files[@]}"; do
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
}

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
  local -a codex_args=("$@")

  mkdir -p "$(dirname "$last_message_file")" "$(dirname "$log_file")"

  set +e
  codex exec "${codex_args[@]}" -C "$repo" --output-last-message "$last_message_file" - < "$prompt_file" | tee "$log_file"
  local status=${PIPESTATUS[0]}
  set -e

  if [[ $status -ne 0 ]]; then
    die "codex exec failed for role '$role' (exit $status)"
  fi
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

write_iteration_notes() {
  local notes_file="$1"
  local loop_id="$2"
  local iteration="$3"
  local promise_matched="$4"
  local tests_status="$5"
  local checklist_status="$6"
  local tests_mode="$7"
  local evidence_status="${8:-}"
  local stuck_streak="${9:-}"
  local stuck_threshold="${10:-}"

  cat <<EOF > "$notes_file"
Iteration: $iteration
Loop: $loop_id
Promise matched: $promise_matched
Tests: $tests_status (mode: $tests_mode)
Checklist: $checklist_status
Evidence: ${evidence_status:-skipped}
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
  local checklist_status="$4"
  local evidence_status="$5"
  local stuck_status="$6"

  printf 'promise=%s tests=%s checklist=%s evidence=%s stuck=%s\n' \
    "$promise_matched" "$tests_status" "$checklist_status" "$evidence_status" "$stuck_status" \
    > "$summary_file"
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
  local checklist_status="${13}"
  local evidence_status="${14}"
  local stuck_streak="${15}"
  local stuck_threshold="${16}"
  local completion_ok="${17}"
  local loop_dir="${18}"
  local events_file="${19}"

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

  local plan_meta implementer_meta test_report_meta reviewer_meta
  local test_output_meta test_status_meta checklist_status_meta checklist_remaining_meta
  local evidence_meta summary_meta notes_meta events_meta

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
  summary_meta=$(file_meta_json "${summary_file_gate#$repo/}" "$summary_file_gate")
  summary_meta=$(json_or_default "$summary_meta" "{}")
  notes_meta=$(file_meta_json "${notes_file#$repo/}" "$notes_file")
  notes_meta=$(json_or_default "$notes_meta" "{}")
  events_meta=$(file_meta_json "${events_file#$repo/}" "$events_file")
  events_meta=$(json_or_default "$events_meta" "{}")

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
    --argjson gate_summary "$summary_meta" \
    --argjson iteration_notes "$notes_meta" \
    --argjson events "$events_meta" \
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
      gate_summary: $gate_summary,
      iteration_notes: $iteration_notes,
      events: $events
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
    --argjson iteration "$iteration" \
    --arg started_at "$started_at" \
    --arg ended_at "$ended_at" \
    --arg promise_expected "$completion_promise" \
    --arg promise_text "$promise_text" \
    --argjson promise_matched "$promise_matched_json" \
    --arg tests_mode "$tests_mode" \
    --arg tests_status "$tests_status" \
    --arg checklist_status "$checklist_status" \
    --arg evidence_status "$evidence_status" \
    --argjson stuck_streak "$stuck_streak" \
    --argjson stuck_threshold "$stuck_threshold" \
    --argjson completion_ok "$completion_json" \
    --argjson artifacts "$artifacts_json" \
    '{
      run_id: $run_id,
      iteration: $iteration,
      started_at: $started_at,
      ended_at: $ended_at,
      promise: {
        expected: $promise_expected,
        text: ($promise_text | select(length>0)),
        matched: $promise_matched
      },
      gates: {
        tests: $tests_status,
        checklist: $checklist_status,
        evidence: $evidence_status
      },
      tests_mode: $tests_mode,
      stuck: { streak: $stuck_streak, threshold: $stuck_threshold },
      completion_ok: $completion_ok,
      artifacts: $artifacts
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
      "- \(.ended_at // .started_at) run=\(.run_id // "unknown") iter=\(.iteration) promise=\(.promise.matched // "unknown") tests=\(.gates.tests // "unknown") checklist=\(.gates.checklist // "unknown") evidence=\(.gates.evidence // "unknown") stuck=\(.stuck.streak // 0)/\(.stuck.threshold // 0) completion=\(.completion_ok // false)"' \
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
  local ralph_dir="$repo/.ralph"

  mkdir -p "$ralph_dir/roles" "$ralph_dir/loops" "$ralph_dir/logs"

  if [[ -f "$ralph_dir/config.json" && $force -ne 1 ]]; then
    die "found existing $ralph_dir/config.json (use --force to overwrite)"
  fi

  cat > "$ralph_dir/config.json" <<'EOF'
{
  "codex": {
    "args": ["--full-auto"],
    "fast_args": []
  },
  "loops": [
    {
      "id": "initiation",
      "spec_file": ".ralph/spec.md",
      "max_iterations": 20,
      "completion_promise": "INITIATION_READY",
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
      "stuck": {
        "enabled": true,
        "threshold": 3,
        "action": "report_and_stop",
        "ignore": [
          ".ralph/**",
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
      "roles": ["planner", "implementer", "tester", "reviewer"]
    }
  ]
}
EOF

  cat > "$ralph_dir/spec.md" <<'EOF'
# Ralph Loop Spec

Replace this file with the actual task specification.

Include:
- Goal and scope
- Requirements and constraints
- Verification steps
- Completion criteria
- Promise tag usage
EOF

  cat > "$ralph_dir/roles/planner.md" <<'EOF'
You are the Planner.

Responsibilities:
- Read the spec and iteration notes.
- Maintain a concise, ordered plan (3-7 steps) aligned with the spec and current status.
- Note blockers or unclear requirements in the plan.

Rules:
- Do not modify code or run tests.
- Do not output a promise tag.
- Minimize plan churn: if the current plan still matches the spec/status, do not edit the plan file.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged steps).
- Avoid speculative blockers: keep "None" unless a concrete blocker appears; do not update blockers just to note verification completion.
- Write only to the plan file path listed in context.
EOF

  cat > "$ralph_dir/roles/implementer.md" <<'EOF'
You are the Implementer.

Responsibilities:
- Read the spec and plan.
- Implement the required changes in the codebase.
- Summarize changes in the implementer report.

Rules:
- Do not edit the spec or plan files.
- Do not run tests.
- Do not output a promise tag.
- Minimize report churn: if the report already reflects the current state and no changes were made, do not edit it.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged bullets).
- Write your summary to the implementer report file path listed in context.
EOF

  cat > "$ralph_dir/roles/tester.md" <<'EOF'
You are the Tester.

Responsibilities:
- Read test status and test output files.
- Summarize failures or gaps in the test report.

Rules:
- Do not modify code or rerun tests.
- Do not output a promise tag.
- Minimize report churn: if test status/output are unchanged and the report is accurate, do not edit it.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged text).
- Do not update the report just to refresh timestamps (e.g., generated_at); update only when status/output or gaps materially change.
- Write your report to the test report file path listed in context.
EOF

  cat > "$ralph_dir/roles/reviewer.md" <<'EOF'
You are the Reviewer.

Responsibilities:
- Read the spec, checklist status, test status, and reports.
- Validate that requirements are met and gates are green.
- Write a short review report.

Rules:
- Do not modify code.
- Only output <promise>...</promise> if tests pass, checklists are complete, and the spec is satisfied.
- Minimize report churn: if the review report already reflects the current state and no gates changed, do not edit it.
- If updates are required, change only the minimum necessary (avoid rephrasing or reordering unchanged text).
- Write your review to the reviewer report file path listed in context.
EOF

  echo "Initialized .ralph in $ralph_dir"
}

run_cmd() {
  local repo="$1"
  local config_path="$2"
  local target_loop_id="$3"
  local fast_mode="$4"
  local dry_run="$5"

  need_cmd jq
  if [[ "${dry_run:-0}" -ne 1 ]]; then
    need_cmd codex
  fi

  local ralph_dir="$repo/.ralph"
  local state_file="$ralph_dir/state.json"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi

  local loop_count
  loop_count=$(jq '.loops | length' "$config_path")
  if [[ "$loop_count" == "0" ]]; then
    die "config has no loops"
  fi

  local -a codex_args=()
  while IFS= read -r line; do
    codex_args+=("$line")
  done < <(jq -r '.codex.args[]?' "$config_path")

  local -a fast_args=()
  while IFS= read -r line; do
    fast_args+=("$line")
  done < <(jq -r '.codex.fast_args[]?' "$config_path")

  if [[ "${fast_mode:-0}" -eq 1 ]]; then
    if [[ ${#fast_args[@]} -gt 0 ]]; then
      codex_args=("${fast_args[@]}")
    else
      echo "warning: --fast set but codex.fast_args is empty; using codex.args" >&2
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

    local loop_dir="$ralph_dir/loops/$loop_id"
    local role_dir="$ralph_dir/roles"
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
    local checklist_status="$loop_dir/checklist-status.json"
    local checklist_remaining="$loop_dir/checklist-remaining.md"
    local evidence_file="$loop_dir/evidence.json"
    local summary_file="$loop_dir/gate-summary.txt"
    local events_file="$loop_dir/events.jsonl"
    local run_summary_file="$loop_dir/run-summary.json"
    local timeline_file="$loop_dir/timeline.md"

    mkdir -p "$loop_dir" "$prompt_dir" "$log_dir"
    touch "$plan_file" "$notes_file" "$implementer_report" "$reviewer_report" "$test_report"

    local -a roles=()
    while IFS= read -r line; do
      roles+=("$line")
    done < <(jq -r '.roles[]?' <<<"$loop_json")
    if [[ ${#roles[@]} -eq 0 ]]; then
      roles=(planner implementer tester reviewer)
    fi

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

    local evidence_enabled
    evidence_enabled=$(jq -r '.evidence.enabled // false' <<<"$loop_json")
    local evidence_require
    evidence_require=$(jq -r '.evidence.require_on_completion // false' <<<"$loop_json")

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

      local tests_status checklist_status_text evidence_status stuck_value
      tests_status=$(read_test_status_summary "$test_status")
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

      echo "Dry-run summary ($loop_id): promise=$promise_status tests=$tests_status checklist=$checklist_status_text evidence=$evidence_status stuck=$stuck_value"
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
          "$checklist_status" \
          "$checklist_remaining" \
          "$evidence_file"

        local last_message_file="$last_messages_dir/${role}.txt"
        local role_log="$log_dir/${role}.log"
        local report_guard=""
        local report_snapshot=""

        case "$role" in
          planner)
            report_guard="$plan_file"
            ;;
          implementer)
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

        local role_start_data
        role_start_data=$(jq -n \
          --arg prompt_file "$prompt_file" \
          --arg log_file "$role_log" \
          --arg last_message_file "$last_message_file" \
          '{prompt_file: $prompt_file, log_file: $log_file, last_message_file: $last_message_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_start" "$role_start_data" "$role"

        run_role "$repo" "$role" "$prompt_file" "$last_message_file" "$role_log" "${codex_args[@]}"
        if [[ -n "$report_guard" ]]; then
          restore_if_unchanged "$report_guard" "$report_snapshot"
        fi
        local role_end_data
        role_end_data=$(jq -n \
          --arg log_file "$role_log" \
          --arg last_message_file "$last_message_file" \
          '{log_file: $log_file, last_message_file: $last_message_file}')
        log_event "$events_file" "$loop_id" "$iteration" "$run_id" "role_end" "$role_end_data" "$role"
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
      if check_checklists "$repo" "$loop_dir" "${checklist_patterns[@]}"; then
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

      local completion_ok=0
      if [[ "$promise_matched" == "true" && $tests_ok -eq 1 && $checklist_ok -eq 1 && $evidence_gate_ok -eq 1 ]]; then
        completion_ok=1
      fi

      local stuck_streak="0"
      local stuck_triggered="false"
      if [[ $completion_ok -eq 0 && "$stuck_enabled" == "true" ]]; then
        local stuck_result
        stuck_result=$(update_stuck_state "$repo" "$loop_dir" "$stuck_threshold" "${stuck_ignore[@]}")
        local stuck_rc=$?
        if [[ $stuck_rc -eq 0 ]]; then
          stuck_streak="$stuck_result"
        elif [[ $stuck_rc -eq 2 ]]; then
          stuck_streak="$stuck_result"
          stuck_triggered="true"
          write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold"
          local stuck_value="n/a"
          if [[ "$stuck_enabled" == "true" ]]; then
            stuck_value="${stuck_streak}/${stuck_threshold}"
          fi
          write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$checklist_status_text" "$evidence_status" "$stuck_value"
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

      write_iteration_notes "$notes_file" "$loop_id" "$iteration" "$promise_matched" "$tests_status" "$checklist_status_text" "$tests_mode" "$evidence_status" "$stuck_streak" "$stuck_threshold"
      local stuck_value="n/a"
      if [[ "$stuck_enabled" == "true" ]]; then
        stuck_value="${stuck_streak}/${stuck_threshold}"
      fi
      write_gate_summary "$summary_file" "$promise_matched" "$tests_status" "$checklist_status_text" "$evidence_status" "$stuck_value"
      local gates_data
      gates_data=$(jq -n \
        --argjson promise "$promise_matched_json" \
        --arg tests "$tests_status" \
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        --arg stuck "$stuck_value" \
        '{promise: $promise, tests: $tests, checklist: $checklist, evidence: $evidence, stuck: $stuck}')
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
        --arg checklist "$checklist_status_text" \
        --arg evidence "$evidence_status" \
        '{started_at: $started_at, ended_at: $ended_at, completion: $completion, promise: $promise, tests: $tests, checklist: $checklist, evidence: $evidence}')
      log_event "$events_file" "$loop_id" "$iteration" "$run_id" "iteration_end" "$iteration_end_data"

      append_run_summary "$run_summary_file" "$repo" "$loop_id" "$run_id" "$iteration" "$iteration_started_at" "$iteration_ended_at" "$promise_matched" "$completion_promise" "$promise_text" "$tests_mode" "$tests_status" "$checklist_status_text" "$evidence_status" "$stuck_streak" "$stuck_threshold" "$completion_ok" "$loop_dir" "$events_file"
      write_timeline "$run_summary_file" "$timeline_file"

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
  local state_file="$repo/.ralph/state.json"

  if [[ ! -f "$state_file" ]]; then
    echo "No state file found."
    return 0
  fi

  cat "$state_file"
}

cancel_cmd() {
  local repo="$1"
  local state_file="$repo/.ralph/state.json"

  if [[ ! -f "$state_file" ]]; then
    echo "No active state file found."
    return 0
  fi

  rm "$state_file"
  echo "Cancelled loop state."
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

  local loop_dir="$repo/.ralph/loops/$loop_id"
  local summary_file="$loop_dir/run-summary.json"
  local timeline_file="$loop_dir/timeline.md"
  local events_file="$loop_dir/events.jsonl"
  local gate_summary="$loop_dir/gate-summary.txt"
  local evidence_file="$loop_dir/evidence.json"
  local report_file="$out_path"
  if [[ -z "$report_file" ]]; then
    report_file="$loop_dir/report.html"
  fi

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    die "missing python3/python for report generation"
  fi

  "$python_bin" - "$loop_id" "$summary_file" "$timeline_file" "$events_file" "$gate_summary" "$evidence_file" "$report_file" <<'PY'
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
out_path = sys.argv[7]

summary = read_json(summary_path)
timeline = read_text(timeline_path)
gate_summary = read_text(gate_path).strip()
evidence = read_json(evidence_path)

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

html_doc = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Ralphcodex Report - {loop_id}</title>
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
  <h1>Ralphcodex Report</h1>
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
  local force=0
  local fast=0
  local dry_run=0

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
      --out)
        out_path="$2"
        shift 2
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

  repo=$(cd "$repo" && pwd)

  if [[ -z "$config_path" ]]; then
    config_path="$repo/.ralph/config.json"
  fi
  if [[ -z "$schema_path" ]]; then
    schema_path="$repo/schema/config.schema.json"
  fi

  case "$cmd" in
    init)
      init_cmd "$repo" "$force"
      ;;
    run)
      run_cmd "$repo" "$config_path" "$loop_id" "$fast" "$dry_run"
      ;;
    status)
      status_cmd "$repo"
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
