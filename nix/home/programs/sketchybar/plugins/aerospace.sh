#!/bin/bash

# shellcheck source=/dev/null
source "$CONFIG_DIR/plugins/colors.sh"

# 全モニターの表示中ワークスペースを取得（フォーカスの有無に関係なく）
VISIBLE_WORKSPACES=$(aerospace list-workspaces --monitor all --visible 2>/dev/null)

HIGHLIGHT=false
for ws in $VISIBLE_WORKSPACES; do
    if [ "$1" = "$ws" ]; then
        HIGHLIGHT=true
        break
    fi
done

if [ "$HIGHLIGHT" = "true" ]; then
    sketchybar --set "$NAME" \
        background.color="$(get_mode_color)" \
        background.drawing=on
else
    sketchybar --set "$NAME" \
        background.color=0x00000000 \
        background.drawing=off
fi
