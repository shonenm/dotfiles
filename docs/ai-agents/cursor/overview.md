# Cursor Agent

> **由来:** **Upstream** Cursor Agent CLI / **Plugin** pi向けCursor provider / **Configuration** settings・MCP・hook連携 / **Custom** 通知・補助スクリプト（[区分](../../provenance.md#区分)）

[Cursor Agent](https://cursor.com/docs/agent/overview) は IDE 内 Agent と `cursor-agent` CLI の両方で使えるコーディングエージェント。dotfiles では Claude / Codex / Gemini / pi と同様、`install.sh` 一発で CLI インストール・設定リンク・通知連携まで行う。

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| cursor-agent CLI | ヘッドレス Agent | `scripts/mac.sh` / `config/tools.linux.bash` (curl install) |
| rules | グローバル振る舞いルール | `common/cursor/.cursor/rules/` → `~/.cursor/rules/` |
| cli-config.json | CLI 権限・承認モード | `templates/cursor-cli-config.json` → `$XDG_CONFIG_HOME/cursor/cli-config.json` |
| statusline | CLI フッター (ctx/model/git/plan) | `common/cursor/.cursor/statusline-command.sh` → `scripts/statusline-render.sh`（Claude と同実装） |
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
3. `cli-config.json`（config dir）と `~/.cursor/hooks.json` をテンプレートから生成
4. 共有 skill を `~/.cursor/skills/` へ symlink、有効な MCP を `~/.cursor/mcp.json` へ生成
5. 1Password から Cursor Webhook をキャッシュ (エントリがある場合)

確認:

```bash
cursor-agent --version
ls -la ~/.cursor/rules/communication.mdc   # dotfiles へのシンボリックリンク
test -f "${XDG_CONFIG_HOME:-$HOME/.config}/cursor/cli-config.json" && echo "cli-config ok"
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

Claude Code と同じ `statusLine.command` 形式。`install.sh` で cli-config.json に設定が入り、`~/.cursor/statusline-command.sh` が stow される。実装は `scripts/statusline-render.sh`（Claude と共有）。

表示内容:

- cwd / git branch / model（`param_summary`・`MAX`・`auto` を含む）
- context 使用率ゲージ（50% 黄・80% 赤）
- Cursor プラン枠（`~/.cache/tmux/cursor_usage` = `ai-usage cursor` と同じキャッシュ。`cursor N% · other M%`）
- worktree / vim / session_name（幅に余裕があるとき）
- cost / duration / diff lines（Claude 側 API が返す場合）

幅（`render_width_chars`）で縮退する: ≥100 detailed、≥70 balanced、<70 minimal（model + ctx + plan）。

状態ダンプは `~/.local/state/cursor/statusline-input.json`（Claude は `…/claude/…`）。更新間隔は 1000ms。

Cursor CLI 内でフッターが見えない場合は `cursor-agent` を再起動する。テンプレート変更後は `dots apply`（または `install.sh` の AI config 生成）で `cli-config.json` を更新する。

### cli-config.json のパス

`cursor-agent` は `CURSOR_CONFIG_DIR` → `$XDG_CONFIG_HOME/cursor` → `~/.cursor` の順で config dir を解決する。dotfiles は `XDG_CONFIG_HOME=~/.config` を設定しているため、正本は `~/.config/cursor/cli-config.json`。`~/.cursor` は data dir 側で、`hooks.json` / `mcp.json` / `rules/` / `skills/` はそのまま。

このファイルは CLI 自身も認証情報・モデル選択・キャッシュの保存に使うため、`install.sh` は上書きせずテンプレートのキーだけをマージする（`write_cursor_cli_config`）。

### CLI UX でできること / できないこと

| 欲しいもの | Cursor CLI | 備考 |
|---|---|---|
| message stash | 不可 | Claude Code 機能。本体に無い |
| C-r 履歴検索 | 不可 | `Ctrl+R` は差分レビュー（`/changes`） |
| `/goal` | 限定 | changelog 上は gated。公式 slash 一覧には未掲載 |
| `/workflow` | 不可 | pi（`pi-dynamic-workflows`）専用 |
| 入力欄の視覚行 ↑↓ | 不可 | 設定項目なし。`↑` は履歴／論理行。`/vim` で hjkl は可 |
| `/rewind` | 可 | テンプレートで `rewind: true` |
| `/setup-terminal` | 可 | Shift+Enter 等の端末キー設定 |

## tmux 使用量表示

tmux サイドバー (`prefix+b`) と pi のカスタムフッターに Cursor のプラン使用量を表示する。どちらも `ai-usage cursor` の同じキャッシュ済みデータを使う。

Pro+ 以降、プラン枠は 2 プールに分かれる。サイドバーはこの 2 つをそのまま並べる。

| 表示 | 意味 |
| --- | --- |
| `cursor` の % | Cursor Models (Composer / Grok / Vega) の利用率 (`autoPercentUsed`) |
| `other` の % | Other Models (Claude / GPT / Gemini) の利用率 (`apiPercentUsed`)。Pro+ は $70 の API 枠 |
| 末尾 | 請求周期終了までの残り日数 |

使用が止まるゲートはプールごとの割合で、どちらかが 100% に達すると on-demand spend に落ちる。非ゼロの利用が 0% と表示されないよう、下限は 1% に丸める (Cursor ダッシュボードと同じ挙動)。

`planUsage.includedSpend / limit` は単一プール時代の名残で使わない。分子が両プール合計の消費額・分母が Other Models だけの枠を指すため、実消費 4% / 1% が 48% に化ける。

データソース: `api2.cursor.sh` の `GetCurrentPeriodUsage` (Pro/Team/Ultra)。Enterprise は `/auth/usage` にフォールバック。

トークン取得 (ai-usage の cursor provider に内蔵、旧 scripts/cursor-auth-token.sh):

1. `CURSOR_AUTH_TOKEN` / `CURSOR_API_KEY` 環境変数
2. macOS Keychain (`cursor-access-token`, cursor-agent login 時)
3. Linux secret-service (同名)
4. cursor-agent CLI の `${XDG_CONFIG_HOME:-~/.config}/cursor/auth.json` (`accessToken`)
5. Cursor IDE の `state.vscdb` (IDE インストール時)

keyring も Cursor IDE も無いリモート/コンテナでは 4 が唯一の取得元になる。

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
| グローバル設定 | `~/.claude/settings.json` (生成) | `~/.config/cursor/cli-config.json` (マージ) |
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
