#!/usr/bin/env bash
# Ralph Plan Guard (PreToolUse: Bash)
# Phase 3 完了後（状態ファイル生成後）の Bash 実行をブロックする。
# マニフェストが存在し、それが指す状態ファイルが存在し、
# マニフェストが2時間以内のものであれば Phase 3 完了済みとみなしブロック。
set -euo pipefail

manifest="/tmp/ralph_session_manifest"

# マニフェストが存在しない → allow
if [[ ! -f "$manifest" ]]; then
  exit 0
fi

state_file="$(cat "$manifest")"

# マニフェストが空 or 状態ファイルが存在しない → allow
if [[ -z "$state_file" ]] || [[ ! -f "$state_file" ]]; then
  exit 0
fi

# マニフェストが2時間以上前 → stale とみなし allow
# find -mmin +120 で判定（macOS/Linux 共通）
if find "$manifest" -mmin +120 2>/dev/null | grep -q .; then
  exit 0
fi

# Phase 3 完了済み → block
printf '{"decision":"block","reason":"[ralph-plan] Phase 3 完了済み。実装は /ralph で行ってください。このセッションではこれ以上のコマンド実行はできません。"}\n'
exit 2
