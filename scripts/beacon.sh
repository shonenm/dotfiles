#!/bin/bash
# Claude Beacon - Register current environment to aerospace workspace
# Usage: beacon.sh <workspace_number>

set -euo pipefail

WORKSPACE="${1:-}"
MAP_FILE="/tmp/claude_workspace_map.json"

if [[ -z "$WORKSPACE" ]]; then
  echo "Usage: beacon.sh <workspace_number>" >&2
  exit 1
fi

# Generate environment key based on current context
generate_env_key() {
  if [[ -n "${TMUX:-}" ]]; then
    echo "tmux_$(tmux display-message -p '#S_#I' 2>/dev/null)"
  elif [[ -n "${VSCODE_PID:-}" ]]; then
    echo "vscode_${VSCODE_PID}"
  else
    # Fallback: use TTY
    local tty_name
    tty_name=$(tty 2>/dev/null | sed 's/\/dev\///' | tr '/' '_' || echo "unknown")
    echo "tty_${tty_name}"
  fi
}

ENV_KEY=$(generate_env_key)

# Initialize map file if it doesn't exist
if [[ ! -f "$MAP_FILE" ]]; then
  echo "{}" > "$MAP_FILE"
fi

# Update mapping (workspace only, no window_id)
if command -v jq &>/dev/null; then
  jq --arg key "$ENV_KEY" \
     --arg ws "$WORKSPACE" \
     --arg ts "$(date +%s)" \
     '.[$key] = {"workspace": $ws, "registered_at": $ts}' \
     "$MAP_FILE" > "${MAP_FILE}.tmp" && mv "${MAP_FILE}.tmp" "$MAP_FILE"
else
  echo "Error: jq is required" >&2
  exit 1
fi

echo "Registered: $ENV_KEY -> workspace $WORKSPACE"
