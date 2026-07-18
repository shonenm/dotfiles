#!/bin/bash
# tmux status metrics daemon.
#
# Renders the cpu/ram/gpu/storage pills and the per-pane git branch OUT OF the
# redraw path, pushing them into tmux options (@sysstat on the server, @git_branch
# per pane) so status-right can interpolate #{@sysstat} / #{@git_branch} with ZERO
# subprocess forks per redraw.
#
# Why this exists: on a long-lived, memory-bloated tmux server, fork() costs
# ~250ms (vs ~5ms on a fresh server). The old status-right ran four metric #()
# forks plus a per-redraw `git branch` #() -- so every screen refresh (pane/window
# switch) paid several forks and lagged 0.5-1s. Moving them here makes redraws
# fork-free; the forks now happen in this one background loop instead.
#
# Launched single-instance from claude-hooks.tmux (run-shell -b), same pattern as
# tmux-agent-index.sh. Inherits $TMUX so tmux commands target the launching server;
# when that server dies, `tmux set-option` fails and the loop exits.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-$HOME/.cache}}"
LOCK_FILE="${TMUX_METRICS_DIR:-$RUNTIME_BASE/claude/tmux-metrics}/daemon.pid"
INTERVAL="${TMUX_METRICS_REFRESH:-3}"

# TokyoNight separator/pill colors. The metric scripts hardcode the same palette,
# so a fixed value here keeps the rendered block identical to the old inline form.
BG="#292e42"
SEP_FG="#545c7e"

render_sysstat() {
  local cpu ram gpu sto
  cpu=$("$here/tmux-cpu.sh" 2>/dev/null)
  ram=$("$here/tmux-ram.sh" 2>/dev/null)
  gpu=$("$here/tmux-gpu.sh" 2>/dev/null)
  sto=$("$here/tmux-storage.sh" 2>/dev/null)
  # cpu | ram gpu storage -- gpu/storage emit their own leading separators.
  printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s]|%s%s%s' \
    "$SEP_FG" "$BG" "$cpu" "$SEP_FG" "$BG" "$ram" "$gpu" "$sto"
}

tick() {
  # sysstat is host-wide -> one server option. Failure here means the server is
  # gone, so propagate it to stop the loop.
  tmux set-option -g @sysstat "$(render_sysstat)" 2>/dev/null || return 1

  # git branch is per-pane -> only compute for the active pane of each active
  # window (the panes a status bar can actually display).
  tmux list-panes -a -f '#{&&:#{window_active},#{pane_active}}' \
      -F '#{pane_id}	#{pane_current_path}' 2>/dev/null |
  while IFS=$'\t' read -r pane path; do
    [ -n "$pane" ] || continue
    br=$(git -C "$path" branch --show-current 2>/dev/null)
    [ -n "$br" ] || br='-'
    tmux set-option -p -t "$pane" @git_branch "$br" 2>/dev/null || true
  done
  return 0
}

daemon() {
  mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || exit 0
  # single instance: bail if a live daemon already holds the lock
  if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
    exit 0
  fi
  echo "$$" > "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
  while :; do
    tick || break
    sleep "$INTERVAL"
  done
}

case "${1:-daemon}" in
  once)      tick ;;        # single render, for testing / manual initial paint
  daemon|"") daemon ;;
  *) echo "usage: ${0##*/} [daemon|once]" >&2; exit 2 ;;
esac
