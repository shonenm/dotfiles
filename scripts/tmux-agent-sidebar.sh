#!/bin/bash
# AI Agent サイドバー (常設・アンビエント表示)
# 「セッションごとに何体の AI がいて各々どの状態か」を一目で見るための密な表示。
# AI 1体 = 色付きアイコン1個(色で状態)。詳細/ジャンプは prefix+a の横断ビューに任せる。
# 状態源は pane option(@agent_status) + リモート/コンテナの file store。
# 仕様: docs/specs/agent-stop-notification.md §5.3
#
# 表示例:
#   AGENTS 5
#   ──────────────
#   main      󰌆 󰔟 ●
#   scratch   ●
#   ailab     󰔟
#
# Usage:
#   tmux-agent-sidebar.sh run      # サイドバー pane 内ループ(自動更新・非フリッカー)
#   tmux-agent-sidebar.sh toggle   # サイドバー pane を開閉 (prefix+b)
#   tmux-agent-sidebar.sh once     # 1回描画(デバッグ)

set -uo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-status.sh"   # ヘルパー(is_shell, trunc_w 由来の helpers, C_*)
set +e +o pipefail

REFRESH="${AGENT_SIDEBAR_REFRESH:-3}"
WIDTH="${AGENT_SIDEBAR_WIDTH:-40}"
STATUS_DIR="${AGENT_STATUS_DIR:-/tmp/claude/status}"
ESC_K=$'\033[K'   # 行末までクリア(全画面クリアせず=チカチカしない)

sb_rank() { case "$1" in permission) echo 0;; hang) echo 1;; error) echo 2;; idle) echo 3;; complete) echo 4;; running) echo 8;; *) echo 9;; esac; }

# 表示幅基準の切り詰め(全角=2幅近似)。[[:ascii:]] は macOS 非対応のため case で判定
trunc_w() {
  local s="$1" max="$2" out="" w=0 ch cw i
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:i:1}"
    case "$ch" in [\ -~]) cw=1 ;; *) cw=2 ;; esac
    (( w + cw > max )) && { out+="…"; break; }
    out+="$ch"; (( w += cw ))
  done
  printf '%s' "$out"
}

# AI 1体のアイコン(色=状態)。色で状態が分かるのが主、グリフで種別も補助
sb_glyph() {
  local c g
  case "$1" in
    permission) c=203; g="󰌆" ;;   # 承認待ち(赤)
    hang)       c=196; g="" ;;   # 無応答(明るい赤)
    error)      c=160; g="" ;;   # エラー(暗い赤)
    idle)       c=214; g="󰔟" ;;   # 入力待ち(amber)
    complete)   c=114; g="" ;;   # 完了(緑)
    running)    c=39;  g="●" ;;   # 実行中(青)
    *)          c=240; g="●" ;;
  esac
  printf '\033[38;5;%sm%s\033[0m' "$c" "$g"
}

# (session, rank, glyph) を収集: local pane option + file store
collect_agents() {
  # local panes
  while IFS=$'\x1f' read -r sess status cmd; do
    [[ -z "$status" ]] && continue
    is_shell "$cmd" && continue
    printf '%s\t%s\t%s\n' "$sess" "$(sb_rank "$status")" "$(sb_glyph "$status")"
  done < <(tmux list-panes -a -F "#{session_name}$(printf '\x1f')#{@agent_status}$(printf '\x1f')#{pane_current_command}")

  # file store (リモート/コンテナ)。workspace ごと最新のみ採用。
  # tmux_session が「ローカルセッション」に一致する行はローカル pane の重複なので除外し、
  # 真のリモート/コンテナ(tmux_session 空 or 非ローカル)のみ採用する。
  [[ -d "$STATUS_DIR" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local local_sessions
  local_sessions="|$(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' '|')"
  local rows="" f ws_seen=""
  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    rows+=$(jq -r --arg us $'\x1f' '[(.updated // .timestamp // 0),(.status // ""),(.workspace // ""),(.tmux_session // ""),(.project // "")]|map(tostring)|join($us)' "$f" 2>/dev/null)$'\n'
  done
  printf '%s' "$rows" | sort -rn -t$'\x1f' -k1,1 | while IFS=$'\x1f' read -r _u status ws tsess project; do
    [[ -z "$status" ]] && continue
    case "$status" in idle|permission|complete|hang|error) ;; *) continue;; esac
    # ローカルセッションに属する行はローカル pane で既出 → 除外
    if [[ -n "$tsess" ]]; then case "$local_sessions" in *"|${tsess}|"*) continue;; esac; fi
    if [[ -n "$ws" ]]; then case "$ws_seen" in *"|${ws}|"*) continue;; *) ws_seen="${ws_seen}|${ws}|";; esac; fi
    local key="$tsess"
    [[ -z "$key" ]] && key="${project%%:*}"   # session 不明なら host/project(リモート)
    [[ -z "$key" ]] && key="remote"
    printf '%s\t%s\t%s\n' "$key" "$(sb_rank "$status")" "$(sb_glyph "$status")"
  done
}

# セッションブロックを出力(セッション名を独立行、アイコンは折返してインデント表示)。
# 動的スコープで render の cur/glyphs/WIDTH を参照する。
_sb_flush() {
  [[ -z "$cur" ]] && return
  printf '%s%s%s%s\n' "$C_BOLD" "$(trunc_w "$cur" $(( WIDTH - 2 )))" "$C_RST" "$ESC_K"
  local per=$(( (WIDTH - 4) / 2 )); (( per < 1 )) && per=1
  local i=0 line="  " g
  for g in "${glyphs[@]}"; do
    line+="$g "
    (( i++ ))
    if (( i % per == 0 )); then printf '%s%s\n' "$line" "$ESC_K"; line="  "; fi
  done
  [[ "$line" != "  " ]] && printf '%s%s\n' "$line" "$ESC_K"
}

render() {
  local rows total cur="" s _rank glyph
  local glyphs=()
  rows=$(collect_agents | sort -t$'\t' -k1,1 -k2,2n)
  total=$(printf '%s' "$rows" | grep -c . 2>/dev/null)

  printf '\033[H'   # ホームへ(全画面クリアしない)
  printf '%s AGENTS%s %s%s%s%s\n' "$C_BOLD" "$C_RST" "$C_DIM" "$total" "$C_RST" "$ESC_K"
  printf '%s────────────────────────%s%s\n' "$C_DIM" "$C_RST" "$ESC_K"
  if [[ -z "$rows" ]]; then
    printf '%s(エージェントなし)%s%s\n' "$C_DIM" "$C_RST" "$ESC_K"
    printf '\033[J'
    return
  fi
  # セッションごとに: 名前を独立行、アイコンを折返してインデント表示
  while IFS=$'\t' read -r s _rank glyph; do
    [[ -z "$s" ]] && continue
    if [[ "$s" != "$cur" ]]; then
      _sb_flush
      cur="$s"; glyphs=("$glyph")
    else
      glyphs+=("$glyph")
    fi
  done <<< "$rows"
  _sb_flush
  printf '\033[J'   # 残りの古い行を消去
}

case "${1:-toggle}" in
  run)
    trap 'printf "\033[?25h"; exit 0' INT TERM
    printf '\033[?25l'   # カーソル非表示(ちらつき低減)
    while true; do
      tmux info &>/dev/null || { printf '\033[?25h'; exit 0; }
      render
      sleep "$REFRESH" & wait $! || true
    done
    ;;
  toggle)
    # サイドバーは window 内の pane。追跡は window 単位にし、別 window/session の
    # サイドバーを誤って kill しない(グローバル追跡だとセッション移動で閉じてしまう)。
    # prefix+b を押した pane($TMUX_PANE)の window に -t で固定して操作する。
    src="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}' 2>/dev/null)}"
    win=$(tmux display-message -t "$src" -p '#{window_id}' 2>/dev/null)
    [[ -z "$win" ]] && exit 0
    existing=$(tmux show-options -w -t "$win" -qv @agent_sidebar_pane 2>/dev/null || echo "")
    if [[ -n "$existing" ]] && tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | grep -qxF "$existing"; then
      tmux kill-pane -t "$existing" 2>/dev/null || true
      tmux set-option -w -t "$win" -u @agent_sidebar_pane 2>/dev/null || true
    else
      pane=$(tmux split-window -t "$src" -fh -b -l "$WIDTH" -P -F '#{pane_id}' \
        "bash '$SCRIPT_DIR/tmux-agent-sidebar.sh' run")
      tmux set-option -p -t "$pane" @agent_status "" 2>/dev/null || true
      tmux set-option -w -t "$win" @agent_sidebar_pane "$pane" 2>/dev/null || true
      tmux select-pane -t "$src" 2>/dev/null || true   # 作業 pane にフォーカスを残す
    fi
    ;;
  once)
    render ;;
  *)
    echo "Usage: $0 {run|toggle|once}" >&2; exit 1 ;;
esac
