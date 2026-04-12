---
name: _ralph-collect
description: ralph-parallel で完了した worker の成果物を回収します。worker への指示送信、変更の保存、結果表示を行います。
user-invocable: true
disable-model-invocation: true
arguments: "<subcommand> [args...]"
allowed-tools: Bash, Read
---

# Ralph Collect - 成果物回収

`/_ralph-parallel` で完了した worker の成果物を回収するスキル。ユーザーがレビュー後に呼び出す。

自動 merge は行わない。worker に PR 作成を指示するか、ユーザーが手動で merge する。

## サブコマンド

### send - worker に指示を送信

指定した worker の claude TUI に tmux send-keys でメッセージを送信する。worker が入力待ち状態であることが前提。

```bash
ralph-orchestrate send <task-id> "<message>"
```

使用例:
```
/_ralph-collect send T-1 "変更のサマリーを出力して"
/_ralph-collect send T-2 "この関数のエッジケースのテストを追加して"
/_ralph-collect send T-3 "git diff を見せて"
```

### save / save-all - 変更を保存

worker の変更を stage + commit + patch 生成で保存する。

```bash
# 個別
ralph-orchestrate save <task-id>

# 一括
ralph-orchestrate save-all
```

### results - 結果表示

全 worker の結果ファイルを stdout に出力する。

```bash
ralph-orchestrate results
```

### status - 状態確認

```bash
ralph-orchestrate status
ralph-orchestrate status --json
```

## 実行ルール

- このスキルは自律実行しない。引数で指定されたサブコマンドを1つ実行して完了する。複数のサブコマンドを実行する場合はユーザーが繰り返し呼び出す
- worker への指示は全て `ralph-orchestrate send` 経由で tmux の Claude TUI に送ること。Task ツール (ralph-worker subagent) へのフォールバックは禁止。Agent サブプロセスは tmux 上に表示されず、ユーザーが進捗を追えなくなる
- worker が permission prompt で停止した場合は、worktree の `.claude/settings.local.json` にパーミッションを追加して対処する
