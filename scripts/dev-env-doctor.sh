#!/usr/bin/env bash
set -euo pipefail

status=0

info() { printf '[info] %s\n' "$*"; }
ok() { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*"; }
fail() { printf '[fail] %s\n' "$*"; status=1; }

check_required() {
  local cmd="$1"
  local label="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local version
    version="$($cmd --version 2>/dev/null | head -n 1 || true)"
    ok "$label detected${version:+: $version}"
  else
    fail "$label is missing ($cmd)"
  fi
}

check_optional() {
  local cmd="$1"
  local label="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local version
    version="$($cmd --version 2>/dev/null | head -n 1 || true)"
    ok "$label detected${version:+: $version}"
  else
    warn "$label not found ($cmd)"
  fi
}

info "Checking Superloop local dev environment..."
check_required bash "bash"
check_required git "git"
check_required jq "jq"
check_required bun "bun"
check_required node "node"
check_required python3 "python3"
check_optional bats "bats"
check_required direnv "direnv"
check_required devenv "devenv"

if [[ "${PORTLESS:-1}" == "0" ]]; then
  warn "PORTLESS=0 set; skipping portless requirement"
else
  check_required portless "portless"
fi

if [[ -f .envrc ]]; then
  ok ".envrc present"
else
  fail ".envrc is missing"
fi

if [[ "$status" -ne 0 ]]; then
  printf '\nSuperloop local stack check failed.\n' >&2
  exit 1
fi

printf '\nAll required checks passed.\n'
printf 'Next: direnv allow && devenv shell\n'
