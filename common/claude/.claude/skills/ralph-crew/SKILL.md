---
name: ralph-crew
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
/ralph-crew init                          # ワーカー起動
/ralph-crew dispatch                      # スケジュール評価 + タスク注入
/ralph-crew status                        # 全ワーカー状態表示
/ralph-crew send <worker-id> "<message>"  # 手動メッセージ送信
/ralph-crew restart <worker-id>           # ワーカー再起動
/ralph-crew teardown                      # 全停止 + cleanup
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
mkdir -p ~/.config/ralph-crew
cp ~/dotfiles/templates/crew.example.json ~/.config/ralph-crew/crew.json
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
cp ~/dotfiles/templates/com.user.ralph-crew.plist ~/Library/LaunchAgents/
sed -i '' "s|__HOME__|$HOME|g; s|__INTERVAL__|900|g" ~/Library/LaunchAgents/com.user.ralph-crew.plist

# 登録
launchctl load ~/Library/LaunchAgents/com.user.ralph-crew.plist
```

### 4. 手動ディスパッチ

```bash
ralph-crew dispatch
```

## 設定ファイル構造

`~/.config/ralph-crew/crew.json`:

- `tmux_session`: tmux セッション名 (default: "ralph-crew")
- `state_dir`: ランタイム状態ディレクトリ (default: "/tmp/ralph-crew")
- `workers[]`: ワーカー定義 (id, project_dir, model, mcp_config, system_prompt, permissions)
- `tasks[]`: タスク定義 (id, pattern, worker_id, prompt, schedule)

テンプレート: `~/dotfiles/templates/crew.example.json`
