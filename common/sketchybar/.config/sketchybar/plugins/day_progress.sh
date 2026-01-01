#!/bin/bash
# Day Progress - 1日の進捗をバーで表示

source "$CONFIG_DIR/plugins/colors.sh"

hour=$(date +%H)
minute=$(date +%M)
progress=$(( (10#$hour * 60 + 10#$minute) * 100 / 1440 ))

# プログレスバー生成（10文字幅）
filled=$(( progress / 10 ))
empty=$(( 10 - filled ))

bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

sketchybar --set day_progress label="${bar} ${progress}%" background.border_color="$(get_mode_color)"
