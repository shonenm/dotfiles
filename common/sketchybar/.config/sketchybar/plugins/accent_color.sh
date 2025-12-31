#!/bin/bash

# Custom accent color (darker blue)
# Override this to use a custom color instead of system accent
CUSTOM_ACCENT_COLOR="0xff0055bb"

# Get macOS system accent color as hex for sketchybar
get_accent_color() {
    # Use custom color if defined
    if [ -n "$CUSTOM_ACCENT_COLOR" ]; then
        echo "$CUSTOM_ACCENT_COLOR"
        return
    fi

    local highlight=$(defaults read -g AppleHighlightColor 2>/dev/null)

    if [ -n "$highlight" ]; then
        # Parse RGB values (format: "R G B ColorName")
        local r=$(echo "$highlight" | awk '{printf "%02x", $1 * 255}')
        local g=$(echo "$highlight" | awk '{printf "%02x", $2 * 255}')
        local b=$(echo "$highlight" | awk '{printf "%02x", $3 * 255}')
        echo "0xff${r}${g}${b}"
    else
        # Default to blue if not set
        echo "0xff007aff"
    fi
}

ACCENT_COLOR=$(get_accent_color)

# Service mode color (orange/red for warning)
SERVICE_MODE_COLOR="0xffff6600"

# Pomodoro mode color (green - same as running timer)
POMODORO_MODE_COLOR="0xff28a745"
