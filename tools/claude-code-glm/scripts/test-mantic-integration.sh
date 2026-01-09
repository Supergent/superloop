#!/bin/bash
#
# Mantic Integration Test Script
# Version: 1.0.0
#
# Comprehensive test suite for Mantic-Grep hook integration
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
HOOK_SCRIPT="$HOME/mantic-grep-hook.sh"

print_header() {
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}\n"
}

print_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Test helper function
test_hook() {
    local test_name=$1
    local input_json=$2
    local expected_behavior=$3

    print_test "$test_name"

    local output
    output=$(echo "$input_json" | "$HOOK_SCRIPT" 2>&1) || {
        print_fail "$test_name - Hook execution failed"
        return 1
    }

    case "$expected_behavior" in
        "uses_mantic")
            if echo "$output" | jq -e '.tool_input._mantic_enabled == true' > /dev/null 2>&1; then
                print_pass "$test_name - Mantic was used"
            else
                print_fail "$test_name - Mantic was not used when expected"
                return 1
            fi
            ;;
        "skips_mantic")
            if echo "$output" | jq -e '.tool_input._mantic_enabled' > /dev/null 2>&1; then
                print_fail "$test_name - Mantic was used when it should have been skipped"
                return 1
            else
                print_pass "$test_name - Mantic was correctly skipped"
            fi
            ;;
        "passes_through")
            if [[ "$output" == "$input_json" ]]; then
                print_pass "$test_name - Input passed through unchanged"
            else
                print_fail "$test_name - Input was modified unexpectedly"
                return 1
            fi
            ;;
    esac

    return 0
}

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

print_header "Prerequisite Checks"

# Check hook script exists
if [[ ! -f "$HOOK_SCRIPT" ]]; then
    print_fail "Hook script not found: $HOOK_SCRIPT"
    exit 1
fi
print_pass "Hook script found"

# Check hook is executable
if [[ ! -x "$HOOK_SCRIPT" ]]; then
    print_fail "Hook script is not executable"
    exit 1
fi
print_pass "Hook script is executable"

# Check for jq
if ! command -v jq &> /dev/null; then
    print_fail "jq is required but not installed"
    exit 1
fi
print_pass "jq is available"

# Check for npx/mantic
if ! command -v npx &> /dev/null; then
    print_fail "npx is required but not installed"
    exit 1
fi
print_pass "npx is available"

# Test mantic.sh accessibility
print_info "Testing Mantic accessibility..."
if npx -y mantic.sh "test" --files --limit 1 &>/dev/null; then
    print_pass "Mantic is accessible via npx"
else
    print_fail "Cannot access mantic.sh via npx"
    exit 1
fi

# ============================================================================
# UNIT TESTS: Hook Decision Logic
# ============================================================================

print_header "Unit Tests: Decision Logic"

# Export for hook
export MANTIC_ENABLED=true
export MANTIC_DEBUG=false

# Test 1: Semantic pattern with file discovery mode - SHOULD USE MANTIC
test_hook "Semantic file discovery" \
    '{"tool_name":"Grep","tool_input":{"pattern":"authentication","output_mode":"files_with_matches"}}' \
    "uses_mantic"

# Test 2: Regex pattern - SHOULD SKIP MANTIC
test_hook "Regex pattern detection" \
    '{"tool_name":"Grep","tool_input":{"pattern":"function\\s+\\w+","output_mode":"files_with_matches"}}' \
    "skips_mantic"

# Test 3: Content mode - SHOULD SKIP MANTIC
test_hook "Content search mode" \
    '{"tool_name":"Grep","tool_input":{"pattern":"TODO","output_mode":"content"}}' \
    "skips_mantic"

# Test 4: Specific path set - SHOULD SKIP MANTIC
test_hook "Specific path set" \
    '{"tool_name":"Grep","tool_input":{"pattern":"auth","output_mode":"files_with_matches","path":"src/specific"}}' \
    "skips_mantic"

# Test 5: Filename pattern - SHOULD SKIP MANTIC
test_hook "Filename pattern" \
    '{"tool_name":"Grep","tool_input":{"pattern":"auth.service.ts","output_mode":"files_with_matches"}}' \
    "skips_mantic"

# Test 6: Non-Grep tool - SHOULD PASS THROUGH
test_hook "Non-Grep tool passthrough" \
    '{"tool_name":"Read","tool_input":{"file_path":"test.ts"}}' \
    "passes_through"

# Test 7: Multi-word semantic pattern - SHOULD USE MANTIC
test_hook "Multi-word semantic query" \
    '{"tool_name":"Grep","tool_input":{"pattern":"payment stripe integration","output_mode":"files_with_matches"}}' \
    "uses_mantic"

# Test 8: Pattern with underscores/hyphens - SHOULD USE MANTIC
test_hook "Pattern with separators" \
    '{"tool_name":"Grep","tool_input":{"pattern":"user_auth","output_mode":"files_with_matches"}}' \
    "uses_mantic"

# ============================================================================
# INTEGRATION TESTS: Full Workflow
# ============================================================================

print_header "Integration Tests: Full Workflow"

# Test 9: End-to-end Mantic call
print_test "End-to-end Mantic integration"
INPUT='{"tool_name":"Grep","tool_input":{"pattern":"authentication","output_mode":"files_with_matches"}}'
OUTPUT=$(echo "$INPUT" | "$HOOK_SCRIPT" 2>&1)

if echo "$OUTPUT" | jq -e '.tool_input._mantic_paths' > /dev/null 2>&1; then
    MANTIC_PATHS=$(echo "$OUTPUT" | jq -r '.tool_input._mantic_paths | length')
    print_pass "Mantic returned $MANTIC_PATHS file paths"
else
    print_fail "Mantic did not return file paths"
fi

# Test 10: Performance check
print_test "Performance test (Mantic speed)"
START=$(date +%s%N)
npx -y mantic.sh "authentication" --files --limit 20 > /dev/null 2>&1
END=$(date +%s%N)
DURATION_MS=$(( (END - START) / 1000000 ))

if [[ $DURATION_MS -lt 5000 ]]; then
    print_pass "Mantic completed in ${DURATION_MS}ms (< 5s threshold)"
else
    print_fail "Mantic took ${DURATION_MS}ms (> 5s threshold)"
fi

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

print_header "Configuration Tests"

# Test 11: Disable via environment variable
print_test "Global disable via MANTIC_ENABLED"
export MANTIC_ENABLED=false
OUTPUT=$(echo '{"tool_name":"Grep","tool_input":{"pattern":"auth","output_mode":"files_with_matches"}}' | "$HOOK_SCRIPT" 2>&1)
if ! echo "$OUTPUT" | jq -e '.tool_input._mantic_enabled' > /dev/null 2>&1; then
    print_pass "Mantic correctly disabled via MANTIC_ENABLED=false"
else
    print_fail "Mantic was not disabled by MANTIC_ENABLED=false"
fi
export MANTIC_ENABLED=true

# Test 12: Project-level disable
print_test "Project-level disable via .no-mantic"
touch .no-mantic
OUTPUT=$(echo '{"tool_name":"Grep","tool_input":{"pattern":"auth","output_mode":"files_with_matches"}}' | "$HOOK_SCRIPT" 2>&1)
if ! echo "$OUTPUT" | jq -e '.tool_input._mantic_enabled' > /dev/null 2>&1; then
    print_pass "Mantic correctly disabled by .no-mantic file"
else
    print_fail "Mantic was not disabled by .no-mantic file"
fi
rm -f .no-mantic

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

print_header "Error Handling Tests"

# Test 13: Graceful fallback when Mantic fails
print_test "Graceful fallback on Mantic failure"
# Temporarily break Mantic by using invalid pattern
INPUT='{"tool_name":"Grep","tool_input":{"pattern":"auth","output_mode":"files_with_matches"}}'
export PATH="/tmp/invalid:$PATH"  # Temporarily break path
OUTPUT=$(echo "$INPUT" | "$HOOK_SCRIPT" 2>&1 || true)
export PATH="${PATH#/tmp/invalid:}"  # Restore path

# Should still return valid JSON (fallback)
if echo "$OUTPUT" | jq empty 2>/dev/null; then
    print_pass "Hook gracefully fell back to standard Grep on error"
else
    print_fail "Hook did not handle Mantic failure gracefully"
fi

# Test 14: Invalid JSON input
print_test "Invalid JSON handling"
OUTPUT=$(echo "invalid json" | "$HOOK_SCRIPT" 2>&1 || true)
if [[ $? -eq 0 ]]; then
    print_pass "Hook handled invalid input without crashing"
else
    print_fail "Hook crashed on invalid input"
fi

# ============================================================================
# SETTINGS VALIDATION
# ============================================================================

print_header "Settings Validation"

SETTINGS_FILE="$HOME/.claude/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    # Test 15: Valid JSON
    print_test "settings.json is valid JSON"
    if jq empty "$SETTINGS_FILE" 2>/dev/null; then
        print_pass "settings.json is valid JSON"
    else
        print_fail "settings.json is not valid JSON"
    fi

    # Test 16: Hook configured
    print_test "Hook is configured in settings.json"
    if jq -e '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS_FILE" > /dev/null 2>&1; then
        CONFIGURED_HOOK=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS_FILE")
        HOOK_MATCHER=$(jq -r '.hooks.PreToolUse[0].matcher.tools[0]' "$SETTINGS_FILE")
        print_pass "PreToolUse hook configured: $CONFIGURED_HOOK (matcher: $HOOK_MATCHER)"
    else
        print_fail "PreToolUse hook not configured in new format in settings.json"
    fi

    # Test 17: System prompt configured
    print_test "System prompt includes Mantic documentation"
    if jq -e '.systemPrompt.append' "$SETTINGS_FILE" | grep -q "Mantic" 2>/dev/null; then
        print_pass "System prompt includes Mantic documentation"
    else
        print_fail "System prompt does not mention Mantic"
    fi
else
    print_info "settings.json not found - skipping settings validation"
fi

# ============================================================================
# RESULTS SUMMARY
# ============================================================================

print_header "Test Results Summary"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
PASS_RATE=0
if [[ $TOTAL_TESTS -gt 0 ]]; then
    PASS_RATE=$((TESTS_PASSED * 100 / TOTAL_TESTS))
fi

echo -e "${BLUE}Total Tests:${NC} $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo -e "${BLUE}Pass Rate:${NC} ${PASS_RATE}%"

echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                        ║${NC}"
    echo -e "${GREEN}║   ✓ ALL TESTS PASSED!                  ║${NC}"
    echo -e "${GREEN}║                                        ║${NC}"
    echo -e "${GREEN}║   Mantic integration is ready to use!  ║${NC}"
    echo -e "${GREEN}║                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Start Claude Code: ${YELLOW}claude${NC}"
    echo "  2. Try a semantic search: ${YELLOW}\"Find authentication code\"${NC}"
    echo "  3. Check metrics: ${YELLOW}cat ~/.claude/mantic-logs/metrics.csv${NC}"
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}║   ✗ SOME TESTS FAILED                  ║${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}║   Please review the failures above     ║${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Troubleshooting:${NC}"
    echo "  - Check logs: ${YELLOW}~/.claude/mantic-logs/${NC}"
    echo "  - Enable debug: ${YELLOW}export MANTIC_DEBUG=true${NC}"
    echo "  - Review docs: ${YELLOW}tools/claude-code-glm/MANTIC_INTEGRATION.md${NC}"
    exit 1
fi
