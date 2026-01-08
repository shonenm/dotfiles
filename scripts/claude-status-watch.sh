#!/bin/bash
# リモートホストのClaudeステータスをinotifywaitで監視
# Usage: claude-status-watch.sh <remote-host>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_HOST="${1:-}"

[[ -z "$REMOTE_HOST" ]] && {
  echo "Usage: $0 <remote-host>" >&2
  exit 1
}

# 起動時: リモートの古いinotifywaitプロセスをクリーンアップ
# SSH切断時にゾンビとして残るプロセスを防止
ssh "$REMOTE_HOST" 'pkill -f "inotifywait.*claude_status" 2>/dev/null || true' 2>/dev/null || true

# リモートでinotifywaitを実行し、変更時にJSONを出力
# unbuffer: SSHの出力バッファリングを無効化
UNBUFFER="/opt/homebrew/bin/unbuffer"
[[ ! -x "$UNBUFFER" ]] && UNBUFFER="unbuffer"

# 終了時にリモートプロセスをクリーンアップ
cleanup() {
  ssh "$REMOTE_HOST" 'pkill -f "inotifywait.*claude_status" 2>/dev/null || true' 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"$UNBUFFER" ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 "$REMOTE_HOST" '
  export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"
  INOTIFYWAIT="$HOME/.local/bin/inotifywait"
  if [ ! -x "$INOTIFYWAIT" ]; then INOTIFYWAIT="inotifywait"; fi

  mkdir -p /tmp/claude_status
  stdbuf -oL "$INOTIFYWAIT" -m -e modify,create --format "%f" /tmp/claude_status/ 2>/dev/null | while read file; do
    case "$file" in *.json) cat "/tmp/claude_status/$file" 2>/dev/null ;; esac
  done
' 2>/dev/null | while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  project=$(echo "$line" | jq -r '.project // empty' 2>/dev/null)
  status=$(echo "$line" | jq -r '.status // empty' 2>/dev/null)
  session_id=$(echo "$line" | jq -r '.session_id // empty' 2>/dev/null)
  container_name=$(echo "$line" | jq -r '.container_name // empty' 2>/dev/null)

  [[ -z "$project" || -z "$status" ]] && continue

  # ホスト名をプロジェクト名に追加して区別
  remote_project="${REMOTE_HOST}:${project}"

  # ローカルのclaude-status.shを呼び出し（container_nameでVS Code検索）
  "$SCRIPT_DIR/claude-status.sh" set "$remote_project" "$status" "$session_id" "" "" "$container_name" 2>/dev/null || true
done
