# Cursor Agent

> **由来:** **Upstream** Cursor Agent CLI / **Plugin** pi向けCursor provider / **Configuration** settings・MCP・hook連携 / **Custom** 通知・補助スクリプト（[区分](../../provenance.md#区分)）

[Cursor Agent](https://cursor.com/docs/agent/overview) は IDE 内 Agent と `cursor-agent` CLI の両方で使えるコーディングエージェント。dotfiles では Claude / Codex / Gemini / pi と同様、`install.sh` 一発で CLI インストール・設定リンク・通知連携まで行う。

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| cursor-agent CLI | ヘッドレス Agent | `scripts/mac.sh` / `config/tools.linux.bash` (curl install) |
| rules | グローバル振る舞いルール | `common/cursor/.cursor/rules/` → `~/.cursor/rules/` |
| cli-config.json | CLI 権限・承認モード | `templates/cursor-cli-config.json` → `~/.cursor/cli-config.json` |
| statusline | CLI フッター (ctx/model/git) | `common/cursor/.cursor/statusline-command.sh` (Claude と共有) |
| hooks.json | tmux状態・完了通知・`/tmp` deny | `templates/cursor-hooks.json` → `~/.cursor/hooks.json` |
| mcp.json | 共有 MCP | `common/agent/.config/agent/mcp.json` → `~/.cursor/mcp.json` |
| 共有 skills | ツール横断スキル | `common/agent/.config/agent/skills/` → `~/.cursor/skills/` |
| tmux 使用量 | プラン制限の可視化 | `ai-usage cursor` (tools/ai-usage) |
| d-* skills | dotfiles ワークフロー | `common/claude/.claude/skills/` → `~/.claude/skills/` (Cursor 互換読み込み) |

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
4. 共有 skill を `~/.cursor/skills/` へ symlink、有効な MCP を `~/.cursor/mcp.json` へ生成
5. 1Password から Cursor Webhook をキャッシュ (エントリがある場合)

確認:

```bash
cursor-agent --version
ls -la ~/.cursor/rules/communication.mdc   # dotfiles へのシンボリックリンク
test -f ~/.cursor/cli-config.json && echo "cli-config ok"
test -f ~/.cursor/hooks.json && echo "hooks ok"
test -f ~/.cursor/mcp.json && echo "mcp ok"
ls ~/.cursor/skills/
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

Cursor が自動読み込みするパス:

| パス | 内容 |
| --- | --- |
| `~/.cursor/skills/` | 共有 agent skill (`install.sh` が symlink) と Cursor 専用スキル |
| `~/.claude/skills/` | Claude 互換 (dotfiles の `d-*` スキル) |
| `~/.codex/skills/` | Codex 互換 (Codex 導入時は同じ共有 skill が見える) |
| `.cursor/skills/` / `.agents/skills/` | プロジェクト固有 |

`~/.config/agent/skills/` は Cursor の探索対象ではない。正本は `common/agent/.config/agent/skills/` に置き、Codex と同じく runtime ディレクトリへ link する。

dotfiles の `d-commit`, `d-pr`, `d-issue` 等は `common/claude/.claude/skills/` 経由で Claude と Cursor 両方から使える。ハーネス監査は `/d-harness-audit`。

## MCP

`install.sh` は `common/agent/.config/agent/mcp.json` の `enabled: true` (省略時も有効) を `~/.cursor/mcp.json` へ upsert する。ユーザーが追加した server は残す。secret が必要な server は共有 mcp.json に入れず、Claude 専用 mcp と同じく個別登録する。

```bash
test -f ~/.cursor/mcp.json && jq '.mcpServers | keys' ~/.cursor/mcp.json
```

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

## Statusline (CLI フッター)

Claude Code と同じ `statusLine.command` 形式。`install.sh` で `~/.cursor/cli-config.json` に設定が入り、`~/.cursor/statusline-command.sh` が stow される。

表示内容 (Claude と同等):

- cwd / git branch / model
- context 使用率ゲージ (`ctx:████░░░░ 34%`)
- cost / duration / diff lines (API が返す場合)

Cursor CLI 内でフッターが見えない場合は `cursor-agent` を再起動する。

## tmux 使用量表示

tmux サイドバー (`prefix+b`) と pi のカスタムフッターに Cursor のプラン使用量を表示する。どちらも `ai-usage cursor` の同じキャッシュ済みデータを使う。

| 表示 | 意味 |
| --- | --- |
| 1つ目の % | 含まれる使用量の総利用率 (`planUsage.totalPercentUsed`) |
| 2つ目の % | Auto/Composer モデル利用率 (`autoPercentUsed`) |
| 末尾 | 請求周期終了までの残り日数 |

データソース: `api2.cursor.sh` の `GetCurrentPeriodUsage` (Pro/Team/Ultra)。Enterprise は `/auth/usage` にフォールバック。

トークン取得 (ai-usage の cursor provider に内蔵、旧 scripts/cursor-auth-token.sh):

1. `CURSOR_AUTH_TOKEN` / `CURSOR_API_KEY` 環境変数
2. macOS Keychain (`cursor-access-token`, cursor-agent login 時)
3. Linux secret-service (同名)
4. Cursor IDE の `state.vscdb` (IDE インストール時)

手動確認:

```bash
ai-usage cursor
```

tmux 反映:

```bash
tmux source ~/.config/tmux/tmux.conf
```

**注意:** Cursor は公式の安定した usage API を公開していない。非公式エンドポイントのため、将来変更で `--` 表示になる可能性がある。

## pi ハーネス + Cursor 課金

**推奨: `pi-cursor-agent` プロバイダ** — 1 つの pi セッションで Cursor サブスクのモデルを使い、dotfiles 拡張 (permission-gate, mcp-gateway, delegation 等) を維持する。

| 方式 | 可否 | 備考 |
| --- | --- | --- |
| **pi-cursor-agent** (dotfiles 標準) | ✅ | Cursor API + pi ツールブリッジ。`settings.json` の `packages` に同梱 |
| `@netandreus/pi-cursor-provider` | △ | `cursor-agent --print` 子プロセス。Cursor CLI がツール実行 → pi 拡張が効かない |
| pi `delegate_agent` → cursor | ❌ | ハードコードで `pi` のみ spawn |
| 別 tmux ペインで cursor-agent | △ | 並行運用向け。ハーネス統合ではない |

### セットアップ (pi-cursor-agent)

`install.sh` 後、`common/pi/.pi/agent/settings.json` に `npm:pi-cursor-agent` が入る。初回 `pi` 起動時にパッケージが自動インストールされる (または `pi install npm:pi-cursor-agent`)。

```bash
pi
> /login          # Cursor Agent を選択 → ブラウザ OAuth
> /model cursor-agent/composer-2-fast
```

`enabledModels` に `cursor-agent/*` が含まれるため `/models` で Cursor モデルが選べる。

### 代替: netandreus/pi-cursor-provider

Cursor CLI をそのままバックエンドにする薄いラッパ。導入は `pi install npm:@netandreus/pi-cursor-provider` だが、**ツール実行が Cursor CLI 側**になるため pi 拡張との統合は弱い。更新も 2026-02 以降停滞 (v0.1.4)。CLI ラッパー方式を試す場合のみ検討。

### その他

- **シェル委譲:** `cursor-agent -p --trust "task"` を pi の Bash から実行 (別ハーネス)
- **delegate_agent:** サブエージェントは Codex の `pi -p`（Cursor モデルは手動オーバーライド可能）

詳細: [pi overview — Cursor Provider](../pi/overview.md#cursor-provider-pi-cursor-agent)

## 他エージェントとの違い

| 項目 | Claude Code | Cursor |
| --- | --- | --- |
| インストール | npm global | curl (`cursor.com/install`) |
| グローバル設定 | `~/.claude/settings.json` (生成) | `~/.cursor/cli-config.json` (生成) |
| ルール形式 | `.claude/rules/*.md` | `.cursor/rules/*.mdc` |
| 共有 skill | `~/.claude/skills/` (stow) | `~/.cursor/skills/` (install.sh link) + Claude 互換 |
| MCP | `claude mcp add-json` | `~/.cursor/mcp.json` (共有 mcp.json から生成) |
| 通知イベント | lifecycle / permission / idle | sessionStart / prompt / shell / read / edit / thought / stop / sessionEnd |
| Statusline | hooks statusLine | cli-config statusLine |
| tmux 使用量 | ai-usage claude | ai-usage cursor |
| SketchyBar 連携 | あり | なし (Slack のみ) |

## 検証

```bash
scripts/test-cursor-config.sh
scripts/check-markdown-links.py
scripts/check-package-duplication.sh
```

## 関連

- [1Password 連携](../../configuration/1password-integration.md) — Webhook 管理
- [install.sh](../../install/index.md) — セットアップ手順
