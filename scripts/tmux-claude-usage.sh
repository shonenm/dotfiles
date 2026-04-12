#!/bin/bash
# Claude Code 使用量表示 (tmux status-right 用)
# OAuth トークンで使用量を取得しキャッシュ
# macOS: Keychain, Linux: ~/.claude/.credentials.json
# 出力: "󰧑 ▃▅ 42%/67%" 形式のプレーンテキスト

CACHE_FILE="/tmp/tmux_claude_usage"
CACHE_TTL=300  # 5分

# クロスプラットフォーム mtime 取得
get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# キャッシュが有効ならそのまま出力
if [[ -f "$CACHE_FILE" ]]; then
  age=$(( $(date +%s) - $(get_mtime "$CACHE_FILE") ))
  if (( age < CACHE_TTL )); then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# OAuth アクセストークンを取得
get_token() {
  case "$(uname -s)" in
    Darwin)
      # macOS: Keychain
      local creds_json
      creds_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
      [[ -z "$creds_json" ]] && return 1
      echo "$creds_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['claudeAiOauth']['accessToken'])
" 2>/dev/null
      ;;
    *)
      # Linux: ~/.claude/.credentials.json
      local creds_file="$HOME/.claude/.credentials.json"
      [[ -f "$creds_file" ]] || return 1
      python3 -c "
import json
with open('$creds_file') as f:
    d = json.load(f)
print(d['claudeAiOauth']['accessToken'])
" 2>/dev/null
      ;;
  esac
}

token=$(get_token)
[[ -z "$token" ]] && echo "󰧑 --" && exit 0

# 使用量を取得
usage=$(curl -sf --max-time 5 \
  -H "Authorization: Bearer $token" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage" 2>/dev/null | \
python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  s = max(0, min(100, round(d['five_hour']['utilization'])))
  w = max(0, min(100, round(d['seven_day']['utilization'])))
  bars = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
  sb = bars[s * 8 // 100] if s < 100 else bars[8]
  wb = bars[w * 8 // 100] if w < 100 else bars[8]
  print(f'󰧑 {sb}{wb} {s}%/{w}%')
except Exception:
  print('󰧑 --')
" 2>/dev/null)

result="${usage:-󰧑 --}"
echo "$result" > "$CACHE_FILE"
echo "$result"
