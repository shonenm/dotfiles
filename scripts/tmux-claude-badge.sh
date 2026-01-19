#!/bin/bash
# tmux Claude バッジ表示スクリプト
# Usage:
#   tmux-claude-badge.sh window <index> [focused]  # ウィンドウ用バッジ

STATUS_DIR="/tmp/claude_status"
BADGE_BG="#ff6600"
BADGE_BG_DIM="#cc5500"  # 薄い版（フォーカス中）- tmuxはアルファ非対応のため暗めの色で代用
BADGE_FG="#ffffff"

# Powerline rounded characters (U+E0B6 / U+E0B4)
LEFT_ROUND=$'\xee\x82\xb6'
RIGHT_ROUND=$'\xee\x82\xb4'

get_session_name() {
  tmux display-message -p '#S' 2>/dev/null || echo ""
}

# ウィンドウ用バッジ: このウィンドウに通知があるか（数字付き）
# Usage: show_window_badge <window_index> [focused]
show_window_badge() {
  local window_index="$1"
  local is_focused="${2:-}"
  local session_name
  session_name=$(get_session_name)
  [[ -z "$session_name" || -z "$window_index" ]] && return

  [[ ! -d "$STATUS_DIR" ]] && return

  local count=0

  for f in "$STATUS_DIR"/workspace_*.json; do
    [[ -f "$f" ]] || continue
    local file_session file_window file_status
    file_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
    file_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)
    file_status=$(jq -r '.status // "none"' "$f" 2>/dev/null)

    if [[ "$file_session" == "$session_name" && "$file_window" == "$window_index" ]]; then
      case "$file_status" in
        idle|permission|complete)
          ((count++))
          ;;
      esac
    fi
  done

  if [[ $count -gt 0 ]]; then
    # フォーカス中は薄い色を使用
    local bg_color="$BADGE_BG"
    if [[ "$is_focused" == "focused" ]]; then
      bg_color="$BADGE_BG_DIM"
    fi
    # 角丸スタイル（オレンジ背景、白文字）
    echo "#[fg=$bg_color,bg=default]${LEFT_ROUND}#[fg=$BADGE_FG,bg=$bg_color,bold] $count #[fg=$bg_color,bg=default]${RIGHT_ROUND}"
  fi
}

case "${1:-}" in
  window)
    show_window_badge "${2:-}" "${3:-}"
    ;;
  *)
    echo "Usage: $0 window <window_index> [focused]" >&2
    exit 1
    ;;
esac
