#!/bin/bash
# AI CLI Slack Notification Script
# Usage: ai-notify.sh <tool> <event>
#        ai-notify.sh --clear-cache
# tool: claude | codex | gemini
# event: stop | complete | permission | idle | error

set -euo pipefail

# キャッシュディレクトリ
CACHE_DIR="${HOME}/.cache/ai-notify"

# --clear-cache オプション
if [[ "${1:-}" == "--clear-cache" ]]; then
  rm -rf "$CACHE_DIR"
  echo "Cache cleared: $CACHE_DIR"
  exit 0
fi

TOOL="${1:-claude}"
EVENT="${2:-notification}"

# デバッグログ
DEBUG_LOG="${CACHE_DIR}/debug.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') TOOL=$TOOL EVENT=$EVENT ARGS=$* \$0=$0 \$#=$# ALL_ARGS=[$@]" >> "$DEBUG_LOG"

# 1. 依存チェック (jq がない場合は何もしない)
if ! command -v jq &> /dev/null; then
  exit 0
fi

mkdir -p "$CACHE_DIR"

# Webhook URL取得関数（キャッシュ優先、なければ1Passwordから取得してキャッシュ）
get_webhook() {
  local tool="$1"
  local cache_file="${CACHE_DIR}/${tool}_webhook"

  # キャッシュがあればそれを使用
  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
    return
  fi

  # 1Password CLIがなければ空を返す
  if ! command -v op &> /dev/null; then
    return
  fi

  # 1Passwordから取得してキャッシュ
  local op_path
  case "$tool" in
    claude) op_path="op://Personal/Claude Webhook/password" ;;
    codex)  op_path="op://Personal/Codex Webhook/password" ;;
    gemini) op_path="op://Personal/Gemini Webhook/password" ;;
    *)      return ;;
  esac

  local webhook
  webhook=$(op read "$op_path" 2>/dev/null) || return
  [[ -n "$webhook" ]] && echo "$webhook" > "$cache_file" && chmod 600 "$cache_file"
  echo "$webhook"
}

# 2. 非同期実行のためにサブシェル化
(
  # stdin から JSON 読み取り (タイムアウト付きでブロック回避)
  if [ -t 0 ]; then
    INPUT="{}"
  else
    INPUT=$(timeout 1 cat 2>/dev/null || echo "{}")
  fi

  # Webhook URL取得（キャッシュ優先）
  WEBHOOK=$(get_webhook "$TOOL")
  [[ -z "$WEBHOOK" ]] && exit 0

  # JSON から情報抽出
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  [[ -z "$CWD" ]] && CWD=$(pwd)
  PROJECT=$(basename "$CWD")
  DEVICE=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")

  # イベントに応じてメンションと色を使い分ける
  case "$EVENT" in
    # 即対応が必要（メンションあり → プッシュ通知）
    permission) ICON="🔐"; TITLE="承認待ち"; COLOR="#ffc107"; MENTION="<!here>" ;;
    idle)       ICON="⏳"; TITLE="入力待ち"; COLOR="#17a2b8"; MENTION="<!here>" ;;
    error)      ICON="❌"; TITLE="エラー発生"; COLOR="#dc3545"; MENTION="<!here>" ;;

    # 後で確認でOK（メンションなし → 静かにログ）
    # Claude CodeのStopフックは自動的に "stop" を渡すため、完了として扱う
    stop)       ICON="✅"; TITLE="完了"; COLOR="#28a745"; MENTION="" ;;
    *)          ICON="📢"; TITLE="通知"; COLOR="#6c757d"; MENTION="" ;;
  esac

  TIMESTAMP=$(date "+%H:%M:%S")

  # Slack 通知送信（App のアイコン・名前はSlack App設定で管理）
  curl -s -X POST "$WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "{
      \"text\": \"${MENTION} ${ICON} ${TITLE} - ${PROJECT} (${DEVICE})\",
      \"attachments\": [{
        \"color\": \"$COLOR\",
        \"blocks\": [
          {
            \"type\": \"header\",
            \"text\": {\"type\": \"plain_text\", \"text\": \"$ICON $TITLE - $PROJECT\", \"emoji\": true}
          },
          {
            \"type\": \"section\",
            \"fields\": [
              {\"type\": \"mrkdwn\", \"text\": \"*Project:*\n\`$PROJECT\`\"},
              {\"type\": \"mrkdwn\", \"text\": \"*Device:*\n\`$DEVICE\`\"},
              {\"type\": \"mrkdwn\", \"text\": \"*Time:*\n$TIMESTAMP\"}
            ]
          }
        ]
      }]
    }" >/dev/null
) &>/dev/null & # バックグラウンドで実行

disown
exit 0
