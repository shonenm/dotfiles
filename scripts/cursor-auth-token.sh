#!/bin/bash
# Print Cursor OAuth/API access token to stdout.
# Used by tmux-cursor-usage.sh (do not log output).
#
# Resolution order:
#   1. CURSOR_AUTH_TOKEN / CURSOR_API_KEY env
#   2. macOS Keychain (cursor-agent CLI login)
#   3. Linux secret-service (same service names)
#   4. Cursor IDE state.vscdb (when IDE is installed)

set -euo pipefail

if [[ -n "${CURSOR_AUTH_TOKEN:-}" ]]; then
  printf '%s' "$CURSOR_AUTH_TOKEN"
  exit 0
fi

if [[ -n "${CURSOR_API_KEY:-}" ]]; then
  printf '%s' "$CURSOR_API_KEY"
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    if token=$(security find-generic-password -s "cursor-access-token" -a "cursor-user" -w 2>/dev/null); then
      printf '%s' "$token"
      exit 0
    fi
    ;;
  Linux)
    if command -v secret-tool &>/dev/null; then
      if token=$(secret-tool lookup service cursor-access-token account cursor-user 2>/dev/null); then
        printf '%s' "$token"
        exit 0
      fi
    fi
    ;;
esac

read_sqlite_token() {
  local db="$1"
  [[ -f "$db" ]] || return 1
  command -v sqlite3 &>/dev/null || return 1

  python3 - "$db" <<'PY'
import json, sqlite3, sys

db = sys.argv[1]
keys = (
    "cursorAuth/accessToken",
    "cursor.accessToken",
    "workos.sessionToken",
    "cursorAuth/refreshToken",
)

conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
try:
    cur = conn.cursor()
    for key in keys:
        cur.execute("SELECT value FROM ItemTable WHERE key = ? LIMIT 1", (key,))
        row = cur.fetchone()
        if not row or not row[0]:
            continue
        raw = row[0]
        try:
            data = json.loads(raw)
            if isinstance(data, dict):
                token = data.get("accessToken") or data.get("token")
                if token:
                    print(token)
                    raise SystemExit(0)
            elif isinstance(data, str) and data:
                print(data)
                raise SystemExit(0)
        except json.JSONDecodeError:
            if raw:
                print(raw)
                raise SystemExit(0)
finally:
    conn.close()
sys.exit(1)
PY
}

for db in \
  "${HOME}/Library/Application Support/Cursor/User/globalStorage/state.vscdb" \
  "${XDG_CONFIG_HOME:-${HOME}/.config}/Cursor/User/globalStorage/state.vscdb"; do
  if token=$(read_sqlite_token "$db" 2>/dev/null); then
    printf '%s' "$token"
    exit 0
  fi
done

exit 1
