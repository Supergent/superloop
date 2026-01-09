#!/bin/bash
#
# Relace Integration Installer for Claude Code GLM
#
# This script installs and configures the Relace instant apply integration
# for your Claude Code GLM VMs (Cerebras and/or Z.ai).
#
# Usage:
#   ./install-relace.sh [options]
#
# Options:
#   --api-key KEY       Set Relace API key
#   --vm cerebras|zai   Install only for specific VM (default: current)
#   --no-backup         Skip backup of existing settings
#   --debug             Enable debug mode
#   --help              Show this help message
#
# The script will:
#   1. Install dependencies (jq, curl)
#   2. Copy hook script to ~/claude-code-relace-hook.sh
#   3. Configure ~/.claude/settings.json with hooks
#   4. Set up environment variables in ~/.bashrc
#   5. Create helper aliases for toggling Relace
#   6. Run validation tests
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/relace-hook.sh"
TARGET_HOOK="$HOME/claude-code-relace-hook.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
BASHRC="$HOME/.bashrc"

# Options
RELACE_API_KEY=""
TARGET_VM="current"
DO_BACKUP=true
DEBUG_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

fatal() {
    error "$*"
    exit 1
}

usage() {
    head -n 20 "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --api-key)
                RELACE_API_KEY="$2"
                shift 2
                ;;
            --vm)
                TARGET_VM="$2"
                shift 2
                ;;
            --no-backup)
                DO_BACKUP=false
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# ============================================================================
# INSTALLATION STEPS
# ============================================================================

check_requirements() {
    info "Checking requirements..."

    # Check if running in a VM (optional)
    if [[ "$TARGET_VM" != "current" ]]; then
        warn "Specific VM targeting not yet implemented. Installing for current environment."
    fi

    # Check if hook script exists
    if [[ ! -f "$HOOK_SCRIPT" ]]; then
        fatal "Hook script not found: $HOOK_SCRIPT"
    fi

    success "Requirements check passed"
}

install_dependencies() {
    info "Installing dependencies..."

    local missing_deps=()

    if ! command -v jq &> /dev/null; then
        missing_deps+=(jq)
    fi

    if ! command -v curl &> /dev/null; then
        missing_deps+=(curl)
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        info "Installing missing dependencies: ${missing_deps[*]}"

        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq "${missing_deps[@]}"
        elif command -v yum &> /dev/null; then
            sudo yum install -y -q "${missing_deps[@]}"
        elif command -v brew &> /dev/null; then
            brew install "${missing_deps[@]}"
        else
            fatal "Could not determine package manager. Please install manually: ${missing_deps[*]}"
        fi

        success "Dependencies installed"
    else
        success "All dependencies already installed"
    fi
}

install_hook_script() {
    info "Installing hook script..."

    if [[ -f "$TARGET_HOOK" ]] && [[ "$DO_BACKUP" == true ]]; then
        local backup="${TARGET_HOOK}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$TARGET_HOOK" "$backup"
        warn "Existing hook script backed up to: $backup"
    fi

    cp "$HOOK_SCRIPT" "$TARGET_HOOK"
    chmod +x "$TARGET_HOOK"

    success "Hook script installed: $TARGET_HOOK"
}

configure_settings() {
    info "Configuring Claude Code settings..."

    # Ensure .claude directory exists
    mkdir -p "$(dirname "$SETTINGS_FILE")"

    # Backup existing settings
    if [[ -f "$SETTINGS_FILE" ]] && [[ "$DO_BACKUP" == true ]]; then
        local backup="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS_FILE" "$backup"
        warn "Existing settings backed up to: $backup"
    fi

    # Create or update settings.json
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        # Create new settings file
        cat > "$SETTINGS_FILE" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "~/claude-code-relace-hook.sh",
            "timeout": 60
          }
        ]
      }
    ]
  },
  "systemPrompt": {
    "append": "# Relace Instant Apply - Edit Formatting\n\nWhen using the Edit tool, format your edits as abbreviated snippets to optimize for speed and cost:\n\n**Rules for Edit Snippets:**\n- Abbreviate sections that remain unchanged with comments like `// ... rest of code ...`, `// ... keep existing code ...`, `// ... code remains the same`\n- Be precise with comment placement - a lightweight model will use your context clues to merge accurately\n- Include concise hints in comments about retained code: `// ... keep calculateTotalFunction ...`\n- For deletions, provide context:\n  - Option 1: Show adjacent blocks without the deleted section\n  - Option 2: Use explicit removal comment: `// ... remove BlockName ...`\n- Use language-appropriate comment syntax (// for JS/TS, # for Python, etc.)\n- Preserve exact indentation showing final code structure\n- Include only lines that will appear in final merged code\n- Be length-efficient without omitting key context\n\n**Example (TypeScript):**\n```typescript\n// ... keep existing imports and setup ...\n\nfunction processData(data: any) {\n  // NEW: Add validation\n  if (!data || !data.id) {\n    throw new Error('Invalid data');\n  }\n  \n  // ... keep existing processing logic ...\n  \n  return result;\n}\n\n// ... rest of file remains the same ...\n```\n\nThe Edit tool will automatically merge your snippet with the original file."
  }
}
EOF
        success "Created new settings file: $SETTINGS_FILE"
    else
        # Update existing settings file
        local temp_file=$(mktemp)

        # Check if hooks already exist
        if jq -e '.hooks.PreToolUse' "$SETTINGS_FILE" > /dev/null 2>&1; then
            # Hooks exist, check if Relace hook already configured
            if jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit") | .hooks[] | select(.command | contains("relace"))' "$SETTINGS_FILE" > /dev/null 2>&1; then
                warn "Relace hook already configured in settings.json. Skipping."
            else
                # Add Relace hook to existing PreToolUse hooks
                jq '.hooks.PreToolUse += [{
                    "matcher": "Edit",
                    "hooks": [{
                        "type": "command",
                        "command": "~/claude-code-relace-hook.sh",
                        "timeout": 60
                    }]
                }]' "$SETTINGS_FILE" > "$temp_file"
                mv "$temp_file" "$SETTINGS_FILE"
                success "Added Relace hook to existing hooks configuration"
            fi
        else
            # No hooks exist, create hooks section
            jq '.hooks = {
                "PreToolUse": [{
                    "matcher": "Edit",
                    "hooks": [{
                        "type": "command",
                        "command": "~/claude-code-relace-hook.sh",
                        "timeout": 60
                    }]
                }]
            }' "$SETTINGS_FILE" > "$temp_file"
            mv "$temp_file" "$SETTINGS_FILE"
            success "Created hooks configuration with Relace hook"
        fi

        # Add system prompt if not already present
        if ! jq -e '.systemPrompt.append | contains("Relace Instant Apply")' "$SETTINGS_FILE" > /dev/null 2>&1; then
            local prompt_text="# Relace Instant Apply - Edit Formatting\n\nWhen using the Edit tool, format your edits as abbreviated snippets to optimize for speed and cost:\n\n**Rules for Edit Snippets:**\n- Abbreviate sections that remain unchanged with comments like \`// ... rest of code ...\`, \`// ... keep existing code ...\`, \`// ... code remains the same\`\n- Be precise with comment placement - a lightweight model will use your context clues to merge accurately\n- Include concise hints in comments about retained code: \`// ... keep calculateTotalFunction ...\`\n- For deletions, provide context:\n  - Option 1: Show adjacent blocks without the deleted section\n  - Option 2: Use explicit removal comment: \`// ... remove BlockName ...\`\n- Use language-appropriate comment syntax (// for JS/TS, # for Python, etc.)\n- Preserve exact indentation showing final code structure\n- Include only lines that will appear in final merged code\n- Be length-efficient without omitting key context\n\nThe Edit tool will automatically merge your snippet with the original file."

            if jq -e '.systemPrompt.append' "$SETTINGS_FILE" > /dev/null 2>&1; then
                # Append to existing system prompt
                jq --arg prompt "\n\n$prompt_text" '.systemPrompt.append += $prompt' "$SETTINGS_FILE" > "$temp_file"
                mv "$temp_file" "$SETTINGS_FILE"
                success "Added Relace system prompt to existing append"
            else
                # Create new system prompt append
                jq --arg prompt "$prompt_text" '.systemPrompt = {append: $prompt}' "$SETTINGS_FILE" > "$temp_file"
                mv "$temp_file" "$SETTINGS_FILE"
                success "Created system prompt with Relace instructions"
            fi
        else
            warn "Relace system prompt already present. Skipping."
        fi
    fi
}

configure_environment() {
    info "Configuring environment variables..."

    local env_config="
# ============================================================================
# Relace Instant Apply Configuration
# ============================================================================

# Relace API Key (get from https://app.relace.ai/settings/api-keys)
export RELACE_API_KEY=\"${RELACE_API_KEY:-your-relace-api-key-here}\"

# Relace Toggle (set to false to disable)
export RELACE_ENABLED=true

# Relace Configuration
export RELACE_MIN_FILE_SIZE=100       # Minimum file size in lines
export RELACE_TIMEOUT=30              # API timeout in seconds
export RELACE_DEBUG=false             # Enable debug logging
export RELACE_COST_TRACKING=true      # Enable cost tracking

# Helper aliases for quick toggling
alias claude-relace-on='export RELACE_ENABLED=true && echo \"Relace enabled\"'
alias claude-relace-off='export RELACE_ENABLED=false && echo \"Relace disabled\"'
alias claude-relace-status='echo \"Relace status: \$RELACE_ENABLED\"'
alias claude-relace-debug-on='export RELACE_DEBUG=true && echo \"Relace debug enabled\"'
alias claude-relace-debug-off='export RELACE_DEBUG=false && echo \"Relace debug disabled\"'
alias claude-relace-logs='tail -f ~/.claude/relace-logs/*.log'
alias claude-relace-costs='cat ~/.claude/relace-logs/costs.csv | tail -20'

# ============================================================================
"

    # Check if already configured
    if grep -q "Relace Instant Apply Configuration" "$BASHRC" 2>/dev/null; then
        warn "Relace configuration already present in $BASHRC. Skipping."
    else
        echo "$env_config" >> "$BASHRC"
        success "Added Relace configuration to $BASHRC"
    fi

    # Set API key if provided
    if [[ -n "$RELACE_API_KEY" ]]; then
        success "Relace API key configured"
    else
        warn "No API key provided. Please set RELACE_API_KEY in $BASHRC before using."
    fi
}

create_test_file() {
    info "Creating test file..."

    local test_file="/tmp/relace-test.js"

    cat > "$test_file" << 'EOF'
// Test file for Relace integration
function calculateSum(a, b) {
  return a + b;
}

function calculateProduct(a, b) {
  return a * b;
}

function calculateDifference(a, b) {
  return a - b;
}

function main() {
  console.log("Sum:", calculateSum(5, 3));
  console.log("Product:", calculateProduct(5, 3));
  console.log("Difference:", calculateDifference(5, 3));
}

main();
EOF

    success "Test file created: $test_file"
    echo "$test_file"
}

run_validation() {
    info "Running validation tests..."

    # Test 1: Check hook script is executable
    if [[ -x "$TARGET_HOOK" ]]; then
        success "✓ Hook script is executable"
    else
        error "✗ Hook script is not executable"
        return 1
    fi

    # Test 2: Check settings.json is valid JSON
    if jq empty "$SETTINGS_FILE" 2>/dev/null; then
        success "✓ settings.json is valid JSON"
    else
        error "✗ settings.json is invalid JSON"
        return 1
    fi

    # Test 3: Check hook is registered
    if jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit")' "$SETTINGS_FILE" > /dev/null 2>&1; then
        success "✓ Relace hook is registered"
    else
        error "✗ Relace hook is not registered"
        return 1
    fi

    # Test 4: Check dependencies
    local all_deps_ok=true
    for cmd in jq curl; do
        if command -v "$cmd" &> /dev/null; then
            success "✓ $cmd is installed"
        else
            error "✗ $cmd is not installed"
            all_deps_ok=false
        fi
    done

    if [[ "$all_deps_ok" == false ]]; then
        return 1
    fi

    success "All validation tests passed!"
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    info "Relace Integration Installer for Claude Code GLM"
    echo ""

    parse_args "$@"

    check_requirements
    install_dependencies
    install_hook_script
    configure_settings
    configure_environment

    echo ""
    info "Creating test file for validation..."
    local test_file
    test_file=$(create_test_file)

    echo ""
    run_validation

    echo ""
    success "Installation complete!"
    echo ""
    info "Next steps:"
    echo "  1. Set your Relace API key:"
    echo "     export RELACE_API_KEY=\"your-key-here\""
    echo "     (Get a key from: https://app.relace.ai/settings/api-keys)"
    echo ""
    echo "  2. Reload your shell configuration:"
    echo "     source ~/.bashrc"
    echo ""
    echo "  3. Test the integration:"
    echo "     claude"
    echo "     # Then ask Claude to edit the test file at: $test_file"
    echo ""
    echo "  4. Toggle Relace on/off:"
    echo "     claude-relace-off  # Disable"
    echo "     claude-relace-on   # Enable"
    echo "     claude-relace-status  # Check status"
    echo ""
    echo "  5. View logs:"
    echo "     claude-relace-logs    # Watch logs in real-time"
    echo "     claude-relace-costs   # View cost tracking"
    echo ""
    echo "  6. Per-project disable:"
    echo "     cd /path/to/project && touch .no-relace"
    echo ""
    info "Documentation: ${SCRIPT_DIR}/../RELACE_INTEGRATION.md"
    echo ""
}

main "$@"
