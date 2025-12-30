# Claude Code 通知システム

Claude Codeのイベント（完了、承認待ち、入力待ちなど）をSlack通知 + SketchyBarバッジで可視化するシステム。

## 概要

- **Slack通知**: Claude Codeの状態変化をSlack Webhookで通知
- **SketchyBarバッジ**: ワークスペースにバッジを表示し、どのプロジェクトが待機中か一目で把握
- **4環境対応**: Local / Local Container / Cloud / Cloud Container すべてに対応
- **エディタ非依存**: VS Code / Terminal どちらでも動作

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

プロジェクト状態の管理。Aerospaceと連携してワークスペースを特定。

```bash
claude-status.sh set <project> <status> [session_id] [tty]
claude-status.sh get <project>
claude-status.sh list
claude-status.sh clear <project>
claude-status.sh cleanup          # 1時間以上更新なしを削除
claude-status.sh find-workspace <project>
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
│   └── claude-status-watch.sh    # リモート監視
├── common/sketchybar/.config/sketchybar/
│   └── plugins/
│       └── claude.sh             # SketchyBarプラグイン
└── templates/
    └── com.user.claude-status-watch.plist  # launchd テンプレート
```

## 関連設定

- `~/.claude/settings.json` - Claude Code hooks設定
- `~/.local/share/ai-notify/` - Webhookキャッシュ
- `/tmp/claude_status/` - 状態ファイル
