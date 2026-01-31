#!/bin/bash
# Per-session accent color for tmux (baked-in approach).
# Subcommands:
#   <session_name>            — print hex color to stdout
#   apply <session_name>      — set @session_color + bake status-left per-session
#   refresh                   — re-bake window-status-current-format for current session
#   fzf-sessions              — ANSI-colored session list in fzf, switch on select

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

DEFAULT_COLOR="#f7768e"

get_color() {
  local name="$1"
  local hash
  hash=$(echo -n "$name" | cksum | awk '{print $1}')
  echo "${COLORS[$(( (hash >> 3) % ${#COLORS[@]} ))]}"
}

# Convert hex color (#rrggbb) to ANSI 24-bit escape
hex_to_ansi() {
  local hex="${1#\#}"
  printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

cmd_apply() {
  local session="$1"
  [ -z "$session" ] && return
  local color
  color=$(get_color "$session")
  tmux set-option -t "$session" @session_color "$color"
  local tmpl
  tmpl=$(tmux show-option -gqv @status_left_tmpl)
  [ -n "$tmpl" ] && tmux set-option -t "$session" status-left "${tmpl//SESSION_COLOR/$color}"
  cmd_refresh "$session"
}

cmd_refresh() {
  local session="${1:-$(tmux display-message -p '#S')}"
  local color
  color=$(tmux show-option -t "$session" -qv @session_color)
  [ -z "$color" ] && color="$DEFAULT_COLOR"
  local tmpl
  tmpl=$(tmux show-option -gqv @window_active_tmpl)
  [ -n "$tmpl" ] && tmux set-option -w -t "$session" window-status-current-format "${tmpl//SESSION_COLOR/$color}"
}

cmd_fzf_sessions() {
  local sessions
  sessions=$(tmux list-sessions -F '#S')
  [ -z "$sessions" ] && exit 0

  local colored_list=""
  local reset=$'\033[0m'
  while IFS= read -r name; do
    local color
    color=$(get_color "$name")
    local ansi
    ansi=$(hex_to_ansi "$color")
    colored_list+="${ansi}${name}${reset}"$'\n'
  done <<< "$sessions"

  local selected
  selected=$(printf '%s' "$colored_list" | fzf --ansi --reverse --header='Switch Session' \
    --preview='tmux capture-pane -ep -t {1}')
  [ -z "$selected" ] && exit 0

  # Strip ANSI codes from selection
  selected=$(echo "$selected" | sed $'s/\033\\[[0-9;]*m//g')
  tmux switch-client -t "$selected"
}

case "$1" in
  apply)
    cmd_apply "$2"
    ;;
  refresh)
    cmd_refresh "$2"
    ;;
  fzf-sessions)
    cmd_fzf_sessions
    ;;
  *)
    session="$1"
    [ -z "$session" ] && exit 1
    get_color "$session"
    ;;
esac
