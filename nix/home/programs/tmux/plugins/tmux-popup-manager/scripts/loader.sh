#!/bin/bash
# tmux-popup-manager: core loader
# Usage: loader.sh global | loader.sh project <session_name>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/helpers.sh"

# Parse a popup definition: key|width|height|command[|display_name]
# Sets: _key, _width, _height, _cmd, _display_name
parse_popup_def() {
    local value="$1"
    local name="$2"
    IFS='|' read -r _key _width _height _cmd _display_name <<< "$value"
    if [ -z "$_display_name" ]; then
        _display_name="$(capitalize "$name")"
    fi
}

# Register a popup command-alias (without bind-key)
register_alias() {
    local name="$1"
    local width="$2"
    local height="$3"
    local cmd="$4"
    local idx="$5"
    local alias_name="popup-${name}"

    local alias_value
    if [ "$cmd" = "SCRATCH" ]; then
        # Special: toggle scratch session
        alias_value="${alias_name}=if-shell -F '#{==:#{session_name},scratch}' { detach-client } { display-popup -E -w ${width}% -h ${height}% -d '#{pane_current_path}' 'tmux new-session -A -s scratch' }"
    else
        local escaped_cmd
        escaped_cmd="$(tmux_escape "$cmd")"
        alias_value="${alias_name}=display-popup -E -w ${width}% -h ${height}% -d '#{pane_current_path}' ${escaped_cmd}"
    fi

    tmux set -g "command-alias[$idx]" "$alias_value"
}

# Enumerate @popup-* options and collect popup definitions
# Populates the _popups array: "name|key|width|height|cmd|display_name"
collect_popups() {
    _popups=()
    while IFS= read -r line; do
        # Extract option name (everything before first space)
        local opt_name="${line%% *}"
        local name="${opt_name#@popup-}"
        local value
        value="$(tmux show-option -gqv "$opt_name")"
        [ -z "$value" ] && continue

        parse_popup_def "$value" "$name"
        _popups+=("${name}|${_key}|${_width}|${_height}|${_cmd}|${_display_name}")
    done < <(tmux show-options -g 2>/dev/null | grep '^@popup-' | grep -v '^@popup-manager-')
}

# Build which-key menu string from popup entries
# Args: popup entries (same format as _popups array)
build_menu_string() {
    local menu=""
    for entry in "$@"; do
        IFS='|' read -r name key width height cmd display_name <<< "$entry"
        local alias_name="popup-${name}"

        # Quote display names containing spaces or hyphens
        local quoted_name
        if [[ "$display_name" == *" "* ]] || [[ "$display_name" == *"-"* ]]; then
            quoted_name="\"${display_name}\""
        else
            quoted_name="$display_name"
        fi

        if [ -n "$menu" ]; then
            menu+=" "
        fi
        menu+="${quoted_name} \"${key}\" ${alias_name}"
    done
    echo "$menu"
}

cmd_global() {
    local alias_start
    alias_start="$(get_tmux_option "@popup-manager-alias-start" "220")"

    collect_popups

    local idx="$alias_start"
    for entry in "${_popups[@]}"; do
        IFS='|' read -r name key width height cmd display_name <<< "$entry"
        register_alias "$name" "$width" "$height" "$cmd" "$idx"
        tmux bind-key "$key" "popup-${name}"
        idx=$((idx + 1))
    done

    # which-key integration
    local wk_var
    wk_var="$(get_tmux_option "@popup-manager-which-key-var" "")"
    if [ -n "$wk_var" ]; then
        local menu
        menu="$(build_menu_string "${_popups[@]}")"
        if [ -n "$menu" ]; then
            tmux set -g "$wk_var" "$menu"
        fi
    fi
}

cmd_project() {
    local session="$1"
    [ -z "$session" ] && return 1

    local project_file_name
    project_file_name="$(get_tmux_option "@popup-manager-project-file" ".tmux-popups")"

    # Get session start directory
    local session_path
    session_path="$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null)"
    [ -z "$session_path" ] && return 1

    # Find git root (fall back to session path)
    local project_root
    project_root="$(git -C "$session_path" rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$project_root" ] && project_root="$session_path"

    local project_file="${project_root}/${project_file_name}"
    [ ! -f "$project_file" ] && return 0

    # Read project-local popup definitions
    local project_popups=()
    local alias_start
    alias_start="$(get_tmux_option "@popup-manager-alias-start" "220")"
    # Offset project aliases by 100 to avoid collision with global aliases
    local project_alias_start=$((alias_start + 100))

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        # Parse: name|key|width|height|command[|display_name]
        local name key width height cmd display_name
        IFS='|' read -r name key width height cmd display_name <<< "$line"
        [ -z "$name" ] && continue
        if [ -z "$display_name" ]; then
            display_name="$(capitalize "$name")"
        fi
        project_popups+=("${name}|${key}|${width}|${height}|${cmd}|${display_name}")
    done < "$project_file"

    [ ${#project_popups[@]} -eq 0 ] && return 0

    # Register project-local command-aliases only (no bind-key to avoid global key collision)
    # Project popups are accessible via which-key +Popup menu
    local idx="$project_alias_start"
    for entry in "${project_popups[@]}"; do
        IFS='|' read -r name key width height cmd display_name <<< "$entry"
        register_alias "$name" "$width" "$height" "$cmd" "$idx"
        idx=$((idx + 1))
    done

    # which-key integration: session-scoped menu (global + project)
    local wk_var
    wk_var="$(get_tmux_option "@popup-manager-which-key-var" "")"
    if [ -n "$wk_var" ]; then
        collect_popups
        local all_popups=("${_popups[@]}")
        # Add separator between global and project popups
        all_popups+=("_sep_||||||")
        all_popups+=("${project_popups[@]}")

        local menu=""
        for entry in "${all_popups[@]}"; do
            if [[ "$entry" == "_sep_"* ]]; then
                [ -n "$menu" ] && menu+=' ""'
                continue
            fi
            IFS='|' read -r name key width height cmd display_name <<< "$entry"
            local alias_name="popup-${name}"
            local quoted_name
            if [[ "$display_name" == *" "* ]] || [[ "$display_name" == *"-"* ]]; then
                quoted_name="\"${display_name}\""
            else
                quoted_name="$display_name"
            fi
            [ -n "$menu" ] && menu+=" "
            menu+="${quoted_name} \"${key}\" ${alias_name}"
        done

        if [ -n "$menu" ]; then
            tmux set -t "$session" "$wk_var" "$menu"
        fi
    fi
}

# Main dispatch
case "${1:-}" in
    global)
        cmd_global
        ;;
    project)
        cmd_project "$2"
        ;;
    *)
        echo "Usage: loader.sh global | loader.sh project <session_name>" >&2
        exit 1
        ;;
esac
