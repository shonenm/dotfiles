#!/bin/bash
# 擬似 zoom (tmux-zoom-lib.sh) の往復で pane 配置が完全に復元され、
# 退避 pane が受ける SIGWINCH が退避と復帰の 1 回ずつに収まることを確認する。
# 専用 socket 上で動くため、稼働中の tmux server には触らない。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-zoom-test.XXXXXX")"
SOCK="$TMP/tmux.sock"
LOG="$TMP/winch.log"
REAL_TMUX="$(command -v tmux)"

cleanup() { "$REAL_TMUX" -S "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# lib は素の tmux を呼ぶので、PATH でテスト socket に向ける
mkdir -p "$TMP/bin"
printf '#!/bin/bash\nexec %s -S %s "$@"\n' "$REAL_TMUX" "$SOCK" > "$TMP/bin/tmux"
chmod +x "$TMP/bin/tmux"
PATH="$TMP/bin:$PATH"

# shellcheck source=/dev/null
source "$ROOT/scripts/tmux-zoom-lib.sh"

tmux -f /dev/null new-session -d -s zoom -x 200 -y 50
WIN=$(tmux display-message -t zoom:1 -p '#{window_id}')
SB=$(tmux display-message -t zoom:1 -p '#{pane_id}')
# probe: WINCH を記録する。他 pane は寝かせるだけ。
PROBE=$(tmux split-window -h -t "$SB" -P -F '#{pane_id}' \
  "bash -c 'trap \"echo winch >> $LOG\" WINCH; while :; do sleep 0.2; done'")
TOP=$(tmux split-window -h -t "$PROBE" -P -F '#{pane_id}' 'exec sleep 600')
BOTTOM=$(tmux split-window -v -t "$TOP" -P -F '#{pane_id}' 'exec sleep 600')
tmux resize-pane -t "$SB" -x 40
tmux set-option -w -t "$WIN" @agent_sidebar_pane "$SB"
sleep 1

# pane_index の採番は join の順で変わるため、位置順に並べて比較する
geometry() {
  tmux list-panes -t "$WIN" -F '#{pane_top}:#{pane_left}:#{pane_id}:#{pane_width}x#{pane_height}' \
    | sort -t: -k1,1n -k2,2n | paste -sd, -
}
layout() { tmux display-message -t "$WIN" -p '#{window_layout}'; }

for target in "$PROBE" "$TOP" "$BOTTOM"; do
  before_geo=$(geometry); before_layout=$(layout)
  : > "$LOG"

  tmux select-pane -t "$target"
  pzoom_apply "$WIN" "$target" || fail "pzoom_apply failed for $target"
  sleep 0.5

  zoom_w=$(tmux display-message -t "$target" -p '#{pane_width}')
  [[ "$zoom_w" -gt 100 ]] || fail "$target did not expand (width=$zoom_w)"
  narrow=$(tmux list-panes -t "$WIN" -F '#{pane_id} #{pane_width}' | awk '$2 <= 2 {print $1}')
  [[ -z "$narrow" ]] || fail "sibling crushed instead of stashed: $narrow"

  pzoom_restore "$WIN" || fail "pzoom_restore failed for $target"
  sleep 0.5

  [[ "$(geometry)" == "$before_geo" ]] || fail "geometry changed zooming $target: $(geometry) != $before_geo"
  [[ "$(layout)" == "$before_layout" ]] || fail "layout changed zooming $target"
  tmux list-windows -t zoom -F '#{window_name}' | grep -qxF _pzoom && fail "stash window left behind"

  if [[ "$target" != "$PROBE" ]]; then
    winches=$(wc -l < "$LOG" | tr -d ' ')
    [[ "$winches" -le 2 ]] || fail "stashed pane got $winches SIGWINCH zooming $target (want <= 2)"
  fi
done

echo "tmux pseudo-zoom: OK"
