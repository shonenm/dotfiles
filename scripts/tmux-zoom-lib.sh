#!/bin/bash
# 擬似 zoom: agent サイドバーを残したまま、残りの表示領域で pane を最大化する。
# tmux の native zoom は window 全体を占有しサイドバーごと隠すため、
# layout を保存し、対象以外の pane は break-pane で session:_pzoom へ退避する。
#
# 以前は resize-pane で他 pane を 1 列/1 行に潰していたが、cursor-agent / live-pr 等の
# TUI が SIGWINCH で再描画を連打し、allow-passthrough 経由で外側端末全体が
# スクロールし続けて入力不能になる。退避なら sibling TUI はサイズを保ったまま隠れる。
#
# join-pane 後は pane の列順が変わることがあり、select-layout だけだとサイズが
# 別 pane に載って配置が入れ替わる。@pzoom_order で列順を復元してから layout を当てる。

pzoom_lock() { tmux set-option -w -t "$1" @pzoom_lock 1 2>/dev/null; }
pzoom_unlock() { tmux set-option -w -t "$1" -u @pzoom_lock 2>/dev/null; }
pzoom_locked() { [ -n "$(tmux show-options -w -t "$1" -qv @pzoom_lock 2>/dev/null)" ]; }

pzoom_sidebar() {   # $1=win $2=pane
    local sb
    sb=$(tmux show-options -w -t "$1" -qv @agent_sidebar_pane 2>/dev/null)
    if [ -z "$sb" ] || [ "$sb" = "$2" ]; then return 1; fi
    tmux list-panes -t "$1" -F '#{pane_id}' 2>/dev/null | grep -qxF "$sb" || return 1
    printf '%s' "$sb"
}

# list-panes 順を @pzoom_order に合わせる
pzoom_reorder() {   # $1=win $2=order(space-separated pane ids)
    local want cur i j
    # shellcheck disable=SC2206
    local order=($2)
    for i in "${!order[@]}"; do
        want="${order[$i]}"
        # shellcheck disable=SC2207
        cur=($(tmux list-panes -t "$1" -F '#{pane_id}'))
        [ "${cur[$i]}" = "$want" ] && continue
        for j in "${!cur[@]}"; do
            if [ "${cur[$j]}" = "$want" ]; then
                tmux swap-pane -d -s "$want" -t "${cur[$i]}" 2>/dev/null || true
                break
            fi
        done
    done
}

pzoom_stash_others() {   # $1=win $2=keep_pane $3=sidebar
    local sess p hidden="" hold=0
    sess=$(tmux display-message -t "$1" -p '#{session_name}' 2>/dev/null) || return 1

    if tmux list-windows -t "$sess" -F '#{window_name}' 2>/dev/null | grep -qxF '_pzoom'; then
        if [ -z "$(tmux list-panes -t "${sess}:_pzoom" -F '#{pane_id}' 2>/dev/null)" ]; then
            tmux kill-window -t "${sess}:_pzoom" 2>/dev/null || true
        else
            hold=1
        fi
    fi

    local panes
    panes=$(tmux list-panes -t "$1" -F '#{pane_id}')
    for p in $panes; do
        [ "$p" = "$2" ] && continue
        [ "$p" = "$3" ] && continue
        if [ "$hold" = "0" ]; then
            tmux break-pane -d -s "$p" -t "${sess}:" -n '_pzoom' 2>/dev/null || continue
            hold=1
        else
            tmux break-pane -d -s "$p" -t "${sess}:_pzoom" 2>/dev/null || continue
        fi
        hidden="${hidden}${hidden:+ }$p"
    done
    printf '%s' "$hidden"
}

pzoom_apply() {   # $1=win $2=pane
    local sb sb_w win_w hidden order
    sb=$(pzoom_sidebar "$1" "$2") || return 1
    [ -n "$(tmux show-options -w -t "$1" -qv @pzoom_layout 2>/dev/null)" ] && return 0
    sb_w=$(tmux display-message -t "$sb" -p '#{pane_width}' 2>/dev/null)
    win_w=$(tmux display-message -t "$1" -p '#{window_width}' 2>/dev/null)
    [ -n "$sb_w" ] && [ -n "$win_w" ] || return 1

    pzoom_lock "$1"
    order=$(tmux list-panes -t "$1" -F '#{pane_id}' | paste -sd' ' -)
    tmux set-option -w -t "$1" @pzoom_layout "$(tmux display-message -t "$1" -p '#{window_layout}')"
    tmux set-option -w -t "$1" @pzoom_order "$order"
    tmux set-option -w -t "$1" @pzoom_pane "$2"

    hidden=$(pzoom_stash_others "$1" "$2" "$sb")
    tmux set-option -w -t "$1" @pzoom_hidden "$hidden"

    tmux resize-pane -t "$sb" -x "$sb_w" 2>/dev/null
    tmux resize-pane -t "$2" -x "$(( win_w - sb_w - 1 ))" 2>/dev/null
    tmux resize-pane -t "$sb" -x "$sb_w" 2>/dev/null
    tmux select-pane -t "$2" 2>/dev/null
    pzoom_unlock "$1"
}

pzoom_restore() {   # $1=win
    local layout hidden p sess zoom_pane order
    layout=$(tmux show-options -w -t "$1" -qv @pzoom_layout 2>/dev/null)
    [ -n "$layout" ] || return 1
    pzoom_locked "$1" && return 0

    pzoom_lock "$1"
    hidden=$(tmux show-options -w -t "$1" -qv @pzoom_hidden 2>/dev/null)
    order=$(tmux show-options -w -t "$1" -qv @pzoom_order 2>/dev/null)
    sess=$(tmux display-message -t "$1" -p '#{session_name}' 2>/dev/null)
    zoom_pane=$(tmux show-options -w -t "$1" -qv @pzoom_pane 2>/dev/null)

    for p in $hidden; do
        if [ -n "$zoom_pane" ] && tmux list-panes -t "$1" -F '#{pane_id}' 2>/dev/null | grep -qxF "$zoom_pane"; then
            tmux join-pane -d -s "$p" -t "$zoom_pane" 2>/dev/null || tmux join-pane -d -s "$p" -t "$1" 2>/dev/null || true
        else
            tmux join-pane -d -s "$p" -t "$1" 2>/dev/null || true
        fi
    done

    # 列順を元に戻してから layout を当てる(順が違うとサイズが別 pane に載る)
    [ -n "$order" ] && pzoom_reorder "$1" "$order"

    if ! tmux select-layout -t "$1" "$layout" 2>/dev/null; then
        pzoom_unlock "$1"
        return 1
    fi
    tmux set-option -w -t "$1" -u @pzoom_layout 2>/dev/null
    tmux set-option -w -t "$1" -u @pzoom_pane 2>/dev/null
    tmux set-option -w -t "$1" -u @pzoom_hidden 2>/dev/null
    tmux set-option -w -t "$1" -u @pzoom_order 2>/dev/null
    if [ -n "$zoom_pane" ]; then
        tmux select-pane -t "$zoom_pane" 2>/dev/null || true
    fi
    if [ -n "$sess" ]; then
        tmux kill-window -t "${sess}:_pzoom" 2>/dev/null || true
    fi
    pzoom_unlock "$1"
}
