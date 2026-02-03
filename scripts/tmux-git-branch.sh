#!/bin/bash
# tmux Git branch display with caching
# Caches branch name per directory to reduce git invocations
# Output: branch name or '-' if not in a git repo

# Get the pane's current path from argument
PANE_PATH="${1:-.}"

CACHE_DIR="/tmp/tmux_sysstat"
CACHE_TTL=3  # seconds

# Create a safe cache key from the path
CACHE_KEY=$(echo "$PANE_PATH" | md5sum 2>/dev/null | cut -d' ' -f1 || md5 -q -s "$PANE_PATH" 2>/dev/null || echo "default")
CACHE_FILE="$CACHE_DIR/git_branch_$CACHE_KEY"

mkdir -p "$CACHE_DIR"

source "${BASH_SOURCE%/*}/tmux-utils.sh"

# Check cache freshness
if [[ -f "$CACHE_FILE" ]]; then
  now=$(date +%s)
  mtime=$(get_mtime "$CACHE_FILE")
  cache_age=$(( now - mtime ))
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# Get git branch
branch=$(cd "$PANE_PATH" 2>/dev/null && git branch --show-current 2>/dev/null || echo "-")
[[ -z "$branch" ]] && branch="-"

printf '%s' "$branch" > "$CACHE_FILE"
printf '%s' "$branch"
