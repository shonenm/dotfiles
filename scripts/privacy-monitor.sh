#!/bin/bash
# Privacy Monitor - カメラ/マイク状態変化を監視し、SketchyBarを更新
# イベント駆動で軽量動作

set -euo pipefail

STATE_FILE="/tmp/privacy_state"

# 初期状態
echo "camera:off,mic:off" > "$STATE_FILE"

# SketchyBar が起動するまで待機
sleep 5

# 初期状態を反映
sketchybar --trigger privacy_change 2>/dev/null || true

# カメラ監視（バックグラウンド）
monitor_camera() {
  log stream --predicate 'eventMessage contains "Cameras changed to"' 2>/dev/null | while IFS= read -r line; do
    if echo "$line" | grep -q "Cameras changed to 1"; then
      sed -i '' 's/camera:off/camera:on/' "$STATE_FILE" 2>/dev/null || true
    elif echo "$line" | grep -q "Cameras changed to 0"; then
      sed -i '' 's/camera:on/camera:off/' "$STATE_FILE" 2>/dev/null || true
    fi
    sketchybar --trigger privacy_change 2>/dev/null || true
  done
}

# マイク監視（バックグラウンド）
# 注: macOSのマイク状態検知は複雑なため、カメラのみ監視
# 必要に応じて拡張可能

# カメラ監視を開始
monitor_camera
