#!/usr/bin/env bash
# Save/restore tmux extras that resurrect does not keep: rcon session
# options, agent resume targets, and sidebar panes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/tmux-agent-lib.sh"

TMUX_BIN="${TMUX_BIN:-$(command -v tmux 2>/dev/null || true)}"
STATE_DIR="${TMUX_RESTART_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux/restart}"
US=$'\x1f'
SNAPSHOT_DIR="${STATE_DIR}/last"
FORCE=false

usage() {
  cat <<'EOF'
Usage: tmux-restore-extras.sh save [DIR]
       tmux-restore-extras.sh restore [DIR] [--force]
EOF
}

shell_quote() {
  printf '%q' "$1"
}

has_session() {
  "$TMUX_BIN" has-session -t "$1" 2>/dev/null
}

pane_exists() {
  local target="$1" session window pane
  session="${target%%:*}"
  window="${target#*:}"
  window="${window%%.*}"
  pane="${target##*.}"
  "$TMUX_BIN" list-panes -t "$session:$window" -F '#{pane_index}' 2>/dev/null |
    grep -qxF "$pane"
}

current_command() {
  "$TMUX_BIN" display-message -p -t "$1" '#{pane_current_command}' 2>/dev/null || true
}

send_command() {
  "$TMUX_BIN" send-keys -t "$1" "$2" C-m
}

container_running() {
  command -v docker >/dev/null 2>&1 || return 1
  [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" == true ]]
}

publish_last() {
  local last="$STATE_DIR/last"
  [[ "$SNAPSHOT_DIR" == "$last" ]] && return 0
  mkdir -p "$last"
  cp -f "$SNAPSHOT_DIR"/*.tsv "$last/"
}

save_extras() {
  local client_session first_session attach_session attach_cwd attach_window
  [[ -n "$TMUX_BIN" ]] || { echo 'tmux-restore-extras: tmux not found' >&2; return 1; }
  umask 077
  mkdir -p "$SNAPSHOT_DIR"
  "$SCRIPT_DIR/tmux-session-group.sh" sync >/dev/null 2>&1 || true

  client_session=$("$TMUX_BIN" list-clients -F '#{client_session}' 2>/dev/null | head -1 || true)
  first_session=$("$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null | head -1 || true)
  attach_session="${client_session:-$first_session}"
  [[ -n "$attach_session" ]] || { echo 'tmux-restore-extras: no tmux session found' >&2; return 1; }
  attach_cwd=$("$TMUX_BIN" list-panes -t "$attach_session" -F '#{pane_current_path}' 2>/dev/null | head -1 || true)
  attach_cwd="${attach_cwd:-$HOME}"
  [[ -d "$attach_cwd" ]] || attach_cwd="$HOME"
  attach_window=$("$TMUX_BIN" list-windows -t "$attach_session" -F '#{window_index}' 2>/dev/null | head -1 || true)
  attach_window="${attach_window:-0}"

  "$TMUX_BIN" list-sessions -F \
    "#{session_name}${US}#{@rcon-host}${US}#{@rcon-container}${US}#{@rcon-container-home}" |
    agent_unvis > "$SNAPSHOT_DIR/sessions.tsv"
  "$TMUX_BIN" list-panes -a -F \
    "#{session_name}${US}#{window_index}${US}#{pane_index}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{@agent_provider}${US}#{@agent_transcript_path}" |
    agent_unvis > "$SNAPSHOT_DIR/panes.tsv"
  while IFS="$US" read -r session window sidebar; do
    sidebar_index=""
    if [[ -n "$sidebar" ]]; then
      sidebar_index=$("$TMUX_BIN" list-panes -t "$session:$window" \
        -F "#{pane_id}${US}#{pane_index}" 2>/dev/null |
        awk -F "$US" -v pane="$sidebar" '$1 == pane { print $2; exit }')
    fi
    printf '%s%s%s%s%s%s%s\n' "$session" "$US" "$window" "$US" "$sidebar" "$US" "$sidebar_index"
  done < <(
    "$TMUX_BIN" list-windows -a -F \
      "#{session_name}${US}#{window_index}${US}#{@agent_sidebar_pane}" |
      agent_unvis
  ) > "$SNAPSHOT_DIR/windows.tsv"

  {
    printf 'attach_session\t%s\n' "$attach_session"
    printf 'attach_cwd\t%s\n' "$attach_cwd"
    printf 'attach_window\t%s\n' "$attach_window"
    printf 'sessions\t%s\n' "$(awk 'NF { n++ } END { print n + 0 }' "$SNAPSHOT_DIR/sessions.tsv")"
    printf 'panes\t%s\n' "$(awk 'NF { n++ } END { print n + 0 }' "$SNAPSHOT_DIR/panes.tsv")"
  } > "$SNAPSHOT_DIR/meta.tsv"
  publish_last
}

restore_sessions() {
  local session rcon_host container container_home docker_cmd pane
  while IFS="$US" read -r session rcon_host container container_home; do
    [[ -n "$session" ]] || continue
    has_session "$session" || continue
    [[ -n "$rcon_host" ]] && "$TMUX_BIN" set-option -t "$session" @rcon-host "$rcon_host"
    [[ -n "$container" ]] || continue

    "$TMUX_BIN" set-option -t "$session" @rcon-container "$container"
    [[ -n "$container_home" ]] &&
      "$TMUX_BIN" set-option -t "$session" @rcon-container-home "$container_home"
    docker_cmd="exec $(shell_quote "$SCRIPT_DIR/tmux-docker-enter") $(shell_quote "$container")"
    "$TMUX_BIN" set-option -t "$session" default-command "$docker_cmd"

    if ! container_running "$container"; then
      echo "Warning: container '$container' is not running; left panes untouched." >&2
      continue
    fi
    while IFS= read -r pane; do
      [[ -n "$pane" ]] || continue
      "$TMUX_BIN" respawn-pane -k -t "$pane" "$docker_cmd" 2>/dev/null || true
    done < <("$TMUX_BIN" list-panes -t "$session" -F '#{pane_id}' 2>/dev/null)
  done < "$SNAPSHOT_DIR/sessions.tsv"
  "$TMUX_BIN" set-environment -g RCON_HOST_HOME "$HOME"
  "$TMUX_BIN" set-environment -g RCON_HOST_MACHINE "${RCON_HOST_MACHINE:-$(hostname -s 2>/dev/null || hostname)}"
}

restore_sidebars() {
  local session window old_sidebar sidebar_index pane socket_path server_pid tmux_env sidebar_command
  MISSING_SIDEBARS=()
  while IFS="$US" read -r session window old_sidebar sidebar_index; do
    [[ -n "$old_sidebar" ]] || continue
    has_session "$session" || continue

    pane=$("$TMUX_BIN" show-options -w -t "$session:$window" -qv @agent_sidebar_pane 2>/dev/null || true)
    if [[ -z "$pane" ]]; then
      sidebar_index="${sidebar_index:-1}"
      pane=$("$TMUX_BIN" list-panes -t "$session:$window" \
        -F "#{pane_index}${US}#{pane_id}" 2>/dev/null |
        awk -F "$US" -v idx="$sidebar_index" '$1 == idx { print $2; exit }')
    fi
    if [[ -z "$pane" ]]; then
      MISSING_SIDEBARS+=("$session${US}$window")
      continue
    fi

    "$TMUX_BIN" set-option -w -t "$session:$window" @agent_sidebar_pane "$pane"
    "$TMUX_BIN" set-option -p -t "$pane" @agent_status "" 2>/dev/null || true
    sidebar_command="bash $(shell_quote "$SCRIPT_DIR/tmux-agent-sidebar.sh") run"
    "$TMUX_BIN" respawn-pane -k -t "$pane" "$sidebar_command" 2>/dev/null ||
      echo "Warning: could not restart sidebar in $session:$window" >&2
    socket_path=$("$TMUX_BIN" display-message -p -t "$pane" '#{socket_path}' 2>/dev/null || true)
    server_pid=$("$TMUX_BIN" display-message -p -t "$pane" '#{pid}' 2>/dev/null || true)
    tmux_env="${socket_path:-default},${server_pid:-0},0"
    TMUX="$tmux_env" TMUX_PANE="$pane" "$SCRIPT_DIR/tmux-agent-sidebar.sh" rehook >/dev/null 2>&1 || true
  done < "$SNAPSHOT_DIR/windows.tsv"
}

restore_missing_sidebars() {
  local target session window pane socket_path server_pid tmux_env
  for target in "${MISSING_SIDEBARS[@]+"${MISSING_SIDEBARS[@]}"}"; do
    IFS="$US" read -r session window <<< "$target"
    pane=$("$TMUX_BIN" list-panes -t "$session:$window" -F '#{pane_id}' 2>/dev/null | head -1 || true)
    [[ -n "$pane" ]] || continue
    socket_path=$("$TMUX_BIN" display-message -p -t "$pane" '#{socket_path}' 2>/dev/null || true)
    server_pid=$("$TMUX_BIN" display-message -p -t "$pane" '#{pid}' 2>/dev/null || true)
    tmux_env="${socket_path:-default},${server_pid:-0},0"
    TMUX="$tmux_env" TMUX_PANE="$pane" "$SCRIPT_DIR/tmux-agent-sidebar.sh" toggle >/dev/null 2>&1 ||
      echo "Warning: could not create missing sidebar in $session:$window" >&2
  done
}

wait_for_pane_shell() {
  local pane="$1" cmd
  for _ in $(seq 1 10); do
    cmd=$(current_command "$pane")
    case "$cmd" in
      tmux-docker-enter|docker|sleep) sleep 0.2 ;;
      *) return 0 ;;
    esac
  done
}

launch_agents() {
  local session window pane path saved_cmd provider transcript target current kind command qpath
  local transcript_path resume_id container
  local launched=0 skipped=0
  while IFS="$US" read -r session window pane path saved_cmd provider transcript; do
    [[ -n "$session" ]] || continue
    target="$session:$window.$pane"
    pane_exists "$target" || { echo "Warning: missing pane $target" >&2; skipped=$((skipped + 1)); continue; }

    wait_for_pane_shell "$target"
    container=$(awk -F "$US" -v s="$session" '$1 == s { print $3; exit }' "$SNAPSHOT_DIR/sessions.tsv")
    if [[ -n "$container" ]] && container_running "$container"; then
      qpath=$(shell_quote "$path")
      send_command "$target" "cd -- $qpath"
      sleep 0.2
    fi

    provider=$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')
    kind="$provider"
    if [[ -z "$kind" ]]; then
      case "$saved_cmd" in
        claude*) kind=claude ;;
        pi*) kind=pi ;;
        codex*) kind=codex ;;
        nvim|vim|view) kind=nvim ;;
        *) kind='' ;;
      esac
    fi
    transcript_path="$transcript"
    resume_id=""
    case "$kind" in
      claude)
        if [[ -n "$transcript_path" ]]; then
          resume_id="${transcript_path##*/}"
          resume_id="${resume_id%.jsonl}"
          command="claude --resume $(shell_quote "$resume_id")"
        else
          command='claude --continue'
        fi
        ;;
      pi) command='pi --continue' ;;
      codex) command='codex resume --last' ;;
      nvim) command='nvim' ;;
      *) continue ;;
    esac

    current=$(current_command "$target")
    if ! agent_is_shell "$current"; then
      case "$kind:$current" in
        nvim:nvim|nvim:vim|claude:claude|pi:pi|codex:codex) continue ;;
        *) echo "Warning: $target is running '$current'; skipped '$command'." >&2; skipped=$((skipped + 1)); continue ;;
      esac
    fi

    [[ -n "$provider" ]] && "$TMUX_BIN" set-option -p -t "$target" @agent_provider "$provider" 2>/dev/null || true
    [[ -n "$transcript_path" ]] &&
      "$TMUX_BIN" set-option -p -t "$target" @agent_transcript_path "$transcript_path" 2>/dev/null || true
    send_command "$target" "$command"
    launched=$((launched + 1))
  done < "$SNAPSHOT_DIR/panes.tsv"
  echo "Processes launched: $launched, skipped: $skipped"
}

restore_extras() {
  [[ -n "$TMUX_BIN" ]] || { echo 'tmux-restore-extras: tmux not found' >&2; return 1; }
  [[ -f "$SNAPSHOT_DIR/meta.tsv" && -f "$SNAPSHOT_DIR/sessions.tsv" && -f "$SNAPSHOT_DIR/panes.tsv" ]] || {
    echo "tmux-restore-extras: no snapshot at $SNAPSHOT_DIR" >&2
    return 0
  }
  if [[ "$FORCE" != true ]] && [[ "$("$TMUX_BIN" show-options -gv @restore-extras-done 2>/dev/null || true)" == 1 ]]; then
    echo 'tmux-restore-extras: already applied'
    return 0
  fi
  "$TMUX_BIN" set-option -g @restore-extras-done 1
  restore_sessions
  restore_sidebars
  "$SCRIPT_DIR/tmux-session-group.sh" restore >/dev/null 2>&1 || true
  launch_agents
  restore_missing_sidebars
}

cmd="${1:-}"
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    *) SNAPSHOT_DIR="$1" ;;
  esac
  shift
done

case "$cmd" in
  save) save_extras ;;
  restore) restore_extras ;;
  -h|--help|'') usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
