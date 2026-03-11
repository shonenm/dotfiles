#!/usr/bin/env bash
# tmux-popup-manager: entry point
# Reads @popup-* options, registers command-aliases, bind-keys, and which-key menu.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Register global popups
"$CURRENT_DIR/scripts/loader.sh" global

# Register hook for project-local popups
tmux set-hook -ga session-created \
    "run-shell '\"$CURRENT_DIR/scripts/loader.sh\" project \"#{hook_session_name}\"'"
