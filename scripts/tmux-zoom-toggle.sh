#!/bin/bash
# Toggle pane zoom with optional pane-sticky persistence.
# Usage: tmux-zoom-toggle.sh [normal|sticky]
#   normal: plain zoom. Leaving the pane lets tmux auto-unzoom; returning does not restore.
#   sticky: marks the pane with @zoom-sticky so the after-select-pane hook re-zooms on return.
# Pressing z or Z on a sticky pane clears the flag and unzooms.

mode="${1:-normal}"
sticky=$(tmux show-options -pqv @zoom-sticky 2>/dev/null)
zoomed=$(tmux display-message -p '#{window_zoomed_flag}')

if [ -n "$sticky" ]; then
    tmux set-option -p -u @zoom-sticky
    [ "$zoomed" = "1" ] && tmux resize-pane -Z
elif [ "$zoomed" = "1" ]; then
    tmux resize-pane -Z
else
    [ "$mode" = "sticky" ] && tmux set-option -p @zoom-sticky 1
    tmux resize-pane -Z
fi
