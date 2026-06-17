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
JUMP_FILE="/tmp/claude/agentpop-jump"
US=$'\x1f'

C_RED=$'\e[38;5;203m'; C_AMBER=$'\e[38;5;214m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
C_CUR=$'\e[38;5;45m'   # 現在の pane 強調(シアン)。prefix+a を押した pane を枠線で示す

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
  # 現在 pane(prefix+a を押した pane)は bind が @agent_cur_pane に保存している
  local now cur; now=$(date +%s); cur="$(tmux show-options -gv @agent_cur_pane 2>/dev/null || echo "")"
  while IFS="$US" read -r pid sess win status hb path cmd title stashed; do
    is_agent "$status" || continue          # 停止状態 + running を対象
    is_shell "$cmd" && continue             # シェル復帰(終了済み)は除外
    local rank icon col task branch elapsed loc tool line1 line2 g1 g2 mk
    # stash 済みは status に関わらず stash セクション(rank 6: stopped と running の間)へ
    if [[ -n "$stashed" ]]; then rank=6; else rank=$(status_rank "$status"); fi
    icon=$(status_icon "$status"); col=$(status_color "$status")
    task=$(trunc "${title:-$(basename "${path:-?}")}" 52)
    branch=$(branch_of "$path"); tool=$(tool_of "$cmd"); loc="${sess}:${win}"
    if [[ "$hb" =~ ^[0-9]+$ ]]; then elapsed=$(humanize "$(( now - hb ))"); else elapsed="-"; fi
    # 現在の pane(prefix+a を押した pane)は左に枠線バー + マーカーで強調
    if [[ -n "$cur" && "$pid" == "$cur" ]]; then
      g1="${C_CUR}▎${C_RST} "; g2="${C_CUR}▎${C_RST}  "; mk=" ${C_CUR}◀ current${C_RST}"
    else
      g1="  "; g2="   "; mk=""
    fi
    line1=$(printf '%s%s%s %-10s%s %s%s' "$g1" "$col" "$icon" "$status" "$C_RST" "$task" "$mk")
    line2=$(printf '%s%s%s · %s · %s · %s · %s%s' "$g2" "$C_DIM" "$sess" "$branch" "$loc" "$tool" "${elapsed}前" "$C_RST")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$pid" "$loc" "$status" "$line1" "$line2"
  done < <(tmux list-panes -a -F \
    "#{pane_id}${US}#{session_name}${US}#{window_index}${US}#{@agent_status}${US}#{@agent_heartbeat}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{pane_title}${US}#{@agent_stashed}")
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
  local prev="" sec
  while IFS=$'\t' read -r rank jt _wl status line1 line2; do
    # rank で区分: 0-4=停止(指示待ち) / 6=stash(あとで見る) / 8+=running
    if [[ "$rank" == 6 ]]; then sec=stash
    elif (( rank >= 8 )); then sec=running
    else sec=stopped; fi
    # セクション境界に独立した区切り項目(status=divider)を挿入。j/k 等が飛び越える(bind)。
    if [[ "$sec" != "$prev" ]]; then
      case "$sec" in
        stash)   printf '%s\t%s\t%s\n%s\0' "-" "divider" "$(printf '%s─── あとで見る (stash) ───%s' "$C_DIM" "$C_RST")" " " ;;
        running) printf '%s\t%s\t%s\n%s\0' "-" "divider" "$(printf '%s─── 実行中 (running) ───%s' "$C_DIM" "$C_RST")" " " ;;
      esac
      prev="$sec"
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
    local cap needs; cap=$(tmux capture-pane -p -e -S -200 -t "$target" 2>/dev/null)
    needs=$(extract_needs "$status" "$cap")
    [[ -n "$needs" ]] && printf '%s%s%s\n' "$col" "$needs" "$C_RST"
    printf '%s%s%s\n' "$C_DIM" "────────────────────────────" "$C_RST"
    printf '%s\n' "$cap"
  else
    printf '%sリモート/コンテナ: ライブ画面なし%s\n' "$C_DIM" "$C_RST"
    printf 'jump: %s\n' "$target"
  fi
}

# --- prefix+a エージェントビュー(swap-pane 方式) ---
# popup 右に blank placeholder を置き、選択エージェントの実ペインを swap-pane で blank と交換して
# 表示する。swap-pane は中身だけ入替えるため元 window の構造(ペイン数/位置/サイズ)は不変で、
# 該当スロットが一時 blank になるだけ。右は実ペインそのものなので live かつ Tab で操作可能。
# 交換は swapper(background)が 0.5秒デバウンスして実行 → スクロール中は swap せず移動を妨げない。
# 下記 selector / swapper / view-focus / blankpane アクション。

# source された場合(サイドバー等がヘルパー再利用)はディスパッチしない
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

case "${1:-popup}" in
  list)
    build_rows | { prev=""
      while IFS=$'\t' read -r _r _jt _wl _st l1 l2; do
        if [[ "$_r" == 6 ]]; then sec=stash; elif (( _r >= 8 )); then sec=running; else sec=stopped; fi
        if [[ "$sec" != "$prev" ]]; then
          case "$sec" in stash) printf '\n─── あとで見る (stash) ───\n';; running) printf '\n─── 実行中 (running) ───\n';; esac
          prev="$sec"
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
  stash-toggle)
    # pane の @agent_stashed をトグル(ローカル pane のみ。リモート行は no-op)。
    p="${2:-}"; [[ "$p" == %* ]] || exit 0
    if [[ -n "$(tmux show-options -p -t "$p" -qv @agent_stashed 2>/dev/null)" ]]; then
      tmux set-option -p -t "$p" -u @agent_stashed 2>/dev/null || true
    else
      tmux set-option -p -t "$p" @agent_stashed 1 2>/dev/null || true
    fi
    ;;
  open)
    # prefix+a エントリ(binding の display-popup 前段)。scratch session でセレクタを起動するだけ。
    # popup(binding 側)がこの session を attach し、中に [セレクタ | 選択エージェント実ペイン] を表示。
    origin=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    # 現在 pane(prefix+a を押した pane)を保存。build_local_rows がこれを読んで「◀ current」強調する。
    tmux set-option -g @agent_cur_pane "$origin" 2>/dev/null || true
    rows=$(build_rows)
    if [[ -z "$rows" ]]; then tmux display-message "停止中のエージェントなし"; exit 0; fi
    tmux kill-session -t _agentpop 2>/dev/null || true   # 残骸掃除
    mkdir -p "$(dirname "$JUMP_FILE")" 2>/dev/null || true
    rm -f "$JUMP_FILE" 2>/dev/null || true
    tmux new-session -d -s _agentpop "exec '$SELF' selector '$origin'"
    # 入れ子表示(status bar / pane 境界タイトル)を消して popup を単一画面に見せる。
    tmux set-option -t _agentpop status off 2>/dev/null || true
    tmux set-option -t _agentpop pane-border-status off 2>/dev/null || true
    # detach-on-destroy on: kill-session 時に popup client を別 session へ切替えず終了させる。
    # グローバル off のままだと popup 内に MAIN が出て閉じた後に二重化する。
    tmux set-option -t _agentpop detach-on-destroy on 2>/dev/null || true
    ;;
  selector)
    origin="${2:-}"
    sel=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    tmux set-option -p -t "$sel" @av_swapped "" 2>/dev/null || true
    tmux set-option -p -t "$sel" @av_blank "" 2>/dev/null || true
    tmux set-option -p -t "$sel" @av_want "" 2>/dev/null || true
    # focus 中は @av_want を立てるだけ(高速・移動を妨げない)。swapper(background)が「0.5秒変化なし」
    # を検知して初めて選択エージェント実ペインを blank と swap-pane する。swap-pane は中身だけ入替え
    # 元 window の構造(ペイン数/位置/サイズ)を保つため、元 window は該当スロットが一時 blank に
    # なるだけで崩れない。右は実ペインそのものなので live・Tab でフォーカスして操作、Enter でジャンプ。
    ( bash "$SELF" swapper "$sel" >/dev/null 2>&1 & )
    sel_out=$(build_rows | to_fzf_records \
      | fzf --read0 --ansi --delimiter=$'\t' --with-nth=3 --no-sort --reverse --height=100% --gap --cycle \
            --prompt 'agent> ' \
            --header 'j/k:移動  Tab:右で操作(C-Space o で戻る)  Enter:ジャンプ  r:再走査  s:stash  /:検索  q:閉じる' \
            --bind "focus:execute-silent(tmux set-option -p -t $sel @av_want {1})" \
            --bind "tab:execute-silent(bash '$SELF' view-focus '$sel')" \
            --bind 'g:first,G:last' \
            --bind 'j:down+transform:[ {2} = divider ] && echo down' \
            --bind 'k:up+transform:[ {2} = divider ] && echo up' \
            --bind 'down:down+transform:[ {2} = divider ] && echo down' \
            --bind 'up:up+transform:[ {2} = divider ] && echo up' \
            --bind 'ctrl-d:half-page-down+transform:[ {2} = divider ] && echo down' \
            --bind 'ctrl-u:half-page-up+transform:[ {2} = divider ] && echo up' \
            --bind 'load:transform:[ {2} = divider ] && echo down' \
            --bind "r:reload(bash '$SELF' rescan)" \
            --bind 'q:abort' \
            --bind "s:reload(bash '$SELF' stash-toggle {1}; bash '$SELF' rescan)" \
            --bind 'change:clear-query' \
            --bind '/:unbind(change)+unbind(j,k,g,G,r,q,s)+change-prompt(検索> )' \
            --bind 'enter:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(j,k,g,G,r,q,s)+change-prompt(agent> )" || echo accept' \
            --bind 'esc:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(change,j,k,g,G,r,q,s)+clear-query+change-prompt(agent> )" || echo abort' \
            --color 'pointer:203,marker:214') || true
    # accept(Enter)された target を jump file に記録 → popup を閉じた後に binding 末尾の
    # run-shell jump が元 client を該当ペインへ switch する(popup client では switch できない)。
    target=$(printf '%s' "$sel_out" | head -1 | cut -f1)
    if [[ -n "$target" && "$target" != "-" && "$target" != "divider" ]]; then
      printf '%s' "$target" > "$JUMP_FILE" 2>/dev/null || true
    fi
    # 後始末(最重要): swap 中の実ペインを元 window へ戻してから session kill。戻さず kill すると
    # 実ペインが _agentpop もろとも kill されエージェントが死ぬ。popup は selector(fzf)終了でしか
    # 閉じない(q/esc → ここで cleanup)ので、この経路で必ず swap back される。
    # swapper を先に止め、完全停止を待つ。swap-pane と @av_swapped 設定の中間で kill されると
    # 状態がズレるため、@av_swapped を信用せず「popup window に居る sel/blank 以外のペイン
    # (=swap 中の実エージェント)」を実配置から特定して blank と交換し元へ戻す(race-proof)。
    pkill -f "tmux-agent-status.sh swapper" 2>/dev/null || true
    for _ in 1 2 3 4 5; do pgrep -f "tmux-agent-status.sh swapper" >/dev/null || break; sleep 0.1; done
    win=$(tmux display-message -p -t "$sel" '#{window_id}' 2>/dev/null || true)
    blank=$(tmux show-options -p -t "$sel" -qv @av_blank 2>/dev/null || true)
    foreign=$(tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | grep -vxF "$sel" | grep -vxF "${blank:-__nope__}" | head -1)
    if [[ -n "$foreign" ]]; then
      if [[ -n "$blank" ]] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$blank"; then
        tmux swap-pane -d -s "$foreign" -t "$blank" 2>/dev/null || true   # 実エージェントを元 window へ
      else
        # blank 不在(異常時)。kill すると実ペインが死ぬため kill せず退避し session は残す。
        tmux break-pane -d -s "$foreign" 2>/dev/null || true
        exit 0
      fi
    fi
    tmux kill-session -t _agentpop 2>/dev/null || true
    ;;
  swapper)
    # swap デバウンス worker。$2=sel(fzf) pane。focus が立てた @av_want が DEBOUNCE 回(≒0.5秒)
    # 変化しなければ、その実ペインを blank と swap する。スクロール中(@av_want が変化し続ける間)は
    # swap せず移動を妨げない。ループ反復数で計時するため date の sub-second 精度に依存しない。
    sel="${2:-}"; [[ -z "$sel" ]] && exit 0
    DEBOUNCE=5            # 5 反復 × sleep 0.1s ≒ 0.5秒
    last_want="__init__"; stable=0
    while tmux has-session -t _agentpop 2>/dev/null; do
      want=$(tmux show-options -p -t "$sel" -qv @av_want 2>/dev/null || true)
      cur=$(tmux show-options -p -t "$sel" -qv @av_swapped 2>/dev/null || true)
      if [[ "$want" != "$last_want" ]]; then last_want="$want"; stable=0; else stable=$((stable+1)); fi
      if [[ "$want" != "$cur" && "$stable" -ge "$DEBOUNCE" ]]; then
        # 右に blank placeholder を遅延生成(popup attach 済み=正サイズ。起動時 split は崩れる)。
        blank=$(tmux show-options -p -t "$sel" -qv @av_blank 2>/dev/null || true)
        if [[ -z "$blank" ]] || ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$blank"; then
          blank=$(tmux split-window -h -l 58% -d -P -F '#{pane_id}' -t "$sel" "exec '$SELF' blankpane" 2>/dev/null || true)
          tmux set-option -p -t "$sel" @av_blank "$blank" 2>/dev/null || true
          tmux select-pane -t "$sel" 2>/dev/null || true
        fi
        if [[ -n "$blank" ]]; then
          # 現在 swap 中の実ペインを元へ戻す(blank が popup 右へ復帰)。-d でフォーカスは fzf に維持。
          if [[ -n "$cur" && "$cur" == %* ]] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$cur"; then
            tmux swap-pane -d -s "$cur" -t "$blank" 2>/dev/null || true
          fi
          # @av_want がローカル実ペインなら blank と swap(実ペインが popup 右へ)。リモート/非ペインは blank のまま。
          # -d 必須: 付けないと swap-pane が swap 先をアクティブ化し、勝手に右へフォーカスが移る。
          if [[ "$want" == %* ]] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$want"; then
            tmux swap-pane -d -s "$want" -t "$blank" 2>/dev/null || true
            tmux set-option -p -t "$sel" @av_swapped "$want" 2>/dev/null || true
          else
            tmux set-option -p -t "$sel" @av_swapped "" 2>/dev/null || true
          fi
        fi
      fi
      sleep 0.1
    done
    ;;
  view-focus)
    # Tab。swap 中の実ペイン(popup 右)へフォーカスして操作する。$2=sel pane。
    v=$(tmux show-options -p -t "${2:-}" -qv @av_swapped 2>/dev/null || true)
    [[ -n "$v" && "$v" == %* ]] && tmux select-pane -t "$v" 2>/dev/null || true
    ;;
  blankpane)
    # swap 用 placeholder。swap で元 window 側へ出たときに「popup で表示中」と分かるよう表示し待機。
    printf '\e[2J\e[H\n  %s(この pane は agent popup に表示中 — popup を閉じると復帰)%s\n' "$C_DIM" "$C_RST"
    exec sleep 2147483647
    ;;
  jump)
    # binding 末尾(display-popup の後)で元 client コンテキストから実行。selector が記録した
    # target へ元 client を switch する。popup を閉じた後に走るのでここで初めて実 client が飛ぶ。
    [[ -f "$JUMP_FILE" ]] || exit 0
    target=$(cat "$JUMP_FILE" 2>/dev/null || true); rm -f "$JUMP_FILE" 2>/dev/null || true
    [[ -z "$target" || "$target" == "-" ]] && exit 0
    tmux switch-client -t "$target" 2>/dev/null || true
    tmux select-window -t "$target" 2>/dev/null || true
    tmux select-pane -t "$target" 2>/dev/null || true
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
            --header 'j/k:移動  g/G:端  r:再走査  s:stash  /:検索  Enter:ジャンプ  q:閉じる' \
            --bind 'g:first,G:last' \
            --bind 'j:down+transform:[ {2} = divider ] && echo down' \
            --bind 'k:up+transform:[ {2} = divider ] && echo up' \
            --bind 'down:down+transform:[ {2} = divider ] && echo down' \
            --bind 'up:up+transform:[ {2} = divider ] && echo up' \
            --bind 'ctrl-d:half-page-down+transform:[ {2} = divider ] && echo down' \
            --bind 'ctrl-u:half-page-up+transform:[ {2} = divider ] && echo up' \
            --bind 'load:transform:[ {2} = divider ] && echo down' \
            --bind "r:reload(bash '$SELF' rescan)" \
            --bind 'q:abort' \
            --bind "s:reload(bash '$SELF' stash-toggle {1}; bash '$SELF' rescan)" \
            --bind 'change:clear-query' \
            --bind '/:unbind(change)+unbind(j,k,g,G,r,q,s)+change-prompt(検索> )' \
            --bind 'enter:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(j,k,g,G,r,q,s)+change-prompt(agent> )" || echo accept' \
            --bind 'esc:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(change,j,k,g,G,r,q,s)+clear-query+change-prompt(agent> )" || echo abort' \
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
    echo "Usage: $0 {open|selector|list|popup|reload|rescan|preview <t> <s>|swapper <sel>|view-focus <sel>|blankpane|jump}" >&2; exit 1 ;;
esac
