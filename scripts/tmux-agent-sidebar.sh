#!/bin/bash
# AI Agent サイドバー (常設・自動更新)
# 全エージェント(running 含む)を狭い tmux pane に2行で常時表示する。opensessions の代替。
# 状態源は pane option(@agent_status)。ヘルパーは tmux-agent-status.sh を source して再利用。
# 仕様: docs/specs/agent-stop-notification.md §5.3
#
# Usage:
#   tmux-agent-sidebar.sh run      # サイドバー pane 内で動くループ(自動更新)
#   tmux-agent-sidebar.sh toggle   # サイドバー pane を開閉 (prefix+b)

set -uo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-status.sh"   # ヘルパー(status_icon/color, is_shell, branch_of, trunc, humanize)
set +e +o pipefail   # status.sh の set -e/pipefail を解除(常駐ループを堅牢に)

REFRESH="${AGENT_SIDEBAR_REFRESH:-3}"
WIDTH="${AGENT_SIDEBAR_WIDTH:-44}"

# running を含む全エージェントの状態順位(stopped 優先、running は後ろ)
sb_rank() { case "$1" in permission) echo 0;; hang) echo 1;; error) echo 2;; idle) echo 3;; complete) echo 4;; running) echo 8;; *) echo 9;; esac; }

# 表示幅基準の切り詰め(全角=2幅近似)。狭い pane で折返さないよう文字数でなく桁で切る
trunc_w() {
  local s="$1" max="$2" out="" w=0 ch cw i
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:i:1}"
    # ASCII 印字可能(0x20-0x7e)=1幅、それ以外(全角等)=2幅と近似。
    # [[:ascii:]] は macOS の正規表現が非対応のため case の範囲で判定する。
    case "$ch" in [\ -~]) cw=1 ;; *) cw=2 ;; esac
    (( w + cw > max )) && { out+="…"; break; }
    out+="$ch"; (( w += cw ))
  done
  printf '%s' "$out"
}

# 全エージェント行を生成: rank \t line1 \t line2
sb_rows() {
  local now w; now=$(date +%s); w=$(( WIDTH - 4 ))
  while IFS=$'\x1f' read -r sess win status hb path cmd title; do
    [[ -z "$status" ]] && continue          # 状態未設定(非エージェント)は除外
    is_shell "$cmd" && continue             # シェル復帰(終了済み)は除外
    local rank icon col task branch elapsed loc tool l1 l2
    rank=$(sb_rank "$status"); icon=$(status_icon "$status")
    if [[ "$status" == running ]]; then col="$C_DIM"; else col=$(status_color "$status"); fi
    task=$(trunc_w "${title:-$(basename "${path:-?}")}" "$w")
    branch=$(branch_of "$path"); tool=$(tool_of "$cmd"); loc="${sess}:${win}"
    if [[ "$hb" =~ ^[0-9]+$ ]]; then elapsed=$(humanize "$(( now - hb ))"); else elapsed="-"; fi
    l1=$(printf '%s%s %s%s' "$col" "$icon" "$task" "$C_RST")
    l2=$(printf '  %s%s · %s · %s · %s前%s' "$C_DIM" "$loc" "$branch" "$tool" "$elapsed" "$C_RST")
    printf '%s\t%s\t%s\n' "$rank" "$l1" "$l2"
  done < <(tmux list-panes -a -F \
    "#{session_name}$(printf '\x1f')#{window_index}$(printf '\x1f')#{@agent_status}$(printf '\x1f')#{@agent_heartbeat}$(printf '\x1f')#{pane_current_path}$(printf '\x1f')#{pane_current_command}$(printf '\x1f')#{pane_title}") \
    | sort -n -t$'\t' -k1,1
}

render() {
  printf '\033[H\033[2J'  # カーソル原点 + クリア
  printf '%s AGENTS%s  %s\n' "$C_BOLD" "$C_RST" "$(date '+%H:%M:%S')"
  printf '%s%s%s\n' "$C_DIM" "────────────────────" "$C_RST"
  local rows; rows=$(sb_rows)
  if [[ -z "$rows" ]]; then
    printf '%s(エージェントなし)%s\n' "$C_DIM" "$C_RST"
    return
  fi
  printf '%s\n' "$rows" | while IFS=$'\t' read -r _rank l1 l2; do
    printf '%s\n%s\n\n' "$l1" "$l2"
  done
}

case "${1:-toggle}" in
  run)
    # サイドバー pane 内ループ。INT/TERM で抜ける
    trap 'exit 0' INT TERM
    while true; do
      tmux info &>/dev/null || exit 0
      render
      sleep "$REFRESH" & wait $! || true
    done
    ;;
  toggle)
    existing=$(tmux show-options -gqv @agent_sidebar_pane 2>/dev/null || echo "")
    if [[ -n "$existing" ]] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$existing"; then
      tmux kill-pane -t "$existing" 2>/dev/null || true
      tmux set-option -gu @agent_sidebar_pane 2>/dev/null || true
    else
      pane=$(tmux split-window -fh -b -l "$WIDTH" -P -F '#{pane_id}' \
        "bash '$SCRIPT_DIR/tmux-agent-sidebar.sh' run")
      tmux set-option -p -t "$pane" @agent_status "" 2>/dev/null || true  # サイドバー自身は対象外
      tmux set-option -g @agent_sidebar_pane "$pane" 2>/dev/null || true
      tmux select-pane -L 2>/dev/null || true
    fi
    ;;
  once)
    render ;;   # 1回だけ描画(デバッグ用)
  *)
    echo "Usage: $0 {run|toggle|once}" >&2; exit 1 ;;
esac
