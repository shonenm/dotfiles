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
# SELF は source の後に定義する(status.sh も冒頭で SELF を設定するため上書きを避ける)
SELF="$SCRIPT_DIR/tmux-agent-sidebar.sh"

REFRESH="${AGENT_SIDEBAR_REFRESH:-3}"
WIDTH="${AGENT_SIDEBAR_WIDTH:-40}"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-$HOME/.cache}}"
STATUS_DIR="${AGENT_STATUS_DIR:-${DOTFILES_SHARED_DIR:-$HOME/.cache}/claude/status}"
ESC_K=$'\033[K'   # 行末までクリア(全画面クリアせず=チカチカしない)

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

# AI 1体の rank と色付きアイコン(色=状態)を "rank<TAB>glyph" で返す
# (rank と glyph を1回の呼び出しで返し subshell を減らす)
sb_rank_glyph() {
  case "$1" in
    permission) printf '0\t\033[38;5;203m󰌆\033[0m' ;;
    hang)       printf '1\t\033[38;5;196m\033[0m' ;;
    error)      printf '2\t\033[38;5;160m\033[0m' ;;
    idle)       printf '3\t\033[38;5;214m󰔟\033[0m' ;;
    complete)   printf '4\t\033[38;5;114m\033[0m' ;;
    running)    printf '8\t\033[38;5;39m●\033[0m' ;;
    *)          printf '9\t\033[38;5;240m●\033[0m' ;;
  esac
}

# (session, rank, glyph) を収集: local pane option + file store
collect_agents() {
  # local panes
  while IFS=$'\x1f' read -r sess status cmd stashed; do
    [[ -z "$status" ]] && continue
    is_shell "$cmd" && continue
    rg=$(sb_rank_glyph "$status")
    # stash 済みはアイコン(グリフ)を変えず色だけ灰色(240)にして、サイドバーでも stash と分かるように
    [[ -n "$stashed" ]] && rg=$(printf '%s' "$rg" | sed 's/38;5;[0-9]*m/38;5;240m/')
    printf '%s\t%s\n' "$sess" "$rg"
  done < <(tmux list-panes -a -F "#{session_name}$(printf '\x1f')#{@agent_status}$(printf '\x1f')#{pane_current_command}$(printf '\x1f')#{@agent_stashed}")

  # file store (リモート/コンテナ)。workspace ごと最新のみ採用。
  # tmux_session が「ローカルセッション」に一致する行はローカル pane の重複なので除外し、
  # 真のリモート/コンテナ(tmux_session 空 or 非ローカル)のみ採用する。
  [[ -d "$STATUS_DIR" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local local_sessions ws_seen="" status ws tsess project _u
  local_sessions="|$(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' '|')"
  # 全ファイルを1回の jq で処理(ファイル数分 jq を spawn しない)
  local files=("$STATUS_DIR"/*.json)
  [[ -e "${files[0]}" ]] || return 0
  while IFS=$'\x1f' read -r _u status ws tsess project; do
    [[ -z "$status" ]] && continue
    case "$status" in idle|permission|complete|hang|error) ;; *) continue;; esac
    if [[ -n "$tsess" ]]; then case "$local_sessions" in *"|${tsess}|"*) continue;; esac; fi
    if [[ -n "$ws" ]]; then case "$ws_seen" in *"|${ws}|"*) continue;; *) ws_seen="${ws_seen}|${ws}|";; esac; fi
    local key="$tsess"
    [[ -z "$key" ]] && key="${project%%:*}"
    [[ -z "$key" ]] && key="remote"
    printf '%s\t%s\n' "$key" "$(sb_rank_glyph "$status")"
  done < <(jq -rs --arg us $'\x1f' '
      sort_by(-(.updated // .timestamp // 0))[]
      | [((.updated // .timestamp // 0)|tostring),(.status // ""),(.workspace // ""),(.tmux_session // ""),(.project // "")]|join($us)
    ' "${files[@]}" 2>/dev/null)
}

# セッションブロックを出力(セッション名を独立行、アイコンは折返してインデント表示)。
# 動的スコープで render の cur/glyphs/WIDTH/_lines を参照し、_lines 配列に追記する。
_sb_flush() {
  [[ -z "$cur" ]] && return
  _lines+=("$(printf '%s%s%s' "$C_BOLD" "$(trunc_w "$cur" $(( WIDTH - 2 )))" "$C_RST")")
  local per=$(( (WIDTH - 4) / 2 )); (( per < 1 )) && per=1
  local i=0 line="  " g
  for g in "${glyphs[@]}"; do
    line+="$g "
    (( i++ ))
    if (( i % per == 0 )); then _lines+=("$line"); line="  "; fi
  done
  [[ "$line" != "  " ]] && _lines+=("$line")
}

# 各 AI の使用量(セッションリミット)を2行で出力(1行目: アイコン+残り時間 / 2行目: ゲージ+%)
# usage スクリプト出力 "ICON GAUGE PCT/PCT REMAINING"(失敗時 "ICON --")をパースして整形。
# 4スクリプトを毎 render 走らせると重いので結果を30秒キャッシュする。
USAGE_CACHE="$RUNTIME_BASE/claude/sidebar-usage"
usage_section() {
  local now mt age
  now=$(date +%s)
  if [[ -f "$USAGE_CACHE" ]]; then
    case "$(uname -s)" in Darwin) mt=$(stat -f %m "$USAGE_CACHE" 2>/dev/null);; *) mt=$(stat -c %Y "$USAGE_CACHE" 2>/dev/null);; esac
    age=$(( now - ${mt:-0} ))
    (( age < 30 )) && { cat "$USAGE_CACHE"; return; }
  fi
  mkdir -p "$(dirname "$USAGE_CACHE")" 2>/dev/null
  # timeout は macOS 既定で無いため、あれば使う(無ければ素で実行。各 usage は内部で
  # curl --max-time + キャッシュ + fail backoff により自己制限する)
  local TO; TO="$(command -v timeout || command -v gtimeout || true)"
  {
    local sc out col icon label gauge pct rem
    for sc in tmux-claude-usage tmux-codex-usage tmux-gemini-usage tmux-cursor-usage; do
      # AI ごとの色分け(ステータスバーと同じ): claude=橙 codex=水色 gemini=青 cursor=紫
      case "$sc" in
        *claude*) col=$'\033[38;2;255;102;0m' ;;
        *codex*)  col=$'\033[38;2;125;211;252m' ;;
        *gemini*) col=$'\033[38;2;66;133;244m' ;;
        *cursor*) col=$'\033[38;2;153;102;255m' ;;
        *)        col="" ;;
      esac
      out=$(${TO:+$TO 6} bash "$SCRIPT_DIR/$sc.sh" 2>/dev/null)
      [[ -z "$out" ]] && continue
      # 各ウィンドウ1レコード "ICON\x1fLABEL\x1fGAUGE\x1fPCT\x1fREMAINING"。
      # データ無しは "ICON\x1f--"。icon は AI ごとに1つ(最初のウィンドウのみ)、
      # 2つ目以降は icon を出さずインデント揃え。current/weekly を縦に並べる:
      #   {icon} {label}
      #     {gauge} {pct}  {remaining}
      local first=1
      while IFS=$'\x1f' read -r icon label gauge pct rem; do
        [[ -z "$icon" ]] && continue
        local head
        if (( first )); then head="$col$icon$C_RST "; first=0; else head="  "; fi
        if [[ "$label" == "--" ]]; then
          printf '%s%s--%s\n' "$head" "$C_DIM" "$C_RST"
        else
          printf '%s%s%s%s\n' "$head" "$C_DIM" "$label" "$C_RST"
          printf '  %s%s %s%s%s  %s%s\n' "$col" "$gauge" "$pct" "$C_RST" "$C_DIM" "$rem" "$C_RST"
        fi
      done <<< "$out"
    done
  } | tee "$USAGE_CACHE"
}

render() {
  local rows total cur="" s _rank glyph
  local glyphs=()
  local _lines=()   # AGENTS ブロックの各行(_sb_flush が追記)
  rows=$(collect_agents | sort -t$'\t' -k1,1 -k2,2n)
  total=$(printf '%s' "$rows" | grep -c . 2>/dev/null)

  # --- pane の幅/高さを取得(divider 長・最下部揃えに使用) ---
  local H W
  H=$(tmux display-message -p -t "${TMUX_PANE}" '#{pane_height}' 2>/dev/null)
  W=$(tmux display-message -p -t "${TMUX_PANE}" '#{pane_width}' 2>/dev/null)
  [[ -z "$H" ]] && H=40
  [[ -z "$W" || "$W" -lt 1 ]] && W="$WIDTH"
  # 以降の幅計算(trunc_w / per / divider)は静的 WIDTH ではなく実 pane 幅に揃える。
  # _sb_flush は動的スコープで WIDTH を参照するため、ここで上書きすれば波及する。
  local WIDTH="$W"
  # divider は pane 幅ちょうどの罫線(リサイズに追従、折返し防止)
  local div; div=$(printf '─%.0s' $(seq 1 "$W"))

  # --- AGENTS ブロックを配列に構築(上部) ---
  local top=()
  top+=("$(printf '%s AGENTS%s %s%s%s' "$C_BOLD" "$C_RST" "$C_DIM" "$total" "$C_RST")")
  top+=("$(printf '%s%s%s' "$C_DIM" "$div" "$C_RST")")
  if [[ -z "$rows" ]]; then
    top+=("$(printf '%s(エージェントなし)%s' "$C_DIM" "$C_RST")")
  else
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
    top+=("${_lines[@]}")
  fi

  # --- USAGE ブロックを配列に構築(下部) ---
  local bot=()
  bot+=("$(printf '%s USAGE%s' "$C_BOLD" "$C_RST")")
  bot+=("$(printf '%s%s%s' "$C_DIM" "$div" "$C_RST")")
  while IFS= read -r ln; do bot+=("$ln"); done < <(usage_section)

  # --- USAGE を最下部に揃える ---
  local n_top=${#top[@]} n_bot=${#bot[@]}
  local pad=$(( H - n_top - n_bot ))
  (( pad < 1 )) && pad=1   # 重なり防止に最低1行は空ける

  # 全行を1配列にまとめる(上: AGENTS / 中: パディング / 下: USAGE)
  local out=()
  local i
  for (( i = 0; i < n_top; i++ )); do out+=("${top[i]}"); done
  for (( i = 0; i < pad; i++ )); do out+=(""); done
  for (( i = 0; i < n_bot; i++ )); do out+=("${bot[i]}"); done

  # 1フレームを1文字列に組み立て、同期更新(DEC 2026)で囲んで1回の write でアトミックに出す。
  # 行ごとに printf するとティアリング(部分描画)でちらつくため必ずまとめて出力する。
  # 最終行に改行を付けると1行スクロールし先頭(AGENTS ヘッダー)が画面外へ落ちるため改行なし。
  local frame="" n_out=${#out[@]}
  for (( i = 0; i < n_out; i++ )); do
    if (( i < n_out - 1 )); then
      frame+="${out[i]}${ESC_K}"$'\n'
    else
      frame+="${out[i]}${ESC_K}"
    fi
  done
  # \033[?2026h/l = 同期更新の開始/終了(tmux 3.3+/Ghostty 対応。非対応端末では無視され無害)。
  # 間に ホーム移動 → フレーム → 残行消去 をまとめ、端末が完成フレームのみ表示する。
  printf '\033[?2026h\033[H%s\033[J\033[?2026l' "$frame"
}

case "${1:-toggle}" in
  run)
    trap 'printf "\033[?25h"; exit 0' INT TERM
    printf '\033[?25l'   # カーソル非表示(ちらつき低減)
    while true; do
      tmux info &>/dev/null || { printf '\033[?25h'; exit 0; }
      # 描画は毎回サブプロセスで実行し、スクリプト更新を自動反映する
      # (常駐ループに関数を抱えると、起動後の更新が反映されず古い表示になるため)
      bash "$SELF" once
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
