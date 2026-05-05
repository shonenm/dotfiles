#!/bin/bash
# Gemini CLI 使用量表示 (tmux status-right 用)
# ~/.gemini/oauth_creds.json の Google OAuth トークンで Code Assist quota を取得
# 出力例: "󰫢 ▄▆ 50%/75% 18h22m" (top2 most-used buckets / 最も早いリセット残り時間)
#
# キャッシュ形式: "<used1_pct>|<used2_pct>|<reset_time_iso>"

CACHE_FILE="/tmp/tmux_gemini_usage"
CACHE_TTL=300
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60

CREDS_FILE="$HOME/.gemini/oauth_creds.json"
PROJECTS_FILE="$HOME/.gemini/projects.json"
LABEL="󰫢"

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
label = sys.argv[4] if len(sys.argv) > 4 else ''
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
      reset_dt = datetime.fromisoformat(resets_at.replace('Z', '+00:00'))
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
  print(f'{label} {sb}{wb} {s}%/{w}%{remaining}')
except Exception:
  print(f'{label} --')
PY
}

# キャッシュ
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

# 失敗バックオフ
if [[ -f "$FAIL_FILE" ]]; then
  fail_age=$(( $(date +%s) - $(get_mtime "$FAIL_FILE") ))
  if (( fail_age < FAIL_TTL )); then
    echo "$LABEL --"
    exit 0
  fi
fi

[[ -f "$CREDS_FILE" ]] || { touch "$FAIL_FILE"; echo "$LABEL --"; exit 0; }

# access_token / expiry_date を読む。
# 期限切れトークンは gemini CLI を一度起動すれば自動リフレッシュされる。
# このスクリプトは常駐 polling のため OAuth client secret を持たず、refresh はしない。
read -r access_token expiry_date < <(python3 - "$CREDS_FILE" <<'PY'
import json, sys
try:
  with open(sys.argv[1]) as f:
    d = json.load(f)
  at = d.get('access_token') or ''
  ex = d.get('expiry_date') or 0
  print(f'{at} {ex}')
except Exception:
  print(' 0')
PY
)

if [[ -z "$access_token" ]]; then
  touch "$FAIL_FILE"
  echo "$LABEL --"
  exit 0
fi

# expiry_date は ms epoch。期限切れなら placeholder (CLI 再起動を促す)
now_ms=$(( $(date +%s) * 1000 ))
if [[ -n "$expiry_date" && "$expiry_date" =~ ^[0-9]+$ ]] && (( expiry_date < now_ms )); then
  touch "$FAIL_FILE"
  echo "$LABEL --"
  exit 0
fi

# project ID 解決: GOOGLE_CLOUD_PROJECT > projects.json の最初のエントリ
project_id="${GOOGLE_CLOUD_PROJECT:-}"
if [[ -z "$project_id" && -f "$PROJECTS_FILE" ]]; then
  project_id=$(python3 -c "
import json
try:
  with open('$PROJECTS_FILE') as f:
    d = json.load(f)
  if isinstance(d, dict):
    for v in d.values():
      if isinstance(v, str) and v:
        print(v); break
      if isinstance(v, dict):
        p = v.get('project') or v.get('projectId') or v.get('cloudaicompanionProject') or ''
        if p:
          print(p); break
except Exception:
  pass
" 2>/dev/null)
fi

# project が空でも free-tier では POST 受理されることがある — 空文字で渡す
raw=$(curl -sf --max-time 5 \
  -X POST \
  -H "Authorization: Bearer $access_token" \
  -H "Content-Type: application/json" \
  -d "{\"project\":\"${project_id}\"}" \
  "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota" 2>/dev/null)

if [[ -z "$raw" ]]; then
  touch "$FAIL_FILE"
  echo "$LABEL --"
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  buckets = d.get('buckets') or []
  if not buckets:
    print(''); raise SystemExit(0)
  scored = []
  for b in buckets:
    rf = b.get('remainingFraction')
    if rf is None: continue
    used = max(0.0, min(1.0, 1.0 - float(rf)))
    scored.append((used, b.get('resetTime') or '', b))
  if not scored:
    print(''); raise SystemExit(0)
  scored.sort(key=lambda x: x[0], reverse=True)
  s = int(round(scored[0][0] * 100))
  w = int(round(scored[1][0] * 100)) if len(scored) > 1 else s
  # 最も早いリセット時刻
  reset_candidates = [r for _, r, _ in scored if r]
  r = min(reset_candidates) if reset_candidates else ''
  print(f'{s}|{w}|{r}')
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
