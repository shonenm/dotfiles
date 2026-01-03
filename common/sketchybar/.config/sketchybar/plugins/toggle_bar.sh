#!/bin/bash

CONFIG_FILE="$HOME/.config/aerospace/aerospace.toml"
SAVED_PADDING_FILE="/tmp/sketchybar_saved_padding"
CURRENT=$(sketchybar --query bar | jq -r ".hidden")

# aerospace.tomlから現在のouter.bottom値を取得
get_current_padding() {
    sed -n 's/^[[:space:]]*outer\.bottom = *\([0-9]*\).*/\1/p' "$CONFIG_FILE"
}

if [ "$CURRENT" = "off" ]; then
    # Hide bar: 現在の値を保存してから2に設定
    CURRENT_PADDING=$(get_current_padding)
    [ -n "$CURRENT_PADDING" ] && echo "$CURRENT_PADDING" > "$SAVED_PADDING_FILE"
    sketchybar --bar hidden=on
    sed -i '' 's/outer\.bottom = *[0-9]*/outer.bottom = 2/' "$CONFIG_FILE"
else
    # Show bar: 保存した値を復元（なければaerospace.tomlのデフォルト値を使用）
    if [ -f "$SAVED_PADDING_FILE" ]; then
        RESTORE_PADDING=$(cat "$SAVED_PADDING_FILE")
    else
        RESTORE_PADDING=$(get_current_padding)
    fi
    sketchybar --bar hidden=off
    sed -i '' "s/outer\.bottom = *[0-9]*/outer.bottom = $RESTORE_PADDING/" "$CONFIG_FILE"
fi

# Reload aerospace config
aerospace reload-config
