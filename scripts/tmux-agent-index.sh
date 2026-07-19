#!/bin/bash
# tmux agent inventory cache.
# Expensive global tmux scans live here so sidebar/status views can read one cache
# instead of each running `tmux list-panes -a` independently.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-lib.sh"
CACHE_DIR="${AGENT_INDEX_DIR:-$(agent_runtime_dir)/index}"
PANES_FILE="$CACHE_DIR/panes.tsv"
SESSIONS_FILE="$CACHE_DIR/sessions.tsv"
UPDATED_FILE="$CACHE_DIR/updated"
LOCK_FILE="$CACHE_DIR/daemon.pid"
MUTEX_DIR="$CACHE_DIR/snapshot.lock"
REFRESH="${AGENT_INDEX_REFRESH:-3}"
STALE="${AGENT_INDEX_STALE:-5}"
US=$'\x1f'

mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null ;;
    *) stat -c %Y "$1" 2>/dev/null ;;
  esac
}

acquire_snapshot_lock() {
  mkdir -p "$CACHE_DIR" 2>/dev/null || return 1
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if mkdir "$MUTEX_DIR" 2>/dev/null; then
      echo $$ > "$MUTEX_DIR/pid"
      return 0
    fi
    sleep 0.05
  done
  local owner
  owner=$(cat "$MUTEX_DIR/pid" 2>/dev/null || true)
  if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
    rm -f "$MUTEX_DIR/pid"
    rmdir "$MUTEX_DIR" 2>/dev/null || return 1
    mkdir "$MUTEX_DIR" 2>/dev/null || return 1
    echo $$ > "$MUTEX_DIR/pid"
    return 0
  fi
  return 1
}

release_snapshot_lock() {
  [[ "$(cat "$MUTEX_DIR/pid" 2>/dev/null || true)" == "$$" ]] || return 0
  rm -f "$MUTEX_DIR/pid"
  rmdir "$MUTEX_DIR" 2>/dev/null || true
}

refresh_unlocked() {
  local panes_tmp sessions_tmp updated_tmp
  panes_tmp="$PANES_FILE.$$"
  sessions_tmp="$SESSIONS_FILE.$$"
  updated_tmp="$UPDATED_FILE.$$"

  tmux list-panes -a -F "#{pane_id}${US}#{session_name}${US}#{window_index}${US}#{@agent_status}${US}#{@agent_heartbeat}${US}#{@agent_state_since}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{pane_title}${US}#{@agent_stashed}${US}#{@agent_sidebar_pane}${US}#{@agent_provider}" >"$panes_tmp" || {
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

refresh() {
  acquire_snapshot_lock || return 1
  refresh_unlocked
  local rc=$?
  release_snapshot_lock
  return "$rc"
}

invalidate() {
  acquire_snapshot_lock || return 1
  rm -f "$UPDATED_FILE"
  release_snapshot_lock
}

ensure_fresh() {
  local now mt age
  now=$(date +%s)
  mt=$(mtime "$UPDATED_FILE")
  age=$(( now - ${mt:-0} ))
  if [[ ! -s "$PANES_FILE" || ! -s "$SESSIONS_FILE" || "$age" -gt "$STALE" ]]; then
    refresh >/dev/null 2>&1 || return 1
  fi
  [[ -s "$PANES_FILE" && -s "$SESSIONS_FILE" ]]
}

daemon() {
  mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0
  if [[ -f "$LOCK_FILE" ]]; then
    local existing command
    existing=$(cat "$LOCK_FILE" 2>/dev/null || true)
    command=$(ps -p "$existing" -o command= 2>/dev/null || true)
    [[ -n "$existing" && "$command" == *tmux-agent-index.sh* ]] && exit 0
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
  invalidate) invalidate ;;
  panes) ensure_fresh && cat "$PANES_FILE" ;;
  sessions) ensure_fresh && cat "$SESSIONS_FILE" ;;
  *) echo "Usage: $0 {daemon|refresh|invalidate|panes|sessions}" >&2; exit 1 ;;
esac
