#!/bin/bash

CONFIG_FILE="$HOME/.config/aerospace/aerospace.toml"
CURRENT=$(sketchybar --query bar | jq -r ".hidden")

if [ "$CURRENT" = "off" ]; then
    # Hide bar, reduce bottom padding
    sketchybar --bar hidden=on
    sed -i '' 's/outer\.bottom = *[0-9]*/outer.bottom = 2/' "$CONFIG_FILE"
else
    # Show bar, restore bottom padding
    sketchybar --bar hidden=off
    sed -i '' 's/outer\.bottom = *[0-9]*/outer.bottom = 48/' "$CONFIG_FILE"
fi

# Reload aerospace config
aerospace reload-config
