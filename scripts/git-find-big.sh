#!/bin/bash
# Find the largest files in a git repository's history
# Usage: git-find-big [count]
#   count: number of files to show (default: 10)

set -euo pipefail

count="${1:-10}"

git rev-list --objects --all \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | sed -n 's/^blob //p' \
  | sort -rnk2 \
  | head -n "$count" \
  | while read -r hash size path; do
    printf "%s\t%s\t%s\n" "$(numfmt --to=iec-i --suffix=B --padding=7 "$size" 2>/dev/null || echo "${size}B")" "$hash" "$path"
  done
