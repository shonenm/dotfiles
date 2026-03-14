#!/bin/bash
# Toggle synchronize-panes with visual feedback

off=$(tmux show-option -gqv @theme-border-inactive)
on=$(tmux show-option -gqv @theme-border-success)
off=${off:-"#3b4261"}
on=${on:-"#73daca"}

if [ "$(tmux show-window-options -v synchronize-panes)" = "on" ]; then
    tmux setw synchronize-panes off
    tmux set -g window-style "fg=colour244,bg=default"
    tmux set -g pane-border-style "fg=${off},bg=default"
else
    tmux setw synchronize-panes on
    tmux set -g window-style "fg=colour255,bg=default"
    tmux set -g pane-border-style "fg=${on},bg=default"
fi
