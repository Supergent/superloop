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
  superloop.sh lifecycle-audit [--repo DIR] [--feature-prefix PREFIX] [--main-ref REF] [--strict] [--json-out FILE] [--no-fetch]
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
  --feature-prefix Branch/worktree prefix to audit (default: feat/)
  --main-ref REF   Main/trunk reference for merge-base checks (default: origin/main)
  --strict         Fail non-zero when lifecycle thresholds are breached
  --json-out FILE  Write lifecycle audit JSON report to file
  --no-fetch       Skip fetch --prune before lifecycle audit
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

write_active_run_state() {
  local active_run_file="$1"
  local repo="$2"
  local pid="$3"
  local pgid="$4"
  local loop_id="$5"
  local iteration="${6:-0}"
  local stage="${7:-run}"

  jq -n \
    --arg repo "$repo" \
    --argjson pid "$pid" \
    --argjson pgid "$pgid" \
    --arg loop_id "$loop_id" \
    --argjson iteration "$iteration" \
    --arg stage "$stage" \
    --arg updated_at "$(timestamp)" \
    '{
      repo: $repo,
      pid: $pid,
      pgid: $pgid,
      loop_id: (if ($loop_id | length) > 0 then $loop_id else null end),
      iteration: $iteration,
      stage: $stage,
      updated_at: $updated_at
    }' \
    > "$active_run_file"
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
