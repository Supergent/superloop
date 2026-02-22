#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-service-client.sh --method <GET|POST> --base-url <url> --path <path> [options]

Options:
  --token <token>                Optional auth token (sent as Bearer and X-Ops-Token)
  --body-file <path>             JSON request body file for POST
  --retry-attempts <n>           Retry attempts on transient failures (default: 3)
  --retry-backoff-seconds <n>    Base backoff seconds between retries (default: 1)
  --connect-timeout-seconds <n>  Curl connect timeout (default: 5)
  --max-time-seconds <n>         Curl max transfer time (default: 30)
  --help                         Show this help message
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "missing required command: $cmd"
  fi
}

method=""
base_url=""
path=""
auth_value=""
body_file=""
retry_attempts="3"
retry_backoff_seconds="1"
connect_timeout_seconds="5"
max_time_seconds="30"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)
      method="${2:-}"
      shift 2
      ;;
    --base-url)
      base_url="${2:-}"
      shift 2
      ;;
    --path)
      path="${2:-}"
      shift 2
      ;;
    --token)
      auth_value="${2:-}"
      shift 2
      ;;
    --body-file)
      body_file="${2:-}"
      shift 2
      ;;
    --retry-attempts)
      retry_attempts="${2:-}"
      shift 2
      ;;
    --retry-backoff-seconds)
      retry_backoff_seconds="${2:-}"
      shift 2
      ;;
    --connect-timeout-seconds)
      connect_timeout_seconds="${2:-}"
      shift 2
      ;;
    --max-time-seconds)
      max_time_seconds="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

need_cmd curl

if [[ -z "$method" ]]; then
  die "--method is required"
fi
case "$method" in
  GET|POST)
    ;;
  *)
    die "--method must be GET or POST"
    ;;
esac
if [[ -z "$base_url" ]]; then
  die "--base-url is required"
fi
if [[ -z "$path" ]]; then
  die "--path is required"
fi
if [[ ! "$retry_attempts" =~ ^[0-9]+$ || "$retry_attempts" -lt 1 ]]; then
  die "--retry-attempts must be an integer >= 1"
fi
if [[ ! "$retry_backoff_seconds" =~ ^[0-9]+$ || ! "$connect_timeout_seconds" =~ ^[0-9]+$ || ! "$max_time_seconds" =~ ^[0-9]+$ ]]; then
  die "timeout/backoff values must be non-negative integers"
fi
if [[ "$method" == "POST" && -z "$body_file" ]]; then
  die "--body-file is required for POST"
fi
if [[ -n "$body_file" && ! -f "$body_file" ]]; then
  die "body file not found: $body_file"
fi

url="${base_url%/}${path}"

is_transient_code() {
  local code="$1"
  case "$code" in
    408|409|425|429|500|502|503|504)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

attempt=1
while (( attempt <= retry_attempts )); do
  body_tmp="$(mktemp)"

  curl_args=(
    -sS
    -X "$method"
    --connect-timeout "$connect_timeout_seconds"
    --max-time "$max_time_seconds"
    -H "Accept: application/json"
    -w "%{http_code}"
    -o "$body_tmp"
  )

  if [[ -n "$auth_value" ]]; then
    curl_args+=(
      -H "Authorization: Bearer $auth_value"
      -H "X-Ops-Token: $auth_value"
    )
  fi

  if [[ "$method" == "POST" ]]; then
    curl_args+=(
      -H "Content-Type: application/json"
      --data-binary "@$body_file"
    )
  fi

  http_code="000"
  if http_code=$(curl "${curl_args[@]}" "$url"); then
    :
  else
    http_code="000"
  fi

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    cat "$body_tmp"
    rm -f "$body_tmp"
    exit 0
  fi

  if (( attempt < retry_attempts )) && is_transient_code "$http_code"; then
    sleep_seconds=$(( retry_backoff_seconds * attempt ))
    if (( sleep_seconds > 0 )); then
      sleep "$sleep_seconds"
    fi
    rm -f "$body_tmp"
    attempt=$((attempt + 1))
    continue
  fi

  response_excerpt=$(tail -n 40 "$body_tmp" | sed 's/\r$//' || true)
  rm -f "$body_tmp"
  die "service request failed (method=$method url=$url code=$http_code): $response_excerpt"
done

die "service request failed after retries"
