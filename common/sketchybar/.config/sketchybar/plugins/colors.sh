#!/bin/bash
# SketchyBar 色管理 - 単一ソース
# すべての色定義とモード色取得APIを提供

# === 色定義 ===

# カスタムアクセントカラー（濃い青）
CUSTOM_ACCENT_COLOR="0xff0055bb"

# サービスモード（オレンジ/警告）
SERVICE_MODE_COLOR="0xffff6600"

# バッジ色（薄い版 - タイマー中）
DIM_BADGE_COLOR="0x88ff6600"

# タイマーモード（緑）
TIMER_MODE_COLOR="0xff28a745"

# === 関数 ===

# システムアクセントカラーまたはカスタムカラーを取得
get_accent_color() {
    if [ -n "$CUSTOM_ACCENT_COLOR" ]; then
        echo "$CUSTOM_ACCENT_COLOR"
        return
    fi

    local highlight=$(defaults read -g AppleHighlightColor 2>/dev/null)
    if [ -n "$highlight" ]; then
        local r=$(echo "$highlight" | awk '{printf "%02x", $1 * 255}')
        local g=$(echo "$highlight" | awk '{printf "%02x", $2 * 255}')
        local b=$(echo "$highlight" | awk '{printf "%02x", $3 * 255}')
        echo "0xff${r}${g}${b}"
    else
        echo "0xff007aff"
    fi
}

# 現在のモードに応じた色を取得
# 使用法: COLOR=$(get_mode_color) または COLOR=$(get_mode_color "service")
get_mode_color() {
    local mode="${1:-$(cat /tmp/sketchybar_mode 2>/dev/null || echo 'main')}"
    case "$mode" in
        service) echo "$SERVICE_MODE_COLOR" ;;
        timer)   echo "$TIMER_MODE_COLOR" ;;
        *)       echo "$(get_accent_color)" ;;
    esac
}

# アクセントカラーを変数として公開
ACCENT_COLOR=$(get_accent_color)
