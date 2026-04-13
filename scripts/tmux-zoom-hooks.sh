#!/bin/bash
# Register zoom sticky hooks once per tmux server (reload-safe guard).

if [ -n "$(tmux show-options -gqv @zoom-hooks-loaded 2>/dev/null)" ]; then
    exit 0
fi

tmux set-hook -ga after-select-pane 'run-shell -b "~/dotfiles/scripts/tmux-zoom-restore.sh"'
tmux set-option -g @zoom-hooks-loaded 1
