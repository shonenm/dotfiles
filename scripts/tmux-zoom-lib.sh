#!/bin/bash
# 擬似 zoom: agent サイドバーを残したまま、残りの表示領域で pane を最大化する。
# tmux の native zoom は window 全体を占有しサイドバーごと隠すため、
# layout を保存して resize-pane で代替する。他の pane は最小(1行)まで縮む。
# ponytail: 他 pane は 1 行残る (tmux に pane を隠す手段が無い)。完全に消したくなったら break-pane 退避へ。

# サイドバー pane id を返す(この window に無い / 対象 pane 自身なら 1)
pzoom_sidebar() {   # $1=win $2=pane
    local sb
    sb=$(tmux show-options -w -t "$1" -qv @agent_sidebar_pane 2>/dev/null)
    if [ -z "$sb" ] || [ "$sb" = "$2" ]; then return 1; fi
    tmux list-panes -t "$1" -F '#{pane_id}' 2>/dev/null | grep -qxF "$sb" || return 1
    printf '%s' "$sb"
}

pzoom_apply() {   # $1=win $2=pane
    local sb sb_w win_w win_h
    sb=$(pzoom_sidebar "$1" "$2") || return 1
    # 既に擬似 zoom 中なら二重適用しない(zoom 後の layout を保存して復元不能になるのを防ぐ)
    [ -n "$(tmux show-options -w -t "$1" -qv @pzoom_layout 2>/dev/null)" ] && return 0
    sb_w=$(tmux display-message -t "$sb" -p '#{pane_width}' 2>/dev/null)
    win_w=$(tmux display-message -t "$1" -p '#{window_width}' 2>/dev/null)
    win_h=$(tmux display-message -t "$1" -p '#{window_height}' 2>/dev/null)
    [ -n "$sb_w" ] && [ -n "$win_w" ] && [ -n "$win_h" ] || return 1
    tmux set-option -w -t "$1" @pzoom_layout "$(tmux display-message -t "$1" -p '#{window_layout}')"
    tmux set-option -w -t "$1" @pzoom_pane "$2"
    # サイドバー分を除いた領域いっぱいに広げる(-x を無制限にするとサイドバーまで潰れる)
    tmux resize-pane -t "$2" -x "$(( win_w - sb_w - 1 ))" -y "$win_h" 2>/dev/null
}

pzoom_restore() {   # $1=win
    local layout
    layout=$(tmux show-options -w -t "$1" -qv @pzoom_layout 2>/dev/null)
    [ -n "$layout" ] || return 1
    # レイアウト復元が完了するまで zoom marker を残す。layout-change hook からも
    # 復元中の window を busy として見せ、競合する sidebar resize を止める。
    tmux select-layout -t "$1" "$layout" 2>/dev/null || return 1
    tmux set-option -w -t "$1" -u @pzoom_layout 2>/dev/null
    tmux set-option -w -t "$1" -u @pzoom_pane 2>/dev/null
}
