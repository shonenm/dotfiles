#!/bin/bash
# tmux Claude Code ペーン通知管理 (純tmuxローカル)
# Claude Code hooks から呼び出され、pane user option で通知状態を管理する。
# Beacon (workspace/Slack/SketchyBar) とは独立して動作。
#
# Usage:
#   tmux-claude-pane.sh set <status>    # idle | permission | complete
#   tmux-claude-pane.sh clear           # 通知クリア
#   tmux-claude-pane.sh scan            # 全ペーンをスキャンして idle Claude を検出・設定

set -euo pipefail

# tmux 外では何もしない
[[ -z "${TMUX:-}" ]] && exit 0

# $TMUX_PANE はプロセス起動元ペーンの ID（固定）
# tmux display-message -p はユーザーのアクティブペーンを返すため、
# hook 経由だと別ペーンの通知を誤クリアする
PANE_ID="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}' 2>/dev/null)}"
[[ -z "$PANE_ID" ]] && exit 0

case "${1:-}" in
  set)
    STATUS="${2:-idle}"
    case "$STATUS" in
      idle)       ICON="󰔟" ;;
      permission) ICON="󰌆" ;;
      complete)   ICON="" ;;
      *)
        echo "Unknown status: $STATUS" >&2
        exit 1
        ;;
    esac

    tmux set-option -p -t "$PANE_ID" @claude_status "$STATUS"
    tmux set-option -p -t "$PANE_ID" @claude_icon "$ICON"
    tmux refresh-client -S 2>/dev/null || true

    # complete は 10秒後に自動クリア（idle_prompt が先に来れば上書きされる）
    if [[ "$STATUS" == "complete" ]]; then
      (
        sleep 10
        # 現在の状態が complete のままなら解除（上書きされていたら何もしない）
        CURRENT=$(tmux show-options -pv -t "$PANE_ID" @claude_status 2>/dev/null || echo "")
        if [[ "$CURRENT" == "complete" ]]; then
          tmux set-option -p -t "$PANE_ID" -u @claude_status 2>/dev/null || true
          tmux set-option -p -t "$PANE_ID" -u @claude_icon 2>/dev/null || true
          tmux refresh-client -S 2>/dev/null || true
        fi
      ) &
      disown
    fi
    ;;

  clear)
    # 既にクリア済みなら何もしない（不要な refresh を避ける）
    CURRENT=$(tmux show-options -pv -t "$PANE_ID" @claude_status 2>/dev/null || echo "")
    [[ -z "$CURRENT" ]] && exit 0

    tmux set-option -p -t "$PANE_ID" -u @claude_status 2>/dev/null || true
    tmux set-option -p -t "$PANE_ID" -u @claude_icon 2>/dev/null || true
    tmux refresh-client -S 2>/dev/null || true
    ;;

  scan)
    # 全ペーンをスキャンして idle/permission 状態の Claude Code を検出
    found=0
    while IFS=$'\t' read -r pid cmd status; do
      # 既に状態設定済みならスキップ
      [[ -n "$status" ]] && continue
      # Claude Code はバージョン番号がコマンド名になる (例: 2.1.39)
      [[ "$cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue

      # ペーン内容の末尾を取得して状態を判定
      content=$(tmux capture-pane -t "$pid" -p -S -10 2>/dev/null || echo "")

      detected_status=""
      if echo "$content" | grep -qE '(permission|approve|allow)'; then
        detected_status="permission"
      elif echo "$content" | grep -qE '(^❯ $|⏵⏵|RALPH_COMPLETE|^\$ $)'; then
        detected_status="idle"
      fi

      if [[ -n "$detected_status" ]]; then
        case "$detected_status" in
          idle)       icon="󰔟" ;;
          permission) icon="󰌆" ;;
        esac
        tmux set-option -p -t "$pid" @claude_status "$detected_status"
        tmux set-option -p -t "$pid" @claude_icon "$icon"
        pane_title=$(tmux display-message -t "$pid" -p '#{pane_title}' 2>/dev/null || echo "")
        echo "$pid ($pane_title): $detected_status"
        ((found++))
      fi
    done < <(tmux list-panes -a -F "#{pane_id}$(printf '\t')#{pane_current_command}$(printf '\t')#{@claude_status}")

    if [[ $found -gt 0 ]]; then
      tmux refresh-client -S 2>/dev/null || true
      echo "Detected $found idle Claude pane(s)"
    else
      echo "No idle Claude panes found"
    fi
    ;;

  *)
    echo "Usage: $0 {set <idle|permission|complete>|clear|scan}" >&2
    exit 1
    ;;
esac
