#!/bin/bash
# Gemini CLI 使用量表示 (tmux status-right 用)
# ~/.gemini/oauth_creds.json の Google OAuth トークンで Code Assist quota を取得
# 出力: サイドバー用の構造化レコード(1行=1ウィンドウ、区切りは US 0x1f)
#   "<icon>\x1f<label>\x1f<gauge>\x1f<pct>\x1f<remaining>" (top2 most-used buckets を current/weekly)
#   データ無しは "<icon>\x1f--"
#
# キャッシュ形式: "<used1_pct>|<used2_pct>|<reset1_iso>|<reset2_iso>"

CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/gemini_usage"
CACHE_TTL=300
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60

CREDS_FILE="$HOME/.gemini/oauth_creds.json"
PROJECTS_FILE="$HOME/.gemini/projects.json"
LABEL="󰫢"

mkdir -p "$(dirname "$CACHE_FILE")"

# データ無しレコードを出力
na() { printf '%s\x1f--\n' "$LABEL"; }

get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# "<s>|<w>|<reset1_iso>|<reset2_iso>" を受け取り2レコード出力
render() {
  python3 - "$LABEL" "$1" "$2" "$3" "$4" <<'PY'
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
    reset_dt = datetime.fromisoformat(iso.replace('Z', '+00:00'))
    delta = int((reset_dt - datetime.now(timezone.utc)).total_seconds())
    if delta <= 0: return '0m'
    total_min = delta // 60
    h, m = divmod(total_min, 60)
    if h >= 24:
      d, h = divmod(h, 24)
      return f'{d}d{h}h'
    return f'{h}h{m:02d}m' if h > 0 else f'{m}m'
  except Exception:
    return ''
try:
  s = int(sys.argv[2]); w = int(sys.argv[3])
  r1 = sys.argv[4]; r2 = sys.argv[5]
  print(US.join([icon, 'current', bar(s), f'{s}%', remain(r1)]))
  print(US.join([icon, 'weekly',  bar(w), f'{w}%', remain(r2)]))
except Exception:
  print(f'{icon}{US}--')
PY
}

# キャッシュ
if [[ -f "$CACHE_FILE" ]]; then
  age=$(( $(date +%s) - $(get_mtime "$CACHE_FILE") ))
  if (( age < CACHE_TTL )); then
    IFS='|' read -r cs cw cr1 cr2 < "$CACHE_FILE" 2>/dev/null
    if [[ -n "$cs" && -n "$cw" ]]; then
      render "$cs" "$cw" "${cr1:-}" "${cr2:-}"
      exit 0
    fi
  fi
fi

# 失敗バックオフ
if [[ -f "$FAIL_FILE" ]]; then
  fail_age=$(( $(date +%s) - $(get_mtime "$FAIL_FILE") ))
  if (( fail_age < FAIL_TTL )); then
    na
    exit 0
  fi
fi

[[ -f "$CREDS_FILE" ]] || { touch "$FAIL_FILE"; na; exit 0; }

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
  na
  exit 0
fi

# expiry_date は ms epoch。期限切れなら placeholder (CLI 再起動を促す)
now_ms=$(( $(date +%s) * 1000 ))
if [[ -n "$expiry_date" && "$expiry_date" =~ ^[0-9]+$ ]] && (( expiry_date < now_ms )); then
  touch "$FAIL_FILE"
  na
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
  na
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
  r1 = scored[0][1] or ''
  if len(scored) > 1:
    w = int(round(scored[1][0] * 100)); r2 = scored[1][1] or ''
  else:
    w = s; r2 = r1
  print(f'{s}|{w}|{r1}|{r2}')
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
IFS='|' read -r s w r1 r2 <<< "$parsed"
render "$s" "$w" "$r1" "$r2"
