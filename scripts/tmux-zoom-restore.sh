#!/bin/bash
# after-select-pane hook: 擬似 zoom の解除と、@zoom-sticky pane の再 zoom。
# native zoom は pane 移動で tmux が自動解除するが、擬似 zoom は layout 変更なので
# 自前で戻す(移動先の 1 行 pane に取り残されるのを防ぐ)。

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/tmux-zoom-lib.sh"

win=$(tmux display-message -p '#{window_id}')
pane=$(tmux display-message -p '#{pane_id}')

# apply/restore の break-pane/join-pane 中に本 hook が再入すると layout が壊れる
pzoom_locked "$win" && exit 0

pzoomed=$(tmux show-options -w -t "$win" -qv @pzoom_pane 2>/dev/null)
sticky=$(tmux show-options -pqv @zoom-sticky 2>/dev/null)
zoomed=$(tmux display-message -p '#{window_zoomed_flag}')

if [ "$pzoomed" = "$pane" ]; then
    exit 0   # この pane で擬似 zoom 中: 保存 layout を壊さないよう何もしない
fi
pzoom_restore "$win"

if [ -n "$sticky" ]; then
    pzoom_apply "$win" "$pane" || { [ "$zoomed" = "0" ] && tmux resize-pane -Z; }
fi
