---
name: github-pr
description: 変更を分析して PR を作成します。リッチな PR 本文を生成します。
user-invocable: true
arguments: "[--draft] [--base <branch>]"
---

# PR - Pull Request 作成

## 手順
1. `gh auth status` で認証確認
2. ベースブランチと現在ブランチを確認
3. uncommitted changes がないこと / 既存PRがないことを確認
4. `git diff --stat <base>..HEAD`, `git log --oneline <base>..HEAD` で変更分析
5. PRタイトル(70文字以内)と本文(Summary/Changes/Test plan)を生成
6. `git push -u origin` → `gh pr create`

## エッジケース
- ブランチ名から Issue 番号抽出 → `Closes #N` を本文に含める
- PRテンプレートがあれば構造に従う
- 既存PRあればURL表示して終了
