#!/bin/bash
# Single tmux hook entrypoint. Keep tmux hooks cheap: one fork per event, then
# dispatch related maintenance from here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-$HOME/.cache}}"
LOCK_DIR="$RUNTIME_BASE/claude/tmux-hook-dispatch"

run_script() {
  local script="$1"
  shift
  "$SCRIPT_DIR/$script" "$@" >/dev/null 2>&1 || true
}

with_lock() {
  local name="$1"
  shift
  mkdir -p "$LOCK_DIR" 2>/dev/null || return 0
  local lock="$LOCK_DIR/$name.lock"
  mkdir "$lock" 2>/dev/null || return 0
  trap 'rm -rf "$lock"' RETURN
  "$@"
}

dispatch() {
  local event="${1:-}"
  shift || true
  case "$event" in
    session-window-changed)
      run_script tmux-claude-focus.sh
      ;;
    client-session-changed)
      local session="${1:-}"
      run_script tmux-claude-focus.sh
      run_script tmux-session-color.sh refresh "$session"
      run_script tmux-session-group.sh remember "$session"
      run_script tmux-agent-sidebar.sh resize-all
      ;;
    session-created)
      local session="${1:-}"
      run_script tmux-session-color.sh apply "$session"
      run_script tmux-session-group.sh apply "$session"
      ;;
    session-renamed)
      run_script tmux-session-group.sh sync
      ;;
    client-attached|after-new-window)
      local session="${1:-}"
      run_script tmux-session-color.sh refresh "$session"
      ;;
    client-resized)
      run_script tmux-agent-sidebar.sh resize-all
      ;;
    window-layout-changed)
      run_script tmux-agent-sidebar.sh resize-all "${1:-}"
      ;;
  esac
}

case "${1:-}" in
  client-resized|window-layout-changed)
    with_lock "${1:-hook}" dispatch "$@"
    ;;
  *)
    dispatch "$@"
    ;;
esac
