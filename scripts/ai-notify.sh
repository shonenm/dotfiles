#!/bin/bash
# AI CLI Slack Notification Script + SketchyBar Integration
# Usage: ai-notify.sh <tool> <event>
#        ai-notify.sh --setup <tool>       # Cache webhook and send setup notification
#        ai-notify.sh --refresh-cache      # Refresh all webhook caches (no notification)
#        ai-notify.sh --clear-cache        # Clear all cached webhooks
# tool: claude | codex | gemini | cursor | cmd
# event: stop | complete | permission | idle | error

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# host-container 共有 runtime base (docker bind mount 共有用)
SHARED_BASE="${DOTFILES_SHARED_DIR:-$HOME/.cache}"

# キャッシュディレクトリ (XDG_DATA_HOME準拠で永続化)
CACHE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ai-notify"

write_private_file() {
  local path="$1" content="$2" tmp
  tmp="${path}.$$"
  printf '%s\n' "$content" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$path"
}

# 1Password パス取得
get_op_path() {
  local tool="$1"
  case "$tool" in
    claude) echo "op://Personal/Claude Webhook/password" ;;
    codex)  echo "op://Personal/Codex Webhook/password" ;;
    gemini) echo "op://Personal/Gemini Webhook/password" ;;
    cursor) echo "op://Personal/Cursor Webhook/password" ;;
    cmd)    echo "op://Personal/Command Code Webhook/password" ;;
    *)      return 1 ;;
  esac
}

# セットアップ通知送信
send_setup_notification() {
  local tool="$1"
  local webhook="$2"

  local device
  device=$(hostname -s 2>/dev/null || hostname)
  local os_info
  os_info="$(uname -s) ($(uname -m))"
  local user
  user=$(whoami)
  local ip
  ip=$(curl -s --max-time 2 ifconfig.me 2>/dev/null || echo "N/A")
  local dotfiles_version
  dotfiles_version=$(git -C "$HOME/dotfiles" rev-parse --short HEAD 2>/dev/null || echo "N/A")
  local timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")

  # ツール名を大文字に変換 (bash 3.2互換)
  local tool_upper
  tool_upper=$(echo "$tool" | tr '[:lower:]' '[:upper:]')

  curl -s --connect-timeout 2 --max-time 5 -X POST "$webhook" \
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
  write_private_file "${CACHE_DIR}/${tool}_webhook" "$webhook"
  echo "Cached webhook for $tool"

  send_setup_notification "$tool" "$webhook"
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

  for tool in claude codex gemini cursor cmd; do
    local op_path
    op_path=$(get_op_path "$tool") || continue

    local webhook
    if webhook=$(op read "$op_path" 2>/dev/null); then
      write_private_file "${CACHE_DIR}/${tool}_webhook" "$webhook"
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

# 状態の正本(tmux pane option)を更新。tmux 内でのみ作用する(スクリプトが自己ガード)。
# 全ツール共通の入口とし、単一フックの codex/cursor もこの経路でペーン状態を得る。
# 仕様: docs/specs/agent-stop-notification.md
case "$EVENT" in
  complete|stop)
    "$SCRIPT_DIR/tmux-claude-pane.sh" set idle "$TOOL" 2>/dev/null || true
    ;;
  permission|idle|error)
    "$SCRIPT_DIR/tmux-claude-pane.sh" set "$EVENT" "$TOOL" 2>/dev/null || true
    ;;
esac

# hook stdin はbackground化する前に読み切る。background subshellでは/dev/nullになるため。
if [ -t 0 ]; then
  INPUT="{}"
else
  INPUT=$(cat 2>/dev/null || echo "{}")
fi

# 1. 依存チェック (jq がない場合は何もしない)
if ! command -v jq &> /dev/null; then
  exit 0
fi

# SketchyBar 用のローカル状態更新関数
update_sketchybar_status() {
  local project="$1"
  local status="$2"
  local workspace="${3:-}"
  local tmux_session="${4:-}"
  local tmux_window_index="${5:-}"

  # ローカル環境かどうかを判定
  if [[ "$(uname)" == "Darwin" ]] && [[ -z "${SSH_CONNECTION:-}" ]]; then
    # ローカル Mac - 直接更新
    "$SCRIPT_DIR/claude-status.sh" set "$project" "$status" "$workspace" "$tmux_session" "$tmux_window_index" 2>/dev/null || true
  else
    # リモート環境 - ファイルに書き込み（Macが監視）
    local status_dir="$SHARED_BASE/claude/status"
    mkdir -p "$status_dir"
    local status_file
    if [[ -n "$workspace" ]]; then
      # workspace があれば新形式
      local timestamp
      timestamp=$(date +%s%N)
      status_file="$status_dir/workspace_${workspace}_${timestamp}.json"
    else
      # workspace がなければプロジェクト名ベース（フォールバック）
      local safe_project="${project//\//_}"
      status_file="$status_dir/${safe_project}.json"
    fi
    local tmp="${status_file}.$$"
    jq -n \
      --arg project "$project" \
      --arg tool "$TOOL" \
      --arg status "$status" \
      --arg workspace "$workspace" \
      --arg tmux_session "$tmux_session" \
      --arg tmux_window_index "$tmux_window_index" \
      --argjson updated "$(date +%s)" \
      '{project:$project, tool:$tool, status:$status, workspace:$workspace, tmux_session:$tmux_session, tmux_window_index:$tmux_window_index, updated:$updated}' \
      > "$tmp" && mv "$tmp" "$status_file"
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
  [[ -n "$webhook" ]] && write_private_file "$cache_file" "$webhook"
  echo "$webhook"
}

# 2. 非同期実行のためにサブシェル化
(
  # session_id: 将来の拡張用に取得可能だが現在未使用
  # SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

  # CLAUDE_CONTEXT 環境変数からコンテキスト取得（コンテナ用）
  # 設定されていれば環境推測をスキップして明示的な値を使用
  if [[ -n "${CLAUDE_CONTEXT:-}" ]]; then
    PROJECT=$(echo "$CLAUDE_CONTEXT" | jq -r '.project // empty' 2>/dev/null)
    DEVICE=$(echo "$CLAUDE_CONTEXT" | jq -r '.device // empty' 2>/dev/null)
    WORKSPACE=$(echo "$CLAUDE_CONTEXT" | jq -r '.workspace // empty' 2>/dev/null)
    TMUX_SESSION=$(echo "$CLAUDE_CONTEXT" | jq -r '.tmux_session // empty' 2>/dev/null)
    TMUX_WINDOW_INDEX=$(echo "$CLAUDE_CONTEXT" | jq -r '.tmux_window // empty' 2>/dev/null)
  else
    # フォールバック: ローカル検出
    CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    [[ -z "$CWD" ]] && CWD=$(pwd)
    PROJECT=$(basename "$CWD")
    DEVICE=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")

    # workspace取得（全環境共通）
    WORKSPACE=""
    WORKSPACE_MAP_FILE="${HOME}/.local/share/claude/workspace_map.json"
    if [[ -f "$WORKSPACE_MAP_FILE" ]]; then
      MAP_ENV_KEY=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
      [[ -z "$MAP_ENV_KEY" ]] && MAP_ENV_KEY="$CWD"
      WORKSPACE=$(jq -r --arg key "$MAP_ENV_KEY" '.[$key].workspace // empty' "$WORKSPACE_MAP_FILE" 2>/dev/null)
    fi

    # tmux情報の取得（tmux内の場合のみ）
    TMUX_SESSION=""
    TMUX_WINDOW_INDEX=""
    if [[ -n "${TMUX:-}" ]]; then
      TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
      TMUX_WINDOW_INDEX=$(tmux display-message -p '#I' 2>/dev/null || echo "")
    fi
  fi

  case "$EVENT" in
    idle)       SHARED_STATUS="idle" ;;
    permission) SHARED_STATUS="permission" ;;
    complete)   SHARED_STATUS="complete" ;;
    error)      SHARED_STATUS="error" ;;
    stop)       SHARED_STATUS="none" ;;
    *)          SHARED_STATUS="" ;;
  esac

  # Local SketchyBarはClaudeのみ。remote/containerの共有storeは全providerを対象にする。
  if [[ -n "$SHARED_STATUS" && -n "$WORKSPACE" ]]; then
    if [[ "$TOOL" == claude || "$(uname)" != Darwin || -n "${SSH_CONNECTION:-}" ]]; then
      update_sketchybar_status "$PROJECT" "$SHARED_STATUS" "$WORKSPACE" "$TMUX_SESSION" "$TMUX_WINDOW_INDEX"
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
    fallback)   ICON="⚠️"; TITLE="APIフォールバック中"; COLOR="#ff6b35"; MENTION="<!here>" ;;

    # 後で確認でOK（メンションなし → 静かにログ）
    complete)   ICON="✅"; TITLE="完了"; COLOR="#28a745"; MENTION="" ;;
    recovered)  ICON="✅"; TITLE="API復旧"; COLOR="#28a745"; MENTION="" ;;
    *)          ICON="📢"; TITLE="通知"; COLOR="#6c757d"; MENTION="" ;;
  esac

  TIMESTAMP=$(date "+%H:%M:%S")

  # Slack 通知送信（App のアイコン・名前はSlack App設定で管理）
  PAYLOAD=$(jq -n \
    --arg mention "$MENTION" \
    --arg icon "$ICON" \
    --arg title "$TITLE" \
    --arg project "$PROJECT" \
    --arg device "$DEVICE" \
    --arg color "$COLOR" \
    --arg ts "$TIMESTAMP" \
    '{
      text: "\($mention) \($icon) \($title) - \($project) (\($device))",
      attachments: [{
        color: $color,
        blocks: [
          {type: "header", text: {type: "plain_text", text: "\($icon) \($title) - \($project)", emoji: true}},
          {type: "section", fields: [
            {type: "mrkdwn", text: "*Project:*\n`\($project)`"},
            {type: "mrkdwn", text: "*Device:*\n`\($device)`"},
            {type: "mrkdwn", text: "*Time:*\n\($ts)"}
          ]}
        ]
      }]
    }')
  curl -s --connect-timeout 2 --max-time 5 -X POST "$WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null
) &>/dev/null & # バックグラウンドで実行

disown
exit 0
