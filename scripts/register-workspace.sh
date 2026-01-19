#!/bin/bash
# Register current environment to aerospace workspace for Claude notification
# Usage: register-workspace.sh <workspace_number>

set -euo pipefail

WORKSPACE="${1:-}"
MAP_FILE="/tmp/claude_workspace_map.json"

if [[ -z "$WORKSPACE" ]]; then
  echo "Usage: register-workspace.sh <workspace_number>" >&2
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

# Get window_id from workspace (first terminal/code window in that workspace)
get_window_id_from_workspace() {
  local ws="$1"

  if ! command -v aerospace &>/dev/null; then
    echo ""
    return
  fi

  # Get first Code or terminal window in the workspace
  aerospace list-windows --workspace "$ws" --json 2>/dev/null | \
    jq -r '
      [.[] | select(.["app-name"] | test("Code|Ghostty|Terminal|iTerm|Alacritty|Warp|WezTerm|kitty"; "i"))] |
      .[0]["window-id"] // empty
    ' 2>/dev/null
}

WINDOW_ID=$(get_window_id_from_workspace "$WORKSPACE")

if [[ -z "$WINDOW_ID" ]]; then
  echo "Warning: No Code/Terminal window found in workspace $WORKSPACE" >&2
  echo "Registering without window_id (will use workspace-based lookup)" >&2
fi

# Initialize map file if it doesn't exist
if [[ ! -f "$MAP_FILE" ]]; then
  echo "{}" > "$MAP_FILE"
fi

# Update mapping
if command -v jq &>/dev/null; then
  jq --arg key "$ENV_KEY" \
     --arg ws "$WORKSPACE" \
     --arg wid "${WINDOW_ID:-}" \
     --arg ts "$(date +%s)" \
     '.[$key] = {"workspace": $ws, "window_id": $wid, "registered_at": $ts}' \
     "$MAP_FILE" > "${MAP_FILE}.tmp" && mv "${MAP_FILE}.tmp" "$MAP_FILE"
else
  echo "Error: jq is required" >&2
  exit 1
fi

echo "Registered: $ENV_KEY → workspace $WORKSPACE (window_id: ${WINDOW_ID:-none})"
