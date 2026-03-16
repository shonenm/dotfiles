---
name: ralph-parallel
description: 状態ファイルのタスクグラフから依存関係を分析し、wt-lib + tmux で可視化された独立 claude プロセスとして並列実行します。
user-invocable: true
disable-model-invocation: true
arguments: "<prd-file-or-task-list>"
allowed-tools: Bash, Read, Write, Glob, Grep, Task
---

# Ralph Parallel - 並列タスク実行オーケストレーター

状態ファイルのタスクグラフまたは PRD/タスクリストから依存関係を分析し、各タスクを独立した claude プロセスとして並列実行する。各ワーカーは git worktree + tmux window で分離され、TUI モードで起動するため進行状況を直接観察できる。

## 自律実行ルール

このスキルは起動後、全ステップを自律的に完走する。途中で質問・確認・報告のために停止してはならない。エラーが発生した場合も自律的に対処し、最終報告でまとめて報告する。

## 引数

| 引数 | 説明 |
|------|------|
| `<prd-file-or-task-list>` | PRD ファイルのパス、カンマ区切りのタスクリスト、または省略 (状態ファイル使用) |

### 使用例

```
/ralph-parallel                                    # 状態ファイルの task_graph を使用
/ralph-parallel docs/prd.md                        # PRD ファイルからタスク分割
/ralph-parallel "Add login page, Add signup page"  # カンマ区切りタスクリスト
```

## 手順

### 1. タスクソースの決定

優先順位:
1. 引数なし: `/tmp/ralph/state/latest` または `/tmp/ralph/state/active_*` から状態ファイルを発見し、`task_graph` を使用
2. ファイルパス指定: ファイルを読み込みタスクを抽出
3. テキスト指定: カンマ区切りまたは改行区切りでタスクに分割

### 2. 依存関係の分析

- 各タスクの `deps` フィールドから DAG (有向非巡回グラフ) を構築
- 循環依存がないか検証
- ファイルの競合 (同じファイルを複数タスクが変更する可能性) を検出・報告
- 依存関係が未解決のタスクは先行タスク完了まで待機

### 3. 環境初期化

Bash で以下を実行:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh init
```

### 4. プロンプト生成

各タスクについて Write ツールで `/tmp/ralph/prompts/<task-id>.md` を生成する。

プロンプトテンプレート:

```markdown
You are a worker agent executing a specific task in an isolated git worktree.

## Task
ID: {task_id}
Name: {task_name}
Completion condition: {completion_condition}
Target files: {files}

## Context
{context_report}

## Instructions
1. Implement the task described above
2. Follow test-driven development when possible
3. Run type checks and linting to verify changes
4. Write result report to /tmp/ralph/results/{task_id}.md:

   Status: DONE / PARTIAL / BLOCKED
   Files changed:
     - <path> (created/modified/deleted)
   Tests:
     - <test_file>: PASS / FAIL
   Completion condition: <status>
   Notes: <any notes>

5. As the very last step, write "0" to /tmp/ralph/results/{task_id}.status:
   echo "0" > /tmp/ralph/results/{task_id}.status

## Constraints
- Only modify files within this task's scope
- Do not git commit or push
- Do not modify files outside the listed target files
```

### 5. 並列起動

実行可能タスク (deps が全て完了済み) を最大4つまで Bash で起動:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh launch <task-id> /tmp/ralph/prompts/<task-id>.md --model sonnet
```

各起動により:
- git worktree が作成される (`ralph/<task-id>` ブランチ)
- tmux window が作成される (TUI モードで進行状況を直接観察可能)
- 独立した claude プロセスが sonnet モデルで起動される
- 完了時に `/tmp/ralph/results/<task-id>.status` に exit code が書かれる

### 6. 完了待機 (ポーリングループ)

以下のループを全ワーカーが完了するまで繰り返す:

1. Bash (timeout: 600000) で `ralph-orchestrate.sh poll --interval 10 --timeout 540` を実行
2. タイムアウトした場合 (return code 1): `ralph-orchestrate.sh status` で running ワーカーを確認し、1 に戻る
3. 全完了した場合 (return code 0): 次のステップへ

途中で停止してはならない。running ワーカーが残っている限りポーリングを継続する。

### 7. 結果収集

全ワーカー完了後:
1. Read ツールで `/tmp/ralph/results/<task-id>.md` を読む (各ワーカーの結果)
2. 状態ファイルの該当タスクを `"done"` に更新
3. 新たに実行可能になったタスクがあれば手順5に戻る

### 8. レビューフェーズ

全タスク完了後、Task ツールで `ralph-reviewer` エージェントを起動:

```
Task(subagent_type: "ralph-reviewer", prompt: "以下のworkerの変更をレビューしてください:
- worktree paths: [各workerのworktreeパス]
- result files: [/tmp/ralph/results/*.md]
- task completion conditions: [各タスクの完了条件]
")
```

ralph-reviewer は各 worktree で `git diff` を実行し、コード品質をチェックし、APPROVE / REQUEST_CHANGES を返す。

### 9. 変更の保存とマージ

レビュー結果に基づき、各タスクの変更を保存する。

全タスクについて、まず変更を保存:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh save <task-id>
```

APPROVE されたタスクのみ、メインブランチにマージ:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh merge <task-id>
```

REQUEST_CHANGES のタスクはマージしない。パッチファイル (`/tmp/ralph/results/<task-id>.patch`) は保存済みなので、後から手動で修正・適用できる。

マージでコンフリクトが発生した場合はスキップし、最終報告で報告する。

### 10. クリーンアップと報告

1. Bash で worker worktree を削除:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh cleanup-all
```

2. 全体のサマリーを報告:
   - 各タスクの完了状態とレビュー結果
   - APPROVE されマージ済みのタスク一覧
   - REQUEST_CHANGES でパッチのみ保存されたタスク一覧
   - マージでコンフリクトが発生したタスク (該当する場合)
   - 変更されたファイル一覧

## 注意事項

- 各ワーカーは独立した git worktree + tmux window で TUI モードで動作し、進行を直接観察できる
- ワーカーは sonnet モデルで動作する (コスト最適化)
- 同時実行ワーカー数の上限は4 (リソース制約)
- ワーカーの結果は `/tmp/ralph/results/` に永続化される (orchestrator のコンテキストを膨張させない)
- レビューと save は cleanup 前に実行する (worktree の diff 参照のため)
- APPROVE された変更は save → merge → cleanup の順で処理される。変更が消失することはない
- 競合が発生した場合はパッチファイルが残るため、手動で解決できる
