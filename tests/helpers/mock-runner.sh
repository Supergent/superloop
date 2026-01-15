#!/bin/bash
# Mock runner that simulates Claude/Codex without API calls
# Usage: mock-runner.sh <mode> <output_file> [promise_text]
#
# Modes:
#   success           - Completes successfully with SUPERLOOP_COMPLETE promise
#   failure           - Exits with error code 1
#   timeout           - Hangs for a long time (simulates timeout)
#   rate-limit        - Returns rate limit error (429)
#   success-promise   - Completes with custom promise text
#   no-promise        - Completes without promise tag
#   partial-output    - Writes partial output then exits
#   thinking-tokens   - Outputs response with thinking tokens
#   cached-tokens     - Outputs response with cached tokens

set -euo pipefail

MODE="${1:-success}"
OUTPUT_FILE="${2:-/dev/stdout}"
PROMISE_TEXT="${3:-SUPERLOOP_COMPLETE}"

case "$MODE" in
  success)
    cat > "$OUTPUT_FILE" << 'EOF'
# Implementation Plan

I will implement the requested feature by following these steps:

1. Create the new functionality
2. Add tests
3. Update documentation

<promise>SUPERLOOP_COMPLETE</promise>

The implementation is complete and ready for review.
EOF
    exit 0
    ;;

  success-promise)
    cat > "$OUTPUT_FILE" <<EOF
# Implementation Update

I have made progress on the task.

<promise>$PROMISE_TEXT</promise>

More work may be needed.
EOF
    exit 0
    ;;

  no-promise)
    cat > "$OUTPUT_FILE" << 'EOF'
# Work in Progress

I am working on the implementation.

The feature has been partially completed.
EOF
    exit 0
    ;;

  failure)
    echo "Error: Mock runner failed" > "$OUTPUT_FILE"
    exit 1
    ;;

  timeout)
    # Simulate a long-running process
    sleep 3600
    ;;

  rate-limit)
    # Simulate rate limit error (like Claude API)
    cat >&2 << 'EOF'
{
  "error": {
    "type": "rate_limit_error",
    "message": "Rate limit exceeded"
  }
}
EOF
    exit 1
    ;;

  partial-output)
    cat > "$OUTPUT_FILE" << 'EOF'
# Partial Implementation

I started working on this but
EOF
    exit 1
    ;;

  thinking-tokens)
    # Mock Claude session with thinking tokens
    cat > "$OUTPUT_FILE" << 'EOF'
<think>
This is internal reasoning that uses thinking tokens.
I need to analyze the problem carefully.
</think>

# Implementation

The solution is ready.

<promise>SUPERLOOP_COMPLETE</promise>
EOF
    exit 0
    ;;

  cached-tokens)
    # This doesn't affect output, but simulates cached input tokens
    cat > "$OUTPUT_FILE" << 'EOF'
# Implementation

Using cached context from previous request.

<promise>SUPERLOOP_COMPLETE</promise>
EOF
    exit 0
    ;;

  *)
    echo "Unknown mode: $MODE" >&2
    echo "Valid modes: success, failure, timeout, rate-limit, success-promise, no-promise, partial-output, thinking-tokens, cached-tokens" >&2
    exit 1
    ;;
esac
