#!/bin/bash
# starship custom module: git diff stats (files + lines)
# Output: "3f +10/-5" (3 files, 10 added, 5 deleted)
git diff --numstat HEAD 2>/dev/null | awk '
BEGIN { a=0; d=0; f=0 }
{ a+=$1; d+=$2; f++ }
END { if (f>0) printf "%df +%d/-%d", f, a, d }
'
