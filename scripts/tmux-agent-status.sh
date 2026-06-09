#!/bin/bash
# AI Agent 横断集約ビュー (リッチ版 / 2行表示)
# 全 tmux session/window/pane(local の pane option) + リモート/コンテナ(file store)を
# 走査し、停止中(idle/permission/complete/hang/error)のエージェントを2行で一覧表示。
# fzf ライブプレビュー(右ペイン)で各エージェントの画面末尾・要対応内容を、開かずに triage。
# 仕様: docs/specs/agent-stop-notification.md §5.3
#
# 表示(2行/エージェント):
#   1行目: <icon> <status>  <タスク(pane_title)>            <経過>
#   2行目:    <session> · <branch> · <loc> · <tool>
#
# Usage:
#   tmux-agent-status.sh list            # CLI 一覧(2行、色なし)
#   tmux-agent-status.sh popup           # fzf + ライブプレビューでジャンプ
#   tmux-agent-status.sh reload          # watcher 再起動 + 即時スキャン
#   tmux-agent-status.sh preview <t> <s> # fzf プレビュー描画(内部用)
#
# 内部 sortable 行(タブ区切り): rank \t jump_target \t window_loc \t status \t line1 \t line2
#   jump_target : local=pane_id(%N) / remote=session:window / "-"=ジャンプ不可
# 注: tmux/jq の多フィールド読みは US(\x1f)区切り(タブは IFS 空白で空フィールドが coalesce する)。

set -euo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STATUS_DIR="${AGENT_STATUS_DIR:-/tmp/claude/status}"
US=$'\x1f'

C_RED=$'\e[38;5;203m'; C_AMBER=$'\e[38;5;214m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'

status_rank() { case "$1" in permission) echo 0;; hang) echo 1;; error) echo 2;; idle) echo 3;; complete) echo 4;; running) echo 8;; *) echo 9;; esac; }
status_icon() { case "$1" in idle) echo "󰔟";; permission) echo "󰌆";; complete) echo "";; hang) echo "";; error) echo "";; running) echo "●";; *) echo " ";; esac; }
status_color() { case "$1" in permission|hang|error) printf '%s' "$C_RED";; running) printf '%s' "$C_DIM";; *) printf '%s' "$C_AMBER";; esac; }
is_stopped() { case "$1" in idle|permission|complete|hang|error) return 0;; *) return 1;; esac; }
is_agent() { case "$1" in idle|permission|complete|hang|error|running) return 0;; *) return 1;; esac; }
is_shell() { case "${1#-}" in zsh|bash|sh|fish|dash|ksh|tcsh|nu|xonsh|elvish) return 0;; *) return 1;; esac; }

humanize() { local s="$1"; if (( s<60 )); then echo "${s}s"; elif (( s<3600 )); then echo "$((s/60))m"; else echo "$((s/3600))h"; fi; }
tool_of() { local c="${1%.exe}"; case "$c" in claude) echo claude;; cmd) echo cmd;; node) echo node;; *) echo "$c";; esac; }
branch_of() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "-"; }
trunc() { local s="$1" n="$2"; s="${s//$'\t'/ }"; if (( ${#s} > n )); then printf '%s…' "${s:0:n}"; else printf '%s' "$s"; fi; }

# ローカル(pane option)行 → sortable 6 フィールド
build_local_rows() {
  local now; now=$(date +%s)
  while IFS="$US" read -r pid sess win status hb path cmd title; do
    is_agent "$status" || continue          # 停止状態 + running を対象
    is_shell "$cmd" && continue             # シェル復帰(終了済み)は除外
    local rank icon col task branch elapsed loc tool line1 line2
    rank=$(status_rank "$status"); icon=$(status_icon "$status"); col=$(status_color "$status")
    task=$(trunc "${title:-$(basename "${path:-?}")}" 52)
    branch=$(branch_of "$path"); tool=$(tool_of "$cmd"); loc="${sess}:${win}"
    if [[ "$hb" =~ ^[0-9]+$ ]]; then elapsed=$(humanize "$(( now - hb ))"); else elapsed="-"; fi
    line1=$(printf '%s%s %-10s%s %s' "$col" "$icon" "$status" "$C_RST" "$task")
    line2=$(printf '   %s%s · %s · %s · %s · %s%s' "$C_DIM" "$sess" "$branch" "$loc" "$tool" "${elapsed}前" "$C_RST")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$pid" "$loc" "$status" "$line1" "$line2"
  done < <(tmux list-panes -a -F \
    "#{pane_id}${US}#{session_name}${US}#{window_index}${US}#{@agent_status}${US}#{@agent_heartbeat}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{pane_title}")
}

# リモート/コンテナ(file store)行 → sortable 6 フィールド。seen_windows の window は除外
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
    local host proj jt disp_loc rank icon col elapsed line1 line2
    if [[ "$project" == *:* ]]; then host="${project%%:*}"; proj="${project#*:}"; else host="ext"; proj="$project"; fi
    if [[ -n "$tsess" && -n "$twin" ]]; then jt="$loc"; disp_loc="$loc"; else jt="-"; disp_loc="-"; fi
    rank=$(status_rank "$status"); icon=$(status_icon "$status"); col=$(status_color "$status")
    if [[ "$updated" =~ ^[0-9]+$ && "$updated" != "0" ]]; then elapsed=$(humanize "$(( now - updated ))"); else elapsed="-"; fi
    line1=$(printf '%s%s %-10s%s %s' "$col" "$icon" "$status" "$C_RST" "$(trunc "$proj" 52)")
    line2=$(printf '   %s%s · %s · %s%s' "$C_DIM" "$host" "$disp_loc" "${elapsed}前" "$C_RST")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$jt" "$loc" "$status" "$line1" "$line2"
  done
}

build_rows() {
  local local_raw seen_windows file_raw
  local_raw=$(build_local_rows)
  seen_windows=$(printf '%s\n' "$local_raw" | awk -F'\t' 'NF{print $3}')
  file_raw=$(build_file_rows "$seen_windows")
  printf '%s\n%s\n' "$local_raw" "$file_raw" | awk -F'\t' 'NF>=6' | sort -n
}

# sortable 行 → fzf 入力(NUL 区切り、各レコードは「target<TAB>status<TAB>line1<LF>line2」)
# running は最下部の別セクション。区切り見出しは独立項目にせず、最初の running 項目の
# 表示先頭に前置する(独立した選択不可ダミー項目を作らない=見出しにカーソルが乗らない)。
to_fzf_records() {
  local seen_running=0
  while IFS=$'\t' read -r _rank jt _wl status line1 line2; do
    if [[ "$status" == running && $seen_running -eq 0 ]]; then
      seen_running=1
      # 区切りは独立項目(status=divider)。j/k/↑/↓ がこの項目を飛び越える(下記 bind)。
      printf '%s\t%s\t%s\n%s\0' "-" "divider" \
        "$(printf '%s─── 実行中 (running) ───%s' "$C_DIM" "$C_RST")" " "
    fi
    printf '%s\t%s\t%s\n%s\0' "$jt" "$status" "$line1" "$line2"
  done
}

extract_needs() {
  local status="$1" tailtxt="$2" line
  line=$(printf '%s\n' "$tailtxt" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*[❯➜$#%>]' | grep -v '󰊠' | tail -1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [[ -z "$line" ]] && return 0
  case "$status" in permission) echo "承認待ち: $line";; idle) echo "最後: $line";; *) echo "$line";; esac
}

render_preview() {
  local target="$1" status="$2"
  [[ "$status" == divider ]] && { printf '%s実行中のエージェント(対応不要)%s\n' "$C_DIM" "$C_RST"; return; }
  local col icon; col=$(status_color "$status"); icon=$(status_icon "$status")
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

# source された場合(サイドバー等がヘルパー再利用)はディスパッチしない
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

case "${1:-popup}" in
  list)
    build_rows | { seen_running=0
      while IFS=$'\t' read -r _r _jt _wl _st l1 l2; do
        if [[ "$_st" == running && $seen_running -eq 0 ]]; then
          seen_running=1; printf '\n─── 実行中 (running) ───\n'
        fi
        printf '%s\n%s\n' "$l1" "$l2"
      done; } | sed $'s/\e\\[[0-9;]*m//g'
    ;;
  preview)
    render_preview "${2:-}" "${3:-}"
    ;;
  rescan)
    # 全再走査(hang-scan で hang 検出・シェル復帰 GC を更新)してから最新の fzf レコードを出力。
    # popup 内 ^R から reload で呼ばれる。
    bash "$(dirname "$SELF")/tmux-claude-pane.sh" hang-scan 2>/dev/null || true
    build_rows | to_fzf_records
    ;;
  popup)
    rows=$(build_rows)
    if [[ -z "$rows" ]]; then tmux display-message "停止中のエージェントなし"; exit 0; fi
    # vim 風操作。既定ナビでは検索しない(空 query=全件表示)。文字を打っても
    # change:clear-query で即クリアするので検索バーに溜まらずフィルタもされない。
    # / で検索開始(change と nav 文字を unbind して入力可能化)。
    # 検索中 enter=確定(フィルタ保持しナビ復帰・遷移しない) / esc=検索取消(空 query に戻し全候補再表示)。
    # ナビ中 enter=ジャンプ / esc=閉じる。--cycle で端循環。↑↓ は常にナビ可能。
    sel=$(printf '%s\n' "$rows" | to_fzf_records \
      | fzf --read0 --ansi --delimiter=$'\t' --with-nth=3 --no-sort --reverse --height=100% --gap --cycle \
            --preview "bash '$SELF' preview {1} {2}" \
            --preview-window 'right,58%,border-left,wrap' \
            --prompt 'agent> ' \
            --header 'j/k:移動  C-u/d:ページ  g/G:上下端  r:再走査  /:検索  Enter:ジャンプ' \
            --bind 'g:first,G:last' \
            --bind 'j:down+transform:[ {2} = divider ] && echo down' \
            --bind 'k:up+transform:[ {2} = divider ] && echo up' \
            --bind 'down:down+transform:[ {2} = divider ] && echo down' \
            --bind 'up:up+transform:[ {2} = divider ] && echo up' \
            --bind 'ctrl-d:half-page-down+transform:[ {2} = divider ] && echo down' \
            --bind 'ctrl-u:half-page-up+transform:[ {2} = divider ] && echo up' \
            --bind "r:reload(bash '$SELF' rescan)" \
            --bind 'change:clear-query' \
            --bind '/:unbind(change)+unbind(j,k,g,G,r)+change-prompt(検索> )' \
            --bind 'enter:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(j,k,g,G,r)+change-prompt(agent> )" || echo accept' \
            --bind 'esc:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(change,j,k,g,G,r)+clear-query+change-prompt(agent> )" || echo abort' \
            --color 'pointer:203,marker:214') || exit 0
    [[ -z "$sel" ]] && exit 0
    target=$(printf '%s' "$sel" | head -1 | cut -f1)
    [[ -z "$target" || "$target" == "-" ]] && exit 0
    tmux switch-client -t "$target" 2>/dev/null || true
    tmux select-window -t "$target" 2>/dev/null || true
    tmux select-pane -t "$target" 2>/dev/null || true
    ;;
  reload)
    reload_dir="$(dirname "$SELF")"
    pkill -f tmux-agent-hang-watch.sh 2>/dev/null || true
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
    echo "Usage: $0 {list|popup|reload|rescan|preview <target> <status>}" >&2; exit 1 ;;
esac
