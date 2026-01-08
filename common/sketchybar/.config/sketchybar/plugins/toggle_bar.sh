#!/bin/bash

CONFIG_FILE="$HOME/.config/aerospace/aerospace.toml"
DEFAULT_PADDING=25
CURRENT=$(sketchybar --query bar | jq -r ".hidden")

if [ "$CURRENT" = "off" ]; then
    # Hide bar
    sketchybar --bar hidden=on
    sed -i '' 's/outer\.bottom = *[0-9]*/outer.bottom = 2/' "$CONFIG_FILE"
else
    # Show bar
    sketchybar --bar hidden=off
    sed -i '' "s/outer\.bottom = *[0-9]*/outer.bottom = $DEFAULT_PADDING/" "$CONFIG_FILE"
fi

# Reload aerospace config
aerospace reload-config
