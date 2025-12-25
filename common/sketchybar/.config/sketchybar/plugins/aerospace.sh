#!/bin/bash

# Highlight focused workspace
if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME background.drawing=on \
                           label.color=0xff1e1f29
else
    sketchybar --set $NAME background.drawing=off \
                           label.color=0xffffffff
fi
