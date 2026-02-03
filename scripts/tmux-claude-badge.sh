#!/bin/bash
# tmux Claude バッジ表示スクリプト
# Usage:
#   tmux-claude-badge.sh window <index> [focused] <session_name>  # ウィンドウ用バッジ

STATUS_DIR="/tmp/claude_status"
CACHE_DIR="/tmp/tmux_cache"
CACHE_TTL=3  # キャッシュ有効期間（秒）
BADGE_BG="#ff6600"
BADGE_BG_DIM="#cc5500"  # 薄い版（フォーカス中）- tmuxはアルファ非対応のため暗めの色で代用
BADGE_FG="#ffffff"

# Powerline rounded characters (U+E0B6 / U+E0B4)
LEFT_ROUND=$'\xee\x82\xb6'
RIGHT_ROUND=$'\xee\x82\xb4'

# キャッシュディレクトリ作成
mkdir -p "$CACHE_DIR" 2>/dev/null

source "${BASH_SOURCE%/*}/tmux-utils.sh"

# ウィンドウ用バッジ: このウィンドウに通知があるか（数字付き）
# Usage: show_window_badge <window_index> [focused] [session_name]
show_window_badge() {
  local window_index="$1"
  local is_focused="${2:-}"
  local session_name="${3:-}"

  # セッション名が引数で渡されなかった場合のみtmuxコマンドを実行
  if [[ -z "$session_name" ]]; then
    session_name=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  fi
  [[ -z "$session_name" || -z "$window_index" ]] && return

  [[ ! -d "$STATUS_DIR" ]] && return

  # キャッシュチェック（セッション+ウィンドウごとにキャッシュ）
  local cache_key="claude_badge_${session_name}_${window_index}"
  local cache_file="$CACHE_DIR/$cache_key"

  if [[ -f "$cache_file" ]]; then
    local cache_age=$(( $(date +%s) - $(get_mtime "$cache_file") ))
    if [[ $cache_age -lt $CACHE_TTL ]]; then
      # キャッシュが有効: countを読み取り
      local cached_count
      cached_count=$(cat "$cache_file" 2>/dev/null)
      if [[ -n "$cached_count" ]]; then
        format_badge "$cached_count" "$is_focused"
        return
      fi
    fi
  fi

  # キャッシュ無効/なし: 計算実行
  local count=0

  for f in "$STATUS_DIR"/workspace_*.json; do
    [[ -f "$f" ]] || continue

    # jq 1回で3フィールドを取得（@tsvでタブ区切り）
    local result
    result=$(jq -r '[.tmux_session // "", .tmux_window_index // "", .status // "none"] | @tsv' "$f" 2>/dev/null)
    [[ -z "$result" ]] && continue

    local file_session file_window file_status
    IFS=$'\t' read -r file_session file_window file_status <<< "$result"

    if [[ "$file_session" == "$session_name" && "$file_window" == "$window_index" ]]; then
      case "$file_status" in
        idle|permission|complete)
          ((count++))
          ;;
      esac
    fi
  done

  # キャッシュ保存
  echo "$count" > "$cache_file" 2>/dev/null

  format_badge "$count" "$is_focused"
}

# バッジ出力フォーマット
format_badge() {
  local count="$1"
  local is_focused="$2"

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
    show_window_badge "${2:-}" "${3:-}" "${4:-}"
    ;;
  *)
    echo "Usage: $0 window <window_index> [focused] [session_name]" >&2
    exit 1
    ;;
esac
