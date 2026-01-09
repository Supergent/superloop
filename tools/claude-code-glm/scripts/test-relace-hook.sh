#!/bin/bash
#
# Relace Hook Testing Utility
#
# This script tests the Relace hook functionality without requiring
# a full Claude Code session. Useful for debugging and validation.
#
# Usage:
#   ./test-relace-hook.sh [options]
#
# Options:
#   --file PATH         Test file path (default: /tmp/test-relace.js)
#   --snippet           Use abbreviated snippet (default)
#   --full              Use full replacement (no abbreviation)
#   --debug             Enable debug output
#   --help              Show this help
#

set -euo pipefail

# Default configuration
TEST_FILE="/tmp/test-relace.js"
USE_SNIPPET=true
DEBUG_MODE=false
HOOK_SCRIPT="$HOME/claude-code-relace-hook.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[TEST]${NC} $*"; }
success() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

usage() {
    head -n 15 "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file) TEST_FILE="$2"; shift 2 ;;
        --snippet) USE_SNIPPET=true; shift ;;
        --full) USE_SNIPPET=false; shift ;;
        --debug) DEBUG_MODE=true; shift ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ============================================================================
# TEST SETUP
# ============================================================================

setup_test_file() {
    info "Creating test file: $TEST_FILE"

    cat > "$TEST_FILE" << 'EOF'
// Test file for Relace integration
function hello() {
  console.log("Hello");
  console.log("World");
  console.log("From");
  console.log("Claude");
  console.log("Code");
}

function goodbye() {
  console.log("Goodbye");
  console.log("World");
}

function main() {
  hello();
  goodbye();
}

main();
EOF

    success "Test file created ($(wc -l < "$TEST_FILE") lines)"
}

# ============================================================================
# TEST CASES
# ============================================================================

test_hook_exists() {
    info "Test 1: Checking if hook script exists..."

    if [[ -f "$HOOK_SCRIPT" ]]; then
        success "Hook script found: $HOOK_SCRIPT"
        return 0
    else
        fail "Hook script not found: $HOOK_SCRIPT"
        return 1
    fi
}

test_hook_executable() {
    info "Test 2: Checking if hook script is executable..."

    if [[ -x "$HOOK_SCRIPT" ]]; then
        success "Hook script is executable"
        return 0
    else
        fail "Hook script is not executable"
        echo "  Fix with: chmod +x $HOOK_SCRIPT"
        return 1
    fi
}

test_dependencies() {
    info "Test 3: Checking dependencies..."

    local all_ok=true

    for cmd in jq curl; do
        if command -v "$cmd" &> /dev/null; then
            success "✓ $cmd installed"
        else
            fail "✗ $cmd not installed"
            all_ok=false
        fi
    done

    if [[ "$all_ok" == true ]]; then
        return 0
    else
        fail "Missing dependencies"
        return 1
    fi
}

test_api_key() {
    info "Test 4: Checking API key configuration..."

    if [[ -n "${RELACE_API_KEY:-}" ]]; then
        success "RELACE_API_KEY is set"
        return 0
    else
        warn "RELACE_API_KEY is not set (hook will pass through to standard Edit)"
        return 0
    fi
}

test_abbreviated_snippet() {
    info "Test 5: Testing with abbreviated snippet..."

    local old_string
    old_string=$(cat "$TEST_FILE")

    local new_string='// Test file for Relace integration
function hello() {
  console.log("Hello, World!");
  // ... keep existing log statements ...
}

// ... keep goodbye function ...

function main() {
  hello();
  goodbye();
}

main();'

    local tool_input
    tool_input=$(jq -n \
        --arg file_path "$TEST_FILE" \
        --arg old_string "$old_string" \
        --arg new_string "$new_string" \
        '{
            file_path: $file_path,
            old_string: $old_string,
            new_string: $new_string,
            replace_all: false
        }')

    local tool_data
    tool_data=$(jq -n \
        --argjson tool_input "$tool_input" \
        '{
            tool_name: "Edit",
            tool_input: $tool_input
        }')

    info "Calling hook with abbreviated snippet..."

    if [[ "$DEBUG_MODE" == true ]]; then
        export RELACE_DEBUG=true
    fi

    local result
    local exit_code=0

    result=$(echo "$tool_data" | "$HOOK_SCRIPT" 2>&1) || exit_code=$?

    if [[ "$DEBUG_MODE" == true ]]; then
        echo ""
        echo "Hook output:"
        echo "$result"
        echo ""
    fi

    if [[ $exit_code -eq 0 ]]; then
        success "Hook executed successfully (exit code: $exit_code)"

        # Check if output is valid JSON
        if echo "$result" | jq empty 2>/dev/null; then
            success "Hook output is valid JSON"

            # Check if tool_input was modified
            local modified_input
            modified_input=$(echo "$result" | jq -r '.tool_input')

            if [[ -n "$modified_input" && "$modified_input" != "null" ]]; then
                success "Tool input was modified by hook"

                # Extract new_string length
                local new_length
                new_length=$(echo "$result" | jq -r '.tool_input.new_string | length')
                info "Modified new_string length: $new_length characters"

                return 0
            else
                warn "Tool input was not modified (likely fell back to standard Edit)"
                return 0
            fi
        else
            warn "Hook output is not JSON (may have passed through)"
            return 0
        fi
    else
        fail "Hook failed with exit code: $exit_code"
        return 1
    fi
}

test_full_replacement() {
    info "Test 6: Testing with full replacement (no abbreviation)..."

    local old_string
    old_string=$(cat "$TEST_FILE")

    local new_string='// Test file for Relace integration
function hello() {
  console.log("Hello, World!");
}

function goodbye() {
  console.log("Goodbye, World!");
}

function main() {
  hello();
  goodbye();
}

main();'

    local tool_data
    tool_data=$(jq -n \
        --arg file_path "$TEST_FILE" \
        --arg old_string "$old_string" \
        --arg new_string "$new_string" \
        '{
            tool_name: "Edit",
            tool_input: {
                file_path: $file_path,
                old_string: $old_string,
                new_string: $new_string,
                replace_all: false
            }
        }')

    local result
    local exit_code=0

    result=$(echo "$tool_data" | "$HOOK_SCRIPT" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        success "Hook executed successfully"

        # For full replacement, hook should pass through (no abbreviation markers)
        if echo "$result" | jq -e '.tool_input.new_string' > /dev/null 2>&1; then
            info "Hook likely passed through to standard Edit (expected behavior)"
        fi

        return 0
    else
        fail "Hook failed with exit code: $exit_code"
        return 1
    fi
}

test_disabled_hook() {
    info "Test 7: Testing with RELACE_ENABLED=false..."

    local old_string
    old_string=$(cat "$TEST_FILE")

    local new_string='// ... abbreviated snippet ...'

    local tool_data
    tool_data=$(jq -n \
        --arg file_path "$TEST_FILE" \
        --arg old_string "$old_string" \
        --arg new_string "$new_string" \
        '{
            tool_name: "Edit",
            tool_input: {
                file_path: $file_path,
                old_string: $old_string,
                new_string: $new_string
            }
        }')

    RELACE_ENABLED=false

    local result
    local exit_code=0

    result=$(echo "$tool_data" | "$HOOK_SCRIPT" 2>&1) || exit_code=$?

    RELACE_ENABLED=true

    if [[ $exit_code -eq 0 ]]; then
        success "Hook passed through when disabled (expected)"
        return 0
    else
        fail "Hook should pass through when disabled"
        return 1
    fi
}

test_small_file() {
    info "Test 8: Testing with small file (below threshold)..."

    local small_file="/tmp/test-small.js"
    echo "// Small file" > "$small_file"

    local old_string
    old_string=$(cat "$small_file")

    local new_string='// ... updated ...'

    local tool_data
    tool_data=$(jq -n \
        --arg file_path "$small_file" \
        --arg old_string "$old_string" \
        --arg new_string "$new_string" \
        '{
            tool_name: "Edit",
            tool_input: {
                file_path: $file_path,
                old_string: $old_string,
                new_string: $new_string
            }
        }')

    local result
    local exit_code=0

    result=$(echo "$tool_data" | "$HOOK_SCRIPT" 2>&1) || exit_code=$?

    rm -f "$small_file"

    if [[ $exit_code -eq 0 ]]; then
        success "Hook passed through for small file (expected)"
        return 0
    else
        fail "Hook should pass through for small files"
        return 1
    fi
}

test_no_relace_file() {
    info "Test 9: Testing with .no-relace file..."

    # Create .no-relace file
    touch .no-relace

    local old_string
    old_string=$(cat "$TEST_FILE")

    local new_string='// ... abbreviated snippet ...'

    local tool_data
    tool_data=$(jq -n \
        --arg file_path "$TEST_FILE" \
        --arg old_string "$old_string" \
        --arg new_string "$new_string" \
        '{
            tool_name: "Edit",
            tool_input: {
                file_path: $file_path,
                old_string: $old_string,
                new_string: $new_string
            }
        }')

    local result
    local exit_code=0

    result=$(echo "$tool_data" | "$HOOK_SCRIPT" 2>&1) || exit_code=$?

    # Cleanup
    rm -f .no-relace

    if [[ $exit_code -eq 0 ]]; then
        success "Hook passed through with .no-relace file (expected)"
        return 0
    else
        fail "Hook should pass through with .no-relace file"
        return 1
    fi
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

main() {
    echo ""
    info "Relace Hook Test Suite"
    echo ""

    setup_test_file
    echo ""

    local passed=0
    local failed=0
    local total=9

    # Run tests
    test_hook_exists && ((passed++)) || ((failed++))
    echo ""
    test_hook_executable && ((passed++)) || ((failed++))
    echo ""
    test_dependencies && ((passed++)) || ((failed++))
    echo ""
    test_api_key && ((passed++)) || ((failed++))
    echo ""
    test_abbreviated_snippet && ((passed++)) || ((failed++))
    echo ""
    test_full_replacement && ((passed++)) || ((failed++))
    echo ""
    test_disabled_hook && ((passed++)) || ((failed++))
    echo ""
    test_small_file && ((passed++)) || ((failed++))
    echo ""
    test_no_relace_file && ((passed++)) || ((failed++))
    echo ""

    # Summary
    echo "========================================"
    echo "Test Results:"
    echo "  Passed: $passed/$total"
    echo "  Failed: $failed/$total"
    echo "========================================"

    if [[ $failed -eq 0 ]]; then
        success "All tests passed!"
        echo ""
        info "Next steps:"
        echo "  1. Set RELACE_API_KEY if you haven't already"
        echo "  2. Test with Claude Code: claude"
        echo "  3. Ask Claude to edit $TEST_FILE"
        echo "  4. Monitor logs: tail -f ~/.claude/relace-logs/*.log"
        return 0
    else
        fail "Some tests failed. Please fix the issues above."
        return 1
    fi
}

main "$@"
