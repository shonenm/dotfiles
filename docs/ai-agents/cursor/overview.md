# Cursor Agent

[Cursor Agent](https://cursor.com/docs/agent/overview) は IDE 内 Agent と `cursor-agent` CLI の両方で使えるコーディングエージェント。dotfiles では Claude / Codex / Gemini / pi と同様、`install.sh` 一発で CLI インストール・設定リンク・通知連携まで行う。

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| cursor-agent CLI | ヘッドレス Agent | `scripts/mac.sh` / `config/tools.linux.bash` (curl install) |
| rules | グローバル振る舞いルール | `common/cursor/.cursor/rules/` → `~/.cursor/rules/` |
| cli-config.json | CLI 権限・承認モード | `templates/cursor-cli-config.json` → `~/.cursor/cli-config.json` |
| hooks.json | 完了通知 | `templates/cursor-hooks.json` → `~/.cursor/hooks.json` |
| d-* skills | dotfiles ワークフロー | `common/claude/.claude/skills/` → `~/.claude/skills/` (Cursor 互換読み込み) |
| 共有 MCP / skills | ツール横断設定 | `common/agent/.config/agent/` → `~/.config/agent/` |

## セットアップ

### 1. install.sh を実行

```bash
cd ~/dotfiles
./install.sh
```

実行内容:

1. `cursor-agent` CLI をインストール (未インストール時)
2. `stow` で `common/cursor/` をリンク (`~/.cursor/rules/`)
3. `~/.cursor/cli-config.json` と `~/.cursor/hooks.json` をテンプレートから生成
4. 1Password から Cursor Webhook をキャッシュ (エントリがある場合)

確認:

```bash
cursor-agent --version
ls -la ~/.cursor/rules/communication.mdc   # dotfiles へのシンボリックリンク
test -f ~/.cursor/cli-config.json && echo "cli-config ok"
test -f ~/.cursor/hooks.json && echo "hooks ok"
```

### 2. 認証

Cursor アカウントで CLI にログインする:

```bash
cursor-agent login
```

または環境変数 `CURSOR_API_KEY` を設定する。

### 3. Slack 通知 (任意)

1Password に Webhook エントリを追加:

```
Item: Cursor Webhook
Field: password (Slack Incoming Webhook URL)
Reference: op://Personal/Cursor Webhook/password
```

手動キャッシュ:

```bash
ai-notify.sh --setup cursor
```

## スキル

Cursor は以下からスキルを自動読み込みする:

| パス | 内容 |
| --- | --- |
| `~/.cursor/skills/` | Cursor 専用スキル |
| `~/.claude/skills/` | Claude 互換 (dotfiles の `d-*` スキル) |
| `~/.config/agent/skills/` | ツール横断共有スキル |

dotfiles の `d-commit`, `d-pr`, `d-issue` 等は `common/claude/.claude/skills/` 経由で Claude と Cursor 両方から使える。

## CLI の使い方

```bash
# 対話セッション
cursor-agent

# 非対話 (スクリプト向け)
cursor-agent -p "fix the failing test in src/foo.test.ts"

# プラン / 質問モード
cursor-agent --plan "design a caching layer for the API"
cursor-agent --mode ask "explain how auth middleware works"
```

## 他エージェントとの違い

| 項目 | Claude Code | Cursor |
| --- | --- | --- |
| インストール | npm global | curl (`cursor.com/install`) |
| グローバル設定 | `~/.claude/settings.json` (生成) | `~/.cursor/cli-config.json` (生成) |
| ルール形式 | `.claude/rules/*.md` | `.cursor/rules/*.mdc` |
| 通知イベント | stop / permission / idle | stop (完了) |
| SketchyBar 連携 | あり | なし (Slack のみ) |

## 関連

- [Agent Infrastructure Spec](../../specs/agent-infrastructure.md) — ツール横断の設計原則
- [1Password 連携](../../configuration/1password-integration.md) — Webhook 管理
- [install.sh](../../install/index.md) — セットアップ手順
