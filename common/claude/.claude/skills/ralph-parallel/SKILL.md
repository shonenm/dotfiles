---
name: ralph-parallel
description: 状態ファイルのタスクグラフから依存関係を分析し、wt-lib + tmux で可視化された独立 claude プロセスとして並列実行します。
user-invocable: true
disable-model-invocation: true
arguments: "<prd-file-or-task-list>"
allowed-tools: Bash, Read, Write, Glob, Grep, Task
---

# Ralph Parallel - 並列タスク実行オーケストレーター

状態ファイルのタスクグラフまたは PRD/タスクリストから依存関係を分析し、各タスクを独立した claude プロセスとして並列実行する。各ワーカーは git worktree + tmux window で分離され、`/ralph` スキルで起動するため Stop hook による自律ループ + backpressure hook による品質ゲートが適用される。

実装フェーズのみを担当する。merge、cleanup、PR 作成は行わない。全 worker 完了後は結果サマリーを出力して停止する。ユーザーは tmux window を行き来して各 worker の diff を確認し、`/ralph-collect` で成果物を回収、`/ralph-cleanup` で後片付けを行う。

## 自律実行ルール

このスキルは起動後、Step 5 まで自律的に完走する。途中で質問・確認・報告のために停止してはならない。エラーが発生した場合も自律的に対処し、最終報告でまとめて報告する。

Step 4-5 は一切中断せず完了まで走ること。

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

### Step 0: チェックポイント確認

```bash
~/dotfiles/scripts/ralph-orchestrate.sh checkpoint-read
```

phase が `none` 以外であれば途中再開。該当フェーズの次のステップから再開する。

### Step 1: タスク分析

優先順位:
1. 引数なし: `/tmp/ralph/state/latest` または `/tmp/ralph/state/active_*` から状態ファイルを発見し、`task_graph` を使用
2. ファイルパス指定: ファイルを読み込みタスクを抽出
3. テキスト指定: カンマ区切りまたは改行区切りでタスクに分割

各タスクの `deps` フィールドから DAG (有向非巡回グラフ) を構築し、wave (同時実行可能グループ) を特定する。

### Step 2: 環境初期化

```bash
# 初回起動
~/dotfiles/scripts/ralph-orchestrate.sh init --force

# 途中再開時
~/dotfiles/scripts/ralph-orchestrate.sh init
```

チェックポイント設定:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh checkpoint initialized
```

### Step 3: プロンプト一括生成

タスク情報を JSON ファイルにまとめて一括生成:

```bash
# /tmp/ralph/task-spec.json を Write ツールで生成
# フォーマット:
# [
#   {"id": "T-1", "name": "...", "completion_condition": "...", "files": "...", "context_file": "..."},
#   ...
# ]

~/dotfiles/scripts/ralph-orchestrate.sh gen-prompt-batch /tmp/ralph/task-spec.json
```

gen-prompt テンプレートには完了条件のみ記載すること。RALPH_COMPLETE は ralph の SKILL.md (Step 6) が自動出力するため、テンプレートでは触れない。

チェックポイント設定:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh checkpoint prompts_generated
```

### Step 4: 並列起動

実行可能タスク (deps が全て完了済み) を最大4つまで起動:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh launch <task-id> /tmp/ralph/prompts/<task-id>.md --model sonnet
```

各起動により:
- git worktree が作成される (`ralph/<task-id>` ブランチ)
- tmux window が作成され、split pane で review (nvim) + claude TUI が配置される
- claude TUI が起動し、capture-pane で起動確認後 `/ralph` が send-keys で送信される
- Stop hook による自律ループ + backpressure hook による品質ゲートが適用される
- 完了時: RALPH_COMPLETE -> Stop hook exit 0 -> claude が入力待ちに戻る

チェックポイント設定:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh checkpoint launched
```

### Step 5: 完了待機 (status --wait ループ)

以下のループを全ワーカーが完了するまで繰り返す:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh status --json --wait 20
```

- `all_done` が `true` になるまで繰り返す
- 各呼び出しは 20 秒 sleep -> 1 回 status 出力 -> return (Bash call は即完了)
- all_done かどうかだけ判断する。考察を長々と出力しない
- `dead` ステータスのワーカーがいる場合は警告として報告

チェックポイント設定:

```bash
~/dotfiles/scripts/ralph-orchestrate.sh checkpoint workers_done
```

### Step 6: 結果サマリー出力して停止

```bash
~/dotfiles/scripts/ralph-orchestrate.sh results
```

全結果を stdout で一括取得し、以下の情報をユーザーに報告して停止する:

- 各タスクの完了状態 (done / dead)
- 各 worker の結果サマリー
- tmux window の一覧（ユーザーが各 worker を確認できるよう）

ここで停止する。merge、cleanup、PR 作成は行わない。

次のステップはユーザーが判断する:
- tmux window で各 worker の diff を直接確認
- `/ralph-collect send T-1 "PRを作成して"` で worker に指示
- `/ralph-collect save-all` で変更を保存
- `/ralph-cleanup` で後片付け

## 注意事項

- 各ワーカーは独立した git worktree + tmux window で動作
- ワーカーは `/ralph` スキルで起動し、Stop hook + backpressure hook が適用される
- `--dangerously-skip-permissions` は使用しない (初回確認問題を回避)
- ワーカーは sonnet モデルで動作する (コスト最適化)
- 同時実行ワーカー数の上限は4 (リソース制約)
- 完了判定は tmux capture-pane (`-S -`) で RALPH_COMPLETE を検出
- pane 消失 + 結果ファイルなし = dead (クラッシュ or 誤操作)
- worktree も tmux window も片付けない。ユーザーが確認できるよう残す
