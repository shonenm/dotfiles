#!/bin/bash

source "$CONFIG_DIR/plugins/accent_color.sh"

# Highlight focused workspace with system accent color
if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME background.color=$ACCENT_COLOR \
                           label.color=0xffffffff
else
    sketchybar --set $NAME background.color=0x00000000 \
                           label.color=0xffffffff
fi
