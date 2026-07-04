#!/bin/bash
# Session groups for tmux.
# 各 session の @group user option (session-scoped) を唯一の真実とし、
# session 名には依存しない (名前は自由に付けられる)。user option は tmux server
# 再起動で消え resurrect も復元しないため、state file に永続化して
# session-created hook / config load 時に再適用する。
#
# Subcommands:
#   set <group>             — 現在の session にグループを設定 (A-Za-z0-9_- のみ)
#   unset                   — 現在の session からグループを外す
#   menu                    — fzf popup: 既存グループ選択 / 新規入力 / (none) で解除
#   next | prev             — 同グループ内の次/前の session へ (名前順・循環)
#   next-group | prev-group — 隣のグループの先頭 session へ (循環)
#   picker                  — グループ一覧メニュー → グループ内 choose-tree の二段 picker
#   apply <session>         — state file からグループを再適用 (session-created hook 用)
#   restore                 — 全 live session に apply (config load 用)
#   sync                    — live の @group を state file へ書き出し (session-renamed hook 用)
#
# state file: $XDG_STATE_HOME/tmux/session-groups (session_name<TAB>group)
# 死んでいる session のエントリは保持する (resurrect 後の同名 session に再適用するため)。

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"
STATE_FILE="$STATE_DIR/session-groups"
TAB=$'\t'

# name<TAB>group を名前順で出力 (@group は format 展開で session-scoped に解決される)
list_all() {
  tmux list-sessions -F "#{session_name}${TAB}#{@group}" 2>/dev/null | sort
}

# run-shell -b の子プロセスは key を押した client/pane の文脈を持たない (tmux が
# 「最後に使った session」等へ勝手に解決し誤動作する) ため、bind 側の format 展開で
# '#{client_name}' '#{client_session}' 等を引数として受け取る。引数がなければ
# (pane 内での手動実行など) 文脈解決にフォールバック。
sess_of()     { [ -n "${1:-}" ] && printf '%s' "$1" || tmux display-message -p '#{session_name}'; }
cur_group()   { tmux show-options -t "$1" -qv @group; }

# $1: client_name ('' なら文脈解決), $2: target session
switch_to() {
  if [ -n "$1" ]; then
    tmux switch-client -c "$1" -t "$2"
  else
    tmux switch-client -t "$2"
  fi
}

# client の現在 session (run-shell -b は文脈を持たないため client 名で引く)
client_session() {
  [ -n "${1:-}" ] && tmux display-message -c "$1" -p '#{session_name}' 2>/dev/null
}

# $1: dir (prev|next|prev-group|next-group), $2: cur session
# → 行き先 session 名を出力 (無ければ空)。cmd_step/cmd_step_group と同じ順序規則。
nav_target() {
  local dir="$1" cur="$2" grp s n i idx=0 d
  grp=$(cur_group "$cur")
  case "$dir" in
    prev | next)
      local members=()
      while IFS= read -r s; do members+=("$s"); done \
        < <(list_all | awk -F "$TAB" -v g="$grp" '$2 == g { print $1 }')
      n=${#members[@]}
      [ "$n" -le 1 ] && return 0
      for ((i = 0; i < n; i++)); do [ "${members[$i]}" = "$cur" ] && idx=$i; done
      d=1; [ "$dir" = prev ] && d=-1
      printf '%s' "${members[$(((idx + d + n) % n))]}"
      ;;
    prev-group | next-group)
      local all target
      local grps=()
      all=$(list_all)
      while IFS= read -r s; do grps+=("$s"); done \
        < <(printf '%s\n' "$all" | awk -F "$TAB" '$2 != "" { print $2 }' | sort -u)
      if printf '%s\n' "$all" | awk -F "$TAB" '$2 == "" { f = 1 } END { exit !f }'; then
        grps+=("")
      fi
      n=${#grps[@]}
      [ "$n" -le 1 ] && return 0
      for ((i = 0; i < n; i++)); do [ "${grps[$i]}" = "$grp" ] && idx=$i; done
      d=1; [ "$dir" = prev-group ] && d=-1
      target="${grps[$(((idx + d + n) % n))]}"
      printf '%s' "$(printf '%s\n' "$all" | awk -F "$TAB" -v g="$target" '$2 == g { print $1; exit }')"
      ;;
  esac
}

# $1: client, $2: cur session — 4 方向の行き先を1行のヒントで status-line に表示。
# C-Option 押しっぱなしで hjkl 連打すると押す度に更新される (display-message は
# 直近を上書きする)。表示秒数は NAV_HINT_MS (既定 2500ms)。
# $1: cur session — 4 方向ヒント文字列を stdout に出力 (display も move もしない=テスト可能)。
build_nav_hint() {
  local cur="$1" grp th tl tk tj dash
  printf -v dash '\342\200\224'   # — em dash: 行き先が無い方向の表示
  grp=$(cur_group "$cur")
  th=$(nav_target prev "$cur")
  tl=$(nav_target next "$cur")
  tk=$(nav_target prev-group "$cur")
  tj=$(nav_target next-group "$cur")
  # glyph は format 側に置く (printf が octal を解釈)。session 名は %s 引数 (エスケープ非解釈)。
  # ⌥ [group]  ◀h <prev>  ▶l <next>  ▲k <prevGroup>  ▼j <nextGroup>
  printf '\342\214\245 [%s]  \342\227\200h %s  \342\226\266l %s  \342\226\262k %s  \342\226\274j %s' \
    "${grp:-ungrouped}" "${th:-$dash}" "${tl:-$dash}" "${tk:-$dash}" "${tj:-$dash}"
}

show_nav_hint() {
  local client="$1" cur="$2" msg opts=()
  msg=$(build_nav_hint "$cur")
  [ -n "$client" ] && opts=(-c "$client")
  tmux display-message "${opts[@]}" -d "${NAV_HINT_MS:-2500}" "$msg"
}

# $1: dir, $2: client, $3: cur session — 移動してから現在地の行き先ヒントを出す。
cmd_navhint() {
  local dir="$1" client="${2:-}" cur now
  cur=$(sess_of "${3:-}")
  case "$dir" in
    prev)       cmd_step -1 "$client" "$cur" ;;
    next)       cmd_step 1 "$client" "$cur" ;;
    prev-group) cmd_step_group -1 "$client" "$cur" ;;
    next-group) cmd_step_group 1 "$client" "$cur" ;;
    *) return 1 ;;
  esac
  now=$(client_session "$client")
  [ -z "$now" ] && now="$cur"
  show_nav_hint "$client" "$now"
}

cmd_sync() {
  mkdir -p "$STATE_DIR"
  local tmp
  tmp=$(mktemp "$STATE_DIR/.session-groups.XXXXXX") || return 1
  {
    # live の非空グループ + live に存在しない (死んだ) session の既存エントリ
    list_all | awk -F "$TAB" '$2 != ""'
    [ -f "$STATE_FILE" ] &&
      awk -F "$TAB" 'NR==FNR { live[$1] = 1; next } !($1 in live)' \
        <(list_all) "$STATE_FILE"
  } > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

cmd_apply() {
  local session="$1" grp
  [ -n "$session" ] && [ -f "$STATE_FILE" ] || return 0
  grp=$(awk -F "$TAB" -v s="$session" '$1 == s { print $2; exit }' "$STATE_FILE")
  [ -n "$grp" ] && tmux set-option -t "$session" @group "$grp"
  return 0
}

cmd_restore() {
  local s
  while IFS= read -r s; do
    cmd_apply "$s"
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
}

cmd_set() {
  local sess="$1" grp="$2"
  # `,` は choose-tree filter (#{==:...}) を、空白等は menu/hook を壊すため制限
  case "$grp" in
    '' | *[!A-Za-z0-9_-]*)
      tmux display-message "invalid group name: '$grp' (A-Za-z0-9_- only)"
      return 1
      ;;
  esac
  tmux set-option -t "$sess" @group "$grp"
  cmd_sync
}

cmd_unset() {
  tmux set-option -t "$1" -u @group
  cmd_sync
}

# $1: client_name, $2: client_session — menu popup を開くラッパー。
# display-popup はコマンド文字列を format 展開せず、popup 内の display-message も
# client の session を解決できない (任意の session に化ける) ため、format 展開が
# 正しく効く run-shell -b から本サブコマンドを経由して session 名を焼き込む。
cmd_menu_popup() {
  local client="${1:-}" sess="${2:-}"
  local popup_opts=()
  [ -n "$client" ] && popup_opts=(-c "$client")
  tmux display-popup "${popup_opts[@]}" -E -w 50% -h 50% "'$0' menu '$sess'"
}

# display-popup -E 内で実行される前提 (fzf が pty を要求するため)
cmd_menu() {
  local cur out rc sel
  cur=$(sess_of "${1:-}")
  out=$(
    {
      echo "(none)"
      list_all | awk -F "$TAB" '$2 != "" { print $2 }' | sort -u
    } | fzf --print-query \
        --prompt "group ($cur)> " \
        --header "select / type new group / (none) clears"
  )
  rc=$?
  # 0=選択, 1=マッチなし (query を新規グループ名として採用), 130=abort
  [ $rc -ne 0 ] && [ $rc -ne 1 ] && return 0
  sel=$(printf '%s' "$out" | tail -n 1)
  [ -z "$sel" ] && return 0
  if [ "$sel" = "(none)" ]; then
    cmd_unset "$cur"
  else
    cmd_set "$cur" "$sel"
  fi
}

# $1: 1 (next) / -1 (prev), $2: client_name, $3: current session — 同グループ内を名前順で循環
cmd_step() {
  local dir="$1" client="${2:-}" cur grp s n i idx=0
  local members=()
  cur=$(sess_of "${3:-}")
  grp=$(cur_group "$cur")
  while IFS= read -r s; do
    members+=("$s")
  done < <(list_all | awk -F "$TAB" -v g="$grp" '$2 == g { print $1 }')
  n=${#members[@]}
  if [ "$n" -le 1 ]; then
    tmux display-message -d 800 "no other session in group '${grp:-ungrouped}'"
    return 0
  fi
  for ((i = 0; i < n; i++)); do
    [ "${members[$i]}" = "$cur" ] && idx=$i
  done
  switch_to "$client" "${members[$(((idx + dir + n) % n))]}"
}

# $1: 1 (next-group) / -1 (prev-group), $2: client_name, $3: current session —
# グループ間を循環し先頭 session へ。
# ungrouped session 群は末尾の 1 バケツ (空文字グループ) として扱う
cmd_step_group() {
  local dir="$1" client="${2:-}" cur grp all g n i idx=0 target
  local grps=()
  cur=$(sess_of "${3:-}")
  grp=$(cur_group "$cur")
  all=$(list_all)
  while IFS= read -r g; do
    grps+=("$g")
  done < <(printf '%s\n' "$all" | awk -F "$TAB" '$2 != "" { print $2 }' | sort -u)
  if printf '%s\n' "$all" | awk -F "$TAB" '$2 == "" { found = 1 } END { exit !found }'; then
    grps+=("")
  fi
  n=${#grps[@]}
  if [ "$n" -le 1 ]; then
    tmux display-message -d 800 "no other session group"
    return 0
  fi
  for ((i = 0; i < n; i++)); do
    [ "${grps[$i]}" = "$grp" ] && idx=$i
  done
  target="${grps[$(((idx + dir + n) % n))]}"
  switch_to "$client" "$(printf '%s\n' "$all" | awk -F "$TAB" -v g="$target" '$2 == g { print $1; exit }')"
}

# $1: client_name, $2: pane_id — menu 表示先の client と choose-tree を開く pane。
# 明示ターゲット必須: menu 選択コマンドは選択した client の文脈で実行されず、
# サーバー側の「最後に使った pane」等へ勝手に解決されて見えない pane に mode が開く。
cmd_picker() {
  local client="${1:-}" pane="${2:-}" all g n i key tgt=''
  local grps=() args=() menu_opts=()
  [ -n "$pane" ] && tgt=" -t '$pane'"
  [ -n "$client" ] && menu_opts=(-c "$client")
  all=$(list_all)
  while IFS= read -r g; do
    [ -n "$g" ] && grps+=("$g")
  done < <(printf '%s\n' "$all" | awk -F "$TAB" '$2 != "" { print $2 }' | sort -u)
  # グループが 1 つもなければ従来のフラットな choose-tree へ
  if [ ${#grps[@]} -eq 0 ]; then
    if [ -n "$pane" ]; then
      exec tmux choose-tree -Zs -O name -t "$pane"
    fi
    exec tmux choose-tree -Zs -O name
  fi
  # filter の ## エスケープ必須: menu item のコマンドは実行時に一度 format 展開される
  # ため、素の #{...} だと空文脈で '0' に潰れて filter が全滅する
  i=1
  for g in "${grps[@]}"; do
    n=$(printf '%s\n' "$all" | awk -F "$TAB" -v g="$g" '$2 == g' | grep -c .)
    key=''
    [ $i -le 9 ] && key=$i
    args+=("$g ($n)" "$key" "choose-tree -Zs -O name$tgt -f '##{==:##{@group},$g}'")
    i=$((i + 1))
  done
  n=$(printf '%s\n' "$all" | awk -F "$TAB" '$2 == ""' | grep -c .)
  [ "$n" -gt 0 ] &&
    args+=("(ungrouped) ($n)" u "choose-tree -Zs -O name$tgt -f '##{==:##{@group},}'")
  args+=("")
  args+=("all sessions" a "choose-tree -Zs -O name$tgt")
  tmux display-menu "${menu_opts[@]}" -T " Session Groups " -x C -y C "${args[@]}"
}

case "${1:-}" in
  set)        cmd_set "$(sess_of "${3:-}")" "${2:-}" ;;
  unset)      cmd_unset "$(sess_of "${2:-}")" ;;
  menu-popup) cmd_menu_popup "${2:-}" "${3:-}" ;;
  menu)       cmd_menu "${2:-}" ;;
  next)       cmd_step 1 "${2:-}" "${3:-}" ;;
  prev)       cmd_step -1 "${2:-}" "${3:-}" ;;
  next-group) cmd_step_group 1 "${2:-}" "${3:-}" ;;
  prev-group) cmd_step_group -1 "${2:-}" "${3:-}" ;;
  navhint)    cmd_navhint "${2:-}" "${3:-}" "${4:-}" ;;
  hint)       build_nav_hint "$(sess_of "${2:-}")"; echo ;;
  picker)     cmd_picker "${2:-}" "${3:-}" ;;
  apply)      cmd_apply "${2:-}" ;;
  restore)    cmd_restore ;;
  sync)       cmd_sync ;;
  *)
    echo "usage: $(basename "$0") {set <group> [session]|unset [session]|menu [session]" \
         "|next|prev|next-group|prev-group [client] [session]|navhint <dir> [client] [session]" \
         "|picker [client] [pane]|apply <session>|restore|sync}" >&2
    exit 1
    ;;
esac
