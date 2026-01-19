#!/bin/bash
# Process notifications from local Docker containers
# Detects /tmp/claude_status/*.json (non-workspace_*) and executes Mac-side processing
# Launched by launchd WatchPaths

set -euo pipefail

STATUS_DIR="/tmp/claude_status"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create directory if it doesn't exist
mkdir -p "$STATUS_DIR"

# Process non-workspace_* .json files
for file in "$STATUS_DIR"/*.json; do
  [[ -f "$file" ]] || continue

  filename=$(basename "$file")

  # Skip workspace_* files (already processed)
  [[ "$filename" == workspace_* ]] && continue

  # Get info from JSON
  project=$(jq -r '.project // empty' "$file" 2>/dev/null)
  status=$(jq -r '.status // empty' "$file" 2>/dev/null)
  workspace=$(jq -r '.workspace // empty' "$file" 2>/dev/null)
  tmux_session=$(jq -r '.tmux_session // empty' "$file" 2>/dev/null)
  tmux_window=$(jq -r '.tmux_window_index // empty' "$file" 2>/dev/null)

  [[ -z "$project" || -z "$status" ]] && continue

  # Call claude-status.sh with new signature
  "$SCRIPT_DIR/claude-status.sh" set "$project" "$status" "$workspace" "$tmux_session" "$tmux_window" 2>/dev/null || true

  # Delete processed file
  rm -f "$file"
done
