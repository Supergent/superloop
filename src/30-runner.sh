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
  "$python_bin" - "${cmd[@]}" <<'PY'
import os
import queue
import subprocess
import sys
import threading
import time


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
                if proc.poll() is not None and q.empty():
                    break
                continue

            if line is None:
                break

            # Got output - reset inactivity deadline
            if inactivity_seconds > 0:
                activity_deadline = time.time() + inactivity_seconds

            sys.stdout.write(line)
            sys.stdout.flush()
            log.write(line)
            log.flush()

        if timed_out and proc.poll() is None:
            time.sleep(2)
            if proc.poll() is None:
                proc.kill()

        rc = proc.wait()
        if timed_out:
            return 124
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
  if [[ "${USAGE_TRACKING_ENABLED:-1}" -eq 1 ]] && type detect_runner_type &>/dev/null; then
    runner_type=$(detect_runner_type "${cmd[@]}")

    if [[ "$runner_type" == "claude" ]]; then
      # Inject --session-id for Claude
      local -a tracked_cmd=()
      while IFS= read -r line; do
        tracked_cmd+=("$line")
      done < <(prepare_tracked_command "$runner_type" "${cmd[@]}")
      cmd=("${tracked_cmd[@]}")
    fi

    # Start usage tracking
    track_usage "start" "$usage_file" "$iteration" "$role" "$repo" "$runner_type"
  fi

  local status=0
  if [[ "${timeout_seconds:-0}" -gt 0 || "${inactivity_seconds:-0}" -gt 0 ]]; then
    run_command_with_timeout "$prompt_file" "$log_file" "$timeout_seconds" "$prompt_mode" "$inactivity_seconds" "${cmd[@]}"
    status=$?
  else
    set +e
    if [[ "$prompt_mode" == "stdin" ]]; then
      "${cmd[@]}" < "$prompt_file" | tee "$log_file"
    else
      "${cmd[@]}" | tee "$log_file"
    fi
    status=${PIPESTATUS[0]}
    set -e
  fi

  # End usage tracking
  if [[ "${USAGE_TRACKING_ENABLED:-1}" -eq 1 ]] && type track_usage &>/dev/null; then
    track_usage "end" "$usage_file" "$iteration" "$role" "$repo" "$runner_type"
  fi

  if [[ $status -eq 124 ]]; then
    return 124
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
