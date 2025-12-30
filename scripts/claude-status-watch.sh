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

# リモートでinotifywaitを実行し、変更時にJSONを出力
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 "$REMOTE_HOST" '
  export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"
  INOTIFYWAIT="$HOME/.local/bin/inotifywait"
  [[ ! -x "$INOTIFYWAIT" ]] && INOTIFYWAIT="inotifywait"

  mkdir -p /tmp/claude_status
  "$INOTIFYWAIT" -m -e modify,create --format "%f" /tmp/claude_status/ 2>/dev/null | while read file; do
    [[ "$file" == *.json ]] && cat "/tmp/claude_status/$file" 2>/dev/null || true
  done
' 2>/dev/null | while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  project=$(echo "$line" | jq -r '.project // empty' 2>/dev/null)
  status=$(echo "$line" | jq -r '.status // empty' 2>/dev/null)
  session_id=$(echo "$line" | jq -r '.session_id // empty' 2>/dev/null)

  [[ -z "$project" || -z "$status" ]] && continue

  # ホスト名をプロジェクト名に追加して区別
  remote_project="${REMOTE_HOST}:${project}"

  # ローカルのclaude-status.shを呼び出し
  "$SCRIPT_DIR/claude-status.sh" set "$remote_project" "$status" "$session_id" "" 2>/dev/null || true
done
