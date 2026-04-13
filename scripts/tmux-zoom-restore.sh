#!/bin/bash
# Re-zoom the window if the newly active pane has @zoom-sticky set.
# Invoked from after-select-pane hook.

sticky=$(tmux show-options -pqv @zoom-sticky 2>/dev/null)
zoomed=$(tmux display-message -p '#{window_zoomed_flag}')
if [ -n "$sticky" ] && [ "$zoomed" = "0" ]; then
    tmux resize-pane -Z
fi
