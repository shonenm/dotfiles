#!/bin/bash
# tmuxウィンドウフォーカス時の通知消去スクリプト
# tmux hook (session-window-changed) から呼び出される
# 5秒タイマーロジック（SketchyBarと同じ）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_DIR="/tmp/claude_status"
FOCUS_STATE_FILE="/tmp/tmux_claude_focus"

# 現在のセッション・ウィンドウ情報を取得
SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
WINDOW_INDEX=$(tmux display-message -p '#I' 2>/dev/null || echo "")

[[ -z "$SESSION" || -z "$WINDOW_INDEX" ]] && exit 0

# tmuxウィンドウの通知を消去（claude-status.shに委譲）
clear_tmux_window() {
  local session="$1"
  local window_index="$2"
  "$SCRIPT_DIR/claude-status.sh" clear-tmux "$session" "$window_index" 2>/dev/null || true
}

# 5秒タイマーを開始（既存タイマーはキャンセル）
start_clear_timer() {
  local session="$1"
  local window_index="$2"

  # 既存タイマーをキャンセル
  if [[ -f "$FOCUS_STATE_FILE" ]]; then
    local prev_pid
    prev_pid=$(cut -d: -f4 "$FOCUS_STATE_FILE" 2>/dev/null)
    [[ -n "$prev_pid" ]] && kill "$prev_pid" 2>/dev/null || true
  fi

  local now
  now=$(date +%s)

  # 5秒後に自動消去するバックグラウンドタイマー
  (
    sleep 5
    clear_tmux_window "$session" "$window_index"
  ) &
  local timer_pid=$!

  echo "${session}:${window_index}:${now}:${timer_pid}" > "$FOCUS_STATE_FILE"
}

# このウィンドウに通知があるかチェック
has_notification() {
  local session="$1"
  local window_index="$2"

  [[ ! -d "$STATUS_DIR" ]] && return 1

  for f in "$STATUS_DIR"/window_*.json; do
    [[ -f "$f" ]] || continue
    local file_session file_window file_status
    file_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
    file_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)
    file_status=$(jq -r '.status // "none"' "$f" 2>/dev/null)

    if [[ "$file_session" == "$session" && "$file_window" == "$window_index" ]]; then
      case "$file_status" in
        idle|permission|complete)
          return 0
          ;;
      esac
    fi
  done

  return 1
}

# 前回のフォーカス状態をチェック
if [[ -f "$FOCUS_STATE_FILE" ]]; then
  prev_state=$(cat "$FOCUS_STATE_FILE" 2>/dev/null)
  prev_session=$(echo "$prev_state" | cut -d: -f1)
  prev_window=$(echo "$prev_state" | cut -d: -f2)
  prev_ts=$(echo "$prev_state" | cut -d: -f3)
  prev_pid=$(echo "$prev_state" | cut -d: -f4)

  # 同じウィンドウなら何もしない（重複イベント対策）
  [[ "$prev_session" == "$SESSION" && "$prev_window" == "$WINDOW_INDEX" ]] && exit 0

  # 前回のタイマーをキャンセル
  [[ -n "$prev_pid" ]] && kill "$prev_pid" 2>/dev/null || true

  # 滞在時間を計算
  now=$(date +%s)
  elapsed=$((now - prev_ts))

  if [[ $elapsed -ge 5 ]]; then
    # 5秒以上滞在 → 前ウィンドウの通知を消す
    clear_tmux_window "$prev_session" "$prev_window"
  fi
  # 5秒未満 → 通知を残す（何もしない）
fi

# 新しいウィンドウに通知があれば5秒タイマーを開始
if has_notification "$SESSION" "$WINDOW_INDEX"; then
  start_clear_timer "$SESSION" "$WINDOW_INDEX"
else
  # 通知がなければ状態ファイルを更新のみ
  now=$(date +%s)
  echo "${SESSION}:${WINDOW_INDEX}:${now}:" > "$FOCUS_STATE_FILE"
fi
