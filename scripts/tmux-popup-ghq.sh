#!/bin/bash
# ghq project switcher for tmux popup
selected=$(ghq list -p | fzf --reverse --header='Switch Project')
[ -z "$selected" ] && exit 0

session_name=$(basename "$selected" | tr '.' '_')

if ! tmux has-session -t="$session_name" 2>/dev/null; then
  tmux new-session -d -s "$session_name" -c "$selected"
fi

# Apply per-session accent color
color=$(~/dotfiles/scripts/tmux-session-color.sh "$session_name")
tmux set-option -t "$session_name" @session_color "$color"

tmux switch-client -t "$session_name"
