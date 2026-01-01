#!/bin/bash
# モード管理 - 簡素化版
# モードキャッシュ更新 + mode_indicatorのみ更新
# 他のアイテムは mode_color_changed イベントで自己更新

source "$CONFIG_DIR/plugins/colors.sh"

# モード取得・キャッシュ
MODE=$(aerospace list-modes --current 2>/dev/null || echo "main")
echo "$MODE" > /tmp/sketchybar_mode

# 現在のモード色を取得
MODE_COLOR=$(get_mode_color "$MODE")

# モード別設定
case "$MODE" in
    service)
        ICON="⚙"
        LABEL="SERVICE"
        HELP="esc:exit  a:reload  r:reset  f:float  c:clear-badges  ⌫:close-others"
        ;;
    timer)
        ICON="󰔛"
        LABEL="TIMER"
        HELP="1-5:sleep  w:work b:break l:long  s:start r:reset"
        ;;
    *)
        ICON="󰍹"
        LABEL="MAIN"
        HELP=""
        ;;
esac

# mode_indicator 更新
sketchybar --set mode_indicator \
    icon="$ICON" \
    icon.drawing=on \
    label="$LABEL" \
    label.drawing=on \
    background.color=$MODE_COLOR \
    background.drawing=on

# keybind_help 更新
if [ -n "$HELP" ]; then
    sketchybar --remove keybind_help 2>/dev/null
    sketchybar --add item keybind_help right \
               --set keybind_help \
               icon.drawing=off \
               label="$HELP" \
               label.font="Hack Nerd Font:Bold:10.0" \
               label.color=0xffffffff \
               label.padding_left=10 \
               label.padding_right=10 \
               background.color=0xff1e1f29 \
               background.corner_radius=5 \
               background.height=24 \
               background.border_color=$MODE_COLOR \
               background.border_width=2 \
               background.drawing=on
else
    sketchybar --remove keybind_help 2>/dev/null
    # main モード時はポモドーロポップアップを閉じる
    sketchybar --set pomodoro popup.drawing=off 2>/dev/null
    sketchybar --remove '/pomodoro_item\..*/' 2>/dev/null
fi

# JankyBorders 更新
borders active_color=$MODE_COLOR 2>/dev/null

# layout_anchor popup の色も更新（開いていれば）
sketchybar --set layout_anchor popup.background.border_color=$MODE_COLOR 2>/dev/null

# ポップアップ内のフォーカスワークスペースアイテムも更新
POPUP_STATE=$(sketchybar --query layout_anchor 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)
if [ "$POPUP_STATE" = "on" ]; then
    FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)
    INDEX=0
    for WS in $(aerospace list-workspaces --monitor all --empty no 2>/dev/null | sort); do
        if [ "$WS" = "$FOCUSED_WS" ]; then
            sketchybar --set "layout_item.$INDEX" background.color=$MODE_COLOR 2>/dev/null
        fi
        INDEX=$((INDEX + 1))
    done
fi

# 他のアイテムに色変更を通知
sketchybar --trigger mode_color_changed
