#!/bin/bash
# Codex (OpenAI) 使用量表示 (tmux status-right 用)
# ~/.codex/auth.json の OAuth トークンで使用量を取得しキャッシュ
# 出力: サイドバー用の構造化レコード(1行=1ウィンドウ、区切りは US 0x1f)
#   "<icon>\x1f<label>\x1f<gauge>\x1f<pct>\x1f<remaining>" (current=primary / weekly=secondary)
#   データ無しは "<icon>\x1f--"
#
# キャッシュ形式: "<primary_pct>|<secondary_pct>|<primary_resets_unix>|<secondary_resets_unix>"
# 残り時間はキャッシュ読み出し時に現在時刻から都度計算する

CACHE_FILE="/tmp/tmux_codex_usage"
CACHE_TTL=300  # 5分
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60    # API 失敗時のバックオフ秒数

AUTH_FILE="$HOME/.codex/auth.json"
LABEL="󰝨"

# データ無しレコードを出力
na() { printf '%s\x1f--\n' "$LABEL"; }

# クロスプラットフォーム mtime 取得
get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# "<s>|<w>|<primary_resets_unix>|<secondary_resets_unix>" を受け取り2レコード出力
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
def remain(ts):
  if not ts: return ''
  try:
    delta = int(ts) - int(datetime.now(timezone.utc).timestamp())
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
  rp = sys.argv[4]; rsec = sys.argv[5]
  print(US.join([icon, 'current', bar(s), f'{s}%', remain(rp)]))
  print(US.join([icon, 'weekly',  bar(w), f'{w}%', remain(rsec)]))
except Exception:
  print(f'{icon}{US}--')
PY
}

# キャッシュ有効なら値を読んで表示時に残り時間を再計算
if [[ -f "$CACHE_FILE" ]]; then
  age=$(( $(date +%s) - $(get_mtime "$CACHE_FILE") ))
  if (( age < CACHE_TTL )); then
    IFS='|' read -r cs cw crp crsec < "$CACHE_FILE" 2>/dev/null
    if [[ -n "$cs" && -n "$cw" ]]; then
      render "$cs" "$cw" "${crp:-}" "${crsec:-}"
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

# auth.json は Mac/Linux 共通でプレーンテキスト保存（macOS Keychain は使わない）
if [[ ! -f "$AUTH_FILE" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

# access_token と account_id を取り出す
# account_id は tokens.account_id を優先、無ければ id_token JWT のクレームから抽出
read -r token account_id < <(python3 - "$AUTH_FILE" <<'PY'
import json, base64, sys
try:
  with open(sys.argv[1]) as f:
    d = json.load(f)
  tokens = d.get('tokens') or {}
  access = tokens.get('access_token') or ''
  acc = tokens.get('account_id') or d.get('account_id') or ''
  if not acc:
    idt = tokens.get('id_token') or ''
    parts = idt.split('.')
    if len(parts) >= 2:
      pad = '=' * (-len(parts[1]) % 4)
      try:
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + pad))
        auth_claim = payload.get('https://api.openai.com/auth') or {}
        acc = auth_claim.get('chatgpt_account_id') or ''
      except Exception:
        pass
  print(f'{access} {acc}')
except Exception:
  print(' ')
PY
)

if [[ -z "$token" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

# 使用量を取得 (ChatGPT login の wham/usage エンドポイント)
curl_args=(
  -sf --max-time 5
  -H "Authorization: Bearer $token"
  -H "User-Agent: codex-cli"
)
if [[ -n "$account_id" ]]; then
  curl_args+=(-H "ChatGPT-Account-Id: $account_id")
fi

raw=$(curl "${curl_args[@]}" "https://chatgpt.com/backend-api/wham/usage" 2>/dev/null)

if [[ -z "$raw" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
def ts(v):
  return str(int(v)) if v is not None else ''
try:
  d = json.load(sys.stdin)
  rl = d.get('rate_limit') or {}
  pw = rl.get('primary_window') or {}
  sw = rl.get('secondary_window') or {}
  s = int(round(pw.get('used_percent') or 0))
  w = int(round(sw.get('used_percent') or 0))
  s = max(0, min(100, s))
  w = max(0, min(100, w))
  rp = ts(pw.get('reset_at'))
  rsec = ts(sw.get('reset_at'))
  print(f'{s}|{w}|{rp}|{rsec}')
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
IFS='|' read -r s w rp rsec <<< "$parsed"
render "$s" "$w" "$rp" "$rsec"
