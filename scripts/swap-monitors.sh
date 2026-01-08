#!/bin/bash
# Swap workspace-to-monitor-force-assignment between main and secondary

CONFIG_FILE="$HOME/.config/aerospace/aerospace.toml"

# Check current state (is 1 assigned to main or secondary?)
CURRENT=$(grep "^1 = " "$CONFIG_FILE" | grep -o "'[^']*'" | tr -d "'")

if [ "$CURRENT" = "secondary" ]; then
    # Swap: secondary -> main, main -> secondary
    sed -i '' "s/ = 'secondary'/ = '__TEMP__'/g" "$CONFIG_FILE"
    sed -i '' "s/ = 'main'/ = 'secondary'/g" "$CONFIG_FILE"
    sed -i '' "s/ = '__TEMP__'/ = 'main'/g" "$CONFIG_FILE"
    echo "Swapped: secondary <-> main"
else
    # Swap back: main -> secondary, secondary -> main
    sed -i '' "s/ = 'main'/ = '__TEMP__'/g" "$CONFIG_FILE"
    sed -i '' "s/ = 'secondary'/ = 'main'/g" "$CONFIG_FILE"
    sed -i '' "s/ = '__TEMP__'/ = 'secondary'/g" "$CONFIG_FILE"
    echo "Swapped: main <-> secondary"
fi

# Reload config
aerospace reload-config
