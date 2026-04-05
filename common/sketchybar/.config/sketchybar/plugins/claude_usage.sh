#!/bin/bash
# Claude Code 使用量ゲージ
# ▁▂▃▄▅▆▇█ の縦棒文字でセッション/週間残量を表示
#
# データ取得: macOS キーチェーン "Claude Code-credentials" の OAuth トークンを使用
# エンドポイント: https://api.anthropic.com/api/oauth/usage (非公式)

# shellcheck source=/dev/null
source "$CONFIG_DIR/plugins/colors.sh"

USAGE_FILE="/tmp/claude_code_usage"
MODE_COLOR=$(get_mode_color)

# キーチェーンからOAuthアクセストークンを取得して使用量を更新
update_usage() {
  local creds_json
  creds_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  [[ -z "$creds_json" ]] && return 1

  local token
  token=$(echo "$creds_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['claudeAiOauth']['accessToken'])
" 2>/dev/null)
  [[ -z "$token" ]] && return 1

  curl -sf --max-time 5 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null | \
  python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  s = round(d['five_hour']['utilization'])
  w = round(d['seven_day']['utilization'])
  print(max(0, min(100, s)))
  print(max(0, min(100, w)))
except Exception:
  sys.exit(1)
" > "$USAGE_FILE" 2>/dev/null
}

# 同期で取得（--max-time 5 なので最大5秒、失敗時は既存キャッシュを使用）
update_usage

session_pct=0
weekly_pct=0

if [[ -f "$USAGE_FILE" ]]; then
  session_pct=$(sed -n '1p' "$USAGE_FILE" 2>/dev/null | tr -d '[:space:]')
  weekly_pct=$(sed -n '2p' "$USAGE_FILE" 2>/dev/null | tr -d '[:space:]')
fi

[[ "$session_pct" =~ ^[0-9]+$ ]] || session_pct=0
[[ "$weekly_pct" =~ ^[0-9]+$ ]] || weekly_pct=0
(( session_pct > 100 )) && session_pct=100
(( weekly_pct > 100 )) && weekly_pct=100

make_vbar() {
  local pct=$1
  local level=$(( pct * 8 / 100 ))
  local chars=(" " "▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
  echo "${chars[$level]}"
}

session_bar=$(make_vbar "$session_pct")
weekly_bar=$(make_vbar "$weekly_pct")

sketchybar --set claude_usage \
  label="${session_bar}${weekly_bar} ${session_pct}%/${weekly_pct}%" \
  background.border_color="$MODE_COLOR"
