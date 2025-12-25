#!/bin/bash

source "$CONFIG_DIR/plugins/accent_color.sh"

# Get current mode for highlight color
MODE=$(aerospace list-modes --current 2>/dev/null)
if [ "$MODE" = "service" ]; then
    HIGHLIGHT_COLOR=$SERVICE_MODE_COLOR
else
    HIGHLIGHT_COLOR=$ACCENT_COLOR
fi

# Get current non-empty workspaces
CURRENT_WS=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null | sort -r)
FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)

# State file to track existing workspace items
STATE_FILE="/tmp/sketchybar_workspaces_state"
PREV_WS=""
[ -f "$STATE_FILE" ] && PREV_WS=$(cat "$STATE_FILE")

CURRENT_WS_LINE=$(echo "$CURRENT_WS" | tr '\n' '|')

# Only rebuild if workspace list changed
if [ "$CURRENT_WS_LINE" != "$PREV_WS" ]; then
    echo "$CURRENT_WS_LINE" > "$STATE_FILE"

    # Remove old workspace items and bracket
    sketchybar --remove '/space\..*/' 2>/dev/null
    sketchybar --remove workspaces 2>/dev/null

    # Create new workspace items
    SPACE_ITEMS=()
    for sid in $CURRENT_WS; do
        SPACE_ITEMS+=("space.$sid")
        sketchybar --add item space.$sid right \
            --subscribe space.$sid aerospace_workspace_change \
            --set space.$sid \
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
    done

    # Create bracket for unified background
    if [ ${#SPACE_ITEMS[@]} -gt 0 ]; then
        sketchybar --add bracket workspaces "${SPACE_ITEMS[@]}" \
                   --set workspaces \
                   background.color=0xff1e1f29 \
                   background.corner_radius=5 \
                   background.height=24 \
                   background.border_color=$HIGHLIGHT_COLOR \
                   background.border_width=2 \
                   background.drawing=on
    fi
fi

# Update highlight for focused workspace
for sid in $CURRENT_WS; do
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
