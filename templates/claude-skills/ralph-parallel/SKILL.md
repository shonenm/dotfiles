---
name: ralph-parallel
description: 複数タスクを worktree 分離されたエージェントで並列実行します。
user-invocable: true
disable-model-invocation: true
arguments: "<prd-file-or-task-list>"
---

# Ralph Parallel - 並列タスク実行

PRD ファイルまたはタスクリストを受け取り、ralph-worker サブエージェントを使って複数タスクを並列実行します。

## 引数

| 引数 | 説明 |
|------|------|
| `<prd-file-or-task-list>` | PRD ファイルのパス、またはカンマ区切りのタスクリスト |

### 使用例

```
/ralph-parallel docs/prd.md
/ralph-parallel "Add login page, Add signup page, Add dashboard"
```

## 手順

### 1. タスクリストの取得

- ファイルパスが指定された場合: ファイルを読み込み、タスクリストを抽出
- テキストが指定された場合: カンマ区切りまたは改行区切りでタスクに分割

### 2. タスクの分析と依存関係の確認

- 各タスクが独立して実行可能か確認する
- ファイルの競合 (同じファイルを複数タスクが変更する可能性) がないか検証
- 依存関係がある場合はユーザーに報告し、実行順序を提案する

### 3. 並列実行

各タスクを `ralph-worker` サブエージェントに委譲する。Task ツールを使用し、各タスクに明確なプロンプトを渡す:

- タスクの説明
- 対象ファイル/ディレクトリのスコープ
- 完了条件

独立したタスクは並列で (同一メッセージ内の複数 Task ツールコールで) 起動する。

### 4. 結果の統合

すべてのワーカーが完了したら:

1. 各ワーカーの結果を収集
2. 変更の競合がないか確認
3. 全体のサマリーをユーザーに報告

## 注意事項

- `isolation: worktree` により各ワーカーは独立した git worktree で作業する
- worktree はワーカー完了時に自動クリーンアップされる
- 競合が発生した場合は手動マージが必要になる可能性がある
- Agent Teams (TeammateTool) が GA になった際はそちらへの移行を検討
