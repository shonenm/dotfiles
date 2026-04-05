---
name: ralph-crew-local
description: 常駐ワーカーの初期化・ディスパッチ・状態確認を行います。launchd と連携して定期的にタスクを注入する自律ワーカー管理システムです。
user-invocable: true
disable-model-invocation: true
arguments: "<subcommand> [args...]"
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Ralph Crew - 定期ディスパッチ自律ワーカー管理

常駐 Claude TUI ワーカーを tmux 上で管理し、設定ファイルのスケジュールに基づいてタスクを定期注入するシステム。

## 使い方

```
/ralph-crew-local init                          # ワーカー起動
/ralph-crew-local dispatch                      # スケジュール評価 + タスク注入
/ralph-crew-local status                        # 全ワーカー状態表示
/ralph-crew-local send <worker-id> "<message>"  # 手動メッセージ送信
/ralph-crew-local restart <worker-id>           # ワーカー再起動
/ralph-crew-local teardown                      # 全停止 + cleanup
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

### 3. launchd で定期実行 (任意)

```bash
# plist テンプレートをコピーしてプレースホルダーを置換
# __INTERVAL__ は秒数 (例: 900 = 15分, 1800 = 30分, 3600 = 1時間)
# __PROJECT__ はプロジェクトの絶対パス
cp ~/dotfiles/templates/com.user.ralph-crew.plist ~/Library/LaunchAgents/
sed -i '' "s|__HOME__|$HOME|g; s|__PROJECT__|/path/to/project|g; s|__INTERVAL__|900|g" ~/Library/LaunchAgents/com.user.ralph-crew.plist

# 登録
launchctl load ~/Library/LaunchAgents/com.user.ralph-crew.plist
```

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
