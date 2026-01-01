#!/bin/bash
# ディスプレイスリープタイマー管理スクリプト
# Usage:
#   sleep-timer.sh set <minutes>  - ディスプレイスリープ時間を設定
#   sleep-timer.sh get            - 現在の設定を取得

set -euo pipefail

case "${1:-}" in
  set)
    MINUTES="${2:-10}"
    # pmset で displaysleep 時間を変更 (sudo 必要)
    sudo pmset -a displaysleep "$MINUTES"
    # SketchyBar に通知
    if command -v sketchybar &>/dev/null; then
      sketchybar --trigger sleep_timer_change &>/dev/null || true
    fi
    echo "Display sleep timer set to ${MINUTES} minutes"
    ;;
  get)
    pmset -g | grep "displaysleep" | awk '{print $2}'
    ;;
  *)
    echo "Usage: sleep-timer.sh <set|get> [minutes]" >&2
    exit 1
    ;;
esac
