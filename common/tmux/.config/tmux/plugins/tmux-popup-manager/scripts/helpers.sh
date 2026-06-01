#!/bin/bash
# tmux-popup-manager: helper functions

get_tmux_option() {
    local option="$1"
    local default="$2"
    local value
    value="$(tmux show-option -gqv "$option")"
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Capitalize first letter of a string
capitalize() {
    local str="$1"
    echo "$(echo "${str:0:1}" | tr '[:lower:]' '[:upper:]')${str:1}"
}

# Escape spaces for tmux command parsing
tmux_escape() {
    printf '%s' "$1" | sed 's/ /\\ /g'
}
