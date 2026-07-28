#!/bin/bash
# Toggle pane zoom with optional pane-sticky persistence.
# Usage: tmux-zoom-toggle.sh [normal|sticky|native]
#   normal: plain zoom. Leaving the pane lets tmux auto-unzoom; returning does not restore.
#   sticky: marks the pane with @zoom-sticky so the after-select-pane hook re-zooms on return.
#   native: 擬似 zoom を使わず常に tmux 標準の zoom (サイドバーも隠れる)。prefix C-z。
# Pressing z or Z on a sticky pane clears the flag and unzooms.
# agent サイドバーがある window では native zoom の代わりに擬似 zoom を使い、
# サイドバーを表示したまま残りの領域で最大化する (tmux-zoom-lib.sh)。

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/tmux-zoom-lib.sh"

mode="${1:-normal}"
win=$(tmux display-message -p '#{window_id}')
pane=$(tmux display-message -p '#{pane_id}')
sticky=$(tmux show-options -pqv @zoom-sticky 2>/dev/null)
zoomed=$(tmux display-message -p '#{window_zoomed_flag}')
pzoomed=$(tmux show-options -w -t "$win" -qv @pzoom_layout 2>/dev/null)

if [ -n "$sticky" ]; then
    tmux set-option -p -u @zoom-sticky
    [ "$zoomed" = "1" ] && tmux resize-pane -Z
    pzoom_restore "$win"
elif [ "$zoomed" = "1" ]; then
    tmux resize-pane -Z
elif [ -n "$pzoomed" ]; then
    pzoom_restore "$win"
else
    [ "$mode" = "sticky" ] && tmux set-option -p @zoom-sticky 1
    if [ "$mode" = "native" ] || ! pzoom_apply "$win" "$pane"; then
        tmux resize-pane -Z
    fi
fi
