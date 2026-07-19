#!/bin/bash
# tmux AI Agent ペーン状態管理 (純tmuxローカル / 状態の正本)
# 各エージェント(Claude Code / Codex / Cursor / Command Code / pi)の hooks から呼ばれ、
# pane user option で状態を管理する。pane option を状態の Single Source of Truth とし、
# ウィンドウバッジ・SketchyBar・Slack はこの集約から導出する派生ビューとする。
# 仕様: docs/specs/agent-stop-notification.md
#
# 状態: running / idle / permission / complete / hang / error
#   running   = ターン実行中(通知アイコンなし)。ハング検知のため heartbeat を持つ
#   idle      = 入力待ちで停止
#   permission= 承認待ちで停止
#   complete  = ターン正常終了
#   hang      = running のまま無応答(watcher が推定設定)
#   error     = エラー終了
#
# Usage:
#   tmux-claude-pane.sh set <running|idle|permission|complete|hang|error> [provider]
#   tmux-claude-pane.sh start [provider] [event|screen]
#   tmux-claude-pane.sh heartbeat [provider] [event|screen]
#   tmux-claude-pane.sh clear       # 通知クリア(全 pane option を解除)
#   tmux-claude-pane.sh hang-scan   # 全ペーン走査: running かつ無応答を hang 化 (watcher が定期実行)

set -euo pipefail

# tmux 外では何もしない(watcher も tmux run-shell 経由で TMUX を継承する)
[[ -z "${TMUX:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-lib.sh"

LOCK_CHANNEL=""
lock_pane() {
  LOCK_CHANNEL="agent-state-${1#%}"
  tmux wait-for -L "$LOCK_CHANNEL"
}
unlock_pane() {
  local channel="$LOCK_CHANNEL"
  LOCK_CHANNEL=""
  [[ -n "$channel" ]] && tmux wait-for -U "$channel" 2>/dev/null || true
}
trap unlock_pane EXIT

# ハング判定閾値(秒)。heartbeat 停滞がこれを超え、かつ出力も変化しなければ hang
HANG_THRESHOLD="${AGENT_HANG_THRESHOLD:-120}"

# 状態 → アイコン対応 (Nerd Font。hang/error の字形は環境に応じ調整可)
status_icon() {
  case "$1" in
    running)    echo "" ;;
    idle)       echo "󰔟" ;;
    permission) echo "󰌆" ;;
    complete)   echo "" ;;
    hang)       echo "" ;;
    error)      echo "" ;;
    *)          return 1 ;;
  esac
}

# semantic state change の後だけ index を無効化する。heartbeatだけなら不要。
invalidate_index() {
  "$SCRIPT_DIR/tmux-agent-index.sh" invalidate >/dev/null 2>&1 || true
}

# 指定ペーンに状態+アイコンを適用
apply_status() {
  local pane="$1" status="$2" provider="${3:-}" icon now
  icon=$(status_icon "$status") || return 1
  now=$(date +%s)
  tmux set-option -p -t "$pane" @agent_status "$status" \; \
       set-option -p -t "$pane" @agent_state_since "$now"
  [[ -n "$provider" ]] && tmux set-option -p -t "$pane" @agent_provider "$provider"
  if [[ -n "$icon" ]]; then
    tmux set-option -p -t "$pane" @agent_icon "$icon"
  else
    tmux set-option -p -t "$pane" -u @agent_icon 2>/dev/null || true
  fi
}

# 通知をクリア(pane option を解除)
clear_pane() {
  local pane="$1"
  local option
  for option in status icon heartbeat state_since outhash heartbeat_source provider stashed; do
    tmux set-option -p -t "$pane" -u "@agent_$option" 2>/dev/null || true
  done
}

# 起動元ペーン ID を取得(hook 経由はこのペーンが対象)。
# $TMUX_PANE はプロセス起動元ペーンの ID(固定)。tmux display-message -p は
# ユーザーのアクティブペーンを返すため、hook 経由だと別ペーンを誤操作する。
resolve_pane() {
  local p="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}' 2>/dev/null)}"
  [[ -z "$p" ]] && exit 0
  echo "$p"
}

scan_pane() {
  local pid="$1" status cmd hb prevhash source provider now curhash
  lock_pane "$pid"
  status=$(tmux show-options -pv -t "$pid" @agent_status 2>/dev/null || true)
  [[ -n "$status" ]] || { unlock_pane; return; }
  cmd=$(tmux display-message -p -t "$pid" '#{pane_current_command}' 2>/dev/null || true)
  if agent_is_shell "$cmd"; then
    clear_pane "$pid"
    changed=1
    unlock_pane
    return
  fi
  [[ "$status" == running ]] || { unlock_pane; return; }
  hb=$(tmux show-options -pv -t "$pid" @agent_heartbeat 2>/dev/null || true)
  [[ "$hb" =~ ^[0-9]+$ ]] || { unlock_pane; return; }
  source=$(tmux show-options -pv -t "$pid" @agent_heartbeat_source 2>/dev/null || true)
  provider=$(tmux show-options -pv -t "$pid" @agent_provider 2>/dev/null || true)
  now=$(date +%s)

  if [[ "${source:-screen}" == screen ]]; then
    prevhash=$(tmux show-options -pv -t "$pid" @agent_outhash 2>/dev/null || true)
    curhash=$(tmux capture-pane -t "$pid" -p -S -5 -E -1 2>/dev/null | cksum | cut -d' ' -f1)
    if [[ -z "$prevhash" ]]; then
      tmux set-option -p -t "$pid" @agent_outhash "$curhash" 2>/dev/null || true
    elif [[ "$curhash" != "$prevhash" ]]; then
      tmux set-option -p -t "$pid" @agent_outhash "$curhash" \; \
           set-option -p -t "$pid" @agent_heartbeat "$now" 2>/dev/null || true
      unlock_pane
      return
    fi
  fi

  if (( now - hb > HANG_THRESHOLD )); then
    apply_status "$pid" hang "$provider"
    changed=1
  fi
  unlock_pane
}

case "${1:-}" in
  set)
    PANE_ID=$(resolve_pane)
    STATUS="${2:-idle}"
    PROVIDER="${3:-}"
    lock_pane "$PANE_ID"
    apply_status "$PANE_ID" "$STATUS" "$PROVIDER" || { echo "Unknown status: $STATUS" >&2; exit 1; }
    unlock_pane
    invalidate_index
    tmux refresh-client -S 2>/dev/null || true
    ;;

  start)
    # ターン開始: running + activity。event source は端末spinnerを生存判定に使わない。
    PANE_ID=$(resolve_pane)
    PROVIDER="${2:-}"
    SOURCE="${3:-screen}"
    [[ "$SOURCE" == event || "$SOURCE" == screen ]] || { echo "Unknown heartbeat source: $SOURCE" >&2; exit 1; }
    lock_pane "$PANE_ID"
    now=$(date +%s)
    tmux set-option -p -t "$PANE_ID" @agent_status running \; \
         set-option -p -t "$PANE_ID" @agent_heartbeat "$now" \; \
         set-option -p -t "$PANE_ID" @agent_state_since "$now" \; \
         set-option -p -t "$PANE_ID" @agent_heartbeat_source "$SOURCE"
    [[ -n "$PROVIDER" ]] && tmux set-option -p -t "$PANE_ID" @agent_provider "$PROVIDER"
    tmux set-option -p -t "$PANE_ID" -u @agent_icon 2>/dev/null || true
    tmux set-option -p -t "$PANE_ID" -u @agent_outhash 2>/dev/null || true
    tmux set-option -p -t "$PANE_ID" -u @agent_stashed 2>/dev/null || true
    unlock_pane
    invalidate_index
    tmux refresh-client -S 2>/dev/null || true
    ;;

  heartbeat)
    # 実イベント由来の生存信号。停止状態から届いた場合だけ running へ復帰する。
    PANE_ID=$(resolve_pane)
    PROVIDER="${2:-}"
    SOURCE="${3:-}"
    lock_pane "$PANE_ID"
    now=$(date +%s)
    current=$(tmux show-options -pv -t "$PANE_ID" @agent_status 2>/dev/null || echo "")
    case "$current" in
      running|permission|hang)
        tmux set-option -p -t "$PANE_ID" @agent_heartbeat "$now" 2>/dev/null || true
        [[ -n "$PROVIDER" ]] && tmux set-option -p -t "$PANE_ID" @agent_provider "$PROVIDER"
        [[ -n "$SOURCE" ]] && tmux set-option -p -t "$PANE_ID" @agent_heartbeat_source "$SOURCE"
        if [[ "$current" != running ]]; then
          apply_status "$PANE_ID" running "$PROVIDER"
          changed=1
        else
          changed=0
        fi
        ;;
      *) changed=0 ;;
    esac
    unlock_pane
    if [[ $changed -eq 1 ]]; then
      invalidate_index
      tmux refresh-client -S 2>/dev/null || true
    fi
    ;;

  clear)
    PANE_ID=$(resolve_pane)
    lock_pane "$PANE_ID"
    current=$(tmux show-options -pv -t "$PANE_ID" @agent_status 2>/dev/null || echo "")
    [[ -z "$current" ]] && { unlock_pane; exit 0; }
    clear_pane "$PANE_ID"
    unlock_pane
    invalidate_index
    tmux refresh-client -S 2>/dev/null || true
    ;;

  hang-scan)
    # event source はhook heartbeatだけを信頼する。screen fallbackだけ末尾5行を比較する。
    changed=0
    while IFS= read -r pid; do
      scan_pane "$pid"
    done < <(tmux list-panes -a -F '#{pane_id}')

    if [[ $changed -eq 1 ]]; then
      invalidate_index
      tmux refresh-client -S 2>/dev/null || true
    fi
    ;;

  *)
    echo "Usage: $0 {set <status> [provider]|start [provider] [event|screen]|heartbeat [provider] [event|screen]|clear|hang-scan}" >&2
    exit 1
    ;;
esac
