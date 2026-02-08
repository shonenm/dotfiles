#!/bin/bash
# Toggle synchronize-panes with visual feedback

if [ "$(tmux show-window-options -v synchronize-panes)" = "on" ]; then
    tmux setw synchronize-panes off
    tmux set -g window-style "fg=colour244,bg=default"
    tmux set -g pane-border-style "fg=#3b4261,bg=default"
else
    tmux setw synchronize-panes on
    tmux set -g window-style "fg=colour255,bg=default"
    tmux set -g pane-border-style "fg=#73daca,bg=default"
fi
