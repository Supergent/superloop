#!/usr/bin/env bash
set -euo pipefail

# Deterministic subcall response used by canary CI and tests.
cat >/dev/null
echo "mock-subcall-ok"
