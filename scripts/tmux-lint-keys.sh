#!/bin/sh
# tmux-lint-keys.sh — detect duplicate key bindings in custom-keys.conf
#
# Usage:
#   scripts/tmux-lint-keys.sh              # check dotfiles source
#   scripts/tmux-lint-keys.sh <file>       # check a specific file

set -e

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
CONF="${1:-$DOTFILES/common/tmux/.config/tmux/custom-keys.conf}"

if [ ! -f "$CONF" ]; then
  echo "File not found: $CONF" >&2
  exit 1
fi

# Extract (table, key) pairs from bind/bind-key lines (skip unbinds).
# Strategy: strip comments and quoted -N descriptions first, then parse.
sed -E \
  -e 's/#.*//' \
  -e 's/-N "[^"]*"//g' \
  -e "s/-N '[^']*'//g" \
  "$CONF" | awk '
/^(bind-key|bind)[[:space:]]/ {
  table = "prefix"
  for (i = 2; i <= NF; i++) {
    if ($i == "-n")         { table = "root"; continue }
    if ($i == "-r")         { continue }
    if ($i == "-T" && (i+1) <= NF) { table = $(i+1); i++; continue }
    if ($i ~ /^-/)          { continue }  # skip unknown flags
    key = $(i)
    break
  }
  if (key != "") printf "%s:%s\n", table, key
}' | sort | uniq -d > /tmp/tmux-dup-keys.txt

if [ -s /tmp/tmux-dup-keys.txt ]; then
  echo "=== DUPLICATE KEYS ==="
  cat /tmp/tmux-dup-keys.txt
  echo ""
  echo "FAIL: $(wc -l < /tmp/tmux-dup-keys.txt | tr -d ' ') duplicate(s)."
  exit 1
else
  count=$(sed -E -e 's/#.*//' -e 's/-N "[^"]*"//g' -e "s/-N '[^']*'//g" "$CONF" | grep -cE '^(bind-key|bind|unbind)[[:space:]]')
  echo "OK: $count bindings, no duplicates."
fi
