#!/bin/bash

source "$CONFIG_DIR/plugins/colors.sh"

# AeroSpaceモニター番号 → sketchybarディスプレイ番号の変換
# macOSの内蔵ディスプレイは通常display=1、外部はdisplay=2
get_sketchybar_display() {
    local aerospace_monitor=$1

    # シングルモニターの場合は常に1を返す
    local monitor_count=$(aerospace list-monitors 2>/dev/null | wc -l | tr -d ' ')
    if [ "$monitor_count" -le 1 ]; then
        echo "1"
        return
    fi

    # 複数モニターの場合：AeroSpaceのモニター名を取得
    local monitor_name=$(aerospace list-monitors --json 2>/dev/null \
        | jq -r ".[] | select(.\"monitor-id\" == $aerospace_monitor) | .\"monitor-name\"")

    # Built-in Retina Display → sketchybar display=1
    # 外部モニター → sketchybar display=2
    if [[ "$monitor_name" == *"Built-in"* ]] || [[ "$monitor_name" == *"Retina"* ]]; then
        echo "1"
    else
        echo "2"
    fi
}

# Get current mode color
HIGHLIGHT_COLOR=$(get_mode_color)

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
# Include monitor count in state to detect display changes
CURRENT_STATE="$MONITOR_COUNT:$ALL_WS"
PREV_STATE=""
[ -f "$STATE_FILE" ] && PREV_STATE=$(cat "$STATE_FILE")

# Rebuild if workspace list or monitor count changed
if [ "$CURRENT_STATE" != "$PREV_STATE" ]; then
    echo "$CURRENT_STATE" > "$STATE_FILE"

    # Remove old workspace items and brackets
    sketchybar --remove '/space\..*/' 2>/dev/null
    sketchybar --remove '/workspaces.*/' 2>/dev/null

    # Create workspace items per monitor
    for monitor in $(seq 1 $MONITOR_COUNT); do
        MONITOR_WS=$(aerospace list-workspaces --monitor $monitor --empty no 2>/dev/null | sort)
        [ -z "$MONITOR_WS" ] && continue

        # AeroSpaceモニター番号をsketchybarディスプレイ番号に変換
        SKETCHYBAR_DISPLAY=$(get_sketchybar_display $monitor)

        SPACE_ITEMS=()
        for sid in $MONITOR_WS; do
            SPACE_ITEMS+=("space.$sid")

            # ワークスペースアイテム（モニター指定付き）
            sketchybar --add item space.$sid left \
                --subscribe space.$sid aerospace_workspace_change \
                --set space.$sid \
                display=$SKETCHYBAR_DISPLAY \
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
                display=$SKETCHYBAR_DISPLAY \
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
                       display=$SKETCHYBAR_DISPLAY \
                       background.color=0xff1e1f29 \
                       background.corner_radius=5 \
                       background.height=24 \
                       background.border_color=$HIGHLIGHT_COLOR \
                       background.border_width=2 \
                       background.drawing=on
        fi
    done
fi

# Update highlight for focused workspace and bracket colors (all monitors)
for monitor in $(seq 1 $MONITOR_COUNT); do
    # Update bracket border color
    sketchybar --set "workspaces_$monitor" background.border_color=$HIGHLIGHT_COLOR 2>/dev/null

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
