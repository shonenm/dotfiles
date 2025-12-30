#!/bin/bash
# AI CLI Slack Notification Script + SketchyBar Integration
# Usage: ai-notify.sh <tool> <event>
#        ai-notify.sh --setup <tool>       # Cache webhook and send setup notification
#        ai-notify.sh --refresh-cache      # Refresh all webhook caches (no notification)
#        ai-notify.sh --clear-cache        # Clear all cached webhooks
# tool: claude | codex | gemini
# event: stop | complete | permission | idle | error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# キャッシュディレクトリ (XDG_DATA_HOME準拠で永続化)
CACHE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ai-notify"

# 1Password パス取得
get_op_path() {
  local tool="$1"
  case "$tool" in
    claude) echo "op://Personal/Claude Webhook/password" ;;
    codex)  echo "op://Personal/Codex Webhook/password" ;;
    gemini) echo "op://Personal/Gemini Webhook/password" ;;
    *)      return 1 ;;
  esac
}

# セットアップ通知送信
send_setup_notification() {
  local tool="$1"
  local webhook="$2"

  local device=$(hostname -s 2>/dev/null || hostname)
  local os_info="$(uname -s) ($(uname -m))"
  local user=$(whoami)
  local ip=$(curl -s --max-time 2 ifconfig.me 2>/dev/null || echo "N/A")
  local dotfiles_version=$(git -C "$HOME/dotfiles" rev-parse --short HEAD 2>/dev/null || echo "N/A")
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

  # ツール名を大文字に変換 (bash 3.2互換)
  local tool_upper=$(echo "$tool" | tr '[:lower:]' '[:upper:]')

  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "{
      \"text\": \"🚀 $tool_upper セットアップ完了 - $device\",
      \"attachments\": [{
        \"color\": \"#6f42c1\",
        \"blocks\": [
          {\"type\": \"header\", \"text\": {\"type\": \"plain_text\", \"text\": \"🚀 $tool_upper セットアップ完了\", \"emoji\": true}},
          {\"type\": \"section\", \"fields\": [
            {\"type\": \"mrkdwn\", \"text\": \"*Device:*\n\`$device\`\"},
            {\"type\": \"mrkdwn\", \"text\": \"*OS:*\n\`$os_info\`\"},
            {\"type\": \"mrkdwn\", \"text\": \"*User:*\n\`$user\`\"},
            {\"type\": \"mrkdwn\", \"text\": \"*IP:*\n\`$ip\`\"},
            {\"type\": \"mrkdwn\", \"text\": \"*Dotfiles:*\n\`$dotfiles_version\`\"},
            {\"type\": \"mrkdwn\", \"text\": \"*Time:*\n$timestamp\"}
          ]}
        ]
      }]
    }" >/dev/null

  echo "Sent setup notification for $tool"
}

# --setup オプション: webhookをキャッシュしてセットアップ通知を送信
setup_tool() {
  local tool="$1"

  if ! command -v op &> /dev/null; then
    echo "Error: 1Password CLI not found" >&2
    return 1
  fi

  # 1Passwordにサインイン済みか確認（未サインインならスキップ）
  if ! op whoami &>/dev/null; then
    echo "Skipped: 1Password not signed in (run 'eval \$(op signin)' first)" >&2
    return 1
  fi

  local op_path
  op_path=$(get_op_path "$tool") || {
    echo "Error: Unknown tool: $tool" >&2
    return 1
  }

  local webhook
  webhook=$(op read "$op_path" 2>/dev/null) || {
    echo "Error: Failed to get webhook for $tool from 1Password" >&2
    return 1
  }

  mkdir -p "$CACHE_DIR"
  echo "$webhook" > "${CACHE_DIR}/${tool}_webhook"
  chmod 600 "${CACHE_DIR}/${tool}_webhook"
  echo "Cached webhook for $tool"

  send_setup_notification "$tool" "$webhook"

  # SketchyBar バッジ作成（リモート環境のみ）
  if [[ "$(uname)" != "Darwin" ]] || [[ -n "${SSH_CONNECTION:-}" ]]; then
    local project="${DEVCONTAINER_NAME:-$(basename "$(pwd)")}"
    local status_dir="/tmp/claude_status"
    mkdir -p "$status_dir"
    echo "{\"project\":\"$project\",\"status\":\"complete\",\"session_id\":\"\",\"timestamp\":$(date +%s)}" > "$status_dir/${project}.json"
  fi
}

# --refresh-cache オプション: 全ツールのキャッシュを更新（通知なし）
refresh_cache() {
  if ! command -v op &> /dev/null; then
    echo "Error: 1Password CLI not found" >&2
    return 1
  fi

  # 1Passwordにサインイン済みか確認（未サインインならスキップ）
  if ! op whoami &>/dev/null; then
    echo "Skipped: 1Password not signed in (run 'eval \$(op signin)' first)" >&2
    return 1
  fi

  mkdir -p "$CACHE_DIR"

  for tool in claude codex gemini; do
    local op_path
    op_path=$(get_op_path "$tool") || continue

    local webhook
    if webhook=$(op read "$op_path" 2>/dev/null); then
      echo "$webhook" > "${CACHE_DIR}/${tool}_webhook"
      chmod 600 "${CACHE_DIR}/${tool}_webhook"
      echo "Refreshed cache for $tool"
    else
      echo "Skipped $tool (not available in 1Password)"
    fi
  done
}

# オプション処理
case "${1:-}" in
  --setup)
    setup_tool "${2:-claude}"
    exit $?
    ;;
  --refresh-cache)
    refresh_cache
    exit $?
    ;;
  --clear-cache)
    rm -rf "$CACHE_DIR"
    echo "Cache cleared: $CACHE_DIR"
    exit 0
    ;;
esac

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

# SketchyBar 用のローカル状態更新関数
update_sketchybar_status() {
  local project="$1"
  local status="$2"
  local session_id="${3:-}"
  local tty="${4:-}"
  local window_id="${5:-}"

  # ローカル環境かどうかを判定
  if [[ "$(uname)" == "Darwin" ]] && [[ -z "${SSH_CONNECTION:-}" ]]; then
    # ローカル Mac - 直接更新（window-id指定）
    "$SCRIPT_DIR/claude-status.sh" set "$project" "$status" "$session_id" "$tty" "$window_id" 2>/dev/null || true
  else
    # リモート環境 - ファイルに書き込み（Macがinotifywaitで監視）
    local status_dir="/tmp/claude_status"
    mkdir -p "$status_dir"
    local safe_project="${project//\//_}"
    local status_file="$status_dir/${safe_project}.json"
    echo "{\"project\":\"$project\",\"status\":\"$status\",\"session_id\":\"$session_id\",\"timestamp\":$(date +%s)}" > "$status_file"
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
  op_path=$(get_op_path "$tool") || return

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

  # プロジェクト名: DEVCONTAINER_NAME 環境変数 > ディレクトリ名
  PROJECT="${DEVCONTAINER_NAME:-$(basename "$CWD")}"

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
      # window_id は渡さない - claude-status.sh が find_window_by_project で正確に検索する
      update_sketchybar_status "$PROJECT" "$SKETCHYBAR_STATUS" "$SESSION_ID" "$TTY" ""
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
