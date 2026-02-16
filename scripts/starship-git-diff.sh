#!/bin/bash
# starship custom module: git diff stats (files + lines)
# Output: "3f +10/-5" (3 files, 10 added, 5 deleted)
# Note: avoid pipeline to prevent orphan processes on timeout

output=$(git diff --numstat HEAD 2>/dev/null) || exit 0
[ -z "$output" ] && exit 0

a=0 d=0 f=0
while IFS=$'\t' read -r added deleted _; do
  [[ "$added" == "-" ]] && continue  # binary file
  (( a += added, d += deleted, f++ ))
done <<< "$output"

(( f > 0 )) && printf '%df +%d/-%d' "$f" "$a" "$d"
