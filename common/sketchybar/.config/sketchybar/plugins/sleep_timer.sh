#!/bin/bash
# ディスプレイスリープ設定を表示

source "$CONFIG_DIR/plugins/colors.sh"

# ディスプレイスリープ設定を分で取得
SLEEP_MIN=$(pmset -g 2>/dev/null | grep "displaysleep" | awk '{print $2}')

# モード色
MODE_COLOR=$(get_mode_color)

# 無効(0)または取得失敗時
if [[ -z "$SLEEP_MIN" || "$SLEEP_MIN" == "0" ]]; then
    sketchybar --set "$NAME" label="󰒲 --" label.color=0xff6c757d background.border_color="$MODE_COLOR"
else
    sketchybar --set "$NAME" label="󰒲 ${SLEEP_MIN}m" label.color=0xffffffff background.border_color="$MODE_COLOR"
fi
