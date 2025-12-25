#!/bin/bash

# Get macOS system accent color as hex for sketchybar
get_accent_color() {
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
