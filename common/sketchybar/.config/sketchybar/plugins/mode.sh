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

    # Create keybind help on the right side
    sketchybar --remove keybind_help 2>/dev/null
    sketchybar --add item keybind_help right \
               --set keybind_help \
               icon.drawing=off \
               label="esc:exit  a:reload  r:reset  f:float  c:clear-badges  ⌫:close-others" \
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

    # Change JankyBorders color to service mode
    borders active_color=$SERVICE_MODE_COLOR 2>/dev/null

    # Change all brackets to service mode color
    sketchybar --set apps_bracket background.border_color=$SERVICE_MODE_COLOR 2>/dev/null
    sketchybar --set '/workspaces.*/' background.border_color=$SERVICE_MODE_COLOR 2>/dev/null
    sketchybar --set day_progress background.border_color=$SERVICE_MODE_COLOR 2>/dev/null
    sketchybar --set pomodoro background.border_color=$SERVICE_MODE_COLOR 2>/dev/null

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

    # Update layout popup colors if visible
    POPUP_STATE=$(sketchybar --query layout_anchor 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)
    if [ "$POPUP_STATE" = "on" ]; then
        # Update popup border color
        sketchybar --set layout_anchor popup.background.border_color=$SERVICE_MODE_COLOR 2>/dev/null
        # Find and update the focused workspace item in the popup
        FOCUSED_WS_LAYOUT=$(aerospace list-workspaces --focused 2>/dev/null)
        INDEX=0
        for WS in $(aerospace list-workspaces --monitor all --empty no 2>/dev/null | sort); do
            if [ "$WS" = "$FOCUSED_WS_LAYOUT" ]; then
                sketchybar --set "layout_item.$INDEX" background.color=$SERVICE_MODE_COLOR 2>/dev/null
            fi
            INDEX=$((INDEX + 1))
        done
    fi
elif [ "$MODE" = "pomodoro" ]; then
    # Pomodoro mode: show with tomato color
    sketchybar --set mode_indicator \
        icon="󰔛" \
        icon.drawing=on \
        label="POMO" \
        label.drawing=on \
        background.color=$POMODORO_MODE_COLOR \
        background.drawing=on

    # Create keybind help on the right side
    sketchybar --remove keybind_help 2>/dev/null
    sketchybar --add item keybind_help right \
               --set keybind_help \
               icon.drawing=off \
               label="esc:exit  s:start/pause  r:reset  1:5m 2:15m 3:25m 4:45m 5:60m" \
               label.font="Hack Nerd Font:Bold:10.0" \
               label.color=0xffffffff \
               label.padding_left=10 \
               label.padding_right=10 \
               background.color=0xff1e1f29 \
               background.corner_radius=5 \
               background.height=24 \
               background.border_color=$POMODORO_MODE_COLOR \
               background.border_width=2 \
               background.drawing=on

    # Change JankyBorders color to pomodoro mode
    borders active_color=$POMODORO_MODE_COLOR 2>/dev/null

    # Change all brackets to pomodoro mode color
    sketchybar --set apps_bracket background.border_color=$POMODORO_MODE_COLOR 2>/dev/null
    sketchybar --set '/workspaces.*/' background.border_color=$POMODORO_MODE_COLOR 2>/dev/null
    sketchybar --set day_progress background.border_color=$POMODORO_MODE_COLOR 2>/dev/null
    sketchybar --set pomodoro background.border_color=$POMODORO_MODE_COLOR 2>/dev/null

    # Change focused workspace highlight color
    FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)
    if [ -n "$FOCUSED_WS" ]; then
        sketchybar --set "space.$FOCUSED_WS" background.color=$POMODORO_MODE_COLOR 2>/dev/null
    fi

    # Change focused app icon color
    FOCUSED_APP=$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null)
    if [ -n "$FOCUSED_APP" ]; then
        item_name="app.$(echo "$FOCUSED_APP" | tr ' .' '_')"
        sketchybar --set "$item_name" icon.background.color=$POMODORO_MODE_COLOR 2>/dev/null
    fi

    # Update layout popup colors if visible
    POPUP_STATE=$(sketchybar --query layout_anchor 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)
    if [ "$POPUP_STATE" = "on" ]; then
        # Update popup border color
        sketchybar --set layout_anchor popup.background.border_color=$POMODORO_MODE_COLOR 2>/dev/null
        # Find and update the focused workspace item in the popup
        FOCUSED_WS_LAYOUT=$(aerospace list-workspaces --focused 2>/dev/null)
        INDEX=0
        for WS in $(aerospace list-workspaces --monitor all --empty no 2>/dev/null | sort); do
            if [ "$WS" = "$FOCUSED_WS_LAYOUT" ]; then
                sketchybar --set "layout_item.$INDEX" background.color=$POMODORO_MODE_COLOR 2>/dev/null
            fi
            INDEX=$((INDEX + 1))
        done
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

    # Close pomodoro popup if open
    sketchybar --set pomodoro popup.drawing=off 2>/dev/null
    sketchybar --remove '/pomodoro_item\..*/' 2>/dev/null

    # Restore JankyBorders color to accent
    borders active_color=$ACCENT_COLOR 2>/dev/null

    # Restore accent color for brackets
    sketchybar --set apps_bracket background.border_color=$ACCENT_COLOR 2>/dev/null
    sketchybar --set '/workspaces.*/' background.border_color=$ACCENT_COLOR 2>/dev/null
    sketchybar --set day_progress background.border_color=$ACCENT_COLOR 2>/dev/null
    sketchybar --set pomodoro background.border_color=$ACCENT_COLOR 2>/dev/null

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

    # Update layout popup colors if visible
    POPUP_STATE=$(sketchybar --query layout_anchor 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)
    if [ "$POPUP_STATE" = "on" ]; then
        # Update popup border color
        sketchybar --set layout_anchor popup.background.border_color=$ACCENT_COLOR 2>/dev/null
        # Find and update the focused workspace item in the popup
        FOCUSED_WS_LAYOUT=$(aerospace list-workspaces --focused 2>/dev/null)
        INDEX=0
        for WS in $(aerospace list-workspaces --monitor all --empty no 2>/dev/null | sort); do
            if [ "$WS" = "$FOCUSED_WS_LAYOUT" ]; then
                sketchybar --set "layout_item.$INDEX" background.color=$ACCENT_COLOR 2>/dev/null
            fi
            INDEX=$((INDEX + 1))
        done
    fi
fi
