#!/bin/bash
# AI CLI Slack Notification Script
# Usage: ai-notify.sh <tool> <event>
# tool: claude | codex | gemini
# event: stop | complete | permission | idle | error

set -euo pipefail

TOOL="${1:-claude}"
EVENT="${2:-notification}"

# 1. 依存チェック (jq, op がない場合は何もしない)
if ! command -v jq &> /dev/null || ! command -v op &> /dev/null; then
  exit 0
fi

# 2. 非同期実行のためにサブシェル化
(
  # stdin から JSON 読み取り (タイムアウト付きでブロック回避)
  if [ -t 0 ]; then
    INPUT="{}"
  else
    INPUT=$(timeout 1 cat 2>/dev/null || echo "{}")
  fi

  # 1Password からツール別 Webhook URL 取得
  case "$TOOL" in
    claude) WEBHOOK=$(op read "op://Personal/Claude Webhook/password" 2>/dev/null || echo "") ;;
    codex)  WEBHOOK=$(op read "op://Personal/Codex Webhook/password" 2>/dev/null || echo "") ;;
    gemini) WEBHOOK=$(op read "op://Personal/Gemini Webhook/password" 2>/dev/null || echo "") ;;
    *)      WEBHOOK="" ;;
  esac
  [[ -z "$WEBHOOK" ]] && exit 0

  # JSON から情報抽出
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || pwd)
  PROJECT=$(basename "$CWD")

  # イベントに応じてメンションと色を使い分ける
  case "$EVENT" in
    # 即対応が必要（メンションあり → プッシュ通知）
    permission) ICON="🔐"; TITLE="承認待ち"; COLOR="#ffc107"; MENTION="<!here>" ;;
    idle)       ICON="⏳"; TITLE="入力待ち"; COLOR="#17a2b8"; MENTION="<!here>" ;;
    error)      ICON="❌"; TITLE="エラー発生"; COLOR="#dc3545"; MENTION="<!here>" ;;

    # 後で確認でOK（メンションなし → 静かにログ）
    stop)       ICON="🛑"; TITLE="中断"; COLOR="#6c757d"; MENTION="" ;;
    complete)   ICON="✅"; TITLE="完了"; COLOR="#28a745"; MENTION="" ;;
    *)          ICON="📢"; TITLE="通知"; COLOR="#6c757d"; MENTION="" ;;
  esac

  TIMESTAMP=$(date "+%H:%M:%S")

  # Slack 通知送信（App のアイコン・名前はSlack App設定で管理）
  curl -s -X POST "$WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "{
      \"text\": \"${MENTION} ${TITLE}\",
      \"attachments\": [{
        \"color\": \"$COLOR\",
        \"blocks\": [
          {
            \"type\": \"header\",
            \"text\": {\"type\": \"plain_text\", \"text\": \"$ICON $TITLE\", \"emoji\": true}
          },
          {
            \"type\": \"section\",
            \"fields\": [
              {\"type\": \"mrkdwn\", \"text\": \"*Project:*\n\`$PROJECT\`\"},
              {\"type\": \"mrkdwn\", \"text\": \"*Time:*\n$TIMESTAMP\"}
            ]
          }
        ]
      }]
    }" >/dev/null
) &>/dev/null & # バックグラウンドで実行

disown
exit 0
