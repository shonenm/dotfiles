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
# 回数を最小にする: 退避先は pane ごとに別ウィンドウへ分け、復元は退避の逆順に、空いた
# 領域を引き取った兄弟へ join-pane する。これで配置がそのまま戻り、select-layout での再配分
# (= もう 1 回のリサイズ)が要らない。ずれた時だけ @pzoom_order で列順を直して当て直す。

pzoom_lock() { tmux set-option -w -t "$1" @pzoom_lock 1 2>/dev/null; }
pzoom_unlock() { tmux set-option -w -t "$1" -u @pzoom_lock 2>/dev/null; }
pzoom_locked() { [ -n "$(tmux show-options -w -t "$1" -qv @pzoom_lock 2>/dev/null)" ]; }

# tmux 3.8+ の window_layout は JSON で、active pane ("a") と最終使用順 ("l") も含む。
# フォーカスが違うだけで不一致と判定しないよう、配置の比較ではこれらを除く。
pzoom_shape() { sed -E 's/"a":true,//g; s/"l":[0-9]+,//g'; }

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

pzoom_geo() { tmux list-panes -t "$1" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}' 2>/dev/null; }

# 次に退避する pane を選ぶ。break-pane で空いた領域は兄弟の 1 つが引き取る(tmux 3.8 以降は
# 直後、それより前は直前。端なら反対側)。引き取り側に同じ辺の長さで接する pane を持つもの
# (= 引き取り手が葉)を優先し、次に反対側に接するもの、最後に残りを選ぶ。サイドバー直右の
# 全高 pane は最後まで残す: そこをサイドバーが引き取ると、apply がサイドバー幅を戻した時に
# 記録した寸法が崩れるため、最後の 1 つにして keep pane へ戻せるようにする。
pzoom_pick() {   # stdin=pzoom_geo, $1=keep $2=sidebar
    local next=0
    case "$(tmux display-message -p '#{version}' 2>/dev/null)" in
        [4-9]*|3.[89]*|3.[1-9][0-9]*) next=1 ;;
    esac
    awk -v keep="$1" -v sb="$2" -v next_side="$next" '
        { id[NR]=$1; l[NR]=$2; t[NR]=$3; w[NR]=$4; h[NR]=$5; if ($1 == sb) { sbr = $2 + $4 + 1; sbh = $5 } }
        function rank(i,   j, r, prev, nxt) {
            r = 3
            for (j = 1; j <= NR; j++) {
                if (i == j || id[j] == sb) continue
                prev = (t[i] == t[j] && h[i] == h[j] && l[i] == l[j] + w[j] + 1) ||
                       (l[i] == l[j] && w[i] == w[j] && t[i] == t[j] + h[j] + 1)
                nxt = (t[i] == t[j] && h[i] == h[j] && l[j] == l[i] + w[i] + 1) ||
                      (l[i] == l[j] && w[i] == w[j] && t[j] == t[i] + h[i] + 1)
                if (next_side ? nxt : prev) return 0
                if (next_side ? prev : nxt) r = 1
            }
            return r
        }
        END {
            best = ""; br = 99
            for (i = 1; i <= NR; i++) {
                if (id[i] == keep || id[i] == sb) continue
                r = rank(i) + (sbr != "" && l[i] == sbr && h[i] == sbh ? 10 : 0)
                if (r < br) { best = id[i]; br = r }
            }
            print best
        }'
}

# 退避 pane を「戻し方」付きで記録する: pane_id:dir(h|v):len:before(b|空):sibling。
# keep pane との位置関係では入れ子の layout を表せず、前の退避で位置もずれる。
# break-pane で空いた領域を引き取った pane が layout 上の兄弟なので、それを実測して
# 記録し、復元は逆順に兄弟へ join-pane する(close の逆操作 = 元の寸法に戻る)。
# 兄弟が subtree で引き取り手が複数なら sibling を空にし、復元側の select-layout に任せる。
# len は退避時点の寸法(先に退避した兄弟の分を引き取って広がった後)を使う。
pzoom_stash_others() {   # $1=win $2=keep_pane $3=sidebar
    local sess p before_geo after_geo grown dir len before hidden="" q
    local pl pt pw ph ql qt
    sess=$(tmux display-message -t "$1" -p '#{session_name}' 2>/dev/null) || return 1

    while :; do
        before_geo=$(pzoom_geo "$1")
        p=$(pzoom_pick "$2" "$3" <<< "$before_geo")
        [ -n "$p" ] || break
        # 退避 pane ごとに window を分ける。1 つの window に集めると、後続の退避が
        # 先に退避した pane を分割してリサイズし、その TUI が再描画してしまう。
        # window は最後の pane が戻った時点で消えるので、後片付けも要らない。
        tmux break-pane -d -s "$p" -t "${sess}:" -n '_pzoom' 2>/dev/null || break
        after_geo=$(pzoom_geo "$1")
        grown=$(grep -vxF -f <(printf '%s\n' "$before_geo") <<< "$after_geo")
        dir=""; len=""; before=""; q=""
        if [ -n "$grown" ] && [ "$(wc -l <<< "$grown")" -eq 1 ]; then
            q=${grown%% *}
            if [ "$q" = "$3" ]; then
                # サイドバーが引き取った = 最後の 1 つ。apply 後は keep が全域を持つので
                # keep の手前へ戻せば元の配置になる。
                read -r _ _ _ pw _ <<< "$(grep "^$p " <<< "$before_geo")"
                hidden="${hidden}${hidden:+ }${p}:h:${pw}:b:$2"
                continue
            fi
            read -r _ pl pt pw ph <<< "$(grep "^$p " <<< "$before_geo")"
            read -r _ ql qt _ _ <<< "$(grep "^$q " <<< "$before_geo")"
            if [ "${grown##* }" = "$(awk -v q="$q" '$1 == q { print $5 }' <<< "$before_geo")" ]; then
                dir=h; len=$pw; [ "$pl" -lt "$ql" ] && before=b
            else
                dir=v; len=$ph; [ "$pt" -lt "$qt" ] && before=b
            fi
        fi
        hidden="${hidden}${hidden:+ }${p}:${dir}:${len}:${before}:${q}"
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
    local layout hidden entry p zoom_pane order dst dir len before sib rev
    local -a args
    layout=$(tmux show-options -w -t "$1" -qv @pzoom_layout 2>/dev/null)
    [ -n "$layout" ] || return 1
    pzoom_locked "$1" && return 0

    pzoom_lock "$1"
    hidden=$(tmux show-options -w -t "$1" -qv @pzoom_hidden 2>/dev/null)
    order=$(tmux show-options -w -t "$1" -qv @pzoom_order 2>/dev/null)
    zoom_pane=$(tmux show-options -w -t "$1" -qv @pzoom_pane 2>/dev/null)

    dst="$1"
    if [ -n "$zoom_pane" ] && tmux list-panes -t "$1" -F '#{pane_id}' 2>/dev/null | grep -qxF "$zoom_pane"; then
        dst="$zoom_pane"
    fi
    # 退避の逆順に、記録した兄弟へ join する。close の逆操作なので元の寸法に戻り、
    # select-layout での再配分が要らない = 退避 pane の再描画が 1 回で済む。
    rev=""
    for entry in $hidden; do rev="$entry${rev:+ }$rev"; done
    for entry in $rev; do
        IFS=: read -r p dir len before sib <<< "$entry"
        if [ -n "$sib" ] && [ -n "$dir" ]; then
            args=(join-pane -d "-$dir" -s "$p" -t "$sib")
            [ -n "$len" ] && args+=(-l "$len")
            [ "$before" = b ] && args+=(-b)
            tmux "${args[@]}" 2>/dev/null && continue
        fi
        tmux join-pane -d -s "$p" -t "$dst" 2>/dev/null || true
    done

    # 寸法通りに戻れば layout は既に一致する。ずれた時だけ列順を直して当て直す
    # (順が違うとサイズが別 pane に載るため)。
    if [ "$(tmux display-message -t "$1" -p '#{window_layout}' 2>/dev/null | pzoom_shape)" != "$(pzoom_shape <<< "$layout")" ]; then
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
    # 退避 window は最後の pane を join すると自動で消える。
    # 同じ session の別 window が zoom 中の場合もあるため、名前で一括削除しない。
    pzoom_unlock "$1"
}
