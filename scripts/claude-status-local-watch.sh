#!/bin/bash
# ローカルDockerコンテナからの通知を処理
# /tmp/claude_status/*.json (非window_*) を検出してMac側処理を実行
# launchd の WatchPaths で起動される

set -euo pipefail

STATUS_DIR="/tmp/claude_status"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ディレクトリがなければ作成して終了
mkdir -p "$STATUS_DIR"

# 非window_* の .json ファイルを処理
for file in "$STATUS_DIR"/*.json; do
  [[ -f "$file" ]] || continue

  filename=$(basename "$file")

  # window_* ファイルはスキップ（既に処理済み）
  [[ "$filename" == window_* ]] && continue

  # JSONからプロジェクトとステータスを取得
  project=$(jq -r '.project // empty' "$file" 2>/dev/null)
  status=$(jq -r '.status // empty' "$file" 2>/dev/null)
  session_id=$(jq -r '.session_id // empty' "$file" 2>/dev/null)

  [[ -z "$project" || -z "$status" ]] && continue

  # Mac側でwindow検索して適切なファイルを作成
  "$SCRIPT_DIR/claude-status.sh" set "$project" "$status" "$session_id" "" 2>/dev/null || true

  # 処理済みファイルを削除
  rm -f "$file"
done
