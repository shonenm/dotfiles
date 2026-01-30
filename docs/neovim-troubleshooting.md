# Neovim トラブルシューティング

## SIGKILL (exit 137) でクラッシュ

**日付**: 2026-01-30
**環境**: macOS (Apple Silicon), nvim 0.11.5, LazyVim

### 症状

- nvim が起動直後に閉じる、またはファイルを開くと SIGKILL (exit 137) で死ぬ
- `:` を押しても反応しない（noice.nvim cmdline フリーズ）
- `nvim --clean` では正常動作

### 原因

3つの問題が同時発生していた:

1. **omnisharp (LazyVim extra)** が起動時に SIGKILL を引き起こしていた
2. **treesitter パーサー破損** — `vim.so`, `markdown.so`, `rust.so` 等のコンパイル済みパーサーが壊れ、該当ファイルタイプを開くとネイティブコードがクラッシュ
3. **treesitter クエリ不整合** — `nvim-treesitter` の `vim` 言語クエリが `"tab"` ノードタイプを参照しているが、パーサーが対応していなかった。これにより `noice.nvim` の cmdline ハイライトが壊れ、全インタラクティブ操作が不能に

### 修正手順

```bash
# 1. omnisharp を無効化 (lazy.lua で該当行をコメントアウト)
# { import = "lazyvim.plugins.extras.lang.omnisharp" },

# 2. treesitter パーサーを全削除・再コンパイル
rm -rf ~/.local/share/nvim/site/parser/
nvim --headless -c "TSUpdate" -c "sleep 60" -c "qa!"

# 3. vim パーサーを個別に再インストール (noice.nvim cmdline 修正)
nvim --headless -c "TSInstall! vim" -c "sleep 30" -c "qa!"

# 4. (必要に応じて) luac キャッシュクリア
rm -rf ~/.cache/nvim/luac
```

### 診断方法メモ

```bash
# ファイルタイプ別にクラッシュを確認
nvim --headless -c "edit /tmp/test.md" -c "sleep 3" -c "qa!"
echo $?  # 137 ならクラッシュ

# treesitter パーサーが原因か確認 (パーサー削除で開けるなら確定)
rm -rf ~/.local/share/nvim/site/parser/
nvim --headless -c "edit /tmp/test.md" -c "sleep 3" -c "qa!"

# noice.nvim のエラーログ確認
cat ~/.local/state/nvim/noice.log
```

### 関連変更

- `lazy.lua`: omnisharp コメントアウト
- mason の omnisharp パッケージも削除済み (`~/.local/share/nvim/mason/packages/omnisharp`)

---

## VSCode → Neovim 移行 (syntopic-platform)

**日付**: 2026-01-30
**目的**: syntopic-platform の開発環境を VSCode から Neovim に完全移行

### 対象リポジトリの技術スタック

| 領域 | 技術 |
|------|------|
| Frontend | TypeScript, React 18, Vite, Tailwind CSS, Apollo Client |
| Backend (BFF) | TypeScript, NestJS 11, Apollo Server (GraphQL), TypeORM, PostgreSQL |
| Agents | Python 3.13, FastAPI, Anthropic SDK, LangChain/LangGraph |
| Formatter/Linter | Biome (TS/JS), Prettier (fallback), Ruff (Python) |
| Testing | Jest (BFF), Vitest (Web), Playwright (E2E), pytest (Agents) |
| Infra | Docker Compose, Valkey, Nginx, Jaeger |
| Monorepo | pnpm workspaces + Turbo (TS), uv workspaces (Python) |

### 既存カバー済み

TypeScript/JSON/YAML/TOML/SQL/Python/Docker/Tailwind LSP, Prettier + ESLint, Git (fugitive, gitsigns, diffview, git-conflict, lazygit), Copilot, vim-dadbod, markdown-preview, treesitter auto-tag, resession.nvim, toggleterm

### 追加したプラグイン・設定

#### 1. Biome (Formatter/Linter)

- `lazyvim.plugins.extras.formatting.biome` を `lazy.lua` に追加
- conform.nvim が `biome.json` を検出したプロジェクトで自動適用 (`require_cwd = true`)
- Prettier と共存可能

#### 2. Neotest (テストランナー)

- `disabled.lua` から neotest, neotest-python, nvim-nio を有効化
- 4アダプター追加 (`lua/plugins/neotest.lua`):
  - `neotest-jest` — BFF (NestJS)
  - `neotest-vitest` — Web (React)
  - `neotest-playwright` — E2E
  - `neotest-python` — Agents (pytest)

#### 3. DAP (デバッグ)

- `lazyvim.plugins.extras.dap.core` を `lazy.lua` に追加
- アダプターは LazyVim extras が mason 経由で自動管理:
  - `lang.typescript` + `dap.core` → `js-debug-adapter` (pwa-node/pwa-chrome/pwa-msedge)
  - `lang.python` + `dap.core` → `debugpy`
- カスタム設定 (`lua/plugins/dap.lua`): Docker attach のみ (port 9229, localRoot/remoteRoot マッピング)
- `nvim-dap-vscode-js` + `microsoft/vscode-js-debug` ソースビルドは非推奨。lazy.nvim が git リポジトリとして管理するため `npm install` が `package-lock.json` を変更し更新不能になる

#### 4. overseer.nvim (タスクランナー)

- `lua/plugins/overseer.lua` を新規作成
- `.vscode/tasks.json` をネイティブで読み取り可能
- Make, npm, cargo タスクも自動検出
- キーマップ: `<leader>or` (Run), `<leader>ot` (Toggle)

#### 5. GraphQL サポート

- `lua/plugins/graphql.lua` を新規作成
- LSP: `graphql-language-service-cli` (mason 経由)
- Treesitter: `graphql` パーサー

#### 6. CSpell (コードスペルチェッカー)

- `lua/plugins/lint.lua` を新規作成
- nvim-lint 経由で `cspell` を TS/JS/Python/Markdown に適用
- 前提: `npm install -g cspell`

#### 7. kulala.nvim (HTTP クライアント)

- `lua/plugins/kulala.lua` を新規作成
- `.http` ファイルから HTTP/GraphQL/WebSocket リクエスト実行
- キーマップ: `<leader>hr` (Run), `<leader>ha` (All), `<leader>he` (Env)

### 追加不要と判明したもの

- **Ruff**: `lazyvim.plugins.extras.lang.python` が既に ruff LSP を含む
- **Python debugpy**: `lang.python` + `dap.core` で自動インストール
- **.env**: 低優先度、treesitter dotenv パーサーのみで十分

### 変更ファイル一覧

| ファイル | 操作 |
|---------|------|
| `lua/config/lazy.lua` | `formatting.biome`, `dap.core` extras 追加 |
| `lua/plugins/disabled.lua` | neotest, neotest-python, nvim-nio を有効化 |
| `lua/plugins/neotest.lua` | 新規: 4アダプター設定 |
| `lua/plugins/dap.lua` | 新規: Docker attach configuration |
| `lua/plugins/overseer.lua` | 新規: タスクランナー |
| `lua/plugins/graphql.lua` | 新規: GraphQL LSP + treesitter |
| `lua/plugins/lint.lua` | 新規: cspell |
| `lua/plugins/kulala.lua` | 新規: HTTP クライアント |
