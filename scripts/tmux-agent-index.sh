#!/bin/bash
# tmux agent inventory cache.
# Expensive global tmux scans live here so sidebar/status views can read one cache
# instead of each running `tmux list-panes -a` independently.

set -uo pipefail

RUNTIME_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-$HOME/.cache}}"
CACHE_DIR="${AGENT_INDEX_DIR:-$RUNTIME_BASE/claude/tmux-agent-index}"
PANES_FILE="$CACHE_DIR/panes.tsv"
SESSIONS_FILE="$CACHE_DIR/sessions.tsv"
UPDATED_FILE="$CACHE_DIR/updated"
LOCK_FILE="$CACHE_DIR/daemon.pid"
REFRESH="${AGENT_INDEX_REFRESH:-3}"
STALE="${AGENT_INDEX_STALE:-5}"
US=$'\x1f'

mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null ;;
    *) stat -c %Y "$1" 2>/dev/null ;;
  esac
}

refresh() {
  mkdir -p "$CACHE_DIR" 2>/dev/null || return 1
  local panes_tmp sessions_tmp updated_tmp
  panes_tmp="$PANES_FILE.$$"
  sessions_tmp="$SESSIONS_FILE.$$"
  updated_tmp="$UPDATED_FILE.$$"

  tmux list-panes -a -F "#{pane_id}${US}#{session_name}${US}#{window_index}${US}#{@agent_status}${US}#{@agent_heartbeat}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{pane_title}${US}#{@agent_stashed}${US}#{@agent_sidebar_pane}" >"$panes_tmp" || {
    rm -f "$panes_tmp" "$sessions_tmp" "$updated_tmp"
    return 1
  }
  tmux list-sessions -F "#{session_name}${US}#{@group}${US}#{session_attached}" >"$sessions_tmp" || {
    rm -f "$panes_tmp" "$sessions_tmp" "$updated_tmp"
    return 1
  }
  date +%s >"$updated_tmp"
  mv "$panes_tmp" "$PANES_FILE"
  mv "$sessions_tmp" "$SESSIONS_FILE"
  mv "$updated_tmp" "$UPDATED_FILE"
}

ensure_fresh() {
  local now mt age
  now=$(date +%s)
  mt=$(mtime "$UPDATED_FILE")
  age=$(( now - ${mt:-0} ))
  if [[ ! -s "$PANES_FILE" || ! -s "$SESSIONS_FILE" || "$age" -gt "$STALE" ]]; then
    refresh >/dev/null 2>&1 || true
  fi
}

daemon() {
  mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0
  if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
    exit 0
  fi
  echo $$ >"$LOCK_FILE"
  cleanup() { [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]] && rm -f "$LOCK_FILE"; }
  trap cleanup EXIT
  trap 'cleanup; exit 0' INT TERM

  while true; do
    tmux info >/dev/null 2>&1 || exit 0
    owner="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    [[ -n "$owner" && "$owner" != "$$" ]] && exit 0
    refresh >/dev/null 2>&1 || true
    sleep "$REFRESH" & wait $! || true
  done
}

case "${1:-panes}" in
  daemon) daemon ;;
  refresh) refresh ;;
  panes) ensure_fresh; cat "$PANES_FILE" 2>/dev/null || true ;;
  sessions) ensure_fresh; cat "$SESSIONS_FILE" 2>/dev/null || true ;;
  *) echo "Usage: $0 {daemon|refresh|panes|sessions}" >&2; exit 1 ;;
esac
