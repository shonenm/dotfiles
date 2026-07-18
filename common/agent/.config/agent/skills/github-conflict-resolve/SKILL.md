---
name: github-conflict-resolve
description: Git merge/rebase のコンフリクトを解決します。
user-invocable: true
arguments: "[<target>] [--rebase]"
---

# Conflict Resolve - コンフリクト解決

## 手順
1. `git status`, `git diff --name-only --diff-filter=U` でコンフリクト検出
2. 各コンフリクトファイルを分析 (`git log --oneline --merge`)
3. 競合解決方針を決定（どちらを優先するか）
4. 解決を実行（ファイル編集 → `git add`）
5. マージ/リベースを完了
6. `git diff --staged` で確認
