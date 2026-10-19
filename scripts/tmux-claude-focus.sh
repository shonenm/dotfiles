#!/bin/bash
# tmuxウィンドウ / TUIOS pane フォーカス時の通知消去スクリプト
# tmux hook (session-window-changed) と TUIOS hook (after-focus-change) から呼び出される
# TUIOS の位置は session を "tuios:<session>"、window を pane ID として扱う
# 5秒タイマーロジック（SketchyBarと同じ）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-lib.sh"
SHARED_BASE="${DOTFILES_SHARED_DIR:-$HOME/.cache}"
STATUS_DIR="$SHARED_BASE/claude/status"
RUNTIME_DIR="$(agent_runtime_dir)"
FOCUS_STATE_FILE="$RUNTIME_DIR/focus"

mkdir -p "$RUNTIME_DIR"

# 現在のセッション・ウィンドウ情報を取得
if [[ "${TUIOS_EVENT:-}" == after-focus-change ]]; then
  SESSION="tuios:${TUIOS_SESSION_ID:-}"
  WINDOW_INDEX="${TUIOS_WINDOW_ID:-}"
  [[ "$SESSION" == tuios: ]] && SESSION=""
else
  SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  WINDOW_INDEX=$(tmux display-message -p '#I' 2>/dev/null || echo "")
fi

[[ -z "$SESSION" || -z "$WINDOW_INDEX" ]] && exit 0

# tmuxウィンドウの通知を消去（ファイルベースのみ）
# pane option はペーン単位の通知なのでここでは消さない（PreToolUse hook で消去）
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
    prev_pid=$(cat "$FOCUS_STATE_FILE" 2>/dev/null)
    prev_pid="${prev_pid##*:}"
    [[ -n "$prev_pid" ]] && { kill "$prev_pid" 2>/dev/null; wait "$prev_pid" 2>/dev/null; } || true
  fi

  local now
  now=$(date +%s)

  # 5秒後に自動消去するバックグラウンドタイマー
  (
    sleep 5
    clear_tmux_window "$session" "$window_index"
  ) &
  local timer_pid=$!
  disown $timer_pid

  echo "${session}:${window_index}:${now}:${timer_pid}" > "$FOCUS_STATE_FILE"
}

# このウィンドウに通知があるかチェック（pane option + ファイルベース）
has_notification() {
  local session="$1"
  local window_index="$2"

  # 1. pane option チェック（高速、tmux のみ）
  local pane_count=0
  [[ "$session" != tuios:* ]] && pane_count=$(tmux list-panes -t "${session}:${window_index}" -F '#{@agent_status}' 2>/dev/null \
    | grep -cE '^(idle|permission|complete|hang|error)$' || true)
  [[ $pane_count -gt 0 ]] && return 0

  # 2. ファイルベース フォールバック
  [[ ! -d "$STATUS_DIR" ]] && return 1

  for f in "$STATUS_DIR"/workspace_*.json; do
    [[ -f "$f" ]] || continue
    local file_session file_window file_status
    file_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
    file_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)
    file_status=$(jq -r '.status // "none"' "$f" 2>/dev/null)

    if [[ "$file_session" == "$session" && "$file_window" == "$window_index" ]]; then
      case "$file_status" in
        idle|permission|complete|hang|error)
          return 0
          ;;
      esac
    fi
  done

  return 1
}

# 前回のフォーカス状態をチェック
if [[ -f "$FOCUS_STATE_FILE" ]]; then
  # session:window:ts:pid。TUIOS の session は "tuios:" を含むため右から分解する。
  prev_state=$(cat "$FOCUS_STATE_FILE" 2>/dev/null)
  prev_pid="${prev_state##*:}"; prev_state="${prev_state%:*}"
  prev_ts="${prev_state##*:}"; prev_state="${prev_state%:*}"
  prev_window="${prev_state##*:}"
  prev_session="${prev_state%:*}"

  # 同じウィンドウなら何もしない（重複イベント対策）
  [[ "$prev_session" == "$SESSION" && "$prev_window" == "$WINDOW_INDEX" ]] && exit 0

  # 前回のタイマーをキャンセル
  [[ -n "$prev_pid" ]] && { kill "$prev_pid" 2>/dev/null; wait "$prev_pid" 2>/dev/null; } || true

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

exit 0
