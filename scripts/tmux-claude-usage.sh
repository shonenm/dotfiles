#!/bin/bash
# Claude Code 使用量表示 (tmux status-right 用)
# OAuth トークンで使用量を取得しキャッシュ
# macOS: Keychain, Linux: ~/.claude/.credentials.json
# 出力: "󰧑 ▃▅ 42%/67% 2h15m" 形式のプレーンテキスト
#   最後のフィールドは five_hour セッションが切れるまでの残り時間
#
# キャッシュ形式: "<five_hour_pct>|<seven_day_pct>|<five_hour_resets_at_iso>"
# 残り時間はキャッシュ読み出し時に現在時刻から都度計算する

CACHE_FILE="/tmp/tmux_claude_usage"
CACHE_TTL=300  # 5分

# クロスプラットフォーム mtime 取得
get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# "<s>|<w>|<resets_at>" を受け取り表示文字列を出力
render() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
from datetime import datetime, timezone
try:
  s = int(sys.argv[1])
  w = int(sys.argv[2])
  resets_at = sys.argv[3]
  bars = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
  sb = bars[s * 8 // 100] if s < 100 else bars[8]
  wb = bars[w * 8 // 100] if w < 100 else bars[8]
  remaining = ''
  if resets_at:
    try:
      reset_dt = datetime.fromisoformat(resets_at)
      now = datetime.now(timezone.utc)
      delta = int((reset_dt - now).total_seconds())
      if delta <= 0:
        remaining = ' 0m'
      else:
        total_min = delta // 60
        h, m = divmod(total_min, 60)
        remaining = f' {h}h{m:02d}m' if h > 0 else f' {m}m'
    except Exception:
      pass
  print(f'󰧑 {sb}{wb} {s}%/{w}%{remaining}')
except Exception:
  print('󰧑 --')
PY
}

# キャッシュが有効なら値を読んで表示時に残り時間を再計算
if [[ -f "$CACHE_FILE" ]]; then
  age=$(( $(date +%s) - $(get_mtime "$CACHE_FILE") ))
  if (( age < CACHE_TTL )); then
    IFS='|' read -r cs cw cresets < "$CACHE_FILE" 2>/dev/null
    if [[ -n "$cs" && -n "$cw" ]]; then
      render "$cs" "$cw" "${cresets:-}"
      exit 0
    fi
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
raw=$(curl -sf --max-time 5 \
  -H "Authorization: Bearer $token" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

if [[ -z "$raw" ]]; then
  echo "󰧑 --"
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  s = max(0, min(100, round(d['five_hour']['utilization'])))
  w = max(0, min(100, round(d['seven_day']['utilization'])))
  r = d['five_hour'].get('resets_at') or ''
  print(f'{s}|{w}|{r}')
except Exception:
  print('')
" 2>/dev/null)

if [[ -z "$parsed" ]]; then
  echo "󰧑 --"
  exit 0
fi

echo "$parsed" > "$CACHE_FILE"
IFS='|' read -r s w resets_at <<< "$parsed"
render "$s" "$w" "$resets_at"
