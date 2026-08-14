#!/bin/bash
# AI Agent サイドバー (常設・アンビエント表示)
# 「セッションごとに何体の AI がいて各々どの状態か」を一目で見るための密な表示。
# AI 1体 = 色付きアイコン1個(色で状態)。詳細/ジャンプは prefix+a の横断ビューに任せる。
# 状態源は pane option(@agent_status) + リモート/コンテナの file store。
# 仕様: docs/specs/agent-stop-notification.md §5.3
#
# 表示例:
#   SESSIONS 4  AGENTS 5
#   ──────────────
#   ▸ work
#     ▶ main  󰌆 󰔟 ●
#       api   ●
#   ▾ ungrouped
#       scratch
#
# Usage:
#   tmux-agent-sidebar.sh run      # サイドバー pane 内ループ(自動更新・非フリッカー)
#   tmux-agent-sidebar.sh toggle   # サイドバー pane を開閉 (prefix+b)
#   tmux-agent-sidebar.sh once     # 1回描画(デバッグ)

set -uo pipefail

[[ -z "${TMUX:-}" ]] && exit 0

# Rust binaries (ai-usage/wt/pomodoro) は ~/.local/bin。tmux run-shell / launchd /
# at など最小 PATH の起動元でも解決できるよう先頭で PATH を通す。
export PATH="$HOME/.local/bin:$PATH"

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
TAB=$'\t'
ESC_K=$'\033[K'   # 行末までクリア(全画面クリアせず=チカチカしない)

# どれかの client が native/pseudo zoom / choose-tree / copy-mode 中なら true。
# 擬似 zoom は window_zoomed_flag が立たないため、@pzoom_pane も判定する。
# @pzoom_pane は "%62" のような pane id。値を連結して grep 1 すると digit 1 を
# 含まない id で擬似 zoom を見逃すので、空判定だけ見る。
# その間に sidebar を resize すると、zoom 中の layout と競合して pane 内容が崩れる。
# transient な状態なので、抜けた後の tick で補正すれば十分。
sidebar_user_busy() {
  tmux list-clients -F '#{?window_zoomed_flag,1,}#{?pane_in_mode,1,}#{?@pzoom_pane,1,}' 2>/dev/null | grep -q 1
}

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
  done < <(agent_index_panes | while IFS="$US" read -r _pid sess _win status _hb _state_since _path cmd _title stashed _sidebar _provider _tty _pw _ph; do
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$sess" "$status" "$cmd" "$stashed"
  done)

  # file store (リモート/コンテナ)。workspace ごと最新のみ採用。
  # tmux_session が「ローカルセッション」に一致する行はローカル pane の重複なので除外し、
  # 真のリモート/コンテナ(tmux_session 空 or 非ローカル)のみ採用する。
  [[ -d "$STATUS_DIR" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local local_sessions ws_seen="" status ws tsess project provider identity _u
  local_sessions="|$(agent_index_sessions | awk -F "$US" '{print $1}' | tr '\n' '|')"
  # 全ファイルを1回の jq で処理(ファイル数分 jq を spawn しない)
  local files=("$STATUS_DIR"/*.json)
  [[ -e "${files[0]}" ]] || return 0
  while IFS=$'\x1f' read -r _u status ws tsess project provider; do
    [[ -z "$status" ]] && continue
    # provider/workspaceごとの最新recordを先に確定し、none tombstoneで古い状態を復活させない。
    if [[ -n "$ws" ]]; then
      identity="${provider:-legacy}:${ws}"
      case "$ws_seen" in *"|${identity}|"*) continue;; *) ws_seen="${ws_seen}|${identity}|";; esac
    fi
    case "$status" in idle|permission|complete|hang|error) ;; *) continue;; esac
    if [[ -n "$tsess" ]]; then case "$local_sessions" in *"|${tsess}|"*) continue;; esac; fi
    local key="$tsess"
    [[ -z "$key" ]] && key="${project%%:*}"
    [[ -z "$key" ]] && key="remote"
    printf '%s\t%s\n' "$key" "$(sb_rank_glyph "$status")"
  done < <(jq -rs --arg us $'\x1f' '
      sort_by(-(.updated // .timestamp // 0))[]
      | [((.updated // .timestamp // 0)|tostring),(.status // ""),(.workspace // ""),(.tmux_session // ""),(.project // ""),(.tool // "")]|join($us)
    ' "${files[@]}" 2>/dev/null)
}

session_glyphs() {
  local rows="$1" sess="$2"
  printf '%s\n' "$rows" | awk -F "$TAB" -v s="$sess" '$1 == s { printf "%s ", $3 }'
}

# 各 AI の使用量(セッションリミット)を2行で出力(1行目: アイコン+残り時間 / 2行目: ゲージ+%)
# usage スクリプト出力 "ICON GAUGE PCT/PCT REMAINING"(失敗時 "ICON --")をパースして整形。
# 各 usage を毎 render 走らせると重いので結果を30秒キャッシュする。
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
    for sc in claude codex gemini cursor grok; do
      # AI ごとの色分け: claude=橙 codex=水色 gemini=青 cursor=白 grok=ティール
      case "$sc" in
        claude) col=$'\033[38;2;255;102;0m' ;;
        codex)  col=$'\033[38;2;125;211;252m' ;;
        gemini) col=$'\033[38;2;66;133;244m' ;;
        cursor) col=$'\033[38;2;255;255;255m' ;;
        grok)   col=$'\033[38;2;94;234;212m' ;;
        *)      col="" ;;
      esac
      out=$(${TO:+$TO 6} ai-usage "$sc" 2>/dev/null)
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

# 全サイドバー共通の素材。pane ごとに違うのは現在 session / group と pane 寸法だけなので、
# 収集(index 読み・jq・usage)は 1 tick に 1 回で済む。
SB_ROWS=""; SB_TOTAL=0; SB_SESSIONS=""; SB_SESSION_COUNT=0; SB_USAGE=""
collect_frame_inputs() {
  SB_ROWS=$(collect_agents | sort -t$'\t' -k1,1 -k2,2n)
  SB_TOTAL=$(printf '%s' "$SB_ROWS" | grep -c . 2>/dev/null)
  SB_SESSIONS=$(agent_index_sessions | awk -F "$US" -v tab="$TAB" '{print $1 tab $2}' | sort)
  SB_SESSION_COUNT=$(printf '%s' "$SB_SESSIONS" | grep -c . 2>/dev/null)
  SB_USAGE=$(usage_section)
}

# build_frame <cur_session> <width> <height> — 1 pane 分のフレームを stdout へ
build_frame() {
  local rows="$SB_ROWS" total="$SB_TOTAL" sessions="$SB_SESSIONS" session_count="$SB_SESSION_COUNT"
  local cur_session="$1" W="$2" H="$3" cur_group
  # @group はセッション一覧(index cache)に入っているので show-options を撃たない
  cur_group=$(printf '%s\n' "$sessions" | awk -F "$TAB" -v s="$cur_session" '$1 == s { print $2; exit }')
  [[ -z "$H" || "$H" -lt 1 ]] && H=40
  [[ -z "$W" || "$W" -lt 1 ]] && W="$WIDTH"
  # 以降の幅計算(trunc_w / per / divider)は静的 WIDTH ではなく実 pane 幅に揃える。
  # _sb_flush は動的スコープで WIDTH を参照するため、ここで上書きすれば波及する。
  local WIDTH="$W"
  # divider は pane 幅ちょうどの罫線(リサイズに追従、折返し防止)
  local div; div=$(printf '─%.0s' $(seq 1 "$W"))

  # --- SESSIONS ブロックを配列に構築(上部) ---
  local top=()
  top+=("$(printf '%s SESSIONS%s %s%s  AGENTS %s%s' "$C_BOLD" "$C_RST" "$C_DIM" "$session_count" "$total" "$C_RST")")
  top+=("$(printf '%s%s%s' "$C_DIM" "$div" "$C_RST")")
  if [[ -z "$sessions" ]]; then
    top+=("$(printf '%s(セッションなし)%s' "$C_DIM" "$C_RST")")
  else
    local groups=() g s label marker name icons line
    while IFS= read -r g; do [[ -n "$g" ]] && groups+=("$g"); done < <(printf '%s\n' "$sessions" | awk -F "$TAB" '$2 != "" { print $2 }' | sort -u)
    if printf '%s\n' "$sessions" | awk -F "$TAB" '$2 == "" { found = 1 } END { exit !found }'; then groups+=(""); fi
    for g in "${groups[@]}"; do
      label="${g:-ungrouped}"
      if [[ "$g" == "$cur_group" ]]; then
        top+=("$(printf '%s▸ %s%s' "$C_CUR$C_BOLD" "$(trunc_w "$label" $(( WIDTH - 3 )))" "$C_RST")")
      else
        top+=("$(printf '%s▾ %s%s' "$C_DIM" "$(trunc_w "$label" $(( WIDTH - 3 )))" "$C_RST")")
      fi
      while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        icons=$(session_glyphs "$rows" "$s")
        marker="  "
        [[ "$s" == "$cur_session" ]] && marker="▶ "
        name=$(trunc_w "$s" $(( WIDTH - 6 )))
        line="  ${marker}${name}"
        [[ -n "$icons" ]] && line+=" $icons"
        if [[ "$s" == "$cur_session" ]]; then
          top+=("$(printf '%s%s%s' "$C_CUR$C_BOLD" "$line" "$C_RST")")
        else
          top+=("$line")
        fi
      done < <(printf '%s\n' "$sessions" | awk -F "$TAB" -v g="$g" '$2 == g { print $1 }')
    done
  fi

  # --- USAGE ブロックを配列に構築(下部) ---
  local bot=()
  bot+=("$(printf '%s USAGE%s' "$C_BOLD" "$C_RST")")
  bot+=("$(printf '%s%s%s' "$C_DIM" "$div" "$C_RST")")
  while IFS= read -r ln; do bot+=("$ln"); done <<< "$SB_USAGE"

  # --- USAGE を最下部に揃える ---
  local n_top=${#top[@]} n_bot=${#bot[@]}
  local pad=$(( H - n_top - n_bot ))
  (( pad < 1 )) && pad=1   # 重なり防止に最低1行は空ける

  # 全行を1配列にまとめる(上: SESSIONS / 中: パディング / 下: USAGE)
  local out=()
  local i
  for (( i = 0; i < n_top; i++ )); do out+=("${top[i]}"); done
  for (( i = 0; i < pad; i++ )); do out+=(""); done
  for (( i = 0; i < n_bot; i++ )); do out+=("${bot[i]}"); done

  # 1フレームを1文字列に組み立て、同期更新(DEC 2026)で囲んで1回の write でアトミックに出す。
  # 行ごとに printf するとティアリング(部分描画)でちらつくため必ずまとめて出力する。
  # 最終行に改行を付けると1行スクロールし先頭(SESSIONS ヘッダー)が画面外へ落ちるため改行なし。
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

DAEMON_PID_FILE="$(agent_runtime_dir)/sidebar-daemon.pid"

# bash は起動時にスクリプトを読む。更新後も古い USAGE / 状態源のままになるので、
# ファイルが新しくなっていたら cache を捨てて自分を差し替える。
script_mtime() {
  case "$(uname -s)" in Darwin) stat -f %m "$SELF" 2>/dev/null;; *) stat -c %Y "$SELF" 2>/dev/null;; esac
}

restart_daemon() {
  local pid command
  pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || true)
  if [[ -n "$pid" ]]; then
    command=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if [[ "$command" == *tmux-agent-sidebar.sh* ]]; then
      kill "$pid" 2>/dev/null || true
      local i
      for i in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
    fi
  fi
  rm -f "$DAEMON_PID_FILE" "$USAGE_CACHE"
  tmux run-shell -b "exec bash '$SELF' daemon >/dev/null 2>&1" 2>/dev/null || true
}

# index cache からサイドバー pane を列挙する。
# @agent_sidebar_pane は window option なので pane 文脈でも継承されて見える。
# よって「自分の pane_id == @agent_sidebar_pane」の行がサイドバー本体。
# 出力: pane_id TAB session TAB tty TAB width TAB height
sidebar_targets() {
  agent_index_panes | awk -F "$US" -v OFS="$TAB" '$1 != "" && $1 == $11 { print $1, $2, $13, $14, $15 }'
}

# 1 tick: 素材を1回だけ集め、各サイドバー pane の tty へフレームを書き込む。
# サイドバーが1つも無くなったら 1 を返す(daemon はそこで畳む)。
sidebar_tick() {
  local targets attached busy=0 collected=0
  targets=$(sidebar_targets)
  [[ -z "$targets" ]] && return 1
  # detached session のサイドバーは誰も見ないので描画しない
  attached=$(agent_index_sessions | awk -F "$US" '$3 != "" && $3 != 0 { printf "|%s|", $1 }')
  sidebar_user_busy && busy=1
  local pane sess tty w h
  while IFS=$'\t' read -r pane sess tty w h; do
    [[ -z "$tty" ]] && continue
    case "$attached" in *"|${sess}|"*) ;; *) continue ;; esac
    if (( collected == 0 )); then collect_frame_inputs; collected=1; fi
    # window-size latest の比例リサイズ丸め誤差で session 切替毎に幅がドリフトする。
    # 差分がある時だけ補正する(resize 自体が window-layout-changed を再発火するため)。
    # zoom / choose-tree / copy-mode 中はスキップ (resize が zoom を潰すため)。
    if (( busy == 0 )) && [[ "$w" != "$WIDTH" ]]; then
      tmux resize-pane -t "$pane" -x "$WIDTH" 2>/dev/null && w="$WIDTH"
    fi
    build_frame "$sess" "$w" "$h" >"$tty" 2>/dev/null || true
  done <<< "$targets"
  return 0
}

case "${1:-toggle}" in
  daemon)
    # tmux server ごとに 1 本だけ常駐し、全サイドバー pane を描画する。
    # 以前は pane ごとにループを持たせていたが、同じ状態を pane 数だけポーリングし
    # (毎 tick に list-panes -a + bash fork)、window を増やすほど線形に重くなっていた。
    mkdir -p "$(dirname "$DAEMON_PID_FILE")" 2>/dev/null || exit 0
    if [[ -f "$DAEMON_PID_FILE" ]]; then
      existing=$(cat "$DAEMON_PID_FILE" 2>/dev/null || true)
      if [[ -n "$existing" && "$existing" != "$$" ]]; then
        command=$(ps -p "$existing" -o command= 2>/dev/null || true)
        [[ "$command" == *tmux-agent-sidebar.sh* ]] && exit 0
      fi
    fi
    echo $$ >"$DAEMON_PID_FILE"
    cleanup() { [[ "$(cat "$DAEMON_PID_FILE" 2>/dev/null)" == "$$" ]] && rm -f "$DAEMON_PID_FILE"; }
    trap cleanup EXIT
    trap 'cleanup; exit 0' INT TERM
    # USR1 = 即時再描画。ハンドラは no-op でよい: sleep の wait が中断されて
    # ループ先頭に戻る = REFRESH 待ちを飛ばして描画する。
    trap 'true' USR1
    started=$(script_mtime)
    while true; do
      tmux info >/dev/null 2>&1 || exit 0
      owner="$(cat "$DAEMON_PID_FILE" 2>/dev/null || true)"
      [[ -n "$owner" && "$owner" != "$$" ]] && exit 0
      if [[ -n "$started" ]]; then
        now_mt=$(script_mtime)
        if [[ -n "$now_mt" && "$now_mt" -gt "$started" ]]; then
          rm -f "$USAGE_CACHE"
          exec bash "$SELF" daemon
        fi
      fi
      sidebar_tick || exit 0
      sleep "$REFRESH" & wait $! || true
    done
    ;;
  run)
    # サイドバー pane 側は描画しない。フレームは daemon が pane_tty へ直接書く。
    # ここは pane を生かしておくだけ: 入力エコーを止め、カーソルを隠して寝る。
    stty -echo -icanon </dev/tty 2>/dev/null || true
    trap 'printf "\033[?25h"; exit 0' INT TERM
    printf '\033[?25l'   # カーソル非表示(ちらつき低減)
    while true; do sleep 3600 & wait $! || true; done
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
      tmux set-hook -w -t "$win" -u window-layout-changed 2>/dev/null || true
    else
      pane=$(tmux split-window -t "$src" -fh -b -l "$WIDTH" -P -F '#{pane_id}' \
        "bash '$SCRIPT_DIR/tmux-agent-sidebar.sh' run")
      tmux set-option -p -t "$pane" @agent_status "" 2>/dev/null || true
      tmux set-option -w -t "$win" @agent_sidebar_pane "$pane" 2>/dev/null || true
      # この window の window-layout-changed を「pane id 焼き込みの直接 resize」に差し替える。
      # グローバル hook は run-shell -b(fork+非同期)のため比例再配分の補正が redraw の後になり、
      # リサイズ/swap の度にサイドバーが一瞬広がってから戻る=ちらつく。直接コマンドは command
      # queue 内で同期実行され中間フレームを描画前に潰す(fork なし=fork-latency にも無害)。
      # 既に WIDTH の時 resize-pane は no-op でレイアウト不変=再発火せず1回で収束。
      # zoom 中は補正しない: zoom もレイアウト変更なので本 hook を撃つが、resize-pane は
      # zoom 中の window を unzoom してしまう(prefix-z が一瞬で戻る)。if-shell -F は format
      # 評価のみで shell を fork しないため、同期・無 fork のまま zoom を素通しできる。
      tmux set-hook -w -t "$win" window-layout-changed "if-shell -F '#{?#{||:#{window_zoomed_flag},#{@pzoom_pane}},0,1}' 'resize-pane -t $pane -x $WIDTH'" 2>/dev/null || true
      tmux select-pane -t "$src" 2>/dev/null || true   # 作業 pane にフォーカスを残す
      # daemon は「サイドバーが1つも無い」と自分で畳むので、開くたびに起動を保証する。
      # 新 pane を index に載せてから起動する(古い cache のまま起動すると即 exit する)。
      "$SCRIPT_DIR/tmux-agent-index.sh" refresh >/dev/null 2>&1 || true
      tmux run-shell -b "exec bash '$SELF' daemon >/dev/null 2>&1" 2>/dev/null || true
    fi
    ;;
  resize-all)
    # サイドバー pane を固定幅へ即時補正(client-resized/session-changed/window-layout-changed hook 用)。
    # tmux はリサイズを比例配分するため、prefix+a の swap-pane 等でレイアウトが変わると固定幅が
    # 崩れて広がる。それを WIDTH へ snap し直す。$2 に window_id があればその window のみ対象。
    # 既に WIDTH の pane は resize しない: resize 自体が window-layout-changed を再発火するため、
    # 無条件 resize だと hook 経由で無限ループになる(差分があるときだけ補正 → 1回で収束)。
    # zoom / choose-tree / copy-mode 中は補正パス全体をスキップ (resize が zoom を潰すため。
    # zoom はレイアウト変更→window-layout-changed→本 resize-all を撃つので即時に unzoom する)。
    sidebar_user_busy && exit 0
    target_win="${2:-}"
    while IFS=$'\t' read -r win attached pane; do
      [[ -z "$pane" ]] && continue
      [[ -n "$target_win" && "$win" != "$target_win" ]] && continue
      [[ -z "$attached" || "$attached" == 0 ]] && continue
      tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane" || continue
      cw=$(tmux display-message -p -t "$pane" '#{pane_width}' 2>/dev/null || echo "")
      [[ "$cw" == "$WIDTH" ]] && continue
      tmux resize-pane -t "$pane" -x "$WIDTH" 2>/dev/null || true
    done < <(tmux list-windows -a -F "#{window_id}$(printf '\t')#{session_attached}$(printf '\t')#{@agent_sidebar_pane}" 2>/dev/null)
    ;;
  rehook)
    # 既存サイドバー window の window-layout-changed hook を最新版へ張り直す。
    # per-window hook は toggle 時に window 単位で焼き込まれるため、スクリプト更新は
    # 「新規サイドバー」にしか効かず既存 window には古い hook が残る。config reload
    # (prefix r) から本コマンドを呼ぶことで、稼働中の全 window(リモート含む)に反映する。
    while IFS=$'\t' read -r win pane; do
      [[ -z "$pane" ]] && continue
      tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane" || continue
      tmux set-hook -w -t "$win" window-layout-changed "if-shell -F '#{?#{||:#{window_zoomed_flag},#{@pzoom_pane}},0,1}' 'resize-pane -t $pane -x $WIDTH'" 2>/dev/null || true
    done < <(tmux list-windows -a -F "#{window_id}$(printf '\t')#{@agent_sidebar_pane}" 2>/dev/null)
    restart_daemon
    ;;
  poke)
    # daemon へ即時再描画を要求 (session/window 切替 hook から呼ぶ)。
    # 切替先の pane は最大 REFRESH 秒古いフレームを表示したままになるため、
    # ポーリングを待たずに叩き起こす。index cache も古いと同じ理由で
    # 古い session 一覧を描くので、先に invalidate して次 tick で引き直させる。
    "$SCRIPT_DIR/tmux-agent-index.sh" invalidate >/dev/null 2>&1 || true
    pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || true)
    [[ -n "$pid" ]] && kill -USR1 "$pid" 2>/dev/null
    exit 0
    ;;
  once)
    # デバッグ用: 現在の pane 向けフレームを stdout に1回出す
    collect_frame_inputs
    build_frame \
      "$(tmux display-message -p -t "${TMUX_PANE}" '#{session_name}' 2>/dev/null)" \
      "$(tmux display-message -p -t "${TMUX_PANE}" '#{pane_width}' 2>/dev/null)" \
      "$(tmux display-message -p -t "${TMUX_PANE}" '#{pane_height}' 2>/dev/null)"
    ;;
  *)
    echo "Usage: $0 {daemon|run|toggle|once|resize-all|rehook|poke}" >&2; exit 1 ;;
esac
