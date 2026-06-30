---
name: d-hunk-review
description: hunk diff の live session に付けたコメントを読んで対応する。Use when the user references hunk comments, says "hunk のコメント見て", or has a hunk diff --watch session running.
---

# Hunk Review

hunk 同梱スキルに委譲する。`hunk skill path` で本体 SKILL.md のパスを取得し、そのファイルを読んで手順に従う。バンドル内容はここに複製しない（hunk 更新で腐るため）。

要点:
- TUI (`hunk diff` / `hunk show`) は直接実行しない。ユーザーのものなので触らない。
- `hunk session *` 系コマンドで daemon のライブセッションを読む。
- 単一セッションなら `--repo .` で自動解決。複数あるなら `hunk session list` で session-id を確認。

クイックスタート:
```bash
hunk session comment list --repo . --type user   # ユーザーが付けたコメント
hunk session review --repo . --json              # コメント込みのレビュー全体
```

セッションが無い場合は、ユーザーに hunk をターミナルで起動するよう促す。
