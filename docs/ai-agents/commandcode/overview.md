# Command Code

[Command Code](https://commandcode.ai/) はターミナル向け AI コーディングエージェント（`cmd`）。Taste 学習・カスタムスラッシュコマンド・MCP・Hooks をサポートする。dotfiles では Claude / Cursor と同様に `install.sh` で CLI 導入・設定リンク・通知連携まで行う。

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| command-code CLI | 対話セッション | `config/packages.npm.txt` → グローバル npm |
| settings.json | tmux状態・Stop時Slack通知 | `templates/commandcode-settings.json` → `~/.commandcode/settings.json` |
| カスタムコマンド | 再利用プロンプト | `common/commandcode/.commandcode/commands/` → `~/.commandcode/commands/` |
| d-* skills | dotfiles ワークフロー | `common/claude/.claude/skills/` → `~/.commandcode/skills/`（install.sh で symlink） |
| MCP | ツール横断設定 | `common/agent/.config/agent/mcp.json` → `cmd mcp add-json --scope user` |
| 共有 agent 設定 | MCP / skills / knowledge | `common/agent/.config/agent/` → `~/.config/agent/` |

## セットアップ

### 1. install.sh を実行

```bash
cd ~/dotfiles
./install.sh
```

実行内容:

1. `command-code` をグローバル npm インストール（未インストール時）
2. `stow` で `common/commandcode/` をリンク
3. `~/.commandcode/settings.json` をテンプレートから生成
4. `PreToolUse` / `PostToolUse` / `Stop` hookでtmux状態を連携
5. `d-*` スキルを `~/.commandcode/skills/` に symlink
6. 有効な MCP サーバーを `cmd mcp add-json` で登録（`cmd` が PATH にある場合）
7. 1Password に Webhook がある場合は `ai-notify.sh --setup cmd`

確認:

```bash
cmd --version
ls -la ~/.commandcode/commands/onboard.md
test -f ~/.commandcode/settings.json && echo "settings ok"
ls -la ~/.commandcode/statusline-command.sh  # claude への symlink
ls ~/.commandcode/skills/   # d-commit 等への symlink
```

### 2. 認証

```bash
cmd login
```

ブラウザで認証。API キーは `~/.commandcode/auth.json`（stow 対象外・gitignore）。

### 3. 初回セッション

```bash
cd ~/dotfiles   # または任意プロジェクト
cmd --trust     # 初回の trust プロンプトをスキップ
```

おすすめの初手:

| 操作 | 説明 |
| --- | --- |
| `/learn-taste` | Claude Code / Cursor 等の過去セッションから Taste を学習 |
| `/ide` | Cursor / VS Code と接続（開いているファイル・選択範囲をコンテキストに） |
| `/onboard` | dotfiles 用カスタムコマンド（`onboard.md`） |
| `/d-commit` | 既存 d-commit スキル（symlink 経由） |

### 4. Slack 通知（任意）

1Password に Webhook エントリを追加:

```
Item: Command Code Webhook
Field: password (Slack Incoming Webhook URL)
Reference: op://Personal/Command Code Webhook/password
```

手動キャッシュ:

```bash
ai-notify.sh --setup cmd
```

## スキルとコマンド

- **スキル**: `~/.commandcode/skills/` — Agent Skills 標準（`SKILL.md`）。dotfiles の `d-*` は Claude と共有。
- **カスタムコマンド**: `~/.commandcode/commands/*.md` — `/ファイル名` でプロンプト展開。`$ARGUMENTS`, `$1` 等が使える。
- **共有 agent**: `~/.config/agent/skills/` も他ツールと共通（Command Code は `.commandcode/skills/` を優先）。

## MCP

`install.sh` は `common/agent/.config/agent/mcp.json` の `enabled: true` のみを `--scope user` で登録する。手動追加例:

```bash
cmd mcp add --transport http notion https://mcp.notion.com/mcp
cmd mcp list
```

セッション内は `/mcp` で接続管理。

## 参考リンク

- [Quickstart](https://commandcode.ai/docs/quickstart)
- [Slash Commands](https://commandcode.ai/docs/reference/slash-commands)
- [IDE Integration](https://commandcode.ai/docs/core-concepts/ide-integration)
- [Hooks](https://commandcode.ai/docs/hooks)
