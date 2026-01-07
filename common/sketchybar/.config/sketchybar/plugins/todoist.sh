#!/bin/bash
# Todoist task progress plugin for SketchyBar
# Shows: ✓completed|remaining (percent%)

source "$CONFIG_DIR/plugins/colors.sh"

TOKEN=$(op read "op://Personal/Todoist API/credential" 2>/dev/null)
if [[ -z "$TOKEN" ]]; then
  sketchybar --set $NAME label="?"
  exit 0
fi

TODAY=$(date +%Y-%m-%d)

# 今日期限の残りタスク数（REST API）
REMAINING=$(curl -s "https://api.todoist.com/rest/v2/tasks?filter=today" \
  -H "Authorization: Bearer $TOKEN" 2>/dev/null | jq 'length' 2>/dev/null)

# 今日完了したタスク数（Sync API）
COMPLETED=$(curl -s -X POST "https://api.todoist.com/sync/v9/completed/get_all" \
  -H "Authorization: Bearer $TOKEN" \
  -d "since=${TODAY}T00:00:00" 2>/dev/null | jq '.items | length' 2>/dev/null)

REMAINING=${REMAINING:-0}
COMPLETED=${COMPLETED:-0}

# 達成率計算
TOTAL=$((COMPLETED + REMAINING))
if [[ $TOTAL -gt 0 ]]; then
  PERCENT=$((COMPLETED * 100 / TOTAL))
else
  PERCENT=0
fi

sketchybar --set $NAME label="${COMPLETED}/${TOTAL}"
