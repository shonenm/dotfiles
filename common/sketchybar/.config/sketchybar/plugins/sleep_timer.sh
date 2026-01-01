#!/bin/bash
# ディスプレイスリープ設定を表示

# ディスプレイスリープ設定を分で取得
SLEEP_MIN=$(pmset -g 2>/dev/null | grep "displaysleep" | awk '{print $2}')

# 無効(0)または取得失敗時
if [[ -z "$SLEEP_MIN" || "$SLEEP_MIN" == "0" ]]; then
    sketchybar --set "$NAME" label="󰒲 --" label.color=0xff6c757d
else
    sketchybar --set "$NAME" label="󰒲 ${SLEEP_MIN}m" label.color=0xffffffff
fi
