#!/bin/bash

source "$CONFIG_DIR/plugins/accent_color.sh"

# Get current mode for highlight color
MODE=$(aerospace list-modes --current 2>/dev/null)
if [ "$MODE" = "service" ]; then
    HIGHLIGHT_COLOR=$SERVICE_MODE_COLOR
else
    HIGHLIGHT_COLOR=$ACCENT_COLOR
fi

# Get number of monitors
MONITOR_COUNT=$(aerospace list-monitors 2>/dev/null | wc -l | tr -d ' ')
[ -z "$MONITOR_COUNT" ] && MONITOR_COUNT=1

# Get all non-empty workspaces for state tracking
ALL_WS=""
for monitor in $(seq 1 $MONITOR_COUNT); do
    WS=$(aerospace list-workspaces --monitor $monitor --empty no 2>/dev/null | sort)
    ALL_WS="$ALL_WS $WS"
done
ALL_WS=$(echo "$ALL_WS" | xargs | tr ' ' '|')

FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)

# State file to track existing workspace items
STATE_FILE="/tmp/sketchybar_workspaces_state"
PREV_WS=""
[ -f "$STATE_FILE" ] && PREV_WS=$(cat "$STATE_FILE")

# Only rebuild if workspace list changed
if [ "$ALL_WS" != "$PREV_WS" ]; then
    echo "$ALL_WS" > "$STATE_FILE"

    # Remove old workspace items and brackets
    sketchybar --remove '/space\..*/' 2>/dev/null
    sketchybar --remove '/workspaces.*/' 2>/dev/null

    # Create workspace items per monitor
    for monitor in $(seq 1 $MONITOR_COUNT); do
        MONITOR_WS=$(aerospace list-workspaces --monitor $monitor --empty no 2>/dev/null | sort)
        [ -z "$MONITOR_WS" ] && continue

        SPACE_ITEMS=()
        for sid in $MONITOR_WS; do
            SPACE_ITEMS+=("space.$sid")

            # ワークスペースアイテム（モニター指定付き）
            sketchybar --add item space.$sid left \
                --subscribe space.$sid aerospace_workspace_change \
                --set space.$sid \
                display=$monitor \
                icon.drawing=off \
                label="$sid" \
                label.font="Hack Nerd Font:Bold:12.0" \
                label.color=0xffffffff \
                label.padding_left=10 \
                label.padding_right=10 \
                background.color=0x00000000 \
                background.corner_radius=5 \
                background.height=24 \
                background.drawing=off \
                click_script="aerospace workspace $sid" \
                script="$CONFIG_DIR/plugins/aerospace.sh $sid"

            # バッジアイテム（モニター指定付き）
            sketchybar --add item "space.${sid}_badge" left \
                --set "space.${sid}_badge" \
                display=$monitor \
                drawing=on \
                icon.drawing=off \
                label="" \
                label.drawing=off \
                label.font="Hack Nerd Font:Bold:9.0" \
                label.color=0xffffffff \
                label.width=14 \
                label.align=center \
                label.y_offset=1 \
                background.color=0xffff6600 \
                background.corner_radius=7 \
                background.height=14 \
                background.drawing=off \
                width=14 \
                y_offset=6 \
                padding_left=-5 \
                padding_right=0
        done

        # Create bracket for unified background (per monitor)
        if [ ${#SPACE_ITEMS[@]} -gt 0 ]; then
            sketchybar --add bracket workspaces_$monitor "${SPACE_ITEMS[@]}" \
                       --set workspaces_$monitor \
                       display=$monitor \
                       background.color=0xff1e1f29 \
                       background.corner_radius=5 \
                       background.height=24 \
                       background.border_color=$HIGHLIGHT_COLOR \
                       background.border_width=2 \
                       background.drawing=on
        fi
    done
fi

# Update highlight for focused workspace (all monitors)
for monitor in $(seq 1 $MONITOR_COUNT); do
    MONITOR_WS=$(aerospace list-workspaces --monitor $monitor --empty no 2>/dev/null)
    for sid in $MONITOR_WS; do
        if [ "$sid" = "$FOCUSED_WS" ]; then
            sketchybar --set "space.$sid" \
                background.color=$HIGHLIGHT_COLOR \
                background.drawing=on
        else
            sketchybar --set "space.$sid" \
                background.color=0x00000000 \
                background.drawing=off
        fi
    done
done
