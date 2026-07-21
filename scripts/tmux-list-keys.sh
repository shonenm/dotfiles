#!/bin/sh
# pretty-print tmux keybindings with ANSI colors
# Usage: tmux-list-keys.sh [all]
#   no args: prefix table only
#   "all": all key tables (includes root, copy-mode, etc.)

if [ "$1" = "all" ]; then
  tmux list-keys -aN
else
  tmux list-keys -N
fi | awk '
/^[[:space:]]/ {
  # root table (no table name column)
  k=$1; $1=""
  sub(/^[[:space:]]+/, "")
  printf "\033[36m%-10s\033[0m \033[33m%-20s\033[0m %s\n", "root", k, $0
  next
}
{
  t=$1; k=$2; $1=""; $2=""
  sub(/^[[:space:]][[:space:]]*/, "")
  printf "\033[36m%-10s\033[0m \033[33m%-20s\033[0m %s\n", t, k, $0
}'
