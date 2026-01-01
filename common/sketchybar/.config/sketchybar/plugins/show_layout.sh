#!/bin/bash

# Ensure CONFIG_DIR is set (for when called directly, not via sketchybar)
: "${CONFIG_DIR:=$HOME/.config/sketchybar}"

source "$CONFIG_DIR/plugins/colors.sh"

# Get current mode color
THEME_COLOR=$(get_mode_color)

# App icon mapping
get_app_icon() {
    case "$1" in
        "Arc") echo "󰞍" ;;
        "Safari") echo "󰀹" ;;
        "Chrome"|"Google Chrome") echo "" ;;
        "Firefox") echo "" ;;
        "Code"|"Visual Studio Code") echo "󰨞" ;;
        "Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp") echo "" ;;
        "Finder") echo "󰀶" ;;
        "Notion Calendar"|"Calendar") echo "" ;;
        "Slack") echo "󰒱" ;;
        "Discord") echo "󰙯" ;;
        "Spotify") echo "" ;;
        "Music") echo "󰎆" ;;
        "Notes") echo "󰎞" ;;
        "Messages") echo "󰍦" ;;
        "Mail") echo "󰇮" ;;
        "Raycast") echo "󱓞" ;;
        "System Preferences"|"System Settings") echo "" ;;
        "Preview") echo "󰋲" ;;
        "Photos") echo "󰉏" ;;
        "Notion") echo "󰈄" ;;
        "Obsidian") echo "󱓧" ;;
        "Docker"|"Docker Desktop") echo "" ;;
        "Postman") echo "󰛮" ;;
        "Figma") echo "" ;;
        "Zoom") echo "󰒃" ;;
        "Teams"|"Microsoft Teams") echo "󰊻" ;;
        *) echo "󰣆" ;;
    esac
}

# Check if popup is currently visible
POPUP_STATE=$(sketchybar --query layout_anchor | jq -r '.popup.drawing')

if [ "$POPUP_STATE" = "on" ]; then
    # Hide popup and remove items
    sketchybar --set layout_anchor popup.drawing=off
    sketchybar --remove '/layout_item\..*/' 2>/dev/null
    exit 0
fi

# Remove old popup items
sketchybar --remove '/layout_item\..*/' 2>/dev/null

# Get current workspace
FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)

# Get all windows grouped by workspace
WORKSPACES=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null | sort)

INDEX=0
for WS in $WORKSPACES; do
    # Get apps in this workspace with icons
    APPS_RAW=$(aerospace list-windows --workspace "$WS" --format '%{app-name}' 2>/dev/null | sort -u)

    if [ -z "$APPS_RAW" ]; then
        continue
    fi

    # Build app list with icons
    APPS_WITH_ICONS=""
    while IFS= read -r APP; do
        ICON=$(get_app_icon "$APP")
        if [ -n "$APPS_WITH_ICONS" ]; then
            APPS_WITH_ICONS="$APPS_WITH_ICONS  $ICON $APP"
        else
            APPS_WITH_ICONS="$ICON $APP"
        fi
    done <<< "$APPS_RAW"

    # Highlight current workspace
    if [ "$WS" = "$FOCUSED" ]; then
        BG_COLOR=$THEME_COLOR
        WS_ICON="󰄯"
    else
        BG_COLOR="0x00000000"
        WS_ICON="󰄰"
    fi

    sketchybar --add item "layout_item.$INDEX" popup.layout_anchor \
               --set "layout_item.$INDEX" \
               icon="$WS_ICON" \
               icon.font="Hack Nerd Font:Bold:18.0" \
               icon.color=0xffffffff \
               icon.padding_left=16 \
               icon.padding_right=8 \
               label="$WS: $APPS_WITH_ICONS" \
               label.font="Hack Nerd Font:Regular:14.0" \
               label.color=0xffffffff \
               label.padding_right=16 \
               background.color=$BG_COLOR \
               background.corner_radius=8 \
               background.height=36 \
               background.padding_left=8 \
               background.padding_right=8 \
               click_script="aerospace workspace $WS; sketchybar --set layout_anchor popup.drawing=off"

    INDEX=$((INDEX + 1))
done

# Show popup with theme-colored border
sketchybar --set layout_anchor \
    popup.background.border_color=$THEME_COLOR \
    popup.drawing=on
