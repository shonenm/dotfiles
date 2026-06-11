#!/bin/bash
# Cursor Agent 使用量表示 (tmux status-right 用)
# cursor-agent OAuth トークンで api2.cursor.sh から取得しキャッシュ
# 出力: "◆ ▃▅ 20%/3% 12d" 形式 (total% / auto% + 請求周期終了まで)
#
# キャッシュ形式: "<total_pct>|<auto_pct>|<billing_cycle_end_ms>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CACHE_FILE="/tmp/tmux_cursor_usage"
CACHE_TTL=300
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60
LABEL="◆"
API_BASE="${CURSOR_API_BASE:-https://api2.cursor.sh}"

get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

render() {
  python3 - "$1" "$2" "$3" "$LABEL" <<'PY'
import sys
from datetime import datetime, timezone

label = sys.argv[4] if len(sys.argv) > 4 else "◆"
try:
    s = int(sys.argv[1])
    w = int(sys.argv[2])
    resets_at = sys.argv[3]
    bars = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    # 0%は空白、それ以外は最低でも▁を表示(低%でゲージが不可視になるのを防ぐ)
    def bar(v):
        if v <= 0:
            return bars[0]
        if v >= 100:
            return bars[8]
        return bars[max(1, v * 8 // 100)]
    sb = bar(s)
    wb = bar(w)
    remaining = ""
    if resets_at:
        try:
            reset_ts = int(resets_at)
            if reset_ts > 10_000_000_000:
                reset_ts //= 1000
            now_ts = int(datetime.now(timezone.utc).timestamp())
            delta = reset_ts - now_ts
            if delta <= 0:
                remaining = " 0m"
            else:
                total_min = delta // 60
                h, m = divmod(total_min, 60)
                if h >= 24:
                    d, h = divmod(h, 24)
                    remaining = f" {d}d" if d > 0 else f" {h}h{m:02d}m"
                elif h > 0:
                    remaining = f" {h}h{m:02d}m"
                else:
                    remaining = f" {m}m"
        except Exception:
            pass
    print(f"{label} {sb}{wb} {s}%/{w}%{remaining}")
except Exception:
    print(f"{label} --")
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
    echo "$LABEL --"
    exit 0
  fi
fi

token=$("$SCRIPT_DIR/cursor-auth-token.sh" 2>/dev/null) || {
  touch "$FAIL_FILE"
  echo "$LABEL --"
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
  echo "$LABEL --"
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  pu = d.get('planUsage') or {}
  if pu:
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
  echo "$LABEL --"
  exit 0
fi

echo "$parsed" > "$CACHE_FILE"
rm -f "$FAIL_FILE"
IFS='|' read -r s w resets_at <<< "$parsed"
render "$s" "$w" "$resets_at"
