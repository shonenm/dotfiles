#!/bin/bash
# Privacy Indicator - カメラ/マイク使用中を表示

STATE_FILE="/tmp/privacy_state"

camera_on=false
mic_on=false

if [[ -f "$STATE_FILE" ]]; then
  grep -q "camera:on" "$STATE_FILE" && camera_on=true
  grep -q "mic:on" "$STATE_FILE" && mic_on=true
fi

if $camera_on && $mic_on; then
  sketchybar --set privacy \
    icon="󰄀 󰍬" \
    icon.drawing=on \
    background.color=0xffdc3545 \
    background.drawing=on
elif $camera_on; then
  sketchybar --set privacy \
    icon="󰄀" \
    icon.drawing=on \
    background.color=0xffdc3545 \
    background.drawing=on
elif $mic_on; then
  sketchybar --set privacy \
    icon="󰍬" \
    icon.drawing=on \
    background.color=0xffff6600 \
    background.drawing=on
else
  sketchybar --set privacy \
    icon.drawing=off \
    background.drawing=off
fi
