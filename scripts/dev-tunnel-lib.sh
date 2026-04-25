#!/usr/bin/env bash
# dev-tunnel-lib.sh - autossh ベースの persistent tunnel 管理ライブラリ
# 関連: scripts/dev-tunnel
#
# 設計:
# - ssh ConfigFile (~/.ssh/config + Include) に定義済みの Host エントリを使う
# - Host エントリ側で LocalForward / ControlMaster / ServerAliveInterval を指定
# - autossh は ssh セッション全体を監視し、死んだら再起動
# - PID は ~/.local/state/dev-tunnel/<host>.pid に保存

set -euo pipefail

DT_STATE_DIR="${DT_STATE_DIR:-$HOME/.local/state/dev-tunnel}"
DT_LOG_DIR="${DT_LOG_DIR:-$HOME/.local/state/dev-tunnel/logs}"

dt_ensure_dirs() {
  mkdir -p "$DT_STATE_DIR" "$DT_LOG_DIR"
}

dt_pidfile() {
  local host="$1"
  printf '%s/%s.pid' "$DT_STATE_DIR" "$host"
}

dt_logfile() {
  local host="$1"
  printf '%s/%s.log' "$DT_LOG_DIR" "$host"
}

dt_is_running() {
  local host="$1"
  local pidfile
  pidfile="$(dt_pidfile "$host")"
  [[ -f "$pidfile" ]] || return 1
  local pid
  pid="$(<"$pidfile")"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

dt_check_host() {
  local host="$1"
  if ! ssh -G "$host" >/dev/null 2>&1; then
    echo "Error: ssh host '$host' not defined in ~/.ssh/config (or Includes)" >&2
    return 1
  fi
}

dt_start() {
  local host="$1"
  dt_check_host "$host" || return 1
  dt_ensure_dirs
  if dt_is_running "$host"; then
    echo "dev-tunnel: $host already running (pid $(<"$(dt_pidfile "$host")"))"
    return 0
  fi
  command -v autossh >/dev/null 2>&1 || {
    echo "Error: autossh not installed. Run: brew install autossh (mac) or apt install autossh (linux)" >&2
    return 1
  }
  local logfile pidfile
  logfile="$(dt_logfile "$host")"
  pidfile="$(dt_pidfile "$host")"
  # AUTOSSH_GATETIME=0 = retry from boot, AUTOSSH_PORT=0 disables monitor port (rely on ServerAlive)
  AUTOSSH_GATETIME=0 AUTOSSH_PORT=0 AUTOSSH_LOGFILE="$logfile" \
    autossh -M 0 -f -N \
      -o "ServerAliveInterval=30" \
      -o "ServerAliveCountMax=3" \
      -o "ExitOnForwardFailure=yes" \
      "$host"
  # autossh -f forks; capture child pid from pgrep filtered by host
  sleep 0.3
  local pid
  pid="$(pgrep -f "autossh.*${host}\$" | head -1 || true)"
  if [[ -z "$pid" ]]; then
    echo "Error: failed to capture autossh pid for $host (check $logfile)" >&2
    return 1
  fi
  printf '%s\n' "$pid" > "$pidfile"
  echo "dev-tunnel: started $host (pid $pid)"
}

dt_stop() {
  local host="$1"
  local pidfile
  pidfile="$(dt_pidfile "$host")"
  if ! dt_is_running "$host"; then
    echo "dev-tunnel: $host not running"
    rm -f "$pidfile"
    return 0
  fi
  local pid
  pid="$(<"$pidfile")"
  kill "$pid" 2>/dev/null || true
  rm -f "$pidfile"
  # Close any lingering ControlMaster session for clean state
  ssh -O exit "$host" 2>/dev/null || true
  echo "dev-tunnel: stopped $host (pid $pid)"
}

dt_status() {
  local host="$1"
  if dt_is_running "$host"; then
    local pid
    pid="$(<"$(dt_pidfile "$host")")"
    echo "dev-tunnel: $host RUNNING (autossh pid $pid)"
  else
    echo "dev-tunnel: $host STOPPED"
    return 1
  fi
  # ControlMaster socket health
  if ssh -O check "$host" 2>&1 | grep -q "Master running"; then
    echo "  ControlMaster: alive"
  else
    echo "  ControlMaster: not connected (autossh may be reconnecting)"
  fi
}

dt_restart() {
  local host="$1"
  dt_stop "$host" || true
  sleep 0.5
  dt_start "$host"
}

dt_health() {
  local host="$1"
  dt_check_host "$host" || return 1
  # Run a trivial command via the multiplexed connection to verify forward path
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null; then
    echo "dev-tunnel: $host reachable via ssh"
  else
    echo "dev-tunnel: $host UNREACHABLE" >&2
    return 1
  fi
}
