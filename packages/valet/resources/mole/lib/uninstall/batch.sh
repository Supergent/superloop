#!/bin/bash

set -euo pipefail

# Ensure common.sh is loaded.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -z "${MOLE_COMMON_LOADED:-}" ]] && source "$SCRIPT_DIR/lib/core/common.sh"

# Batch uninstall with a single confirmation.

# User data detection patterns (prompt user to backup if found).
readonly SENSITIVE_DATA_PATTERNS=(
    "\.warp"                               # Warp terminal configs/themes
    "/\.config/"                           # Standard Unix config directory
    "/themes/"                             # Theme customizations
    "/settings/"                           # Settings directories
    "/Application Support/[^/]+/User Data" # Chrome/Electron user data
    "/Preferences/[^/]+\.plist"            # User preference files
    "/Documents/"                          # User documents
    "/\.ssh/"                              # SSH keys and configs (critical)
    "/\.gnupg/"                            # GPG keys (critical)
)

# Join patterns into a single regex for grep.
SENSITIVE_DATA_REGEX=$(
    IFS='|'
    echo "${SENSITIVE_DATA_PATTERNS[*]}"
)

# Decode and validate base64 file list (safe for set -e).
decode_file_list() {
    local encoded="$1"
    local app_name="$2"
    local decoded

    # macOS uses -D, GNU uses -d. Always return 0 for set -e safety.
    if ! decoded=$(printf '%s' "$encoded" | base64 -D 2> /dev/null); then
        if ! decoded=$(printf '%s' "$encoded" | base64 -d 2> /dev/null); then
            log_error "Failed to decode file list for $app_name" >&2
            echo ""
            return 0 # Return success with empty string
        fi
    fi

    if [[ "$decoded" =~ $'\0' ]]; then
        log_warning "File list for $app_name contains null bytes, rejecting" >&2
        echo ""
        return 0 # Return success with empty string
    fi

    while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ ^/ ]]; then
            log_warning "Invalid path in file list for $app_name: $line" >&2
            echo ""
            return 0 # Return success with empty string
        fi
    done <<< "$decoded"

    echo "$decoded"
    return 0
}
# Note: find_app_files() and calculate_total_size() are in lib/core/common.sh.

# Stop Launch Agents/Daemons for an app.
stop_launch_services() {
    local bundle_id="$1"
    local has_system_files="${2:-false}"

    [[ -z "$bundle_id" || "$bundle_id" == "unknown" ]] && return 0

    if [[ -d ~/Library/LaunchAgents ]]; then
        while IFS= read -r -d '' plist; do
            launchctl unload "$plist" 2> /dev/null || true
        done < <(find ~/Library/LaunchAgents -maxdepth 1 -name "${bundle_id}*.plist" -print0 2> /dev/null)
    fi

    if [[ "$has_system_files" == "true" ]]; then
        if [[ -d /Library/LaunchAgents ]]; then
            while IFS= read -r -d '' plist; do
                sudo launchctl unload "$plist" 2> /dev/null || true
            done < <(find /Library/LaunchAgents -maxdepth 1 -name "${bundle_id}*.plist" -print0 2> /dev/null)
        fi
        if [[ -d /Library/LaunchDaemons ]]; then
            while IFS= read -r -d '' plist; do
                sudo launchctl unload "$plist" 2> /dev/null || true
            done < <(find /Library/LaunchDaemons -maxdepth 1 -name "${bundle_id}*.plist" -print0 2> /dev/null)
        fi
    fi
}

# Remove files (handles symlinks, optional sudo).
remove_file_list() {
    local file_list="$1"
    local use_sudo="${2:-false}"
    local count=0

    while IFS= read -r file; do
        [[ -n "$file" && -e "$file" ]] || continue

        if [[ -L "$file" ]]; then
            if [[ "$use_sudo" == "true" ]]; then
                sudo rm "$file" 2> /dev/null && ((count++)) || true
            else
                rm "$file" 2> /dev/null && ((count++)) || true
            fi
        else
            if [[ "$use_sudo" == "true" ]]; then
                safe_sudo_remove "$file" && ((count++)) || true
            else
                safe_remove "$file" true && ((count++)) || true
            fi
        fi
    done <<< "$file_list"

    echo "$count"
}

# Batch uninstall with single confirmation.
batch_uninstall_applications() {
    local total_size_freed=0

    # shellcheck disable=SC2154
    if [[ ${#selected_apps[@]} -eq 0 ]]; then
        log_warning "No applications selected for uninstallation"
        return 0
    fi

    # Pre-scan: running apps, sudo needs, size.
    local -a running_apps=()
    local -a sudo_apps=()
    local total_estimated_size=0
    local -a app_details=()

    if [[ -t 1 ]]; then start_inline_spinner "Scanning files..."; fi
    for selected_app in "${selected_apps[@]}"; do
        [[ -z "$selected_app" ]] && continue
        IFS='|' read -r _ app_path app_name bundle_id _ _ <<< "$selected_app"

        # Check running app by bundle executable if available.
        local exec_name=""
        if [[ -e "$app_path/Contents/Info.plist" ]]; then
            exec_name=$(defaults read "$app_path/Contents/Info.plist" CFBundleExecutable 2> /dev/null || echo "")
        fi
        local check_pattern="${exec_name:-$app_name}"
        if pgrep -x "$check_pattern" > /dev/null 2>&1; then
            running_apps+=("$app_name")
        fi

        # Check if it's a Homebrew cask
        local cask_name=""
        cask_name=$(get_brew_cask_name "$app_path" || echo "")
        local is_brew_cask="false"
        [[ -n "$cask_name" ]] && is_brew_cask="true"

        # For Homebrew casks, skip detailed file scanning since brew handles it
        if [[ "$is_brew_cask" == "true" ]]; then
            local app_size_kb=$(get_path_size_kb "$app_path")
            local total_kb=$app_size_kb
            ((total_estimated_size += total_kb))

            # Homebrew may need sudo for system-wide installations
            local needs_sudo=false
            if [[ "$app_path" == "/Applications/"* ]]; then
                needs_sudo=true
                sudo_apps+=("$app_name")
            fi

            # Store minimal details for Homebrew apps
            app_details+=("$app_name|$app_path|$bundle_id|$total_kb|||false|$needs_sudo|$is_brew_cask|$cask_name")
        else
            # For non-Homebrew apps, do full file scanning
            local needs_sudo=false
            local app_owner=$(get_file_owner "$app_path")
            local current_user=$(whoami)
            if [[ ! -w "$(dirname "$app_path")" ]] ||
                [[ "$app_owner" == "root" ]] ||
                [[ -n "$app_owner" && "$app_owner" != "$current_user" ]]; then
                needs_sudo=true
            fi

            # Size estimate includes related and system files.
            local app_size_kb=$(get_path_size_kb "$app_path")
            local related_files=$(find_app_files "$bundle_id" "$app_name")
            local related_size_kb=$(calculate_total_size "$related_files")
            # system_files is a newline-separated string, not an array.
            # shellcheck disable=SC2178,SC2128
            local system_files=$(find_app_system_files "$bundle_id" "$app_name")
            # shellcheck disable=SC2128
            local system_size_kb=$(calculate_total_size "$system_files")
            local total_kb=$((app_size_kb + related_size_kb + system_size_kb))
            ((total_estimated_size += total_kb))

            # shellcheck disable=SC2128
            if [[ -n "$system_files" ]]; then
                needs_sudo=true
            fi

            if [[ "$needs_sudo" == "true" ]]; then
                sudo_apps+=("$app_name")
            fi

            # Check for sensitive user data once.
            local has_sensitive_data="false"
            if [[ -n "$related_files" ]] && echo "$related_files" | grep -qE "$SENSITIVE_DATA_REGEX"; then
                has_sensitive_data="true"
            fi

            # Store details for later use (base64 keeps lists on one line).
            local encoded_files
            encoded_files=$(printf '%s' "$related_files" | base64 | tr -d '\n')
            local encoded_system_files
            encoded_system_files=$(printf '%s' "$system_files" | base64 | tr -d '\n')
            app_details+=("$app_name|$app_path|$bundle_id|$total_kb|$encoded_files|$encoded_system_files|$has_sensitive_data|$needs_sudo|$is_brew_cask|$cask_name")
        fi
    done
    if [[ -t 1 ]]; then stop_inline_spinner; fi

    local size_display=$(bytes_to_human "$((total_estimated_size * 1024))")

    echo ""
    echo -e "${PURPLE_BOLD}Files to be removed:${NC}"
    echo ""

    # Warn if user data is detected.
    local has_user_data=false
    for detail in "${app_details[@]}"; do
        IFS='|' read -r _ _ _ _ _ _ has_sensitive_data <<< "$detail"
        if [[ "$has_sensitive_data" == "true" ]]; then
            has_user_data=true
            break
        fi
    done

    if [[ "$has_user_data" == "true" ]]; then
        echo -e "${YELLOW}${ICON_WARNING}${NC} ${YELLOW}Note: Some apps contain user configurations/themes${NC}"
        echo ""
    fi

    for detail in "${app_details[@]}"; do
        IFS='|' read -r app_name app_path bundle_id total_kb encoded_files encoded_system_files has_sensitive_data needs_sudo_flag is_brew_cask cask_name <<< "$detail"
        local app_size_display=$(bytes_to_human "$((total_kb * 1024))")

        local brew_tag=""
        [[ "$is_brew_cask" == "true" ]] && brew_tag=" ${CYAN}[Brew]${NC}"
        echo -e "${BLUE}${ICON_CONFIRM}${NC} ${app_name}${brew_tag} ${GRAY}(${app_size_display})${NC}"

        # For Homebrew apps, [Brew] tag is enough indication
        # For non-Homebrew apps, show detailed file list
        if [[ "$is_brew_cask" != "true" ]]; then
            local related_files=$(decode_file_list "$encoded_files" "$app_name")
            local system_files=$(decode_file_list "$encoded_system_files" "$app_name")

            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} ${app_path/$HOME/~}"

            # Show related files (limit to 5).
            local file_count=0
            local max_files=5
            while IFS= read -r file; do
                if [[ -n "$file" && -e "$file" ]]; then
                    if [[ $file_count -lt $max_files ]]; then
                        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} ${file/$HOME/~}"
                    fi
                    ((file_count++))
                fi
            done <<< "$related_files"

            # Show system files (limit to 5).
            local sys_file_count=0
            while IFS= read -r file; do
                if [[ -n "$file" && -e "$file" ]]; then
                    if [[ $sys_file_count -lt $max_files ]]; then
                        echo -e "  ${BLUE}${ICON_SOLID}${NC} System: $file"
                    fi
                    ((sys_file_count++))
                fi
            done <<< "$system_files"

            local total_hidden=$((file_count > max_files ? file_count - max_files : 0))
            ((total_hidden += sys_file_count > max_files ? sys_file_count - max_files : 0))
            if [[ $total_hidden -gt 0 ]]; then
                echo -e "  ${GRAY}  ... and ${total_hidden} more files${NC}"
            fi
        fi
    done

    # Confirmation before requesting sudo.
    local app_total=${#selected_apps[@]}
    local app_text="app"
    [[ $app_total -gt 1 ]] && app_text="apps"

    echo ""
    local removal_note="Remove ${app_total} ${app_text}"
    [[ -n "$size_display" ]] && removal_note+=" (${size_display})"
    if [[ ${#running_apps[@]} -gt 0 ]]; then
        removal_note+=" ${YELLOW}[Running]${NC}"
    fi
    echo -ne "${PURPLE}${ICON_ARROW}${NC} ${removal_note}  ${GREEN}Enter${NC} confirm, ${GRAY}ESC${NC} cancel: "

    drain_pending_input # Clean up any pending input before confirmation
    IFS= read -r -s -n1 key || key=""
    drain_pending_input # Clean up any escape sequence remnants
    case "$key" in
        $'\e' | q | Q)
            echo ""
            echo ""
            return 0
            ;;
        "" | $'\n' | $'\r' | y | Y)
            echo "" # Move to next line
            ;;
        *)
            echo ""
            echo ""
            return 0
            ;;
    esac

    # Request sudo if needed.
    if [[ ${#sudo_apps[@]} -gt 0 ]]; then
        if ! sudo -n true 2> /dev/null; then
            if ! request_sudo_access "Admin required for system apps: ${sudo_apps[*]}"; then
                echo ""
                log_error "Admin access denied"
                return 1
            fi
        fi
        # Keep sudo alive during uninstall.
        parent_pid=$$
        (while true; do
            if ! kill -0 "$parent_pid" 2> /dev/null; then
                exit 0
            fi
            sudo -n true
            sleep 60
        done 2> /dev/null) &
        sudo_keepalive_pid=$!
    fi

    # Perform uninstallations with per-app progress feedback
    local success_count=0 failed_count=0
    local -a failed_items=()
    local -a success_items=()
    local current_index=0
    for detail in "${app_details[@]}"; do
        ((current_index++))
        IFS='|' read -r app_name app_path bundle_id total_kb encoded_files encoded_system_files has_sensitive_data needs_sudo is_brew_cask cask_name <<< "$detail"
        local related_files=$(decode_file_list "$encoded_files" "$app_name")
        local system_files=$(decode_file_list "$encoded_system_files" "$app_name")
        local reason=""

        # Show progress for current app
        local brew_tag=""
        [[ "$is_brew_cask" == "true" ]] && brew_tag=" ${CYAN}[Brew]${NC}"
        if [[ -t 1 ]]; then
            if [[ ${#app_details[@]} -gt 1 ]]; then
                start_inline_spinner "[$current_index/${#app_details[@]}] Uninstalling ${app_name}${brew_tag}..."
            else
                start_inline_spinner "Uninstalling ${app_name}${brew_tag}..."
            fi
        fi

        # Stop Launch Agents/Daemons before removal.
        local has_system_files="false"
        [[ -n "$system_files" ]] && has_system_files="true"
        stop_launch_services "$bundle_id" "$has_system_files"

        if ! force_kill_app "$app_name" "$app_path"; then
            reason="still running"
        fi

        # Remove the application only if not running.
        if [[ -z "$reason" ]]; then
            if [[ "$is_brew_cask" == "true" && -n "$cask_name" ]]; then
                # Use brew uninstall --cask with progress indicator
                local brew_output_file=$(mktemp)
                local brew_failed=false
                if ! run_with_timeout 120 brew uninstall --cask "$cask_name" > "$brew_output_file" 2>&1; then
                    brew_failed=true
                    log_warning "brew uninstall failed for $app_name, falling back to manual cleanup"
                fi
                rm -f "$brew_output_file"
                if [[ "$brew_failed" == "true" ]]; then
                    [[ -z "$related_files" ]] && related_files=$(find_app_files "$bundle_id" "$app_name")
                    [[ -z "$system_files" ]] && system_files=$(find_app_system_files "$bundle_id" "$app_name")
                    if [[ "$needs_sudo" == true ]]; then
                        safe_sudo_remove "$app_path" || reason="remove failed"
                    else
                        safe_remove "$app_path" true || reason="remove failed"
                    fi
                fi
            elif [[ "$needs_sudo" == true ]]; then
                if ! safe_sudo_remove "$app_path"; then
                    local app_owner=$(get_file_owner "$app_path")
                    local current_user=$(whoami)
                    if [[ -n "$app_owner" && "$app_owner" != "$current_user" && "$app_owner" != "root" ]]; then
                        reason="owned by $app_owner"
                    else
                        reason="permission denied"
                    fi
                fi
            else
                safe_remove "$app_path" true || reason="remove failed"
            fi
        fi

        # Remove related files if app removal succeeded.
        if [[ -z "$reason" ]]; then
            remove_file_list "$related_files" "false" > /dev/null
            remove_file_list "$system_files" "true" > /dev/null

            # Clean up macOS defaults (preference domains).
            if [[ -n "$bundle_id" && "$bundle_id" != "unknown" ]]; then
                if defaults read "$bundle_id" &> /dev/null; then
                    defaults delete "$bundle_id" 2> /dev/null || true
                fi

                # ByHost preferences (machine-specific).
                if [[ -d ~/Library/Preferences/ByHost ]]; then
                    find ~/Library/Preferences/ByHost -maxdepth 1 -name "${bundle_id}.*.plist" -delete 2> /dev/null || true
                fi
            fi

            # Stop spinner and show success
            if [[ -t 1 ]]; then
                stop_inline_spinner
                if [[ ${#app_details[@]} -gt 1 ]]; then
                    echo -e "\r\033[K${GREEN}✓${NC} [$current_index/${#app_details[@]}] ${app_name}"
                else
                    echo -e "\r\033[K${GREEN}✓${NC} ${app_name}"
                fi
            fi

            ((total_size_freed += total_kb))
            ((success_count++))
            ((files_cleaned++))
            ((total_items++))
            success_items+=("$app_name")
        else
            # Stop spinner and show failure
            if [[ -t 1 ]]; then
                stop_inline_spinner
                if [[ ${#app_details[@]} -gt 1 ]]; then
                    echo -e "\r\033[K${RED}✗${NC} [$current_index/${#app_details[@]}] ${app_name} ${GRAY}($reason)${NC}"
                else
                    echo -e "\r\033[K${RED}✗${NC} ${app_name} failed: $reason"
                fi
            fi

            ((failed_count++))
            failed_items+=("$app_name:$reason")
        fi
    done

    # Summary
    local freed_display
    freed_display=$(bytes_to_human "$((total_size_freed * 1024))")

    local summary_status="success"
    local -a summary_details=()

    if [[ $success_count -gt 0 ]]; then
        local success_list="${success_items[*]}"
        local success_text="app"
        [[ $success_count -gt 1 ]] && success_text="apps"
        local success_line="Removed ${success_count} ${success_text}"
        if [[ -n "$freed_display" ]]; then
            success_line+=", freed ${GREEN}${freed_display}${NC}"
        fi

        # Format app list with max 3 per line.
        if [[ -n "$success_list" ]]; then
            local idx=0
            local is_first_line=true
            local current_line=""

            for app_name in "${success_items[@]}"; do
                local display_item="${GREEN}${app_name}${NC}"

                if ((idx % 3 == 0)); then
                    if [[ -n "$current_line" ]]; then
                        summary_details+=("$current_line")
                    fi
                    if [[ "$is_first_line" == true ]]; then
                        current_line="${success_line}: $display_item"
                        is_first_line=false
                    else
                        current_line="$display_item"
                    fi
                else
                    current_line="$current_line, $display_item"
                fi
                ((idx++))
            done
            if [[ -n "$current_line" ]]; then
                summary_details+=("$current_line")
            fi
        else
            summary_details+=("$success_line")
        fi
    fi

    if [[ $failed_count -gt 0 ]]; then
        summary_status="warn"

        local failed_names=()
        for item in "${failed_items[@]}"; do
            local name=${item%%:*}
            failed_names+=("$name")
        done
        local failed_list="${failed_names[*]}"

        local reason_summary="could not be removed"
        if [[ $failed_count -eq 1 ]]; then
            local first_reason=${failed_items[0]#*:}
            case "$first_reason" in
                still*running*) reason_summary="is still running" ;;
                remove*failed*) reason_summary="could not be removed" ;;
                permission*denied*) reason_summary="permission denied" ;;
                owned*by*) reason_summary="$first_reason (try with sudo)" ;;
                *) reason_summary="$first_reason" ;;
            esac
        fi
        summary_details+=("Failed: ${RED}${failed_list}${NC} ${reason_summary}")
    fi

    if [[ $success_count -eq 0 && $failed_count -eq 0 ]]; then
        summary_status="info"
        summary_details+=("No applications were uninstalled.")
    fi

    local title="Uninstall complete"
    if [[ "$summary_status" == "warn" ]]; then
        title="Uninstall incomplete"
    fi

    echo ""
    print_summary_block "$title" "${summary_details[@]}"
    printf '\n'

    # Clean up Dock entries for uninstalled apps.
    if [[ $success_count -gt 0 ]]; then
        local -a removed_paths=()
        for detail in "${app_details[@]}"; do
            IFS='|' read -r app_name app_path _ _ _ _ <<< "$detail"
            for success_name in "${success_items[@]}"; do
                if [[ "$success_name" == "$app_name" ]]; then
                    removed_paths+=("$app_path")
                    break
                fi
            done
        done
        if [[ ${#removed_paths[@]} -gt 0 ]]; then
            remove_apps_from_dock "${removed_paths[@]}" 2> /dev/null || true
        fi
    fi

    # Clean up sudo keepalive if it was started.
    if [[ -n "${sudo_keepalive_pid:-}" ]]; then
        kill "$sudo_keepalive_pid" 2> /dev/null || true
        wait "$sudo_keepalive_pid" 2> /dev/null || true
        sudo_keepalive_pid=""
    fi

    # Invalidate cache if any apps were successfully uninstalled.
    if [[ $success_count -gt 0 ]]; then
        local cache_file="$HOME/.cache/mole/app_scan_cache"
        rm -f "$cache_file" 2> /dev/null || true
    fi

    ((total_size_cleaned += total_size_freed))
    unset failed_items
}
