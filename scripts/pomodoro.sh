#!/bin/bash
# Pomodoro Timer CLI
# Usage:
#   pomodoro start [minutes]  # 開始（デフォルト25分）
#   pomodoro pause            # 一時停止
#   pomodoro toggle           # スタート/ポーズ切り替え
#   pomodoro reset            # リセット
#   pomodoro set <minutes>    # 時間設定
#   pomodoro status           # 状態表示

set -euo pipefail

STATE_DIR="/tmp/sketchybar_pomodoro"
STATE_FILE="$STATE_DIR/state"
END_FILE="$STATE_DIR/end_time"
REMAIN_FILE="$STATE_DIR/remaining"
DURATION_FILE="$STATE_DIR/duration"

DEFAULT_DURATION=1500  # 25分

mkdir -p "$STATE_DIR"

# 状態読み込み
get_state() {
  cat "$STATE_FILE" 2>/dev/null || echo "stopped"
}

get_duration() {
  cat "$DURATION_FILE" 2>/dev/null || echo "$DEFAULT_DURATION"
}

get_remaining() {
  local state=$(get_state)
  local duration=$(get_duration)

  case "$state" in
    running)
      local end_time=$(cat "$END_FILE" 2>/dev/null || echo "0")
      local now=$(date +%s)
      echo $((end_time - now))
      ;;
    paused)
      cat "$REMAIN_FILE" 2>/dev/null || echo "$duration"
      ;;
    *)
      echo "$duration"
      ;;
  esac
}

# スタート
start_timer() {
  local minutes="${1:-}"
  local duration=$(get_duration)

  if [[ -n "$minutes" ]]; then
    duration=$((minutes * 60))
    echo "$duration" > "$DURATION_FILE"
  fi

  local state=$(get_state)
  local remaining

  if [[ "$state" == "paused" ]]; then
    remaining=$(cat "$REMAIN_FILE" 2>/dev/null || echo "$duration")
  else
    remaining=$duration
  fi

  local now=$(date +%s)
  local end_time=$((now + remaining))

  echo "$end_time" > "$END_FILE"
  echo "running" > "$STATE_FILE"

  sketchybar --trigger pomodoro_update 2>/dev/null || true
  echo "Started: $((remaining / 60))m $((remaining % 60))s"
}

# 一時停止
pause_timer() {
  local state=$(get_state)

  if [[ "$state" != "running" ]]; then
    echo "Not running"
    return
  fi

  local end_time=$(cat "$END_FILE" 2>/dev/null || echo "0")
  local now=$(date +%s)
  local remaining=$((end_time - now))

  echo "$remaining" > "$REMAIN_FILE"
  echo "paused" > "$STATE_FILE"

  sketchybar --trigger pomodoro_update 2>/dev/null || true
  echo "Paused: $((remaining / 60))m $((remaining % 60))s remaining"
}

# トグル（スタート/ポーズ切り替え）
toggle_timer() {
  local state=$(get_state)

  case "$state" in
    running)
      pause_timer
      ;;
    paused|stopped|*)
      start_timer
      ;;
  esac
}

# リセット
reset_timer() {
  local duration=$(get_duration)

  echo "stopped" > "$STATE_FILE"
  echo "$duration" > "$REMAIN_FILE"
  rm -f "$END_FILE"

  sketchybar --trigger pomodoro_update 2>/dev/null || true
  echo "Reset: $((duration / 60))m"
}

# 時間設定
set_duration() {
  local minutes="${1:-25}"
  local duration=$((minutes * 60))

  echo "$duration" > "$DURATION_FILE"

  # stoppedの場合はremainingも更新
  local state=$(get_state)
  if [[ "$state" == "stopped" ]]; then
    echo "$duration" > "$REMAIN_FILE"
  fi

  sketchybar --trigger pomodoro_update 2>/dev/null || true
  echo "Duration set: ${minutes}m"
}

# 状態表示
show_status() {
  local state=$(get_state)
  local duration=$(get_duration)
  local remaining=$(get_remaining)

  echo "State: $state"
  echo "Duration: $((duration / 60))m"
  echo "Remaining: $((remaining / 60))m $((remaining % 60))s"
}

# メイン
case "${1:-status}" in
  start)
    start_timer "${2:-}"
    ;;
  pause)
    pause_timer
    ;;
  toggle)
    toggle_timer
    ;;
  reset)
    reset_timer
    ;;
  set)
    set_duration "${2:-25}"
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: pomodoro <start|pause|toggle|reset|set|status> [minutes]"
    exit 1
    ;;
esac
