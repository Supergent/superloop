#!/bin/bash
# Mole - Common Functions Library
# Main entry point that loads all core modules

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_COMMON_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_COMMON_LOADED=1

_MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load core modules
source "$_MOLE_CORE_DIR/base.sh"
source "$_MOLE_CORE_DIR/log.sh"

source "$_MOLE_CORE_DIR/timeout.sh"
source "$_MOLE_CORE_DIR/file_ops.sh"
source "$_MOLE_CORE_DIR/ui.sh"
source "$_MOLE_CORE_DIR/app_protection.sh"

# Load sudo management if available
if [[ -f "$_MOLE_CORE_DIR/sudo.sh" ]]; then
    source "$_MOLE_CORE_DIR/sudo.sh"
fi

# Update via Homebrew
update_via_homebrew() {
    local current_version="$1"
    local temp_update temp_upgrade
    temp_update=$(mktemp_file "brew_update")
    temp_upgrade=$(mktemp_file "brew_upgrade")

    # Set up trap for interruption (Ctrl+C) with inline cleanup
    trap 'stop_inline_spinner 2>/dev/null; safe_remove "$temp_update" true; safe_remove "$temp_upgrade" true; echo ""; exit 130' INT TERM

    # Update Homebrew
    if [[ -t 1 ]]; then
        start_inline_spinner "Updating Homebrew..."
    else
        echo "Updating Homebrew..."
    fi

    brew update > "$temp_update" 2>&1 &
    local update_pid=$!
    wait $update_pid 2> /dev/null || true # Continue even if brew update fails

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    # Upgrade Mole
    if [[ -t 1 ]]; then
        start_inline_spinner "Upgrading Mole..."
    else
        echo "Upgrading Mole..."
    fi

    brew upgrade mole > "$temp_upgrade" 2>&1 &
    local upgrade_pid=$!
    wait $upgrade_pid 2> /dev/null || true # Continue even if brew upgrade fails

    local upgrade_output
    upgrade_output=$(cat "$temp_upgrade")

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    # Clear trap
    trap - INT TERM

    # Cleanup temp files
    safe_remove "$temp_update" true
    safe_remove "$temp_upgrade" true

    if echo "$upgrade_output" | grep -q "already installed"; then
        local installed_version
        installed_version=$(brew list --versions mole 2> /dev/null | awk '{print $2}')
        echo ""
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Already on latest version (${installed_version:-$current_version})"
        echo ""
    elif echo "$upgrade_output" | grep -q "Error:"; then
        log_error "Homebrew upgrade failed"
        echo "$upgrade_output" | grep "Error:" >&2
        return 1
    else
        echo "$upgrade_output" | grep -Ev "^(==>|Updating Homebrew|Warning:)" || true
        local new_version
        new_version=$(brew list --versions mole 2> /dev/null | awk '{print $2}')
        echo ""
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Updated to latest version (${new_version:-$current_version})"
        echo ""
    fi

    # Clear update cache (suppress errors if cache doesn't exist or is locked)
    rm -f "$HOME/.cache/mole/version_check" "$HOME/.cache/mole/update_message" 2> /dev/null || true
}

# Get Homebrew cask name for an application bundle
get_brew_cask_name() {
    local app_path="$1"
    [[ -z "$app_path" || ! -d "$app_path" ]] && return 1

    # Check if brew command exists
    command -v brew > /dev/null 2>&1 || return 1

    local app_bundle_name
    app_bundle_name=$(basename "$app_path")

    # 1. Search in Homebrew Caskroom for the app bundle (most reliable for name mismatches)
    # Checks /opt/homebrew (Apple Silicon) and /usr/local (Intel)
    # Note: Modern Homebrew uses symlinks in Caskroom, not directories
    local cask_match
    for room in "/opt/homebrew/Caskroom" "/usr/local/Caskroom"; do
        [[ -d "$room" ]] || continue
        # Path is room/token/version/App.app (can be directory or symlink)
        cask_match=$(find "$room" -maxdepth 3 -name "$app_bundle_name" 2> /dev/null | head -1 || echo "")
        if [[ -n "$cask_match" ]]; then
            local relative="${cask_match#"$room"/}"
            echo "${relative%%/*}"
            return 0
        fi
    done

    # 2. Check for symlink from Caskroom
    if [[ -L "$app_path" ]]; then
        local target
        target=$(readlink "$app_path")
        for room in "/opt/homebrew/Caskroom" "/usr/local/Caskroom"; do
            if [[ "$target" == "$room/"* ]]; then
                local relative="${target#"$room"/}"
                echo "${relative%%/*}"
                return 0
            fi
        done
    fi

    # 3. Fallback: Direct list check (handles some cases where app is moved)
    local app_name_only="${app_bundle_name%.app}"
    local cask_name
    cask_name=$(brew list --cask 2> /dev/null | grep -Fx "$(echo "$app_name_only" | LC_ALL=C tr '[:upper:]' '[:lower:]')" || echo "")
    if [[ -n "$cask_name" ]]; then
        if brew info --cask "$cask_name" 2> /dev/null | grep -q "$app_path"; then
            echo "$cask_name"
            return 0
        fi
    fi

    return 1
}

# Remove applications from Dock
remove_apps_from_dock() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    local -a targets=()
    for arg in "$@"; do
        [[ -n "$arg" ]] && targets+=("$arg")
    done

    if [[ ${#targets[@]} -eq 0 ]]; then
        return 0
    fi

    # Use pure shell (PlistBuddy) to remove items from Dock
    # This avoids dependencies on Python 3 or osascript (AppleScript)
    local plist="$HOME/Library/Preferences/com.apple.dock.plist"
    [[ -f "$plist" ]] || return 0

    command -v PlistBuddy > /dev/null 2>&1 || return 0

    local changed=false
    for target in "${targets[@]}"; do
        local app_path="$target"
        # Normalize path for comparison - realpath might fail if app is already deleted
        local full_path
        full_path=$(cd "$(dirname "$app_path")" 2> /dev/null && pwd || echo "")
        [[ -n "$full_path" ]] && full_path="$full_path/$(basename "$app_path")"

        # Find the index of the app in persistent-apps
        local i=0
        while true; do
            local label
            label=$(/usr/libexec/PlistBuddy -c "Print :persistent-apps:$i:tile-data:file-label" "$plist" 2> /dev/null || echo "")
            [[ -z "$label" ]] && break

            local url
            url=$(/usr/libexec/PlistBuddy -c "Print :persistent-apps:$i:tile-data:file-data:_CFURLString" "$plist" 2> /dev/null || echo "")
            [[ -z "$url" ]] && {
                ((i++))
                continue
            }

            # Match by full path only to avoid removing apps with the same label.
            if [[ -n "$full_path" && "$url" == *"$full_path"* ]]; then
                if /usr/libexec/PlistBuddy -c "Delete :persistent-apps:$i" "$plist" 2> /dev/null; then
                    changed=true
                    # After deletion, current index i now points to the next item
                    continue
                fi
            fi
            ((i++))
        done
    done

    if [[ "$changed" == "true" ]]; then
        # Restart Dock to apply changes from the plist
        killall Dock 2> /dev/null || true
    fi
}
