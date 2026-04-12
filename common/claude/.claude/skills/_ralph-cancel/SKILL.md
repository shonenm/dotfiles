---
name: _ralph-cancel
description: 実行中の Ralph ループを中断します。状態ファイルのアーカイブを保存してからクリーンアップします。
user-invocable: true
disable-model-invocation: true
---

# Ralph Cancel - ループ中断

実行中の Ralph 自律開発ループを中断します。

## 手順

1. セッション固有の active ファイルから状態ファイルを特定し、アーカイブを保存してから削除する:

```bash
SESSION_HASH="$(echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5sum 2>/dev/null | cut -c1-12 || echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5 2>/dev/null | cut -c1-12)"
ACTIVE_FILE="/tmp/ralph/state/active_${SESSION_HASH}"
if [ -f "$ACTIVE_FILE" ]; then
  STATE_FILE="$(cat "$ACTIVE_FILE")"
  if [ -f "$STATE_FILE" ]; then
    # アーカイブを保存
    ARCHIVE="/tmp/ralph/state/archive_$(date +%Y%m%d_%H%M%S).json"
    cp "$STATE_FILE" "$ARCHIVE"
    rm -f "$STATE_FILE"
    echo "State file archived to: $ARCHIVE"
  fi
  rm -f "$ACTIVE_FILE"
  echo "Ralph loop cancelled."
else
  echo "No active Ralph loop found."
fi
```

2. 結果をユーザーに報告:
   - active ファイルが存在して削除できた場合: "Ralph loop cancelled. Archive: <archive_path>"
   - active ファイルが存在しなかった場合: "No active Ralph loop found."
