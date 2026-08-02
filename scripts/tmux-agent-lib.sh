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

# tmux 3.4〜3.5a はコマンド出力を vis エスケープする (0x1f → literal "\037")。
# cmdq_print が server_client_print へ parse=0 を渡すため VIS_OCTAL 経路に入る。
# 3.6 で parse=1 固定になり解消したが、3.4〜3.5a を使う環境ではフィールド区切りの
# 0x1f が壊れて分割できないため、読み取り境界で戻す。該当しない版では no-op。
agent_unvis() {
  local us=$'\x1f'
  sed "s/\\\\037/${us}/g"
}

agent_is_shell() {
  case "${1#-}" in
    zsh|bash|sh|fish|dash|ksh|tcsh|nu|xonsh|elvish) return 0 ;;
    *) return 1 ;;
  esac
}
