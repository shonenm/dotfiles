#!/bin/bash
# Claude Code 状態管理スクリプト（workspace単位 + tmux連携）
# Usage:
#   claude-status.sh set <project> <status> <workspace> [tmux_session] [tmux_window_index]
#   claude-status.sh get <workspace>
#   claude-status.sh list
#   claude-status.sh clear <workspace>
#   claude-status.sh clear-tmux <tmux_session> <tmux_window_index>
#   claude-status.sh cleanup

set -euo pipefail

STATUS_DIR="/tmp/claude_status"
STALE_THRESHOLD=3600  # 1時間以上更新なしは削除

# 状態を設定
set_status() {
  local project="$1"
  local status="$2"
  local workspace="${3:-}"
  local tmux_session="${4:-}"
  local tmux_window_index="${5:-}"

  # workspaceが空なら終了
  if [[ -z "$workspace" ]]; then
    return
  fi

  mkdir -p "$STATUS_DIR"

  # 重複通知チェック: 同じworkspace + statusの通知が2秒以内にあればスキップ
  local now_sec
  now_sec=$(date +%s)
  for existing_file in "$STATUS_DIR"/workspace_${workspace}_*.json; do
    [[ -f "$existing_file" ]] || continue
    local existing_status existing_updated
    existing_status=$(jq -r '.status // ""' "$existing_file" 2>/dev/null || echo "")
    existing_updated=$(jq -r '.updated // 0' "$existing_file" 2>/dev/null || echo "0")
    if [[ "$existing_status" == "$status" ]] && (( now_sec - existing_updated < 2 )); then
      return
    fi
  done

  # workspace_${workspace}_${timestamp}.json 形式でユニークに
  local timestamp
  timestamp=$(date +%s%N)

  cat > "$STATUS_DIR/workspace_${workspace}_${timestamp}.json" <<EOF
{
  "status": "$status",
  "project": "$project",
  "workspace": "$workspace",
  "tmux_session": "$tmux_session",
  "tmux_window_index": "$tmux_window_index",
  "updated": $(date +%s)
}
EOF

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi

  # tmux通知（セッションがある場合のみ）
  if [[ -n "$tmux_session" ]]; then
    tmux refresh-client -S 2>/dev/null || true
  fi
}

# 状態を取得
get_status() {
  local workspace="$1"

  # 最新のファイルを取得
  local latest_file
  latest_file=$(ls -t "$STATUS_DIR"/workspace_${workspace}_*.json 2>/dev/null | head -1)

  if [[ -n "$latest_file" && -f "$latest_file" ]]; then
    cat "$latest_file"
  else
    echo "{}"
  fi
}

# 全セッションをリスト
list_status() {
  [[ ! -d "$STATUS_DIR" ]] && echo "[]" && return

  local files=("$STATUS_DIR"/workspace_*.json)
  if [[ ! -e "${files[0]}" ]]; then
    echo "[]"
    return
  fi

  cat "$STATUS_DIR"/workspace_*.json 2>/dev/null | jq -s '.'
}

# 状態をクリア
clear_status() {
  local workspace="$1"
  rm -f "$STATUS_DIR"/workspace_${workspace}_*.json

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi
}

# tmuxウィンドウの通知を消去
clear_tmux_window() {
  local tmux_session="$1"
  local tmux_window_index="$2"

  [[ -z "$tmux_session" || -z "$tmux_window_index" ]] && return
  [[ ! -d "$STATUS_DIR" ]] && return

  for f in "$STATUS_DIR"/workspace_*.json; do
    [[ -f "$f" ]] || continue
    local file_session file_window
    file_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
    file_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

    if [[ "$file_session" == "$tmux_session" && "$file_window" == "$tmux_window_index" ]]; then
      rm -f "$f"
    fi
  done

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi

  # tmuxを更新
  tmux refresh-client -S 2>/dev/null || true
}

# 古いセッションをクリーンアップ
cleanup() {
  [[ ! -d "$STATUS_DIR" ]] && return

  local now
  now=$(date +%s)

  for f in "$STATUS_DIR"/workspace_*.json; do
    [[ -f "$f" ]] || continue
    local updated
    updated=$(jq -r '.updated // 0' "$f" 2>/dev/null || echo "0")
    if (( now - updated > STALE_THRESHOLD )); then
      rm -f "$f"
    fi
  done

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi
}

# メイン
case "${1:-}" in
  set)
    set_status "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
    ;;
  get)
    get_status "${2:-}"
    ;;
  list)
    list_status
    ;;
  clear)
    clear_status "${2:-}"
    ;;
  cleanup)
    cleanup
    ;;
  clear-tmux)
    clear_tmux_window "${2:-}" "${3:-}"
    ;;
  *)
    echo "Usage: claude-status.sh <set|get|list|clear|clear-tmux|cleanup> [args]" >&2
    exit 1
    ;;
esac
