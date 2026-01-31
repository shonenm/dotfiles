#!/bin/bash
# Hash tmux session name to a unique TokyoNight accent color.
# Usage:
#   tmux-session-color.sh <session_name>        — print hex color
#   tmux-session-color.sh apply <session_name>   — set @session_color on the session

COLORS=(
  "#f7768e"  # red/pink
  "#ff9e64"  # orange
  "#e0af68"  # yellow
  "#9ece6a"  # green
  "#73daca"  # teal
  "#7aa2f7"  # blue
  "#bb9af7"  # purple
  "#7dcfff"  # cyan
)

get_color() {
  local name="$1"
  local hash
  hash=$(echo -n "$name" | cksum | awk '{print $1}')
  echo "${COLORS[$((hash % ${#COLORS[@]}))]}"
}

if [ "$1" = "apply" ]; then
  session="$2"
  [ -z "$session" ] && exit 0
  color=$(get_color "$session")
  tmux set-option -t "$session" @session_color "$color"
else
  session="$1"
  [ -z "$session" ] && exit 1
  get_color "$session"
fi
