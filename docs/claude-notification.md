# Claude Code 通知システム

Claude Codeのイベント（完了、承認待ち、入力待ちなど）をSlack通知 + SketchyBar/tmuxバッジで可視化するシステム。

## 概要

- **Slack通知**: Claude Codeの状態変化をSlack Webhookで通知
- **SketchyBarバッジ**: Aerospaceワークスペースにバッジを表示
- **tmuxバッジ**: tmuxステータスバーにウィンドウ毎のバッジを表示
- **4環境対応**: Local / Local Container / Cloud / Cloud Container すべてに対応
- **エディタ非依存**: VS Code / Terminal / Ghostty+tmux どれでも動作

## 対応環境

| 環境 | 説明 | 通知方式 |
|------|------|----------|
| **Local** | Mac上で直接実行 | 直接SketchyBar更新 |
| **Local Container** | Mac上のDocker Container | bind mount経由 |
| **Cloud** | リモートサーバー (SSH接続) | SSH + inotifywait |
| **Cloud Container** | リモートのDev Container | SSH + inotifywait + bind mount |

## 対応エディタ/ターミナル

ワークスペース検索は以下のアプリケーションに対応:

| アプリ | ウィンドウタイトルから取得 |
|--------|---------------------------|
| **VS Code** | コンテナ名 (`開発コンテナー: xxx @`) またはプロジェクト名 (`— xxx [`) |
| **Ghostty** | ディレクトリ名 |
| **Terminal.app** | ディレクトリ名 |
| **iTerm2** | ディレクトリ名 |
| **Alacritty** | ディレクトリ名 |
| **WezTerm** | ディレクトリ名 |
| **kitty** | ディレクトリ名 |
| **Warp** | ディレクトリ名 |

## アーキテクチャ

### 1. Local (Mac直接)

```
Claude Code (hooks)
    ↓ ai-notify.sh <tool> <event>
    ↓ claude-status.sh set <project> <status>
/tmp/claude_status/*.json
    ↓ sketchybar --trigger claude_status_change
SketchyBar バッジ更新
```

### 2. Local Container (Mac上のDocker)

```
Claude Code (hooks) @ Container
    ↓ ai-notify.sh (ファイル書き込み)
/tmp/claude_status/*.json @ Container
    ↓ bind mount (docker run -v /tmp/claude_status:/tmp/claude_status)
/tmp/claude_status/*.json @ Mac
    ↓ sketchybar --trigger (ai-notify.sh が直接実行)
SketchyBar バッジ更新
```

### 3. Cloud (リモートサーバー)

```
Claude Code (hooks) @ Remote
    ↓ ai-notify.sh (ファイル書き込み)
/tmp/claude_status/*.json @ Remote
    ↓ inotifywait (ファイル変更検知)
    ↓ 永続SSH接続
Mac (claude-status-watch.sh)
    ↓ claude-status.sh set
/tmp/claude_status/*.json @ Mac
    ↓ sketchybar --trigger
SketchyBar バッジ更新
```

### 4. Cloud Container (リモートのDev Container)

```
Claude Code (hooks) @ Container
    ↓ ai-notify.sh (ファイル書き込み)
/tmp/claude_status/*.json @ Container
    ↓ bind mount (devcontainer.json で設定)
/tmp/claude_status/*.json @ Remote Host
    ↓ inotifywait (ファイル変更検知)
    ↓ 永続SSH接続
Mac (claude-status-watch.sh)
    ↓ claude-status.sh set
/tmp/claude_status/*.json @ Mac
    ↓ sketchybar --trigger
SketchyBar バッジ更新
```

## tmux 統合

Ghostty + tmux 環境では、SketchyBar に加えて tmux ステータスバーにもバッジを表示。

### 動作

```
Claude Code (hooks)
    ↓ ai-notify.sh (tmux_session, tmux_window_index を記録)
/tmp/claude_status/window_*.json
    ↓ tmux refresh-client -S
tmux ステータスバー更新
    ↓ tmux-claude-badge.sh (window-status-format から呼び出し)
オレンジバッジ表示（通知数付き）
```

### バッジ表示

- **位置**: 各ウィンドウ名の右側
- **色**: オレンジ背景 (`#ff6600`) + 白文字
- **形状**: 角丸 (Powerline style)
- **内容**: 通知数

### 自動消去

1. ウィンドウにフォーカスして **6秒滞在** → 通知消去
2. ウィンドウを離れる（6秒未満）→ 通知を維持
3. `clear-tmux` コマンドで手動消去も可能

### 設定ファイル

tmux.conf で以下を読み込み:

```bash
# ~/.config/tmux/tmux.conf
source-file ~/.config/tmux/claude-hooks.tmux
```

## コンポーネント

### scripts/ai-notify.sh

メイン通知スクリプト。Claude Code hooksから呼び出される。

```bash
# 使い方
ai-notify.sh <tool> <event>
ai-notify.sh --setup <tool>       # Webhook キャッシュ + セットアップ通知
ai-notify.sh --refresh-cache      # 全ツールのWebhookキャッシュ更新
ai-notify.sh --clear-cache        # キャッシュ削除

# tool: claude | codex | gemini
# event: stop | complete | permission | idle | error
```

**機能**:
- 1PasswordからWebhook URLを取得・キャッシュ
- Slack通知送信（イベントに応じてメンション有無を切替）
- SketchyBar状態更新

### scripts/claude-status.sh

プロジェクト状態の管理。Aerospace/tmuxと連携してワークスペースを特定。

```bash
claude-status.sh set <project> <status> [session_id] [tty] [window_id] [container_name] [tmux_session] [tmux_window_index]
claude-status.sh get <window_id>
claude-status.sh list
claude-status.sh clear <window_id>
claude-status.sh clear-tmux <tmux_session> <tmux_window_index>  # tmuxウィンドウの通知を消去
claude-status.sh cleanup          # 1時間以上更新なしを削除
claude-status.sh find-workspace <window_id>
```

**ワークスペース検索ロジック**:
1. VS Codeウィンドウタイトルからコンテナ名/プロジェクト名を検索
2. ターミナルウィンドウタイトルから検索
3. ウィンドウIDからAerospaceワークスペースを特定

### scripts/claude-status-watch.sh

リモートホストの `/tmp/claude_status/` を監視し、変更をMacに転送。

```bash
claude-status-watch.sh <remote-host>
```

launchdで常駐させ、SSH接続を永続化。

### common/sketchybar/.config/sketchybar/plugins/claude.sh

SketchyBarプラグイン。ワークスペースバッジの表示/非表示を制御。

**トリガー**:
- `claude_status_change`: 状態ファイル変更時
- `front_app_switched`: フォーカス変更時（通知解除）
- `aerospace_workspace_change`: ワークスペース変更時

### templates/com.user.claude-status-watch.plist

リモート監視用のlaunchd設定テンプレート。

### scripts/tmux-claude-badge.sh

tmuxステータスバー用のバッジ表示スクリプト。`window-status-format` から呼び出される。

```bash
tmux-claude-badge.sh window <window_index> [focused]
```

- 指定ウィンドウの通知数をカウントしてバッジを出力
- `focused` 指定時は薄い色で表示

### scripts/tmux-claude-focus.sh

tmuxウィンドウフォーカス時の通知消去処理。`session-window-changed` hookから呼び出される。

- 6秒タイマーで自動消去
- ウィンドウを離れた場合はタイマーキャンセル

### common/tmux/.config/tmux/claude-hooks.tmux

tmux hooks設定ファイル。

```bash
# ウィンドウ切り替え時にフォーカス処理を実行
set-hook -g session-window-changed 'run-shell -b "~/dotfiles/scripts/tmux-claude-focus.sh"'
set-hook -g client-session-changed 'run-shell -b "~/dotfiles/scripts/tmux-claude-focus.sh"'
```

## セットアップ

### 前提条件 (Mac)

- 1Password CLI (`op`)
- jq
- SketchyBar
- Aerospace

### 共通設定

1. **1PasswordにWebhook URLを登録**

   - `op://Personal/Claude Webhook/password` にSlack Webhook URLを保存

2. **Claude Code hooksを設定** (`~/.claude/settings.json`)

   ```json
   {
     "hooks": {
       "Stop": [
         {
           "matcher": "",
           "hooks": ["~/dotfiles/scripts/ai-notify.sh claude stop"]
         }
       ],
       "Notification": [
         {
           "matcher": "",
           "hooks": ["~/dotfiles/scripts/ai-notify.sh claude $CLAUDE_NOTIFICATION_TYPE"]
         }
       ]
     }
   }
   ```

3. **初回セットアップ（Webhookキャッシュ）**

   ```bash
   ai-notify.sh --setup claude
   ```

---

### 1. Local (Mac直接)

追加設定不要。上記の共通設定のみでOK。

---

### 2. Local Container (Mac上のDocker)

1. **bind mountを追加** (docker-compose.yml または docker run)

   ```yaml
   # docker-compose.yml
   volumes:
     - /tmp/claude_status:/tmp/claude_status
   ```

   ```bash
   # docker run
   docker run -v /tmp/claude_status:/tmp/claude_status ...
   ```

2. **DEVCONTAINER_NAME環境変数を設定** (推奨)

   ```yaml
   environment:
     - DEVCONTAINER_NAME=my-project
   ```

---

### 3. Cloud (リモートサーバー)

1. **リモートにinotify-toolsをインストール**

   ```bash
   # apt が使える場合
   sudo apt install inotify-tools

   # sudo不可の場合はソースビルド
   cd /tmp
   curl -LO https://github.com/inotify-tools/inotify-tools/archive/refs/tags/4.23.9.0.tar.gz
   tar xzf 4.23.9.0.tar.gz
   cd inotify-tools-4.23.9.0
   ./autogen.sh && ./configure --prefix=$HOME/.local && make && make install
   ```

2. **Macでlaunchd設定**

   ```bash
   # テンプレートをコピーしてホスト名を編集
   cp ~/dotfiles/templates/com.user.claude-status-watch.plist \
      ~/Library/LaunchAgents/

   # <remote-host> を実際のSSH config ホスト名に変更
   vim ~/Library/LaunchAgents/com.user.claude-status-watch.plist

   # 起動
   launchctl load ~/Library/LaunchAgents/com.user.claude-status-watch.plist
   ```

---

### 4. Cloud Container (リモートのDev Container)

Cloud の設定に加えて:

1. **devcontainer.jsonにbind mountを追加**

   ```json
   {
     "mounts": [
       "source=/tmp/claude_status,target=/tmp/claude_status,type=bind"
     ]
   }
   ```

2. **DEVCONTAINER_NAME環境変数を設定**

   ```json
   {
     "containerEnv": {
       "DEVCONTAINER_NAME": "my-project"
     }
   }
   ```

   これにより、VS Codeのウィンドウタイトル `開発コンテナー: my-project @...` と一致し、正しいワークスペースにバッジが表示される。

## 使い方

### イベント種別

| イベント | Slack通知 | メンション | バッジ色 |
|----------|-----------|------------|----------|
| permission | あり | @here | 黄色 |
| idle | あり | @here | 青 |
| error | あり | @here | 赤 |
| complete | あり | なし | 緑 |
| stop | なし | - | - |

### 手動コマンド

```bash
# 状態確認
claude-status.sh list

# 特定プロジェクトの状態
claude-status.sh get my-project

# 手動で状態設定（テスト用）
claude-status.sh set my-project complete

# 古い状態をクリーンアップ
claude-status.sh cleanup
```

### Service Mode コマンド

Aerospaceの `alt+shift+;` でService Modeに入り:

| キー | 動作 |
|------|------|
| c | 全バッジをクリア |

## トラブルシューティング

### バッジが表示されない

1. 状態ファイルを確認:
   ```bash
   ls -la /tmp/claude_status/
   cat /tmp/claude_status/*.json
   ```

2. ワークスペース検索をテスト:
   ```bash
   claude-status.sh find-workspace my-project
   ```

3. SketchyBarを手動トリガー:
   ```bash
   sketchybar --trigger claude_status_change
   ```

### リモート通知が届かない

1. SSH接続を確認:
   ```bash
   ssh remote-host 'echo ok'
   ```

2. inotifywaitを確認:
   ```bash
   ssh remote-host 'which inotifywait || ls ~/.local/bin/inotifywait'
   ```

3. launchdログを確認:
   ```bash
   cat /tmp/claude-status-watch.err
   ```

4. bind mountを確認:
   ```bash
   # Container内から
   ls -la /tmp/claude_status/

   # Remote host から
   ls -la /tmp/claude_status/
   ```

### Webhookが取得できない

1. 1Passwordにサインイン:
   ```bash
   eval $(op signin)
   ```

2. キャッシュを更新:
   ```bash
   ai-notify.sh --refresh-cache
   ```

3. キャッシュを確認:
   ```bash
   ls -la ~/.local/share/ai-notify/
   ```

## ファイル構成

```
dotfiles/
├── scripts/
│   ├── ai-notify.sh              # メイン通知スクリプト
│   ├── claude-status.sh          # 状態管理
│   ├── claude-status-watch.sh    # リモート監視
│   ├── tmux-claude-badge.sh      # tmuxバッジ表示
│   └── tmux-claude-focus.sh      # tmuxフォーカス処理
├── common/sketchybar/.config/sketchybar/
│   └── plugins/
│       └── claude.sh             # SketchyBarプラグイン
├── common/tmux/.config/tmux/
│   └── claude-hooks.tmux         # tmux hooks設定
└── templates/
    └── com.user.claude-status-watch.plist  # launchd テンプレート
```

## 関連設定

- `~/.claude/settings.json` - Claude Code hooks設定
- `~/.local/share/ai-notify/` - Webhookキャッシュ
- `/tmp/claude_status/` - 状態ファイル
