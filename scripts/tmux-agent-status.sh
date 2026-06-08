#!/bin/bash
# AI Agent 横断集約ビュー
# 全 tmux session/window/pane(local の pane option) + リモート/コンテナ(file store)を
# 走査し、停止中(idle/permission/complete/hang/error)のエージェントを一覧表示、
# 選択でそのペーン/ウィンドウへジャンプする。
# 仕様: docs/specs/agent-stop-notification.md §5.3 / §3.3 / §4.4
#
# Usage:
#   tmux-agent-status.sh list    # 停止中エージェントを一覧出力(人間可読)
#   tmux-agent-status.sh popup   # fzf 一覧から選択してジャンプ (tmux display-popup 用)
#
# 内部行フォーマット(タブ区切り): rank \t jump_target \t window_loc \t 表示文字列
#   jump_target : local=pane_id / remote=session:window
#   window_loc  : session:window (local 行とリモート行の重複排除キー)

set -euo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

STATUS_DIR="${AGENT_STATUS_DIR:-/tmp/claude/status}"

# 状態 → 表示順位(小さいほど緊急)
status_rank() {
  case "$1" in
    permission) echo 0 ;;
    hang)       echo 1 ;;
    error)      echo 2 ;;
    idle)       echo 3 ;;
    complete)   echo 4 ;;
    *)          echo 9 ;;
  esac
}

status_icon() {
  case "$1" in
    idle)       echo "󰔟" ;;
    permission) echo "󰌆" ;;
    complete)   echo "" ;;
    hang)       echo "" ;;
    error)      echo "" ;;
    *)          echo " " ;;
  esac
}

# 経過秒を人間可読に
humanize() {
  local s="$1"
  if   (( s < 60 ));   then echo "${s}s"
  elif (( s < 3600 )); then echo "$(( s / 60 ))m"
  else                      echo "$(( s / 3600 ))h"
  fi
}

is_stopped() {
  case "$1" in
    idle|permission|complete|hang|error) return 0 ;;
    *) return 1 ;;
  esac
}

# ローカル(pane option)行を生成
build_local_rows() {
  local now
  now=$(date +%s)
  while IFS=$'\t' read -r pid sess win pane status hb path host; do
    is_stopped "$status" || continue

    local rank icon project elapsed loc hostlabel
    rank=$(status_rank "$status")
    icon=$(status_icon "$status")
    project=$(basename "${path:-?}")
    loc="${sess}:${win}"
    [[ -n "$hb" ]] && elapsed=$(humanize "$(( now - hb ))") || elapsed="-"
    hostlabel="local"
    [[ -n "$host" ]] && hostlabel="$host"

    printf '%s\t%s\t%s\t%s %-10s %-7s %-18s %-12s %s\n' \
      "$rank" "$pid" "$loc" "$icon" "$status" "$hostlabel" "$project" "${loc}.${pane}" "$elapsed"
  done < <(tmux list-panes -a -F \
    "#{pane_id}$(printf '\t')#{session_name}$(printf '\t')#{window_index}$(printf '\t')#{pane_index}$(printf '\t')#{@agent_status}$(printf '\t')#{@agent_heartbeat}$(printf '\t')#{pane_current_path}$(printf '\t')#{@agent_host}")
}

# リモート/コンテナ(file store)行を生成。seen_windows に含まれる window は除外(local 優先)
build_file_rows() {
  local seen_windows="$1"
  [[ -d "$STATUS_DIR" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local now ws_seen=""
  now=$(date +%s)

  # updated 降順で走査し、workspace ごとに最新のみ採用
  local f rows
  rows=""
  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    rows+=$(jq -r '[(.updated // .timestamp // 0), (.status // ""), (.project // ""), (.workspace // ""), (.tmux_session // ""), (.tmux_window_index // .tmux_window // "")] | @tsv' "$f" 2>/dev/null)$'\n'
  done

  printf '%s' "$rows" | sort -rn -t"$(printf '\t')" -k1,1 | while IFS=$'\t' read -r updated status project ws tsess twin; do
    [[ -z "$status" ]] && continue
    is_stopped "$status" || continue

    # workspace 重複排除(最新優先)
    if [[ -n "$ws" ]]; then
      case "$ws_seen" in
        *"|${ws}|"*) continue ;;
        *) ws_seen="${ws_seen}|${ws}|" ;;
      esac
    fi

    local loc="${tsess}:${twin}"
    # local で既出の window はスキップ(重複防止)
    if [[ -n "$tsess" && -n "$twin" ]]; then
      printf '%s\n' "$seen_windows" | grep -qxF "$loc" && continue
    fi

    local host proj jt disp_loc
    if [[ "$project" == *:* ]]; then host="${project%%:*}"; proj="${project#*:}"; else host="ext"; proj="$project"; fi
    if [[ -n "$tsess" && -n "$twin" ]]; then jt="$loc"; disp_loc="$loc"; else jt="-"; disp_loc="-"; fi

    local rank icon elapsed
    rank=$(status_rank "$status")
    icon=$(status_icon "$status")
    if [[ -n "$updated" && "$updated" != "0" ]]; then elapsed=$(humanize "$(( now - updated ))"); else elapsed="-"; fi

    printf '%s\t%s\t%s\t%s %-10s %-7s %-18s %-12s %s\n' \
      "$rank" "$jt" "$loc" "$icon" "$status" "$host" "$proj" "$disp_loc" "$elapsed"
  done
}

build_rows() {
  local local_raw seen_windows file_raw
  local_raw=$(build_local_rows)
  seen_windows=$(printf '%s\n' "$local_raw" | awk -F'\t' 'NF{print $3}')
  file_raw=$(build_file_rows "$seen_windows")
  printf '%s\n%s\n' "$local_raw" "$file_raw" | awk 'NF' | sort -n
}

jump_to() {
  local target="$1"
  [[ -z "$target" ]] && return 0
  tmux switch-client -t "$target" 2>/dev/null || true
  tmux select-window -t "$target" 2>/dev/null || true
  tmux select-pane -t "$target" 2>/dev/null || true
}

case "${1:-popup}" in
  list)
    build_rows | cut -f4-
    ;;

  popup)
    rows=$(build_rows)
    if [[ -z "$rows" ]]; then
      tmux display-message "停止中のエージェントなし"
      exit 0
    fi
    sel=$(printf '%s\n' "$rows" \
      | fzf --delimiter=$'\t' --with-nth=4 --no-sort \
            --prompt='agent> ' --height=100% --reverse \
            --header='停止中エージェント: Enter でジャンプ') || exit 0
    [[ -z "$sel" ]] && exit 0
    jump_to "$(printf '%s' "$sel" | cut -f2)"
    ;;

  *)
    echo "Usage: $0 {list|popup}" >&2
    exit 1
    ;;
esac
