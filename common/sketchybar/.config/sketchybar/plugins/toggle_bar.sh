#!/bin/bash

CONFIG_FILE="$HOME/.config/aerospace/aerospace.toml"
CURRENT=$(sketchybar --query bar | jq -r ".hidden")

if [ "$CURRENT" = "off" ]; then
    # Hide bar, reduce top padding
    sketchybar --bar hidden=on
    sed -i '' 's/outer\.top = *[0-9]*/outer.top = 2/' "$CONFIG_FILE"
else
    # Show bar, restore top padding
    sketchybar --bar hidden=off
    sed -i '' 's/outer\.top = *[0-9]*/outer.top = 10/' "$CONFIG_FILE"
fi

# Reload aerospace config
aerospace reload-config
