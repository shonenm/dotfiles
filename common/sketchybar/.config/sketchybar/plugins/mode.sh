#!/bin/bash

source "$CONFIG_DIR/plugins/accent_color.sh"

# Get current mode from aerospace
MODE=$(aerospace list-modes --current 2>/dev/null)

# Handle mode change
if [ "$MODE" = "service" ]; then
    # Service mode: show with warning color
    sketchybar --set mode_indicator \
        icon="⚙" \
        icon.drawing=on \
        label="SERVICE" \
        label.drawing=on \
        background.color=$SERVICE_MODE_COLOR \
        background.drawing=on

    # Create keybind help on the left side
    sketchybar --remove keybind_help 2>/dev/null
    sketchybar --add item keybind_help left \
               --set keybind_help \
               icon.drawing=off \
               label="esc:exit  r:reset  f:float  ⌫:close-others" \
               label.font="Hack Nerd Font:Bold:10.0" \
               label.color=0xffffffff \
               label.padding_left=10 \
               label.padding_right=10 \
               background.color=0xff1e1f29 \
               background.corner_radius=5 \
               background.height=24 \
               background.border_color=$SERVICE_MODE_COLOR \
               background.border_width=2 \
               background.drawing=on

    # Change all brackets to service mode color
    sketchybar --set apps_bracket background.border_color=$SERVICE_MODE_COLOR 2>/dev/null
    sketchybar --set workspaces background.border_color=$SERVICE_MODE_COLOR 2>/dev/null

    # Change focused workspace highlight color
    FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)
    if [ -n "$FOCUSED_WS" ]; then
        sketchybar --set "space.$FOCUSED_WS" background.color=$SERVICE_MODE_COLOR 2>/dev/null
    fi

    # Change focused app icon color
    FOCUSED_APP=$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null)
    if [ -n "$FOCUSED_APP" ]; then
        item_name="app.$(echo "$FOCUSED_APP" | tr ' .' '_')"
        sketchybar --set "$item_name" icon.background.color=$SERVICE_MODE_COLOR 2>/dev/null
    fi
else
    # Main mode: show with accent color
    sketchybar --set mode_indicator \
        icon="󰍹" \
        icon.drawing=on \
        label="MAIN" \
        label.drawing=on \
        background.color=$ACCENT_COLOR \
        background.drawing=on

    # Remove keybind help
    sketchybar --remove keybind_help 2>/dev/null

    # Restore accent color for brackets
    sketchybar --set apps_bracket background.border_color=$ACCENT_COLOR 2>/dev/null
    sketchybar --set workspaces background.border_color=$ACCENT_COLOR 2>/dev/null

    # Restore focused workspace highlight color
    FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)
    if [ -n "$FOCUSED_WS" ]; then
        sketchybar --set "space.$FOCUSED_WS" background.color=$ACCENT_COLOR 2>/dev/null
    fi

    # Restore focused app icon color
    FOCUSED_APP=$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null)
    if [ -n "$FOCUSED_APP" ]; then
        item_name="app.$(echo "$FOCUSED_APP" | tr ' .' '_')"
        sketchybar --set "$item_name" icon.background.color=$ACCENT_COLOR 2>/dev/null
    fi
fi
