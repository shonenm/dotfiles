#!/bin/bash

source "$CONFIG_DIR/plugins/icon_map.sh"
source "$CONFIG_DIR/plugins/colors.sh"

# Get current mode color
HIGHLIGHT_COLOR=$(get_mode_color)

# Get focused workspace and focused app
FOCUSED_WS=$(aerospace list-workspaces --focused)
FOCUSED_APP=$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null)
APPS=$(aerospace list-windows --workspace "$FOCUSED_WS" --format '%{app-name}' 2>/dev/null | sort -u)

# State file to track current apps
STATE_FILE="/tmp/sketchybar_apps_state"
CURRENT_APPS=$(echo "$APPS" | tr '\n' '|')

# Check if apps list changed (workspace switch) or just focus changed
PREV_APPS=""
[ -f "$STATE_FILE" ] && PREV_APPS=$(cat "$STATE_FILE")

if [ "$CURRENT_APPS" != "$PREV_APPS" ]; then
    # Apps changed - need to recreate items
    echo "$CURRENT_APPS" > "$STATE_FILE"

    # Remove old items and bracket
    sketchybar --remove '/app\..*/' 2>/dev/null
    sketchybar --remove apps_bracket 2>/dev/null

    if [ -z "$APPS" ]; then
        exit 0
    fi

    # Collect item names for bracket
    APP_ITEMS=()

    # Create items in order (first app = leftmost)
    while IFS= read -r app; do
        item_name="app.$(echo "$app" | tr ' .' '_')"
        APP_ITEMS+=("$item_name")
        __icon_map "$app"

        sketchybar --add item "$item_name" left \
                   --set "$item_name" \
                   icon="$icon_result" \
                   icon.font="sketchybar-app-font:Regular:14.0" \
                   icon.color=0xffffffff \
                   icon.padding_left=6 \
                   icon.padding_right=6 \
                   label.font="Hack Nerd Font:Bold:10.0" \
                   label.color=0xffffffff \
                   label.padding_left=2 \
                   label.padding_right=6 \
                   background.drawing=off
    done <<< "$APPS"

    # Create bracket for unified black background with mode-aware border
    if [ ${#APP_ITEMS[@]} -gt 0 ]; then
        sketchybar --add bracket apps_bracket "${APP_ITEMS[@]}" \
                   --set apps_bracket \
                   background.color=0xff1e1f29 \
                   background.corner_radius=5 \
                   background.height=24 \
                   background.border_color=$HIGHLIGHT_COLOR \
                   background.border_width=2 \
                   background.drawing=on

        # Add separator between workspaces and apps
        sketchybar --remove apps_separator 2>/dev/null
        last_space=$(sketchybar --query bar | grep -o '"space\.[^"]*"' | tail -1 | tr -d '"')
        sketchybar --add item apps_separator left \
                   --set apps_separator \
                   icon.drawing=off \
                   label.drawing=off \
                   background.drawing=off \
                   width=8
        if [ -n "$last_space" ]; then
            sketchybar --move apps_separator after "$last_space"
        fi
    fi
fi

# Update apps_bracket border color (for mode changes)
sketchybar --set apps_bracket background.border_color=$HIGHLIGHT_COLOR 2>/dev/null

# Update styles based on focus (without recreating)
if [ -n "$APPS" ]; then
    while IFS= read -r app; do
        item_name="app.$(echo "$app" | tr ' .' '_')"

        if [ "$app" = "$FOCUSED_APP" ]; then
            sketchybar --set "$item_name" \
                label="$app" \
                label.drawing=on \
                icon.background.drawing=on \
                icon.background.color=$HIGHLIGHT_COLOR \
                icon.background.corner_radius=4 \
                icon.background.height=20
        else
            sketchybar --set "$item_name" \
                label.drawing=off \
                icon.background.drawing=off
        fi
    done <<< "$APPS"
fi
