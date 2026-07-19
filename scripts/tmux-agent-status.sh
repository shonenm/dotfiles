#!/bin/bash
# AI Agent 横断ビュー。pane option + remote file storeを集約し、prefix+aで表示する。

set -euo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-lib.sh"
STATUS_DIR="${AGENT_STATUS_DIR:-${DOTFILES_SHARED_DIR:-$HOME/.cache}/claude/status}"
US=$'\x1f'

agent_index_panes() {
  "$SCRIPT_DIR/tmux-agent-index.sh" panes 2>/dev/null || tmux list-panes -a -F \
    "#{pane_id}${US}#{session_name}${US}#{window_index}${US}#{@agent_status}${US}#{@agent_heartbeat}${US}#{@agent_state_since}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{pane_title}${US}#{@agent_stashed}${US}#{@agent_sidebar_pane}${US}#{@agent_provider}"
}

agent_index_sessions() {
  "$SCRIPT_DIR/tmux-agent-index.sh" sessions 2>/dev/null || tmux list-sessions -F \
    "#{session_name}${US}#{@group}${US}#{session_attached}"
}

C_RED=$'\e[38;5;203m'; C_AMBER=$'\e[38;5;214m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
C_CUR=$'\e[38;5;45m'

status_rank() { case "$1" in permission) echo 0;; hang) echo 1;; error) echo 2;; idle) echo 3;; complete) echo 4;; running) echo 8;; *) echo 9;; esac; }
status_icon() { case "$1" in idle) echo "󰔟";; permission) echo "󰌆";; complete) echo "";; hang) echo "";; error) echo "";; running) echo "●";; *) echo " ";; esac; }
status_color() { case "$1" in permission|hang|error) printf '%s' "$C_RED";; running) printf '%s' "$C_DIM";; *) printf '%s' "$C_AMBER";; esac; }
is_stopped() { case "$1" in idle|permission|complete|hang|error) return 0;; *) return 1;; esac; }
is_agent() { case "$1" in idle|permission|complete|hang|error|running) return 0;; *) return 1;; esac; }
is_shell() { agent_is_shell "$1"; }

humanize() { local s="$1"; if (( s<60 )); then echo "${s}s"; elif (( s<3600 )); then echo "$((s/60))m"; else echo "$((s/3600))h"; fi; }
tool_of() { printf '%s\n' "${1%.exe}"; }
branch_of() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "-"; }
trunc() { local s="$1" n="$2"; s="${s//$'\t'/ }"; if (( ${#s} > n )); then printf '%s…' "${s:0:n}"; else printf '%s' "$s"; fi; }

build_local_rows() {
  local now cur; now=$(date +%s); cur="$(tmux show-options -gv @agent_cur_pane 2>/dev/null || echo "")"
  while IFS="$US" read -r pid sess win status hb state_since path cmd title stashed _sidebar provider; do
    is_agent "$status" || continue
    is_shell "$cmd" && continue
    local rank icon col task branch elapsed loc tool line1 line2 g1 g2 mk
    if [[ -n "$stashed" ]]; then rank=6; else rank=$(status_rank "$status"); fi
    icon=$(status_icon "$status"); col=$(status_color "$status")
    task=$(trunc "${title:-$(basename "${path:-?}")}" 52)
    branch=$(branch_of "$path"); tool="${provider:-$(tool_of "$cmd")}"; loc="${sess}:${win}"
    if [[ "$state_since" =~ ^[0-9]+$ ]]; then elapsed=$(humanize "$(( now - state_since ))")
    elif [[ "$hb" =~ ^[0-9]+$ ]]; then elapsed=$(humanize "$(( now - hb ))")
    else elapsed="-"; fi
    if [[ -n "$cur" && "$pid" == "$cur" ]]; then
      g1="${C_CUR}▎${C_RST} "; g2="${C_CUR}▎${C_RST}  "; mk=" ${C_CUR}◀ current${C_RST}"
    else
      g1="  "; g2="   "; mk=""
    fi
    line1=$(printf '%s%s%s %-10s%s %s%s' "$g1" "$col" "$icon" "$status" "$C_RST" "$task" "$mk")
    line2=$(printf '%s%s%s · %s · %s · %s · %s%s' "$g2" "$C_DIM" "$sess" "$branch" "$loc" "$tool" "${elapsed}前" "$C_RST")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rank" "$pid" "$loc" "$status" "$line1" "$line2"
  done < <(agent_index_panes)
}

build_file_rows() {
  local seen_windows="$1"
  [[ -d "$STATUS_DIR" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local now ws_seen="" identity; now=$(date +%s)
  local f rows=""
  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    rows+=$(jq -r --arg us "$US" '[(.updated // .timestamp // 0),(.status // ""),(.project // ""),(.workspace // ""),(.tmux_session // ""),(.tmux_window_index // .tmux_window // ""),(.tool // "")]|map(tostring)|join($us)' "$f" 2>/dev/null)$'\n'
  done
  printf '%s' "$rows" | sort -rn -t"$US" -k1,1 | while IFS="$US" read -r updated status project ws tsess twin provider; do
    [[ -z "$status" ]] && continue
    if [[ -n "$ws" ]]; then
      identity="${provider:-legacy}:${ws}"
      case "$ws_seen" in *"|${identity}|"*) continue;; *) ws_seen="${ws_seen}|${identity}|";; esac
    fi
    is_stopped "$status" || continue
    local loc="${tsess}:${twin}"
    if [[ -n "$tsess" && -n "$twin" ]]; then printf '%s\n' "$seen_windows" | grep -qxF "$loc" && continue; fi
    local host proj jt disp_loc rank icon col elapsed line1 line2
    if [[ "$project" == *:* ]]; then host="${project%%:*}"; proj="${project#*:}"; else host="ext"; proj="$project"; fi
    if [[ -n "$tsess" && -n "$twin" ]]; then jt="$loc"; disp_loc="$loc"; else jt="-"; disp_loc="-"; fi
    rank=$(status_rank "$status"); icon=$(status_icon "$status"); col=$(status_color "$status")
    if [[ "$updated" =~ ^[0-9]+$ && "$updated" != 0 ]]; then elapsed=$(humanize "$(( now - updated ))"); else elapsed="-"; fi
    line1=$(printf '%s%s %-10s%s %s' "$col" "$icon" "$status" "$C_RST" "$(trunc "$proj" 52)")
    line2=$(printf '   %s%s · %s · %s · %s%s' "$C_DIM" "$host" "$disp_loc" "${provider:-agent}" "${elapsed}前" "$C_RST")
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

to_fzf_records() {
  local prev="" sec
  while IFS=$'\t' read -r rank jt _wl status line1 line2; do
    if [[ "$rank" == 6 ]]; then sec=stash; elif (( rank >= 8 )); then sec=running; else sec=stopped; fi
    if [[ "$sec" != "$prev" ]]; then
      case "$sec" in
        stash) printf '%s\tdivider\t%s\n \0' "-" "${C_DIM}─── あとで見る (stash) ───${C_RST}" ;;
        running) printf '%s\tdivider\t%s\n \0' "-" "${C_DIM}─── 実行中 (running) ───${C_RST}" ;;
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
    local path title cmd branch tool cap needs
    path=$(tmux display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null)
    title=$(tmux display-message -p -t "$target" '#{pane_title}' 2>/dev/null)
    cmd=$(tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null)
    branch=$(branch_of "$path"); tool=$(tool_of "$cmd")
    printf '%s%s · %s · %s%s\n' "$C_DIM" "$target" "$tool" "$branch" "$C_RST"
    printf '%sタスク%s %s\n' "$C_BOLD" "$C_RST" "$title"
    cap=$(tmux capture-pane -p -e -S -200 -t "$target" 2>/dev/null)
    needs=$(extract_needs "$status" "$cap")
    [[ -n "$needs" ]] && printf '%s%s%s\n' "$col" "$needs" "$C_RST"
    printf '%s────────────────────────────%s\n%s\n' "$C_DIM" "$C_RST" "$cap"
  else
    printf '%sリモート/コンテナ: ライブ画面なし%s\njump: %s\n' "$C_DIM" "$C_RST" "$target"
  fi
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

case "${1:-popup}" in
  list)
    build_rows | while IFS=$'\t' read -r _rank _target _loc _status line1 line2; do printf '%s\n%s\n' "$line1" "$line2"; done | sed $'s/\e\\[[0-9;]*m//g'
    ;;
  preview) render_preview "${2:-}" "${3:-}" ;;
  rescan)
    "$SCRIPT_DIR/tmux-claude-pane.sh" hang-scan 2>/dev/null || true
    "$SCRIPT_DIR/tmux-agent-index.sh" refresh 2>/dev/null || true
    build_rows | to_fzf_records
    ;;
  stash-toggle)
    p="${2:-}"; [[ "$p" == %* ]] || exit 0
    if [[ -n "$(tmux show-options -p -t "$p" -qv @agent_stashed 2>/dev/null)" ]]; then
      tmux set-option -p -t "$p" -u @agent_stashed 2>/dev/null || true
    else
      tmux set-option -p -t "$p" @agent_stashed 1 2>/dev/null || true
    fi
    "$SCRIPT_DIR/tmux-agent-index.sh" invalidate 2>/dev/null || true
    ;;
  popup)
    rows=$(build_rows)
    if [[ -z "$rows" ]]; then tmux display-message "エージェントなし"; exit 0; fi
    sel=$(printf '%s\n' "$rows" | to_fzf_records \
      | fzf --read0 --ansi --delimiter=$'\t' --with-nth=3 --no-sort --reverse --height=100% --gap --cycle \
            --preview "bash '$SELF' preview {1} {2}" --preview-window 'right,58%,border-left,wrap' \
            --prompt 'agent> ' --header 'j/k:移動  g/G:端  r:再走査  s:stash  Enter:ジャンプ  /:検索  q:閉じる' \
            --bind 'g:first,G:last' \
            --bind 'j:down+transform:[ {2} = divider ] && echo down' \
            --bind 'k:up+transform:[ {2} = divider ] && echo up' \
            --bind 'down:down+transform:[ {2} = divider ] && echo down' \
            --bind 'up:up+transform:[ {2} = divider ] && echo up' \
            --bind 'ctrl-d:half-page-down+transform:[ {2} = divider ] && echo down' \
            --bind 'ctrl-u:half-page-up+transform:[ {2} = divider ] && echo up' \
            --bind 'load:transform:[ {2} = divider ] && echo down' \
            --bind "r:reload(bash '$SELF' rescan)" \
            --bind "s:reload(bash '$SELF' stash-toggle {1}; bash '$SELF' rescan)" \
            --bind 'q:abort' --bind 'change:clear-query' \
            --bind '/:unbind(change)+unbind(j,k,g,G,r,q,s)+change-prompt(検索> )' \
            --bind 'enter:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(j,k,g,G,r,q,s)+change-prompt(agent> )" || echo accept' \
            --bind 'esc:transform:[ "$FZF_PROMPT" = "検索> " ] && echo "rebind(change,j,k,g,G,r,q,s)+clear-query+change-prompt(agent> )" || echo abort' \
            --color 'pointer:203,marker:214') || exit 0
    target=$(printf '%s' "$sel" | head -1 | cut -f1)
    [[ -z "$target" || "$target" == "-" ]] && exit 0
    tmux switch-client -t "$target" 2>/dev/null || true
    tmux select-window -t "$target" 2>/dev/null || true
    tmux select-pane -t "$target" 2>/dev/null || true
    ;;
  reload)
    runtime_dir=$(agent_runtime_dir)
    base=$(agent_runtime_base)
    for lock in "$runtime_dir/hang-watch.pid" "$runtime_dir/index/daemon.pid" \
                "$base/claude/hang-watch.pid" "$base/claude/tmux-agent-index/daemon.pid"; do
      [[ -f "$lock" ]] || continue
      daemon_pid=$(cat "$lock" 2>/dev/null || true)
      if [[ -n "$daemon_pid" ]]; then
        case "$lock" in *index*) expected=tmux-agent-index.sh;; *) expected=tmux-agent-hang-watch.sh;; esac
        daemon_command=$(ps -p "$daemon_pid" -o command= 2>/dev/null || true)
        [[ "$daemon_command" == *"$expected"* ]] || continue
        kill "$daemon_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          kill -0 "$daemon_pid" 2>/dev/null || break
          sleep 0.1
        done
        [[ "$(cat "$lock" 2>/dev/null || true)" == "$daemon_pid" ]] && rm -f "$lock"
      fi
    done
    tmux run-shell -b "$SCRIPT_DIR/tmux-agent-index.sh daemon >/dev/null 2>&1 || true"
    tmux run-shell -b "$SCRIPT_DIR/tmux-agent-hang-watch.sh >/dev/null 2>&1 || true"
    "$SCRIPT_DIR/tmux-claude-pane.sh" hang-scan 2>/dev/null || true
    "$SCRIPT_DIR/tmux-agent-index.sh" refresh 2>/dev/null || true
    tmux refresh-client -S 2>/dev/null || true
    tmux display-message "agent state reloaded"
    ;;
  *) echo "Usage: $0 {list|popup|rescan|preview <target> <status>|stash-toggle <pane>|reload}" >&2; exit 1 ;;
esac
