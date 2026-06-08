#!/bin/bash
# AI Agent 横断集約ビュー (リッチ版)
# 全 tmux session/window/pane(local の pane option) + リモート/コンテナ(file store)を
# 走査し、停止中(idle/permission/complete/hang/error)のエージェントを一覧表示。
# fzf ライブプレビュー(右ペイン)で各エージェントの画面末尾・要対応内容を、開かずに triage。
# 仕様: docs/specs/agent-stop-notification.md §5.3
#
# Usage:
#   tmux-agent-status.sh list            # CLI 一覧(人間可読、色なし)
#   tmux-agent-status.sh popup           # fzf + ライブプレビューでジャンプ (display-popup 用)
#   tmux-agent-status.sh preview <t> <s> # fzf プレビュー描画(内部用): t=jump_target s=status
#
# 内部行: rank \t jump_target \t window_loc \t status \t display(ANSI)
#   jump_target : local=pane_id(%N) / remote=session:window / "-"=ジャンプ不可
#
# 注: tmux/jq の多フィールド読みは US(\x1f)区切り(タブは IFS 空白で空フィールドが coalesce する)。

set -euo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STATUS_DIR="${AGENT_STATUS_DIR:-/tmp/claude/status}"
US=$'\x1f'

# ANSI
C_RED=$'\e[38;5;203m'; C_AMBER=$'\e[38;5;214m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'

status_rank() { case "$1" in permission) echo 0;; hang) echo 1;; error) echo 2;; idle) echo 3;; complete) echo 4;; *) echo 9;; esac; }
status_icon() { case "$1" in idle) echo "󰔟";; permission) echo "󰌆";; complete) echo "";; hang) echo "";; error) echo "";; *) echo " ";; esac; }
# 状態色: 要対応(permission/hang/error)=赤、それ以外(idle/complete)=amber
status_color() { case "$1" in permission|hang|error) printf '%s' "$C_RED";; *) printf '%s' "$C_AMBER";; esac; }
is_stopped() { case "$1" in idle|permission|complete|hang|error) return 0;; *) return 1;; esac; }

humanize() {
  local s="$1"
  if (( s < 60 )); then echo "${s}s"; elif (( s < 3600 )); then echo "$(( s/60 ))m"; else echo "$(( s/3600 ))h"; fi
}

# ツール種別(pane_current_command から)
tool_of() { local c="${1%.exe}"; case "$c" in claude) echo claude;; cmd) echo cmd;; node) echo node;; *) echo "$c";; esac; }
# 前景コマンドがシェル(=エージェント終了でプロンプト復帰)か
is_shell() { case "${1#-}" in zsh|bash|sh|fish|dash|ksh|tcsh|nu|xonsh|elvish) return 0;; *) return 1;; esac; }
# git ブランチ(worktree 含む)
branch_of() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "-"; }
# 簡易切り詰め(文字数)
trunc() { local s="$1" n="$2"; if (( ${#s} > n )); then printf '%s…' "${s:0:n}"; else printf '%s' "$s"; fi; }

# ローカル(pane option)行。task=pane_title, tool=pane_current_command
build_local_rows() {
  local now; now=$(date +%s)
  while IFS="$US" read -r pid sess win status hb path cmd title; do
    is_stopped "$status" || continue
    is_shell "$cmd" && continue   # エージェント終了済み(シェル復帰)→ 残留を表示しない
    local rank icon col task branch elapsed loc
    rank=$(status_rank "$status"); icon=$(status_icon "$status"); col=$(status_color "$status")
    task=$(trunc "${title:-$(basename "${path:-?}")}" 40)
    branch=$(branch_of "$path")
    loc="${sess}:${win}"
    if [[ "$hb" =~ ^[0-9]+$ ]]; then elapsed=$(humanize "$(( now - hb ))"); else elapsed="-"; fi
    local disp
    disp=$(printf '%s%s %-10s%s  %-42s  %s%-14s%s  %s%4s%s' \
      "$col" "$icon" "$status" "$C_RST" "$task" "$C_DIM" "$branch" "$C_RST" "$C_DIM" "$elapsed" "$C_RST")
    printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "$pid" "$loc" "$status" "$disp"
  done < <(tmux list-panes -a -F \
    "#{pane_id}${US}#{session_name}${US}#{window_index}${US}#{@agent_status}${US}#{@agent_heartbeat}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{pane_title}")
}

# リモート/コンテナ(file store)行。seen_windows の window は除外(local 優先)
build_file_rows() {
  local seen_windows="$1"
  [[ -d "$STATUS_DIR" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local now ws_seen=""; now=$(date +%s)
  local f rows=""
  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    rows+=$(jq -r --arg us "$US" '[(.updated // .timestamp // 0),(.status // ""),(.project // ""),(.workspace // ""),(.tmux_session // ""),(.tmux_window_index // .tmux_window // "")]|map(tostring)|join($us)' "$f" 2>/dev/null)$'\n'
  done
  printf '%s' "$rows" | sort -rn -t"$US" -k1,1 | while IFS="$US" read -r updated status project ws tsess twin; do
    [[ -z "$status" ]] && continue
    is_stopped "$status" || continue
    if [[ -n "$ws" ]]; then case "$ws_seen" in *"|${ws}|"*) continue;; *) ws_seen="${ws_seen}|${ws}|";; esac; fi
    local loc="${tsess}:${twin}"
    if [[ -n "$tsess" && -n "$twin" ]]; then printf '%s\n' "$seen_windows" | grep -qxF "$loc" && continue; fi
    local host proj jt disp_loc
    if [[ "$project" == *:* ]]; then host="${project%%:*}"; proj="${project#*:}"; else host="ext"; proj="$project"; fi
    if [[ -n "$tsess" && -n "$twin" ]]; then jt="$loc"; disp_loc="$loc"; else jt="-"; disp_loc="-"; fi
    local rank icon col elapsed
    rank=$(status_rank "$status"); icon=$(status_icon "$status"); col=$(status_color "$status")
    if [[ "$updated" =~ ^[0-9]+$ && "$updated" != "0" ]]; then elapsed=$(humanize "$(( now - updated ))"); else elapsed="-"; fi
    local disp
    disp=$(printf '%s%s %-10s%s  %s%-8s%s %-33s  %s%-14s%s  %s%4s%s' \
      "$col" "$icon" "$status" "$C_RST" "$C_BOLD" "$host" "$C_RST" "$(trunc "$proj" 33)" "$C_DIM" "$disp_loc" "$C_RST" "$C_DIM" "$elapsed" "$C_RST")
    printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "$jt" "$loc" "$status" "$disp"
  done
}

build_rows() {
  local local_raw seen_windows file_raw
  local_raw=$(build_local_rows)
  seen_windows=$(printf '%s\n' "$local_raw" | awk -F'\t' 'NF{print $3}')
  file_raw=$(build_file_rows "$seen_windows")
  printf '%s\n%s\n' "$local_raw" "$file_raw" | awk 'NF' | sort -n
}

# 要対応の中身を capture-pane 末尾から軽く抽出
extract_needs() {
  local status="$1" tailtxt="$2" line
  # 空行・シェルプロンプト・powerline/装飾行を除外し、意味のある最終行を採用
  line=$(printf '%s\n' "$tailtxt" \
    | grep -vE '^[[:space:]]*$' \
    | grep -vE '^[[:space:]]*[❯➜$#%>]' \
    | grep -v '󰊠' \
    | tail -1 \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [[ -z "$line" ]] && return 0
  case "$status" in
    permission) echo "承認待ち: $line" ;;
    idle)       echo "最後: $line" ;;
    *)          echo "$line" ;;
  esac
}

# プレビュー描画(fzf から各カーソル移動で呼ばれる)
render_preview() {
  local target="$1" status="$2"
  local col icon; col=$(status_color "$status"); icon=$(status_icon "$status")
  # 状態色のヘッダバー(=枠の色)
  printf '%s%s ▌ %s%s\n' "$col" "$icon" "$(echo "$status" | tr '[:lower:]' '[:upper:]')" "$C_RST"
  if [[ "$target" == %* ]]; then
    local path title cmd branch tool
    path=$(tmux display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null)
    title=$(tmux display-message -p -t "$target" '#{pane_title}' 2>/dev/null)
    cmd=$(tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null)
    branch=$(branch_of "$path"); tool=$(tool_of "$cmd")
    printf '%s%s · %s · %s%s\n' "$C_DIM" "$target" "$tool" "$branch" "$C_RST"
    printf '%sタスク%s %s\n' "$C_BOLD" "$C_RST" "$title"
    local cap needs; cap=$(tmux capture-pane -p -S -40 -t "$target" 2>/dev/null)
    needs=$(extract_needs "$status" "$cap")
    [[ -n "$needs" ]] && printf '%s%s%s\n' "$col" "$needs" "$C_RST"
    printf '%s%s%s\n' "$C_DIM" "────────────────────────────" "$C_RST"
    printf '%s\n' "$cap"
  else
    printf '%sリモート/コンテナ: ライブ画面なし%s\n' "$C_DIM" "$C_RST"
    printf 'jump: %s\n' "$target"
  fi
}

case "${1:-popup}" in
  list)
    build_rows | cut -f5- | sed $'s/\e\\[[0-9;]*m//g'  # 色除去
    ;;
  preview)
    render_preview "${2:-}" "${3:-}"
    ;;
  popup)
    rows=$(build_rows)
    if [[ -z "$rows" ]]; then tmux display-message "停止中のエージェントなし"; exit 0; fi
    sel=$(printf '%s\n' "$rows" \
      | fzf --ansi --delimiter=$'\t' --with-nth=5 --no-sort --reverse --height=100% \
            --preview "bash '$SELF' preview {2} {4}" \
            --preview-window 'right,58%,border-left,wrap' \
            --prompt 'agent> ' \
            --header '停止中エージェント: ↑↓ で確認, Enter でジャンプ' \
            --color 'pointer:203,marker:214') || exit 0
    [[ -z "$sel" ]] && exit 0
    target=$(printf '%s' "$sel" | cut -f2)
    [[ -z "$target" || "$target" == "-" ]] && exit 0
    tmux switch-client -t "$target" 2>/dev/null || true
    tmux select-window -t "$target" 2>/dev/null || true
    tmux select-pane -t "$target" 2>/dev/null || true
    ;;
  reload)
    # エージェント通知サブシステムを最新化:
    #   watcher を単一インスタンスに再起動 + 即時 hang-scan(残留/シェル復帰の GC・ハング検出)
    # ※ テーマ/キーバインド等 tmux 設定の再読込は別途 prefix+r
    reload_dir="$(dirname "$SELF")"
    pkill -f tmux-agent-hang-watch.sh 2>/dev/null || true
    # 旧インスタンスの終了を最大3s待つ(多重起動防止)
    for _ in 1 2 3 4 5 6; do
      ps axo command 2>/dev/null | grep 'tmux-agent-hang-watch.sh' | grep -v grep | grep -q '/bin/bash' || break
      sleep 0.5
    done
    rm -f /tmp/claude/hang-watch.pid
    tmux run-shell -b "$reload_dir/tmux-agent-hang-watch.sh >/dev/null 2>&1 || true"
    bash "$reload_dir/tmux-claude-pane.sh" hang-scan 2>/dev/null || true
    tmux refresh-client -S 2>/dev/null || true
    tmux display-message "agent-notify reloaded (watcher 再起動 + 状態スキャン)"
    ;;
  *)
    echo "Usage: $0 {list|popup|reload|preview <target> <status>}" >&2; exit 1 ;;
esac
