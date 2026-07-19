#!/bin/bash
# Shared helpers for tmux agent state scripts.

agent_runtime_base() {
  printf '%s' "${XDG_RUNTIME_DIR:-${TMPDIR:-$HOME/.cache}}"
}

agent_server_key() {
  local socket="${TMUX%%,*}"
  [[ -n "$socket" ]] || socket="default"
  printf '%s' "$socket" | cksum | awk '{print $1}'
}

agent_runtime_dir() {
  printf '%s/claude/tmux-%s' "$(agent_runtime_base)" "$(agent_server_key)"
}

agent_is_shell() {
  case "${1#-}" in
    zsh|bash|sh|fish|dash|ksh|tcsh|nu|xonsh|elvish) return 0 ;;
    *) return 1 ;;
  esac
}
