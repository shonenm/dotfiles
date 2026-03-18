---
name: ralph-collect
description: ralph-parallel で完了した worker の成果物を回収します。worker への指示送信、変更の保存、結果表示を行います。
user-invocable: true
disable-model-invocation: true
arguments: "<subcommand> [args...]"
allowed-tools: Bash, Read
---

# Ralph Collect - 成果物回収

`/ralph-parallel` で完了した worker の成果物を回収するスキル。ユーザーがレビュー後に呼び出す。

自動 merge は行わない。worker に PR 作成を指示するか、ユーザーが手動で merge する。

## サブコマンド

### send - worker に指示を送信

指定した worker の claude TUI に tmux send-keys でメッセージを送信する。worker が入力待ち状態であることが前提。

```bash
~/dotfiles/scripts/ralph-orchestrate.sh send <task-id> "<message>"
```

使用例:
```
/ralph-collect send T-1 "変更のサマリーを出力して"
/ralph-collect send T-2 "この関数のエッジケースのテストを追加して"
/ralph-collect send T-3 "git diff を見せて"
```

### save / save-all - 変更を保存

worker の変更を stage + commit + patch 生成で保存する。

```bash
# 個別
~/dotfiles/scripts/ralph-orchestrate.sh save <task-id>

# 一括
~/dotfiles/scripts/ralph-orchestrate.sh save-all
```

### results - 結果表示

全 worker の結果ファイルを stdout に出力する。

```bash
~/dotfiles/scripts/ralph-orchestrate.sh results
```

### status - 状態確認

```bash
~/dotfiles/scripts/ralph-orchestrate.sh status
~/dotfiles/scripts/ralph-orchestrate.sh status --json
```

## 実行ルール

このスキルは自律実行しない。引数で指定されたサブコマンドを1つ実行して完了する。複数のサブコマンドを実行する場合はユーザーが繰り返し呼び出す。
