#!/bin/bash
# starship custom module: jj working-copy change-id + bookmarks
# Output: "qpvu main" (change-id short prefix, optional bookmark names)
# --ignore-working-copy: snapshot/lock を取らない (prompt 毎の read-only 表示用)

command -v jj >/dev/null 2>&1 || exit 0

jj log --ignore-working-copy --no-graph --color never -r @ \
  -T 'change_id.shortest(4) ++ if(bookmarks, " " ++ bookmarks.join(" "))' 2>/dev/null
