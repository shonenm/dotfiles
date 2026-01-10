#!/bin/bash
# Todoist task progress plugin for SketchyBar
# 分子: 今日期限タスクの完了数
# 分母: 今日期限タスク総数 + 過去期限切れ未完了タスク数

source "$CONFIG_DIR/plugins/colors.sh"

TOKEN=$(op read "op://Personal/Todoist API/credential" 2>/dev/null)
if [[ -z "$TOKEN" ]]; then
  sketchybar --set $NAME label="?"
  exit 0
fi

TODAY=$(date +%Y-%m-%d)

# 今日期限 + 期限切れの未完了タスク数（REST API）
ACTIVE=$(curl -s "https://api.todoist.com/rest/v2/tasks?filter=today%20%7C%20overdue" \
  -H "Authorization: Bearer $TOKEN" 2>/dev/null | jq 'length' 2>/dev/null)

# 今日完了したタスクのうち、今日期限だったものの数（Sync API）
COMPLETED_TODAY_DUE=$(curl -s -X POST "https://api.todoist.com/sync/v9/completed/get_all" \
  -H "Authorization: Bearer $TOKEN" \
  -d "since=${TODAY}T00:00:00" 2>/dev/null | \
  jq --arg today "$TODAY" '[.items[] | select(.due.date == $today)] | length' 2>/dev/null)

ACTIVE=${ACTIVE:-0}
COMPLETED_TODAY_DUE=${COMPLETED_TODAY_DUE:-0}

# 分子: 今日期限の完了数、分母: 分子 + 未完了（今日+期限切れ）
NUMERATOR=$COMPLETED_TODAY_DUE
DENOMINATOR=$((COMPLETED_TODAY_DUE + ACTIVE))

sketchybar --set $NAME label="${NUMERATOR}/${DENOMINATOR}"
