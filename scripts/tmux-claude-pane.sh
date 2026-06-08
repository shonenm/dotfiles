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
#   tmux-claude-pane.sh set <running|idle|permission|complete|hang|error>
#   tmux-claude-pane.sh start       # ターン開始: running + heartbeat 更新 (UserPromptSubmit 相当)
#   tmux-claude-pane.sh heartbeat   # 生存信号更新 (PreToolUse/PostToolUse 相当)。hang からの復帰も担う
#   tmux-claude-pane.sh clear       # 通知クリア(全 pane option を解除)
#   tmux-claude-pane.sh hang-scan   # 全ペーン走査: running かつ無応答を hang 化 (watcher が定期実行)

set -euo pipefail

# tmux 外では何もしない(watcher も tmux run-shell 経由で TMUX を継承する)
[[ -z "${TMUX:-}" ]] && exit 0

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

# 指定ペーンに状態+アイコンを適用
apply_status() {
  local pane="$1" status="$2" icon
  icon=$(status_icon "$status") || return 1
  tmux set-option -p -t "$pane" @agent_status "$status"
  if [[ -n "$icon" ]]; then
    tmux set-option -p -t "$pane" @agent_icon "$icon"
  else
    tmux set-option -p -t "$pane" -u @agent_icon 2>/dev/null || true
  fi
}

# 通知をクリア(pane option を解除)
clear_pane() {
  local pane="$1"
  tmux set-option -p -t "$pane" -u @agent_status 2>/dev/null || true
  tmux set-option -p -t "$pane" -u @agent_icon 2>/dev/null || true
  tmux set-option -p -t "$pane" -u @agent_outhash 2>/dev/null || true
}

# 起動元ペーン ID を取得(hook 経由はこのペーンが対象)。
# $TMUX_PANE はプロセス起動元ペーンの ID(固定)。tmux display-message -p は
# ユーザーのアクティブペーンを返すため、hook 経由だと別ペーンを誤操作する。
resolve_pane() {
  local p="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}' 2>/dev/null)}"
  [[ -z "$p" ]] && exit 0
  echo "$p"
}

case "${1:-}" in
  set)
    PANE_ID=$(resolve_pane)
    STATUS="${2:-idle}"
    apply_status "$PANE_ID" "$STATUS" || { echo "Unknown status: $STATUS" >&2; exit 1; }
    tmux refresh-client -S 2>/dev/null || true

    # complete は 10秒後に自動クリア(start/他状態が先に来れば上書きされる)
    # NOTE: 時間減衰クリアの是非は仕様 §9 で確定予定。現状は既存挙動を維持。
    if [[ "$STATUS" == "complete" ]]; then
      (
        sleep 10
        current=$(tmux show-options -pv -t "$PANE_ID" @agent_status 2>/dev/null || echo "")
        if [[ "$current" == "complete" ]]; then
          clear_pane "$PANE_ID"
          tmux refresh-client -S 2>/dev/null || true
        fi
      ) &
      disown
    fi
    ;;

  start)
    # ターン開始: running 化 + heartbeat。通知アイコンは消える。出力ハッシュもリセット
    PANE_ID=$(resolve_pane)
    tmux set-option -p -t "$PANE_ID" @agent_status running 2>/dev/null || true
    tmux set-option -p -t "$PANE_ID" @agent_heartbeat "$(date +%s)" 2>/dev/null || true
    tmux set-option -p -t "$PANE_ID" -u @agent_icon 2>/dev/null || true
    tmux set-option -p -t "$PANE_ID" -u @agent_outhash 2>/dev/null || true
    tmux refresh-client -S 2>/dev/null || true
    ;;

  heartbeat)
    # 生存信号更新。停止状態(idle/permission/complete/error)は触らない。
    # running/hang/未設定 のみ running へ(hang からの自動復帰)。
    PANE_ID=$(resolve_pane)
    tmux set-option -p -t "$PANE_ID" @agent_heartbeat "$(date +%s)" 2>/dev/null || true
    current=$(tmux show-options -pv -t "$PANE_ID" @agent_status 2>/dev/null || echo "")
    case "$current" in
      ""|running|hang)
        tmux set-option -p -t "$PANE_ID" @agent_status running 2>/dev/null || true
        tmux set-option -p -t "$PANE_ID" -u @agent_icon 2>/dev/null || true
        [[ "$current" == "hang" ]] && tmux refresh-client -S 2>/dev/null || true
        ;;
    esac
    ;;

  clear)
    PANE_ID=$(resolve_pane)
    # 既にクリア済みなら何もしない(不要な refresh を避ける)
    current=$(tmux show-options -pv -t "$PANE_ID" @agent_status 2>/dev/null || echo "")
    [[ -z "$current" ]] && exit 0
    clear_pane "$PANE_ID"
    tmux refresh-client -S 2>/dev/null || true
    ;;

  hang-scan)
    # 全ペーン走査。running かつ heartbeat 停滞 > 閾値、かつ出力も不変なら hang。
    # 出力が動いていれば生存とみなし heartbeat をリセット(長時間 Bash の誤検知防止)。
    now=$(date +%s)
    changed=0
    while IFS=$'\t' read -r pid status hb prevhash; do
      [[ "$status" == "running" ]] || continue
      [[ -n "$hb" ]] || continue
      (( now - hb > HANG_THRESHOLD )) || continue

      curhash=$(tmux capture-pane -t "$pid" -p -S -5 2>/dev/null | cksum | cut -d' ' -f1)
      if [[ -z "$prevhash" || "$curhash" != "$prevhash" ]]; then
        # 出力が変化 or 初観測 → 生存。基準ハッシュ更新 + heartbeat リセット
        tmux set-option -p -t "$pid" @agent_outhash "$curhash" 2>/dev/null || true
        tmux set-option -p -t "$pid" @agent_heartbeat "$now" 2>/dev/null || true
        continue
      fi
      # 出力も停止 → hang
      apply_status "$pid" hang
      changed=1
    done < <(tmux list-panes -a -F "#{pane_id}$(printf '\t')#{@agent_status}$(printf '\t')#{@agent_heartbeat}$(printf '\t')#{@agent_outhash}")

    [[ $changed -eq 1 ]] && tmux refresh-client -S 2>/dev/null || true
    ;;

  *)
    echo "Usage: $0 {set <running|idle|permission|complete|hang|error>|start|heartbeat|clear|hang-scan}" >&2
    exit 1
    ;;
esac
