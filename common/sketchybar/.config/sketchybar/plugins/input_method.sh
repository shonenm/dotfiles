#!/bin/bash
# 入力方式インジケータ（日本語/英語）

# shellcheck source=/dev/null
source "$CONFIG_DIR/plugins/colors.sh"

MODE_COLOR=$(get_mode_color)

# 現在の入力モードを取得（Input Mode で判定）
# Roman = 英語、Japanese/* = 日本語
input_mode=$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleSelectedInputSources 2>/dev/null \
  | /usr/bin/grep '"Input Mode"' | head -1 \
  | sed 's/.*= "\(.*\)";/\1/')

if echo "$input_mode" | /usr/bin/grep -qi "japanese"; then
  label="JP"
  label_color=0xffffffff
  bg_color="$ACCENT_COLOR"
else
  label="EN"
  label_color=0xff6c757d
  bg_color=0xff1e1f29
fi

sketchybar --set input_method \
  label="$label" \
  label.color="$label_color" \
  background.color="$bg_color" \
  background.border_color="$MODE_COLOR"
