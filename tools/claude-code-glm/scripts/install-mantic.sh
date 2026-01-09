#!/bin/bash
#
# Mantic Integration Setup Script for Claude Code GLM
# Version: 1.0.0
#
# This script installs and configures Mantic semantic search integration
# for Claude Code's Grep tool, enabling faster and more accurate file discovery.
#
# What it does:
# 1. Installs mantic.sh via npm (if not already installed)
# 2. Copies hook script to ~/mantic-grep-hook.sh
# 3. Configures Claude Code settings.json with hook and system prompt
# 4. Tests the integration
# 5. Provides usage instructions
#
# Usage:
#   ./install-mantic.sh [OPTIONS]
#
# Options:
#   --skip-test         Skip integration test
#   --no-backup         Don't backup existing settings.json
#   --debug             Enable debug mode
#   --help              Show this help message
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/mantic-grep-hook.sh"
SYSTEM_PROMPT="${SCRIPT_DIR}/mantic-system-prompt.md"
TARGET_HOOK="$HOME/mantic-grep-hook.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_DIR="$HOME/.claude"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
SKIP_TEST=false
NO_BACKUP=false
DEBUG=false

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

show_help() {
    cat << EOF
Mantic Integration Setup for Claude Code GLM

This script installs Mantic semantic search integration to enhance
Claude Code's Grep tool with faster, smarter file discovery.

Usage:
    ./install-mantic.sh [OPTIONS]

Options:
    --skip-test         Skip integration test
    --no-backup         Don't backup existing settings.json
    --debug             Enable debug mode
    --help              Show this help message

What gets installed:
    - mantic.sh npm package (globally)
    - Hook script: ~/mantic-grep-hook.sh
    - Updated: ~/.claude/settings.json

Examples:
    # Standard installation
    ./install-mantic.sh

    # Install without testing
    ./install-mantic.sh --skip-test

    # Install with debug output
    ./install-mantic.sh --debug

For more information, see:
    tools/claude-code-glm/MANTIC_INTEGRATION.md
EOF
}

# ============================================================================
# COMMAND LINE PARSING
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        --debug)
            DEBUG=true
            set -x
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

print_header "Checking Prerequisites"

# Check for required commands
for cmd in node npm npx jq; do
    if ! command -v $cmd &> /dev/null; then
        print_error "$cmd is required but not installed"
        echo ""
        echo "Install with:"
        case $cmd in
            node|npm|npx)
                echo "  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
                echo "  sudo apt-get install -y nodejs"
                ;;
            jq)
                echo "  sudo apt-get install -y jq"
                ;;
        esac
        exit 1
    fi
    print_success "$cmd found: $(command -v $cmd)"
done

# Check source files exist
if [[ ! -f "$HOOK_SCRIPT" ]]; then
    print_error "Hook script not found: $HOOK_SCRIPT"
    exit 1
fi
print_success "Hook script found: $HOOK_SCRIPT"

if [[ ! -f "$SYSTEM_PROMPT" ]]; then
    print_error "System prompt not found: $SYSTEM_PROMPT"
    exit 1
fi
print_success "System prompt found: $SYSTEM_PROMPT"

# ============================================================================
# INSTALLATION
# ============================================================================

print_header "Installing Mantic"

# Install mantic.sh
print_info "Installing mantic.sh via npm..."
if npm list -g mantic.sh &>/dev/null; then
    print_success "mantic.sh already installed"
else
    if npm install -g mantic.sh &>/dev/null; then
        print_success "mantic.sh installed globally"
    else
        print_warning "Global install failed, will use npx (slower but works)"
    fi
fi

# Verify mantic is accessible
print_info "Verifying mantic.sh is accessible..."
if npx -y mantic.sh --version &>/dev/null; then
    print_success "mantic.sh is accessible via npx"
else
    print_error "Cannot access mantic.sh via npx"
    exit 1
fi

# ============================================================================
# HOOK INSTALLATION
# ============================================================================

print_header "Installing Hook Script"

# Copy hook script
print_info "Copying hook script to $TARGET_HOOK..."
cp "$HOOK_SCRIPT" "$TARGET_HOOK"
chmod +x "$TARGET_HOOK"
print_success "Hook script installed: $TARGET_HOOK"

# ============================================================================
# CLAUDE SETTINGS CONFIGURATION
# ============================================================================

print_header "Configuring Claude Code Settings"

# Create .claude directory if it doesn't exist
if [[ ! -d "$CLAUDE_DIR" ]]; then
    print_info "Creating $CLAUDE_DIR directory..."
    mkdir -p "$CLAUDE_DIR"
    print_success "Created $CLAUDE_DIR"
fi

# Backup existing settings.json
if [[ -f "$CLAUDE_SETTINGS" ]] && [[ "$NO_BACKUP" != "true" ]]; then
    BACKUP_FILE="${CLAUDE_SETTINGS}.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Backing up existing settings to $BACKUP_FILE..."
    cp "$CLAUDE_SETTINGS" "$BACKUP_FILE"
    print_success "Backup created: $BACKUP_FILE"
fi

# Read system prompt content
SYSTEM_PROMPT_CONTENT=$(cat "$SYSTEM_PROMPT")

# Create or update settings.json
print_info "Updating Claude Code settings..."

if [[ -f "$CLAUDE_SETTINGS" ]]; then
    # Update existing settings
    TEMP_SETTINGS=$(mktemp)

    jq --arg hook "$TARGET_HOOK" \
       --arg prompt "$SYSTEM_PROMPT_CONTENT" \
       '
       .hooks.PreToolUse = [
         {
           "matcher": "Grep",
           "hooks": [
             {
               "type": "command",
               "command": $hook
             }
           ]
         }
       ] |
       .systemPrompt.append = ((.systemPrompt.append // "") + "\n\n" + $prompt)
       ' "$CLAUDE_SETTINGS" > "$TEMP_SETTINGS"

    mv "$TEMP_SETTINGS" "$CLAUDE_SETTINGS"
    print_success "Updated existing settings.json"
else
    # Create new settings
    jq -n --arg hook "$TARGET_HOOK" \
          --arg prompt "$SYSTEM_PROMPT_CONTENT" \
          '{
            hooks: {
              PreToolUse: [
                {
                  "matcher": "Grep",
                  "hooks": [
                    {
                      "type": "command",
                      "command": $hook
                    }
                  ]
                }
              ]
            },
            systemPrompt: {
              append: $prompt
            }
          }' > "$CLAUDE_SETTINGS"
    print_success "Created new settings.json"
fi

# ============================================================================
# ENVIRONMENT SETUP
# ============================================================================

print_header "Environment Configuration"

# Check if env vars are already in bashrc/zshrc
SHELL_RC="$HOME/.bashrc"
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
fi

if ! grep -q "MANTIC_ENABLED" "$SHELL_RC" 2>/dev/null; then
    print_info "Adding Mantic environment variables to $SHELL_RC..."
    cat >> "$SHELL_RC" << 'EOF'

# Mantic Configuration for Claude Code
export MANTIC_ENABLED=true
export MANTIC_DEBUG=false
# export MANTIC_THRESHOLD=20  # Uncomment to change threshold

# Helper aliases
alias mantic-on='export MANTIC_ENABLED=true && echo "Mantic enabled"'
alias mantic-off='export MANTIC_ENABLED=false && echo "Mantic disabled"'
alias mantic-status='echo "Mantic enabled: $MANTIC_ENABLED"'
alias mantic-logs='tail -f ~/.claude/mantic-logs/metrics.csv'
alias mantic-debug='export MANTIC_DEBUG=true && echo "Debug mode enabled"'
alias mantic-stats='[[ -f ~/.claude/mantic-logs/metrics.csv ]] && echo "Mantic Statistics:" && tail -20 ~/.claude/mantic-logs/metrics.csv || echo "No stats yet"'
EOF
    print_success "Environment variables added to $SHELL_RC"
    print_info "Run: source $SHELL_RC"
else
    print_success "Environment variables already configured"
fi

# ============================================================================
# TESTING
# ============================================================================

if [[ "$SKIP_TEST" != "true" ]]; then
    print_header "Testing Integration"

    # Test 1: Hook script is executable
    print_info "Test 1: Hook script executable..."
    if [[ -x "$TARGET_HOOK" ]]; then
        print_success "Hook script is executable"
    else
        print_error "Hook script is not executable"
        exit 1
    fi

    # Test 2: Mantic can be called
    print_info "Test 2: Mantic accessibility..."
    if npx -y mantic.sh "test" --files --limit 1 &>/dev/null; then
        print_success "Mantic is accessible"
    else
        print_error "Cannot call mantic.sh"
        exit 1
    fi

    # Test 3: Hook can process sample input
    print_info "Test 3: Hook processing..."
    SAMPLE_INPUT='{
      "tool_name": "Grep",
      "tool_input": {
        "pattern": "authentication",
        "output_mode": "files_with_matches"
      }
    }'

    if echo "$SAMPLE_INPUT" | "$TARGET_HOOK" >/dev/null 2>&1; then
        print_success "Hook processes input correctly"
    else
        print_error "Hook failed to process input"
        exit 1
    fi

    # Test 4: Settings.json is valid JSON
    print_info "Test 4: Settings validation..."
    if jq empty "$CLAUDE_SETTINGS" 2>/dev/null; then
        print_success "settings.json is valid JSON"
    else
        print_error "settings.json is not valid JSON"
        exit 1
    fi

    print_success "All tests passed!"
fi

# ============================================================================
# COMPLETION
# ============================================================================

print_header "Installation Complete!"

cat << EOF
${GREEN}Mantic integration has been successfully installed!${NC}

${BLUE}What was installed:${NC}
  ✓ mantic.sh package (globally or via npx)
  ✓ Hook script: $TARGET_HOOK
  ✓ Claude settings: $CLAUDE_SETTINGS
  ✓ Environment vars: $SHELL_RC

${BLUE}How to use:${NC}
  1. Start Claude Code normally:
     ${YELLOW}claude${NC}

  2. Use Grep as usual - Mantic enhances it automatically:
     ${YELLOW}"Find authentication code"${NC}
     ${YELLOW}"Search for payment integration"${NC}

  3. Mantic will automatically speed up file discovery!

${BLUE}Control commands:${NC}
  ${YELLOW}mantic-on${NC}         Enable Mantic globally
  ${YELLOW}mantic-off${NC}        Disable Mantic globally
  ${YELLOW}mantic-status${NC}     Check if Mantic is enabled
  ${YELLOW}mantic-stats${NC}      View performance statistics
  ${YELLOW}mantic-debug${NC}      Enable debug logging

${BLUE}Project-level control:${NC}
  ${YELLOW}touch .no-mantic${NC}  Disable for current project
  ${YELLOW}rm .no-mantic${NC}     Re-enable for current project

${BLUE}Performance metrics:${NC}
  Logs: ${YELLOW}~/.claude/mantic-logs/${NC}
  - metrics.csv    Performance data
  - errors.log     Error tracking

${BLUE}Next steps:${NC}
  1. Source your shell config:
     ${YELLOW}source $SHELL_RC${NC}

  2. Start Claude Code and try a file search!

${BLUE}Documentation:${NC}
  See: ${YELLOW}tools/claude-code-glm/MANTIC_INTEGRATION.md${NC}

${GREEN}Happy coding with Mantic!${NC}
EOF
