#!/bin/bash
# Cursor Agent 使用量表示 (tmux status-right 用)
# cursor-agent OAuth トークンで api2.cursor.sh から取得しキャッシュ
# 出力: サイドバー用の構造化レコード(1行=1ウィンドウ、区切りは US 0x1f)
#   "<icon>\x1f<label>\x1f<gauge>\x1f<pct>\x1f<remaining>" (total / auto、いずれも請求周期末まで)
#   データ無しは "<icon>\x1f--"
#
# キャッシュ形式: "<total_pct>|<auto_pct>|<billing_cycle_end_ms>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CACHE_FILE="/tmp/tmux_cursor_usage"
CACHE_TTL=300
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60
LABEL="◆"
API_BASE="${CURSOR_API_BASE:-https://api2.cursor.sh}"

# データ無しレコードを出力
na() { printf '%s\x1f--\n' "$LABEL"; }

get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# "<total>|<auto>|<billing_end_ms>" を受け取り2レコード出力(total / auto)
render() {
  python3 - "$LABEL" "$1" "$2" "$3" <<'PY'
import sys
from datetime import datetime, timezone
US = "\x1f"
icon = sys.argv[1]
bars = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
# 0%は空白、それ以外は最低でも▁を表示(低%でゲージが不可視になるのを防ぐ)
def bar(v):
    if v <= 0:
        return bars[0]
    if v >= 100:
        return bars[8]
    return bars[max(1, v * 8 // 100)]
def remain(ts):
    if not ts:
        return ""
    try:
        reset_ts = int(ts)
        if reset_ts > 10_000_000_000:
            reset_ts //= 1000
        delta = reset_ts - int(datetime.now(timezone.utc).timestamp())
        if delta <= 0:
            return "0m"
        total_min = delta // 60
        h, m = divmod(total_min, 60)
        if h >= 24:
            d, h = divmod(h, 24)
            return f"{d}d{h}h"
        return f"{h}h{m:02d}m" if h > 0 else f"{m}m"
    except Exception:
        return ""
try:
    s = int(sys.argv[2]); w = int(sys.argv[3])
    rem = remain(sys.argv[4])
    print(US.join([icon, "total", bar(s), f"{s}%", rem]))
    print(US.join([icon, "auto",  bar(w), f"{w}%", rem]))
except Exception:
    print(f"{icon}{US}--")
PY
}

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

if [[ -f "$FAIL_FILE" ]]; then
  fail_age=$(( $(date +%s) - $(get_mtime "$FAIL_FILE") ))
  if (( fail_age < FAIL_TTL )); then
    na
    exit 0
  fi
fi

token=$("$SCRIPT_DIR/cursor-auth-token.sh" 2>/dev/null) || {
  touch "$FAIL_FILE"
  na
  exit 0
}

raw=$(
  curl -sf --max-time 5 \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Connect-Protocol-Version: 1" \
    -d '{}' \
    "${API_BASE}/aiserver.v1.DashboardService/GetCurrentPeriodUsage" 2>/dev/null
)

if [[ -z "$raw" ]]; then
  raw=$(curl -sf --max-time 5 \
    -H "Authorization: Bearer $token" \
    "${API_BASE}/auth/usage" 2>/dev/null)
fi

if [[ -z "$raw" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  pu = d.get('planUsage') or {}
  if pu:
    # total = included 枠の消化率(Cursor UI の 'X% of your included usage' と一致)。
    # includedSpend/limit を優先し、無ければ totalPercentUsed にフォールバック。
    limit = float(pu.get('limit') or 0)
    spend = float(pu.get('includedSpend') or pu.get('totalSpend') or 0)
    if limit > 0:
      s = int(round(spend * 100 / limit))
    else:
      s = int(round(float(pu.get('totalPercentUsed') or 0)))
    w = int(round(float(pu.get('autoPercentUsed') or pu.get('apiPercentUsed') or 0)))
    s = max(0, min(100, s))
    w = max(0, min(100, w))
    r = d.get('billingCycleEnd') or ''
    print(f'{s}|{w}|{r}')
    raise SystemExit(0)

  # Enterprise-style /auth/usage fallback
  best = None
  for key, bucket in d.items():
    if not isinstance(bucket, dict):
      continue
    max_u = bucket.get('maxRequestUsage')
    num = bucket.get('numRequestsTotal') or bucket.get('numRequests') or 0
    if max_u in (None, 0):
      continue
    used = int(round(num * 100 / max_u))
    if best is None or used > best[0]:
      best = (used, used, '')
  if best:
    print(f'{best[0]}|{best[1]}|{best[2]}')
  else:
    print('')
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
IFS='|' read -r s w resets_at <<< "$parsed"
render "$s" "$w" "$resets_at"
