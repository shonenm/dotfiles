#!/bin/bash
# tmux Git status display with caching
# Output: "<branch> [⇡N⇣M] [<F>f +<A>/-<D>]"
#   - branch: current branch name (or '-' if not in a git repo)
#   - ⇡N⇣M:  ahead/behind counts vs upstream (omitted when both are 0 or no upstream)
#   - Ff +A/-D: number of changed files and added/deleted lines vs HEAD (omitted when no changes)
# Cached per directory to reduce git invocations.

PANE_PATH="${1:-.}"

CACHE_DIR="/tmp/tmux_sysstat"
CACHE_TTL=5  # seconds

CACHE_KEY=$(echo "$PANE_PATH" | md5sum 2>/dev/null | cut -d' ' -f1 || md5 -q -s "$PANE_PATH" 2>/dev/null || echo "default")
CACHE_FILE="$CACHE_DIR/git_status_$CACHE_KEY"

mkdir -p "$CACHE_DIR"

# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/tmux-utils.sh"

if [[ -f "$CACHE_FILE" ]]; then
  now=$(date +%s)
  mtime=$(get_mtime "$CACHE_FILE")
  cache_age=$(( now - mtime ))
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

cd "$PANE_PATH" 2>/dev/null || { printf '%s' '-' | tee "$CACHE_FILE"; exit 0; }

branch=$(git branch --show-current 2>/dev/null)
if [[ -z "$branch" ]]; then
  # detached HEAD: show short SHA if available, otherwise '-'
  sha=$(git rev-parse --short HEAD 2>/dev/null)
  branch="${sha:-"-"}"
fi

out="$branch"

# ahead/behind vs upstream (silent when no upstream configured)
if counts=$(git rev-list --count --left-right '@{upstream}...HEAD' 2>/dev/null); then
  behind=${counts%%$'\t'*}
  ahead=${counts##*$'\t'}
  ab=""
  [[ "$ahead"  -gt 0 ]] && ab+="⇡${ahead}"
  [[ "$behind" -gt 0 ]] && ab+="⇣${behind}"
  [[ -n "$ab" ]] && out+=" ${ab}"
fi

# diff stats vs HEAD (working tree + index combined)
if diff_out=$(git diff --numstat HEAD 2>/dev/null) && [[ -n "$diff_out" ]]; then
  a=0 d=0 f=0
  while IFS=$'\t' read -r added deleted _; do
    [[ "$added" == "-" ]] && continue  # binary file
    (( a += added, d += deleted, f++ ))
  done <<< "$diff_out"
  (( f > 0 )) && out+=$(printf ' %df +%d/-%d' "$f" "$a" "$d")
fi

printf '%s' "$out" > "$CACHE_FILE"
printf '%s' "$out"
