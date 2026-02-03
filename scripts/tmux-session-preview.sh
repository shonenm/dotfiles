#!/bin/bash
# tmux session preview for fzf
# Usage: tmux-session-preview.sh <session_name>

session="$1"
[ -z "$session" ] && exit 1

# Check if session exists
tmux has-session -t "$session" 2>/dev/null || exit 1

# Colors
COLORS=(
  "#f7768e" "#ff9e64" "#e0af68" "#9ece6a"
  "#73daca" "#7aa2f7" "#bb9af7" "#7dcfff"
)
RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'

hex_to_ansi() {
  local hex="${1#\#}"
  printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

get_color() {
  local name="$1"
  local hash
  hash=$(echo -n "$name" | cksum | awk '{print $1}')
  echo "${COLORS[$(( (hash >> 3) % ${#COLORS[@]} ))]}"
}

# Get session color
color=$(get_color "$session")
ansi_color=$(hex_to_ansi "$color")

# Get session info
session_info=$(tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_created}|#{session_attached}' | grep "^${session}|")
IFS='|' read -r _ window_count created attached <<< "$session_info"

# Format creation time
if [[ "$OSTYPE" == "darwin"* ]]; then
  created_fmt=$(date -r "$created" '+%Y-%m-%d %H:%M')
else
  created_fmt=$(date -d "@$created" '+%Y-%m-%d %H:%M')
fi

# Attach status
if [ "$attached" = "1" ]; then
  attach_status="${BOLD}(attached)${RESET}"
else
  attach_status="${DIM}(detached)${RESET}"
fi

# Print header
echo -e "${ansi_color}${BOLD}━━━ ${session} ━━━${RESET}"
echo -e "${DIM}Windows:${RESET} ${window_count}  ${DIM}Created:${RESET} ${created_fmt}  ${attach_status}"
echo ""

# Print window list
echo -e "${ansi_color}${BOLD}Windows${RESET}"
tmux list-windows -t "$session" -F '#{window_index}|#{window_name}|#{window_active}|#{pane_current_path}' | while IFS='|' read -r idx name active path; do
  # Shorten home directory
  path="${path/#$HOME/~}"
  # Truncate long paths
  if [ ${#path} -gt 30 ]; then
    path="…${path: -29}"
  fi

  if [ "$active" = "1" ]; then
    echo -e "  ${ansi_color}▶${RESET} ${BOLD}${idx}: ${name}${RESET}  ${DIM}${path}${RESET}"
  else
    echo -e "    ${idx}: ${name}  ${DIM}${path}${RESET}"
  fi
done
echo ""

# Print pane content
echo -e "${ansi_color}${BOLD}Active Pane${RESET}"
echo -e "${DIM}─────────────────────────────────${RESET}"
tmux capture-pane -ep -t "$session"
