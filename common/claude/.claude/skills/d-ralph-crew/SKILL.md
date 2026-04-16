---
name: d-ralph-crew
description: 常駐ワーカーの初期化・ディスパッチ・状態確認を行います。ralph-crew daemon が tmux session 内で定期的にタスクを注入する自律ワーカー管理システムです。
user-invocable: true
disable-model-invocation: true
arguments: "<subcommand> [args...]"
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Ralph Crew - 定期ディスパッチ自律ワーカー管理

常駐 Claude TUI ワーカーを tmux 上で管理し、設定ファイルのスケジュールに基づいてタスクを定期注入するシステム。

## 使い方

```
/d-ralph-crew init                          # ワーカー起動
/d-ralph-crew dispatch                      # スケジュール評価 + タスク注入
/d-ralph-crew status                        # 全ワーカー状態表示
/d-ralph-crew send <worker-id> "<message>"  # 手動メッセージ送信
/d-ralph-crew restart <worker-id>           # ワーカー再起動
/d-ralph-crew teardown                      # 全停止 + cleanup
```

## 手順

### 引数をパースしてサブコマンドを実行

```bash
ralph-crew <引数をそのまま渡す>
```

結果をユーザーに報告する。

## セットアップガイド

### 1. 設定ファイルを作成

```bash
# プロジェクトディレクトリで実行
mkdir -p .claude
cp ~/dotfiles/templates/crew.example.json .claude/crew.json
# crew.json を編集: workers, tasks, schedule を設定
```

### 2. ワーカーを起動

```bash
ralph-crew init
# または: ralph-crew init --config /path/to/crew.json
```

### 3. daemon で定期実行

`ralph-crew daemon` を tmux の専用 window に常駐させる。外部 scheduler (launchd/cron) は不要。

```bash
# ralph-crew init で tmux session (default: ralph-crew) と worker を立てておく
tmux new-window -d -t ralph-crew -n scheduler \
  "exec ralph-crew daemon --interval 60 --config /path/to/project/.claude/crew.json"
```

- `--interval` は秒単位の tick (60 秒推奨)。per-task interval は crew.json の `schedule.minutes` で別途評価される。
- tmux-continuum (`@continuum-restore on`) が session を復元。daemon コマンドも含めて復元したい場合は `@resurrect-processes` に `'~ralph-crew daemon'` を追加。
- 停止: `tmux kill-window -t ralph-crew:scheduler` または `kill -TERM $(cat /tmp/ralph-crew/<project-name>/daemon.pid)`。

### 4. 手動ディスパッチ

```bash
ralph-crew dispatch
```

## 設定ファイル構造

`<project>/.claude/crew.json` (プロジェクトディレクトリから自動導出):

- `tmux_session`: tmux セッション名 (default: `crew-<project-name>`)
- `state_dir`: ランタイム状態ディレクトリ (default: `/tmp/ralph-crew/<project-name>`)
- `workers[]`: ワーカー定義 (id, model, mcp_config, system_prompt, permissions)
- `tasks[]`: タスク定義 (id, pattern, worker_id, action, prompt, schedule)
  - `action`: `"fix"` (デフォルト: worktree で修正 -> PR) または `"issue-only"` (報告のみ)

テンプレート: `~/dotfiles/templates/crew.example.json`
