#!/bin/bash
# Codex (OpenAI) 使用量表示 (tmux status-right 用)
# ~/.codex/auth.json の OAuth トークンで使用量を取得しキャッシュ
# 出力: サイドバー用の構造化レコード(1行=1ウィンドウ、区切りは US 0x1f)
#   "<icon>\x1f<label>\x1f<gauge>\x1f<pct>\x1f<remaining>" (current=短期 window / weekly=週次 window)
#   データ無しは "<icon>\x1f--"
#
# キャッシュ形式: "v2|<current_pct>|<weekly_pct>|<current_resets_unix>|<weekly_resets_unix>"
# 残り時間はキャッシュ読み出し時に現在時刻から都度計算する

CACHE_FILE="${CODEX_USAGE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux/codex_usage}"
CACHE_TTL=300  # 5分
FAIL_FILE="${CACHE_FILE}.fail"
FAIL_TTL=60    # API 失敗時のバックオフ秒数

AUTH_FILE="${CODEX_AUTH_FILE:-$HOME/.codex/auth.json}"
REFRESH_URL="${CODEX_REFRESH_URL:-https://auth.openai.com/oauth/token}"
USAGE_URL="${CODEX_USAGE_URL:-https://chatgpt.com/backend-api/wham/usage}"
CLIENT_ID="${CODEX_CLIENT_ID:-app_EMoamEEZ73f0CkXaXp7hrann}"
LABEL="󰝨"

mkdir -p "$(dirname "$CACHE_FILE")"

# データ無しレコードを出力
na() { printf '%s\x1f--\n' "$LABEL"; }

# クロスプラットフォーム mtime 取得
get_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
  esac
}

# "<current>|<weekly>|<current_resets_unix>|<weekly_resets_unix>" を受け取り2レコード出力
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
    IFS='|' read -r ver cs cw crp crsec < "$CACHE_FILE" 2>/dev/null
    if [[ "$ver" == "v2" && -n "$cs" && -n "$cw" ]]; then
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

# access_token / account_id / refresh_token / exp を取り出す
# account_id は tokens.account_id を優先、無ければ id_token JWT のクレームから抽出
read_auth() {
  python3 - "$AUTH_FILE" <<'PY'
import json, base64, sys

def jwt_payload(jwt):
  parts = (jwt or '').split('.')
  if len(parts) < 2:
    return {}
  try:
    return json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
  except Exception:
    return {}

def account_id(tokens, d):
  acc = tokens.get('account_id') or d.get('account_id') or ''
  if acc:
    return acc
  auth_claim = jwt_payload(tokens.get('id_token') or '').get('https://api.openai.com/auth') or {}
  return auth_claim.get('chatgpt_account_id') or ''

try:
  with open(sys.argv[1]) as f:
    d = json.load(f)
  tokens = d.get('tokens') or {}
  access = tokens.get('access_token') or ''
  print('\t'.join([
    access,
    account_id(tokens, d),
    tokens.get('refresh_token') or '',
    str(jwt_payload(access).get('exp') or ''),
  ]))
except Exception:
  print('\t\t\t')
PY
}

# Codex CLI と同じ refresh-token flow。期限切れ access_token を使い続けると usage が 401 で落ちる。
refresh_auth() {
  python3 - "$AUTH_FILE" "${CACHE_FILE}.refresh.lock" "$CLIENT_ID" "$REFRESH_URL" <<'PY'
import base64, datetime as dt, fcntl, json, os, sys, time, urllib.error, urllib.request

auth_file, lock_file, client_id, refresh_url = sys.argv[1:]

def jwt_payload(jwt):
  parts = (jwt or '').split('.')
  if len(parts) < 2:
    return {}
  try:
    return json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
  except Exception:
    return {}

def account_id(tokens, d):
  acc = tokens.get('account_id') or d.get('account_id') or ''
  if acc:
    return acc
  auth_claim = jwt_payload(tokens.get('id_token') or '').get('https://api.openai.com/auth') or {}
  return auth_claim.get('chatgpt_account_id') or ''

def load():
  with open(auth_file) as f:
    return json.load(f)

try:
  os.makedirs(os.path.dirname(lock_file), exist_ok=True)
  with open(lock_file, 'w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    d = load()
    tokens = d.get('tokens') or {}
    access = tokens.get('access_token') or ''
    acc = account_id(tokens, d)
    exp = int(jwt_payload(access).get('exp') or 0)
    if access and exp > int(time.time()) + 60:
      print(f'{access}\t{acc}')
      raise SystemExit(0)

    refresh = tokens.get('refresh_token') or ''
    if not refresh:
      raise SystemExit(1)

    body = json.dumps({
      'client_id': client_id,
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    }).encode()
    req = urllib.request.Request(refresh_url, data=body, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=10) as res:
      r = json.load(res)

    new_access = r.get('access_token') or access
    new_refresh = r.get('refresh_token') or refresh
    new_id = r.get('id_token') or tokens.get('id_token') or ''
    tokens.update(access_token=new_access, refresh_token=new_refresh)
    if new_id:
      tokens['id_token'] = new_id
    new_acc = account_id(tokens, d)
    if new_acc:
      tokens['account_id'] = new_acc
    d['tokens'] = tokens
    d['last_refresh'] = dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00', 'Z')

    tmp = f'{auth_file}.tmp.{os.getpid()}'
    with open(tmp, 'w') as f:
      json.dump(d, f, indent=2)
      f.write('\n')
    try:
      os.chmod(tmp, os.stat(auth_file).st_mode & 0o777)
    except OSError:
      pass
    os.replace(tmp, auth_file)
    print(f'{new_access}\t{new_acc}')
except (urllib.error.HTTPError, urllib.error.URLError, OSError, ValueError, json.JSONDecodeError):
  raise SystemExit(1)
PY
}

IFS=$'\t' read -r token account_id refresh_token access_exp < <(read_auth)

refresh_attempted=0
now=$(date +%s)
if [[ -n "$refresh_token" && ( -z "$token" || ( -n "$access_exp" && "$access_exp" =~ ^[0-9]+$ && $access_exp -le $((now + 60)) ) ) ]]; then
  refresh_attempted=1
  if IFS=$'\t' read -r token account_id < <(refresh_auth); [[ -z "$token" ]]; then
    touch "$FAIL_FILE"
    na
    exit 0
  fi
fi

if [[ -z "$token" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

fetch_usage() {
  local -a curl_args=(
    -sf --max-time 5
    -H "Authorization: Bearer $token"
    -H "User-Agent: codex-cli"
  )
  if [[ -n "$account_id" ]]; then
    curl_args+=(-H "ChatGPT-Account-Id: $account_id")
  fi
  curl "${curl_args[@]}" "$USAGE_URL" 2>/dev/null
}

# 使用量を取得 (ChatGPT login の wham/usage エンドポイント)
raw=$(fetch_usage)

# access_token がサーバ側で無効化済みでも、refresh_token が生きていれば1回だけ復旧する。
if [[ -z "$raw" && -n "$refresh_token" && "$refresh_attempted" == 0 ]]; then
  refresh_attempted=1
  if IFS=$'\t' read -r token account_id < <(refresh_auth); [[ -n "$token" ]]; then
    raw=$(fetch_usage)
  fi
fi

if [[ -z "$raw" ]]; then
  touch "$FAIL_FILE"
  na
  exit 0
fi

parsed=$(echo "$raw" | python3 -c "
import sys, json
WEEK = 7 * 24 * 60 * 60

def ts(v):
  return str(int(v)) if v is not None else ''
def pct(w):
  return max(0, min(100, int(round(w.get('used_percent') or 0))))
def is_weekly(w):
  sec = int(w.get('limit_window_seconds') or 0)
  return WEEK * 0.95 <= sec <= WEEK * 1.05
def pick(windows):
  weekly = next((w for w in windows if is_weekly(w)), None)
  current = next((w for w in windows if not is_weekly(w)), None)
  # 古い/未知 payload では従来通り primary=current, secondary=weekly にフォールバック。
  if current is None and windows:
    current = windows[0]
  if weekly is None and len(windows) > 1:
    weekly = windows[1]
  return current or {}, weekly or {}
try:
  d = json.load(sys.stdin)
  rl = d.get('rate_limit') or {}
  windows = [w for w in (rl.get('primary_window') or {}, rl.get('secondary_window') or {}) if w]
  current, weekly = pick(windows)
  print('v2|{}|{}|{}|{}'.format(
    pct(current), pct(weekly), ts(current.get('reset_at')), ts(weekly.get('reset_at'))
  ))
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
IFS='|' read -r _ver s w rp rsec <<< "$parsed"
render "$s" "$w" "$rp" "$rsec"
