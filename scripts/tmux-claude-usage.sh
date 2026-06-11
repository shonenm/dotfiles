#!/bin/bash
# Claude Code 使用量表示 (tmux status-right 用)
# OAuth トークンで使用量を取得しキャッシュ
# macOS: Keychain, Linux: ~/.claude/.credentials.json
# 出力: サイドバー用の構造化レコード(1行=1ウィンドウ、区切りは US 0x1f)
#   "<icon>\x1f<label>\x1f<gauge>\x1f<pct>\x1f<remaining>"  (current=five_hour / weekly=seven_day)
#   データ無しは "<icon>\x1f--"
#
# キャッシュ形式: "<five_hour_pct>|<seven_day_pct>|<five_hour_resets_iso>|<seven_day_resets_iso>"
# 残り時間はキャッシュ読み出し時に現在時刻から都度計算する

CACHE_FILE="/tmp/tmux_claude_usage"
CACHE_TTL=300  # 5分
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60    # API 失敗時のバックオフ秒数（tmux 再描画ごとの再試行を防ぐ）
ICON="󰛄"

# データ無しレコードを出力
na() { printf '%s\x1f--\n' "$ICON"; }

# クロスプラットフォーム mtime 取得
get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# "<s>|<w>|<five_resets_iso>|<seven_resets_iso>" を受け取り2レコード出力
render() {
  python3 - "$ICON" "$1" "$2" "$3" "$4" <<'PY'
import sys
from datetime import datetime, timezone
US = '\x1f'
icon = sys.argv[1]
bars = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
def bar(v):
  if v <= 0: return bars[0]
  if v >= 100: return bars[8]
  return bars[max(1, v * 8 // 100)]
def remain(iso):
  if not iso: return ''
  try:
    delta = int((datetime.fromisoformat(iso) - datetime.now(timezone.utc)).total_seconds())
    if delta <= 0: return '0m'
    total_min = delta // 60
    h, m = divmod(total_min, 60)
    if h >= 24:
      d, h = divmod(h, 24)
      return f'{d}d'
    return f'{h}h{m:02d}m' if h > 0 else f'{m}m'
  except Exception:
    return ''
try:
  s = int(sys.argv[2]); w = int(sys.argv[3])
  r5 = sys.argv[4]; r7 = sys.argv[5]
  print(US.join([icon, 'current', bar(s), f'{s}%', remain(r5)]))
  print(US.join([icon, 'weekly',  bar(w), f'{w}%', remain(r7)]))
except Exception:
  print(f'{icon}{US}--')
PY
}

# キャッシュが有効なら値を読んで表示時に残り時間を再計算
if [[ -f "$CACHE_FILE" ]]; then
  age=$(( $(date +%s) - $(get_mtime "$CACHE_FILE") ))
  if (( age < CACHE_TTL )); then
    IFS='|' read -r cs cw cr5 cr7 < "$CACHE_FILE" 2>/dev/null
    if [[ -n "$cs" && -n "$cw" ]]; then
      render "$cs" "$cw" "${cr5:-}" "${cr7:-}"
      exit 0
    fi
  fi
fi

# 直近で API 取得に失敗していたら再試行せず placeholder を返す
if [[ -f "$FAIL_FILE" ]]; then
  fail_age=$(( $(date +%s) - $(get_mtime "$FAIL_FILE") ))
  if (( fail_age < FAIL_TTL )); then
    na
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
if [[ -z "$token" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

# 使用量を取得
raw=$(curl -sf --max-time 5 \
  -H "Authorization: Bearer $token" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

if [[ -z "$raw" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  s = max(0, min(100, round(d['five_hour']['utilization'])))
  w = max(0, min(100, round(d['seven_day']['utilization'])))
  r5 = d['five_hour'].get('resets_at') or ''
  r7 = d['seven_day'].get('resets_at') or ''
  print(f'{s}|{w}|{r5}|{r7}')
except Exception:
  print('')
" 2>/dev/null)

if [[ -z "$parsed" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

echo "$parsed" > "$CACHE_FILE"
rm -f "$FAIL_FILE"
IFS='|' read -r s w r5 r7 <<< "$parsed"
render "$s" "$w" "$r5" "$r7"
