---
name: ralph-cancel
description: 実行中の Ralph ループを中断します。
user-invocable: true
disable-model-invocation: true
---

# Ralph Cancel - ループ中断

実行中の Ralph 自律開発ループを中断します。

## 手順

1. 状態ファイルを削除する:

```bash
rm -f "/tmp/ralph_${CLAUDE_SESSION_ID}.json"
```

2. 削除結果を確認し、ユーザーに報告:
   - ファイルが存在して削除できた場合: "Ralph loop cancelled."
   - ファイルが存在しなかった場合: "No active Ralph loop found for this session."
