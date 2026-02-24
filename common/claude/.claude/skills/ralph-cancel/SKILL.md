---
name: ralph-cancel
description: 実行中の Ralph ループを中断します。状態ファイルのアーカイブを保存してからクリーンアップします。
user-invocable: true
disable-model-invocation: true
---

# Ralph Cancel - ループ中断

実行中の Ralph 自律開発ループを中断します。

## 手順

1. マニフェストから状態ファイルを特定し、アーカイブを保存してから削除する:

```bash
MANIFEST="/tmp/ralph_session_manifest"
if [ -f "$MANIFEST" ]; then
  STATE_FILE="$(cat "$MANIFEST")"
  if [ -f "$STATE_FILE" ]; then
    # アーカイブを保存
    ARCHIVE="/tmp/ralph_archive_$(date +%Y%m%d_%H%M%S).json"
    cp "$STATE_FILE" "$ARCHIVE"
    rm -f "$STATE_FILE"
    echo "State file archived to: $ARCHIVE"
  fi
  rm -f "$MANIFEST"
  echo "Ralph loop cancelled."
else
  echo "No active Ralph loop found."
fi
```

2. 結果をユーザーに報告:
   - マニフェストが存在して削除できた場合: "Ralph loop cancelled. Archive: <archive_path>"
   - マニフェストが存在しなかった場合: "No active Ralph loop found."
