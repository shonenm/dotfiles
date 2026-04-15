#!/bin/bash
# Apply a tmux theme and persist the choice so tmux.conf can restore it on
# server start.
#
# State file: $XDG_STATE_HOME/tmux/current-theme (fallback ~/.local/state)
# Usage:      tmux-theme-toggle.sh <tokyonight|syntopic>

set -eu

name="${1:-}"
if [ -z "$name" ]; then
    tmux display-message "usage: tmux-theme-toggle.sh <tokyonight|syntopic>"
    exit 1
fi

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"
mkdir -p "$state_dir"

tmux source-file "$HOME/.config/tmux/${name}.tmux"
echo "$name" >"$state_dir/current-theme"
tmux display-message "theme: $name"
