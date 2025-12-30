#!/bin/bash
# AI CLI Slack Notification Script + SketchyBar Integration
# Usage: ai-notify.sh <tool> <event>
#        ai-notify.sh --clear-cache
# tool: claude | codex | gemini
# event: stop | complete | permission | idle | error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

mkdir -p "$CACHE_DIR"

# デバッグログ
DEBUG_LOG="${CACHE_DIR}/debug.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') TOOL=$TOOL EVENT=$EVENT ARGS=$* \$0=$0 \$#=$# ALL_ARGS=[$@]" >> "$DEBUG_LOG"

# 1. 依存チェック (jq がない場合は何もしない)
if ! command -v jq &> /dev/null; then
  exit 0
fi

# ローカル Mac への SSH ホスト名（~/.ssh/config で設定）
# 例: Host mac-local
#       HostName 192.168.x.x
#       User username
LOCAL_MAC_HOST="${CLAUDE_LOCAL_MAC_HOST:-}"

# SketchyBar 用のローカル状態更新関数
update_sketchybar_status() {
  local project="$1"
  local status="$2"
  local session_id="${3:-}"
  local tty="${4:-}"

  # ローカル環境かどうかを判定
  if [[ "$(uname)" == "Darwin" ]] && [[ -z "${SSH_CONNECTION:-}" ]]; then
    # ローカル Mac - 直接更新
    "$SCRIPT_DIR/claude-status.sh" set "$project" "$status" "$session_id" "$tty" 2>/dev/null || true
  elif [[ -n "$LOCAL_MAC_HOST" ]]; then
    # リモート環境 - SSH 経由で通知（バックグラウンド）
    ssh -o ConnectTimeout=2 -o BatchMode=yes "$LOCAL_MAC_HOST" \
      "\$HOME/dotfiles/scripts/claude-status.sh set '$project' '$status' '$session_id' '$tty'" \
      &>/dev/null &
  fi
}

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

  # JSON から情報抽出
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  [[ -z "$CWD" ]] && CWD=$(pwd)

  # Dev Container の場合はコンテナ名を使用
  PROJECT=""
  # devcontainer.json から name を取得
  for devcontainer_path in "$CWD/.devcontainer/devcontainer.json" "$CWD/.devcontainer.json" "/workspaces/.devcontainer/devcontainer.json"; do
    if [[ -f "$devcontainer_path" ]]; then
      PROJECT=$(jq -r '.name // empty' "$devcontainer_path" 2>/dev/null)
      [[ -n "$PROJECT" ]] && break
    fi
  done
  # コンテナ名が取得できなければディレクトリ名を使用
  [[ -z "$PROJECT" ]] && PROJECT=$(basename "$CWD")

  DEVICE=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  TTY=$(tty 2>/dev/null || echo "")

  # SketchyBar 用の状態を決定（Claude 専用）
  if [[ "$TOOL" == "claude" ]]; then
    case "$EVENT" in
      idle)       SKETCHYBAR_STATUS="idle" ;;
      permission) SKETCHYBAR_STATUS="permission" ;;
      complete)   SKETCHYBAR_STATUS="complete" ;;
      stop|error) SKETCHYBAR_STATUS="none" ;;
      *)          SKETCHYBAR_STATUS="" ;;
    esac

    # SketchyBar 状態更新
    if [[ -n "$SKETCHYBAR_STATUS" ]]; then
      update_sketchybar_status "$PROJECT" "$SKETCHYBAR_STATUS" "$SESSION_ID" "$TTY"
    fi
  fi

  # Webhook URL取得（キャッシュ優先）
  WEBHOOK=$(get_webhook "$TOOL")
  [[ -z "$WEBHOOK" ]] && exit 0

  # イベントに応じてメンションと色を使い分ける
  case "$EVENT" in
    # 即対応が必要（メンションあり → プッシュ通知）
    permission) ICON="🔐"; TITLE="承認待ち"; COLOR="#ffc107"; MENTION="<!here>" ;;
    idle)       ICON="⏳"; TITLE="入力待ち"; COLOR="#17a2b8"; MENTION="<!here>" ;;
    error)      ICON="❌"; TITLE="エラー発生"; COLOR="#dc3545"; MENTION="<!here>" ;;

    # 後で確認でOK（メンションなし → 静かにログ）
    complete) ICON="✅"; TITLE="完了"; COLOR="#28a745"; MENTION="" ;;
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
