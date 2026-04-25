#!/usr/bin/env bash
# dev-gateway-lib.sh - リモートホスト上の Traefik gateway 管理ライブラリ
# 関連: scripts/dev-gateway, common/traefik-dev/

set -euo pipefail

DG_REMOTE_DIR="${DG_REMOTE_DIR:-\$HOME/.config/traefik-dev}"
DG_NETWORK="${DG_NETWORK:-dev-edge}"
DG_API_LOCAL_PORT="${DG_API_LOCAL_PORT:-48090}"

# ssh exec helper. Quoted single-arg style to keep remote shell predictable.
# Client-side expansion of $@ is intentional — callers compose remote commands
# using DG_REMOTE_DIR / DG_NETWORK that already escape remote-side $HOME.
dg_ssh() {
  local host="$1"; shift
  # shellcheck disable=SC2029
  ssh "$host" "$@"
}

dg_check_host() {
  local host="$1"
  if ! ssh -G "$host" >/dev/null 2>&1; then
    echo "Error: ssh host '$host' not defined" >&2
    return 1
  fi
}

dg_ensure_network() {
  local host="$1"
  if ! dg_ssh "$host" "docker network inspect $DG_NETWORK >/dev/null 2>&1"; then
    echo "dev-gateway: creating docker network '$DG_NETWORK' on $host"
    dg_ssh "$host" "docker network create $DG_NETWORK"
  fi
}

dg_up() {
  local host="$1"
  dg_check_host "$host" || return 1
  dg_ensure_network "$host"
  dg_ssh "$host" "cd $DG_REMOTE_DIR && docker compose up -d"
  echo "dev-gateway: up on $host"
}

dg_down() {
  local host="$1"
  dg_check_host "$host" || return 1
  dg_ssh "$host" "cd $DG_REMOTE_DIR && docker compose down"
  echo "dev-gateway: down on $host"
}

dg_status() {
  local host="$1"
  dg_check_host "$host" || return 1
  dg_ssh "$host" "cd $DG_REMOTE_DIR && docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'"
}

dg_logs() {
  local host="$1"
  local svc="${2:-traefik}"
  dg_check_host "$host" || return 1
  dg_ssh "$host" "cd $DG_REMOTE_DIR && docker compose logs -f --tail=100 $svc"
}

dg_reload() {
  local host="$1"
  dg_check_host "$host" || return 1
  dg_ssh "$host" "cd $DG_REMOTE_DIR && docker compose restart traefik"
  echo "dev-gateway: traefik restarted on $host"
}

dg_routes() {
  local host="$1"
  dg_check_host "$host" || return 1
  # Traefik API は 127.0.0.1:48090 (compose 設定) で localhost only。
  # ssh config 側で LocalForward 48090 ... を入れていれば直接叩ける。
  # それ以外なら ssh 経由で curl。
  if curl -fsS --max-time 2 "http://127.0.0.1:${DG_API_LOCAL_PORT}/api/http/routers" >/dev/null 2>&1; then
    curl -fsS "http://127.0.0.1:${DG_API_LOCAL_PORT}/api/http/routers" \
      | jq -r '.[] | "[http]\t\(.name)\t\(.rule)\t-> \(.service)"' 2>/dev/null
    curl -fsS "http://127.0.0.1:${DG_API_LOCAL_PORT}/api/tcp/routers" \
      | jq -r '.[] | "[tcp] \t\(.name)\t\(.rule)\t-> \(.service)"' 2>/dev/null
  else
    echo "(API not reachable on localhost:${DG_API_LOCAL_PORT}, fetching via ssh)"
    dg_ssh "$host" "curl -fsS http://127.0.0.1:48090/api/http/routers" \
      | jq -r '.[] | "[http]\t\(.name)\t\(.rule)\t-> \(.service)"' 2>/dev/null
    dg_ssh "$host" "curl -fsS http://127.0.0.1:48090/api/tcp/routers" \
      | jq -r '.[] | "[tcp] \t\(.name)\t\(.rule)\t-> \(.service)"' 2>/dev/null
  fi
}
