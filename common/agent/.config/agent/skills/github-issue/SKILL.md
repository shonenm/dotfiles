---
name: github-issue
description: GitHub Issue を作成し、作業ブランチを準備します。
user-invocable: true
arguments: "<title-or-description>"
---

# Issue - GitHub Issue 作成 + ブランチ準備

## 手順
1. 引数から Issue タイトルを決定
2. `gh label list`, `git log --oneline -10` でリポジトリ情報収集
3. タイトル・本文(Overview/Acceptance criteria)・ラベルを生成
4. `gh issue create --title "..." --body "..." --assignee @me`
5. `gh issue develop <N> --name "<N>-<slug>" --checkout`

## 完了報告
- Issue URL, ブランチ名, 次ステップ(実装 → commit → PR)
