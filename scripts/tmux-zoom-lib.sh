#!/bin/bash
# 擬似 zoom: agent サイドバーを残したまま、残りの表示領域で pane を最大化する。
# tmux の native zoom は window 全体を占有しサイドバーごと隠すため、layout を保存し、
# 対象以外の pane は break-pane で _pzoom ウィンドウへ退避する。
#
# 以前は resize-pane で他 pane を 1 列/1 行に潰していたが、cursor-agent / live-pr 等の
# TUI が SIGWINCH で再描画を連打し、allow-passthrough 経由で外側端末全体が
# スクロールし続けて入力不能になる。
#
# 退避 pane が受けるリサイズは 1 回でも高コスト(長い履歴を全部折り返し直す)なので、
# 回数を最小にする: 退避先は pane ごとに別ウィンドウへ分け、復元は退避前の方向・寸法・
# 前後関係のまま join-pane する。これで配置がそのまま戻り、select-layout での再配分
# (= もう 1 回のリサイズ)が要らない。ずれた時だけ @pzoom_order で列順を直して当て直す。

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

# 退避 pane を「戻し方」付きで記録する: pane_id:dir(h|v):len:before(b|空)。
# dir/len/before は退避前の位置関係から決める。復元中の pane 寸法を見て決めると、
# 先に戻した pane が対象を分割した後で判定が狂う。
pzoom_stash_others() {   # $1=win $2=keep_pane $3=sidebar
    local sess p left top keep_left keep_top dir len before hidden="" panes
    sess=$(tmux display-message -t "$1" -p '#{session_name}' 2>/dev/null) || return 1
    keep_left=$(tmux display-message -t "$2" -p '#{pane_left}' 2>/dev/null)
    keep_top=$(tmux display-message -t "$2" -p '#{pane_top}' 2>/dev/null)

    panes=$(tmux list-panes -t "$1" -F '#{pane_id}')
    for p in $panes; do
        [ "$p" = "$2" ] && continue
        [ "$p" = "$3" ] && continue
        left=$(tmux display-message -t "$p" -p '#{pane_left}' 2>/dev/null)
        top=$(tmux display-message -t "$p" -p '#{pane_top}' 2>/dev/null)
        if [ "$left" != "$keep_left" ]; then
            dir=h
            len=$(tmux display-message -t "$p" -p '#{pane_width}' 2>/dev/null)
            before=""; [ "$left" -lt "$keep_left" ] 2>/dev/null && before=b
        else
            dir=v
            len=$(tmux display-message -t "$p" -p '#{pane_height}' 2>/dev/null)
            before=""; [ "$top" -lt "$keep_top" ] 2>/dev/null && before=b
        fi
        # 退避 pane ごとに window を分ける。1 つの window に集めると、後続の退避が
        # 先に退避した pane を分割してリサイズし、その TUI が再描画してしまう。
        # window は最後の pane が戻った時点で消えるので、後片付けも要らない。
        tmux break-pane -d -s "$p" -t "${sess}:" -n '_pzoom' 2>/dev/null || continue
        hidden="${hidden}${hidden:+ }${p}:${dir}:${len}:${before}"
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
    local layout hidden entry pass p sess zoom_pane order dst dir len before wid
    local -a args
    layout=$(tmux show-options -w -t "$1" -qv @pzoom_layout 2>/dev/null)
    [ -n "$layout" ] || return 1
    pzoom_locked "$1" && return 0

    pzoom_lock "$1"
    hidden=$(tmux show-options -w -t "$1" -qv @pzoom_hidden 2>/dev/null)
    order=$(tmux show-options -w -t "$1" -qv @pzoom_order 2>/dev/null)
    sess=$(tmux display-message -t "$1" -p '#{session_name}' 2>/dev/null)
    zoom_pane=$(tmux show-options -w -t "$1" -qv @pzoom_pane 2>/dev/null)

    dst="$1"
    if [ -n "$zoom_pane" ] && tmux list-panes -t "$1" -F '#{pane_id}' 2>/dev/null | grep -qxF "$zoom_pane"; then
        dst="$zoom_pane"
    fi
    # 横並びだった pane を先に戻す。対象を上下分割してから左右の pane を戻すと、
    # 分割後の狭い cell に入って配置が崩れる。
    for pass in h v; do
        for entry in $hidden; do
            IFS=: read -r p dir len before <<< "$entry"
            [ "$dir" = "$pass" ] || continue
            # 退避時の寸法と位置関係で戻すのでそのまま元の配置になり、select-layout
            # での再配分が要らない = 退避 pane の再描画が 1 回で済む。
            args=(join-pane -d "-$dir" -s "$p" -t "$dst")
            [ -n "$len" ] && args+=(-l "$len")
            [ "$before" = b ] && args+=(-b)
            tmux "${args[@]}" 2>/dev/null && continue
            tmux join-pane -d -s "$p" -t "$dst" 2>/dev/null || true
        done
    done

    # 寸法通りに戻れば layout は既に一致する。ずれた時だけ列順を直して当て直す
    # (順が違うとサイズが別 pane に載るため)。
    if [ "$(tmux display-message -t "$1" -p '#{window_layout}' 2>/dev/null)" != "$layout" ]; then
        [ -n "$order" ] && pzoom_reorder "$1" "$order"
        if ! tmux select-layout -t "$1" "$layout" 2>/dev/null; then
            pzoom_unlock "$1"
            return 1
        fi
    fi
    tmux set-option -w -t "$1" -u @pzoom_layout 2>/dev/null
    tmux set-option -w -t "$1" -u @pzoom_pane 2>/dev/null
    tmux set-option -w -t "$1" -u @pzoom_hidden 2>/dev/null
    tmux set-option -w -t "$1" -u @pzoom_order 2>/dev/null
    if [ -n "$zoom_pane" ]; then
        tmux select-pane -t "$zoom_pane" 2>/dev/null || true
    fi
    # 戻し損ねた退避 window が残っていたら畳む(通常は最後の pane が戻った時点で消える)
    if [ -n "$sess" ]; then
        for wid in $(tmux list-windows -t "$sess" -F '#{window_id} #{window_name}' 2>/dev/null | awk '$2 == "_pzoom" { print $1 }'); do
            tmux kill-window -t "$wid" 2>/dev/null || true
        done
    fi
    pzoom_unlock "$1"
}
