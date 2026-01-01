#!/bin/bash
# Pomodoro Timer Plugin for SketchyBar
# 進捗バー表示、状態に応じた色変更

source "$CONFIG_DIR/plugins/colors.sh"

STATE_DIR="/tmp/sketchybar_pomodoro"
STATE_FILE="$STATE_DIR/state"
END_FILE="$STATE_DIR/end_time"
REMAIN_FILE="$STATE_DIR/remaining"
DURATION_FILE="$STATE_DIR/duration"

DEFAULT_DURATION=1500  # 25分

mkdir -p "$STATE_DIR"

# 状態読み込み
state=$(cat "$STATE_FILE" 2>/dev/null || echo "stopped")
duration=$(cat "$DURATION_FILE" 2>/dev/null || echo "$DEFAULT_DURATION")

case "$state" in
  running)
    end_time=$(cat "$END_FILE" 2>/dev/null || echo "0")
    now=$(date +%s)
    remaining=$((end_time - now))

    if [[ $remaining -le 0 ]]; then
      # タイマー完了
      echo "stopped" > "$STATE_FILE"
      osascript -e 'display notification "ポモドーロ完了！休憩しましょう" with title "Pomodoro" sound name "Glass"' &
      remaining=0
      state="stopped"
    fi
    ;;
  paused)
    remaining=$(cat "$REMAIN_FILE" 2>/dev/null || echo "$duration")
    ;;
  stopped|*)
    remaining=$duration
    state="stopped"
    ;;
esac

# プログレスバー生成
if [[ $duration -gt 0 ]]; then
  progress=$((100 - remaining * 100 / duration))
else
  progress=0
fi
filled=$((progress / 10))
empty=$((10 - filled))

bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

# 時間フォーマット
mins=$((remaining / 60))
secs=$((remaining % 60))
time_str=$(printf "%02d:%02d" $mins $secs)

# 色設定
case "$state" in
  running) color="0xff28a745" ;;  # 緑
  paused)  color="0xffffc107" ;;  # 黄
  stopped) color="0xff6c757d" ;;  # グレー
esac

sketchybar --set pomodoro \
  label="${bar} ${time_str}" \
  label.color="$color" \
  background.border_color="$(get_mode_color)"
