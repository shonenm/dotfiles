#!/bin/bash
# Codex (OpenAI) 使用量表示 (tmux status-right 用)
# ~/.codex/auth.json の OAuth トークンで使用量を取得しキャッシュ
# 出力: "OAI ▃▅ 42%/67% 2h15m" 形式のプレーンテキスト
#   最後のフィールドは primary_window がリセットされるまでの残り時間
#
# キャッシュ形式: "<primary_pct>|<secondary_pct>|<primary_resets_at_unix>"
# 残り時間はキャッシュ読み出し時に現在時刻から都度計算する

CACHE_FILE="/tmp/tmux_codex_usage"
CACHE_TTL=300  # 5分
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60    # API 失敗時のバックオフ秒数

AUTH_FILE="$HOME/.codex/auth.json"
LABEL="OAI"

# クロスプラットフォーム mtime 取得
get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# "<s>|<w>|<resets_at_unix>" を受け取り表示文字列を出力
render() {
  python3 - "$1" "$2" "$3" "$LABEL" <<'PY'
import sys
from datetime import datetime, timezone
label = sys.argv[4] if len(sys.argv) > 4 else 'OAI'
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
      reset_ts = int(resets_at)
      now_ts = int(datetime.now(timezone.utc).timestamp())
      delta = reset_ts - now_ts
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

# キャッシュ有効なら値を読んで表示時に残り時間を再計算
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

# 直近で API 取得に失敗していたら再試行せず placeholder を返す
if [[ -f "$FAIL_FILE" ]]; then
  fail_age=$(( $(date +%s) - $(get_mtime "$FAIL_FILE") ))
  if (( fail_age < FAIL_TTL )); then
    echo "$LABEL --"
    exit 0
  fi
fi

# auth.json は Mac/Linux 共通でプレーンテキスト保存（macOS Keychain は使わない）
if [[ ! -f "$AUTH_FILE" ]]; then
  touch "$FAIL_FILE"
  echo "$LABEL --"
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
  echo "$LABEL --"
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
  echo "$LABEL --"
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  rl = d.get('rate_limit') or {}
  pw = rl.get('primary_window') or {}
  sw = rl.get('secondary_window') or {}
  s = int(round(pw.get('used_percent') or 0))
  w = int(round(sw.get('used_percent') or 0))
  s = max(0, min(100, s))
  w = max(0, min(100, w))
  r = pw.get('reset_at')
  r_str = str(int(r)) if r is not None else ''
  print(f'{s}|{w}|{r_str}')
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
