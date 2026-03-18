---
name: ralph-cleanup
description: ralph-parallel で作成された worktree、tmux window、ブランチを削除します。
user-invocable: true
disable-model-invocation: true
arguments: "<options>"
allowed-tools: Bash
---

# Ralph Cleanup - クリーンアップ

`/ralph-parallel` で作成された worktree、tmux window、`ralph/*` ブランチ、結果ファイルを削除するスキル。全ての作業が終わった後にユーザーが呼び出す。

## 使い方

```
/ralph-cleanup                    # 全削除 (worktree + window + branch + results + prompts + checkpoint)
/ralph-cleanup --keep-results     # results ディレクトリを保持
/ralph-cleanup T-1 T-3            # 指定タスクのみ cleanup
```

## 手順

引数をパースし、`ralph-orchestrate.sh cleanup-all` を実行する。

```bash
# 全削除
~/dotfiles/scripts/ralph-orchestrate.sh cleanup-all

# results 保持
~/dotfiles/scripts/ralph-orchestrate.sh cleanup-all --keep-results

# 指定タスクのみ
~/dotfiles/scripts/ralph-orchestrate.sh cleanup-all T-1 T-3
```

完了後、削除されたリソースをユーザーに報告する。

## 実行ルール

引数で指定された操作を1回実行して完了する。
