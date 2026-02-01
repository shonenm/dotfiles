# Neovim

LazyVim ベースの Neovim 設定。lazy.nvim によるプラグイン管理。

## プラグイン一覧

### フレームワーク・コア

| プラグイン   | 役割                         |
| ------------ | ---------------------------- |
| LazyVim      | 設定フレームワーク（ベース） |
| lazy.nvim    | プラグインマネージャー       |
| plenary.nvim | Lua ユーティリティライブラリ |

### UI

| プラグイン               | 役割                                   |
| ------------------------ | -------------------------------------- |
| tokyonight.nvim          | カラースキーム（デフォルト）           |
| vscode.nvim              | VS Code Dark Modern テーマ             |
| alpha-nvim               | スタートスクリーン                     |
| ascii.nvim               | ASCII アート（alpha用）                |
| bufferline.nvim          | タブ/バッファライン                    |
| lualine.nvim             | ステータスライン                       |
| noice.nvim               | コマンドライン・通知UI改善             |
| nui.nvim                 | UI コンポーネントライブラリ            |
| mini.icons               | ファイルアイコン                       |
| which-key.nvim           | キーバインドヘルプ表示                 |
| snacks.nvim              | ユーティリティ集（ファイルピッカー等） |
| hlchunk.nvim                | インデントガイド・チャンクハイライト    |
| nvim-hlslens                | 検索マッチ数・位置表示                  |
| nvim-scrollbar              | スクロールバー・診断/Git マーカー       |
| treesitter-context          | 関数/クラスコンテキスト表示             |
| rainbow-delimiters.nvim     | ブラケットペアカラー化                  |
| dropbar.nvim                | VS Code風ブレッドクラムナビゲーション   |
| tiny-inline-diagnostic.nvim | フォーマットされたインライン診断表示    |

### エディタ機能

| プラグイン        | 役割                              |
| ----------------- | --------------------------------- |
| blink.cmp         | 補完エンジン                      |
| friendly-snippets | スニペット集                      |
| flash.nvim        | 高速カーソル移動                  |
| mini.ai           | テキストオブジェクト拡張          |
| mini.pairs        | 括弧自動補完                      |
| mini.surround     | 囲み文字操作                      |
| dial.nvim         | インクリメント/デクリメント拡張   |
| yanky.nvim        | ヤンク履歴                        |
| ts-comments.nvim  | コメントトグル                    |
| inc-rename.nvim   | インラインリネーム                |
| vim-visual-multi  | マルチカーソル編集                |
| harpoon2          | 高速ファイルナビゲーション        |
| LazyVim core fold | LSP ベースコードフォールディング  |
| mini.bufremove    | レイアウト維持バッファ削除     |
| resession.nvim    | セッション管理（保存・復元・削除）|
| neogen            | JSDoc/docstring 自動生成          |
| refactoring.nvim  | Extract function/variable 等      |
| outline.nvim      | シンボルアウトライン              |

### AI

| プラグイン       | 役割                                  |
| ---------------- | ------------------------------------- |
| copilot.lua      | GitHub Copilot（インライン補完）      |
| CopilotChat.nvim | Copilot Chat（対話型コードレビュー等）|
| avante.nvim      | Claude AI 統合（対話型コーディング）  |

### LSP・構文解析

| プラグイン                  | 役割                                        |
| --------------------------- | ------------------------------------------- |
| nvim-lspconfig              | LSP 設定                                    |
| mason.nvim                  | LSP/フォーマッター/リンターのインストーラー |
| mason-lspconfig.nvim        | mason と lspconfig の連携                   |
| nvim-treesitter             | シンタックスハイライト・構文解析            |
| nvim-treesitter-textobjects | Treesitter ベースのテキストオブジェクト     |
| nvim-ts-autotag             | HTML/JSX タグ自動閉じ                       |
| lazydev.nvim                | Neovim Lua 開発補助                         |
| SchemaStore.nvim            | JSON/YAML スキーマ                          |

### フォーマッター・リンター

| プラグイン   | 役割                                    |
| ------------ | --------------------------------------- |
| conform.nvim | フォーマッター（Biome, Prettier, Ruff） |
| nvim-lint    | リンター（CSpell, Mypy, ESLint）       |

### Git

| プラグイン        | 役割                                        |
| ----------------- | ------------------------------------------- |
| gitsigns.nvim     | Git 差分表示・hunk 操作・インライン blame   |
| vim-fugitive      | Git コマンド統合                            |
| codediff.nvim     | サイドバイサイド diff・履歴・stage・commit  |
| git-conflict.nvim | コンフリクト解決支援                        |
| telescope-repo    | リポジトリ/サブモジュール切替               |

### GitHub

| プラグイン    | 役割                               |
| ------------- | ---------------------------------- |
| octo.nvim     | GitHub PR/Issue 管理（レビュー等） |
| gh-dash.nvim  | GitHub Dashboard TUI（PR/Issue 一覧） |

### 検索・診断

| プラグイン         | 役割                          |
| ------------------ | ----------------------------- |
| grug-far.nvim      | プロジェクト全体の検索・置換  |
| todo-comments.nvim | TODO/FIXME コメントハイライト |
| trouble.nvim       | 診断・エラー一覧表示          |

### 言語固有

| プラグイン             | 役割                    |
| ---------------------- | ----------------------- |
| rustaceanvim           | Rust 開発支援           |
| crates.nvim            | Cargo.toml クレート情報 |
| venv-selector.nvim     | Python 仮想環境選択     |
| clangd_extensions.nvim | C/C++ 開発支援 (clangd) |
| solidity (custom)      | Solidity 開発支援 (LSP + treesitter + forge fmt) |
| package-info.nvim      | package.json バージョン表示 (pnpm 対応) |

### ターミナル・外部連携

| プラグイン         | 役割                                        |
| ------------------ | ------------------------------------------- |
| toggleterm.nvim    | フローティングターミナル (lazygit/lazydocker)|
| vim-tmux-navigator | Neovim ⇔ tmux シームレス移動                |
| remote-nvim.nvim   | リモート/コンテナ開発（Dev Containers 相当） |

### Markdown

| プラグイン            | 役割                             |
| --------------------- | -------------------------------- |
| markdown-preview.nvim | ブラウザプレビュー               |
| render-markdown.nvim  | バッファ内 Markdown レンダリング |

### メディア

| プラグイン | 役割                                            |
| ---------- | ----------------------------------------------- |
| image.nvim | ターミナル内画像表示（Kitty Graphics Protocol） |

### テスト

| プラグイン         | 役割                        |
| ------------------ | --------------------------- |
| neotest            | テストランナー UI（overseer 統合） |
| neotest-jest       | Jest アダプター (BFF)       |
| neotest-vitest     | Vitest アダプター (Web)     |
| neotest-python     | pytest アダプター (Agents)  |
| neotest-playwright | Playwright アダプター (E2E) |

neotest は overseer.nvim と統合済み。テスト実行時の出力が overseer パネルにストリーミングされ、履歴管理・再実行が可能。

### デバッグ

| プラグイン            | 役割                             |
| --------------------- | -------------------------------- |
| nvim-dap              | Debug Adapter Protocol 実装      |
| nvim-dap-ui           | DAP UI フロントエンド            |
| nvim-dap-virtual-text | デバッグ変数のバーチャルテキスト |
| nvim-dap-go           | Go デバッガー (delve)            |
| nvim-dap-python       | Python デバッガー (debugpy)      |

### タスクランナー・HTTP

| プラグイン    | 役割                                          |
| ------------- | --------------------------------------------- |
| overseer.nvim | タスクランナー (.vscode/tasks.json, Make 対応) |
| kulala.nvim   | HTTP クライアント (.http ファイル)             |

### データベース

| プラグイン            | 役割                   |
| --------------------- | ---------------------- |
| vim-dadbod            | データベースクライアント |
| vim-dadbod-ui         | データベース UI        |
| vim-dadbod-completion | データベース補完       |

## LazyVim Extras

`lua/config/lazy.lua` で有効化している LazyVim extras:

### 言語サポート

| Extra                | 対象                           |
| -------------------- | ------------------------------ |
| `lang.typescript`    | TypeScript/JavaScript LSP      |
| `lang.json`          | JSON LSP + SchemaStore         |
| `lang.tailwind`      | Tailwind CSS 補完・カラー表示  |
| `lang.python`        | Python LSP (basedpyright)      |
| `lang.rust`          | Rust (rustaceanvim)            |
| `lang.go`            | Go (gopls)                     |
| `lang.sql`           | SQL (vim-dadbod)               |
| `lang.toml`          | TOML                           |
| `lang.yaml`          | YAML                           |
| `lang.clangd`        | C/C++ (clangd)                 |
| `lang.docker`        | Dockerfile/docker-compose LSP  |
| `lang.git`           | git filetype treesitter        |
| `lang.markdown`      | Markdown 強化                  |

### フォーマッター・リンター

| Extra                  | 対象                    |
| ---------------------- | ----------------------- |
| `formatting.biome`     | Biome (JS/TS)           |
| `formatting.prettier`  | Prettier (fallback)     |
| `linting.eslint`       | ESLint                  |

### コーディング

| Extra                  | 対象                    |
| ---------------------- | ----------------------- |
| `coding.mini-surround` | 囲み文字操作            |
| `coding.yanky`         | ヤンク履歴              |
| `coding.neogen`        | JSDoc/docstring 生成    |

### エディタ

| Extra                  | 対象                    |
| ---------------------- | ----------------------- |
| `editor.harpoon2`      | ファイルナビゲーション  |
| `editor.dial`          | インクリメント拡張      |
| `editor.inc-rename`    | インラインリネーム      |
| `editor.outline`       | シンボルアウトライン    |
| `editor.refactoring`   | リファクタリング操作    |

### UI

| Extra                    | 対象                    |
| ------------------------ | ----------------------- |
| `ui.treesitter-context`  | 関数/クラスコンテキスト |

### テスト・デバッグ

| Extra       | 対象              |
| ----------- | ----------------- |
| `test.core` | neotest コア      |
| `dap.core`  | nvim-dap コア     |

### AI

| Extra             | 対象              |
| ----------------- | ----------------- |
| `ai.copilot-chat` | Copilot Chat      |

### ユーティリティ

| Extra      | 対象                  |
| ---------- | --------------------- |
| `util.octo`| GitHub PR/Issue 管理  |
| `util.dot` | dotfiles サポート     |

## 無効化したプラグイン

| プラグイン       | 理由                      |
| ---------------- | ------------------------- |
| catppuccin       | tokyonight を使用         |
| neotest-golang   | macOS で SIGKILL 発生     |
| persistence.nvim | resession.nvim に置き換え |

## カスタム設定ファイル

```
common/nvim/.config/nvim/lua/plugins/
├── alpha.lua              # スタートスクリーン設定
├── avante.lua             # Claude AI 統合 (avante.nvim)
├── buffer.lua             # バッファ管理 (mini.bufremove)
├── colorscheme.lua        # カラースキーム設定
├── copilot.lua            # Copilot 設定
├── dap.lua                # DAP カスタム設定 (Docker attach, Playwright debug)
├── codediff.lua           # Git diff 表示設定
├── disabled.lua           # プラグイン無効化
├── dotenv.lua             # .env ファイルサポート
├── explorer.lua           # ファイルエクスプローラー・snacks設定 (frecency)
├── git.lua                # Git 関連設定 (fugitive, lazygit, lazydocker)
├── gh-dash.lua            # GitHub Dashboard TUI (gh-dash.nvim)
├── git-conflict.lua       # コンフリクト解決設定
├── git-worktree.lua       # telescope-repo (サブモジュール/リポジトリ切替)
├── gitsigns.lua           # Git 行blame設定 (GitLens相当)
├── graphql.lua            # GraphQL LSP + treesitter
├── hlchunk.lua            # インデントガイド設定
├── hlslens.lua            # 検索マッチ表示設定
├── image.lua              # 画像表示設定
├── kulala.lua             # HTTP クライアント設定
├── lint.lua               # CSpell リンター設定
├── multicursor.lua        # マルチカーソル (vim-visual-multi)
├── neotest.lua            # テストランナー設定 (4アダプター, monorepo対応)
├── overseer.lua           # タスクランナー設定 (タスク出力表示強化)
├── package-info.lua       # package.json バージョン表示 (pnpm)
├── python-tools.lua       # Python ツール (Ruff + Mypy + basedpyright extraPaths)
├── rainbow-delimiters.lua # ブラケットペアカラー化
├── remote.lua             # リモート/コンテナ開発 (remote-nvim)
├── scrollbar.lua          # スクロールバー設定
├── session.lua            # セッション管理設定
├── solidity.lua           # Solidity 開発支援 (LSP, treesitter, forge fmt)
├── tiny-inline-diagnostic.lua # インライン診断表示 (virtual_text 置換)
├── tmux-navigator.lua     # tmux 連携設定
├── typescript-enhanced.lua # vtsls 設定 (import, inlay hints)
└── dropbar.lua            # ブレッドクラムナビゲーション
```

## キーバインド

LazyVim のデフォルトキーバインドを使用。`<leader>` は `Space`。

### 基本操作

| キー             | 動作                     |
| ---------------- | ------------------------ |
| `<leader>ff`     | ファイル検索             |
| `<leader>fg`     | Grep 検索                |
| `<leader><space>`| Smart Find Files (frecency) |
| `<leader>fr`     | 最近開いたファイル       |
| `<leader>e`      | ファイルエクスプローラー |
| `<leader>gg`     | LazyGit                  |
| `gd`             | 定義へジャンプ           |
| `gr`             | 参照一覧                 |
| `K`              | ホバードキュメント       |
| `<leader>cr`     | リネーム                 |
| `<leader>ca`     | コードアクション         |
| `<leader>cs`     | シンボルアウトライン     |

### マルチカーソル

| キー               | 動作                   |
| ------------------ | ---------------------- |
| `Ctrl+n`           | 次の一致にカーソル追加 |
| `Ctrl+Shift+Down`  | 下にカーソル追加       |
| `Ctrl+Shift+Up`    | 上にカーソル追加       |
| `Ctrl+Shift+l`     | 全一致を選択           |
| `Ctrl+x`           | 現在の一致をスキップ   |

### バッファ

| キー         | 動作                           |
| ------------ | ------------------------------ |
| `<leader>bd` | バッファ削除（レイアウト維持） |
| `<leader>bD` | バッファ強制削除               |

### AI

| キー         | 動作                 |
| ------------ | -------------------- |
| `<leader>aa` | Avante: AI に質問    |
| `<leader>ae` | Avante: コード編集   |
| `<leader>ar` | Avante: リフレッシュ |

### Git / GitHub

| キー         | 動作                             |
| ------------ | -------------------------------- |
| `<leader>gs` | Git status                       |
| `<leader>gb` | Git blame                        |
| `<leader>gd` | CodeDiff 開く                    |
| `<leader>gf` | ファイル履歴                     |
| `<leader>gF` | コミット履歴                     |
| `<leader>gH` | GH Dash（GitHub Dashboard）      |
| `<leader>gR` | リポジトリ/サブモジュール切替    |

### CodeDiff 内操作

| キー | 動作                          |
| ---- | ----------------------------- |
| `-`  | ファイル stage/unstage トグル |
| `S`  | 全ファイル stage              |
| `U`  | 全ファイル unstage            |
| `X`  | 変更を破棄 (restore)         |
| `cc` | Git commit (fugitive)         |
| `ca` | Git commit --amend            |
| `R`  | エクスプローラー更新          |

### タスク・テスト・デバッグ

| キー         | 動作                     |
| ------------ | ------------------------ |
| `<leader>or` | タスク実行 (Overseer)    |
| `<leader>ot` | タスクリスト表示         |
| `<leader>ob` | タスクビルド             |
| `<leader>oa` | タスククイックアクション |
| `<leader>ol` | 直前タスク出力表示       |
| `<leader>hr` | HTTP リクエスト実行      |

### Docker

| キー         | 動作                     |
| ------------ | ------------------------ |
| `<leader>od` | Lazydocker               |

### パッケージ管理 (package.json)

| キー         | 動作                     |
| ------------ | ------------------------ |
| `<leader>np` | バージョン表示トグル     |
| `<leader>nu` | パッケージ更新           |
| `<leader>nd` | パッケージ削除           |
| `<leader>ni` | パッケージ追加           |
| `<leader>nc` | バージョン変更           |

### リモート開発

| キー         | 動作             |
| ------------ | ---------------- |
| `<leader>Rs` | Remote: 接続開始 |
| `<leader>Ri` | Remote: 情報表示 |
| `<leader>Rx` | Remote: 接続停止 |
| `<leader>Rl` | Remote: ログ表示 |

詳細: <https://www.lazyvim.org/keymaps>

## DAP デバッグ構成

| 名前                             | 対象                                |
| -------------------------------- | ----------------------------------- |
| Attach to Docker (port 9229)     | BFF コンテナへの Node.js アタッチ   |
| Debug Playwright Tests           | Playwright E2E テスト (headed mode) |
| Python debugpy                   | Python デバッグ (pytest 対応)       |
| Go delve                         | Go デバッグ                         |

## 自動化

- TypeScript/JavaScript 保存時に import 自動整理 (`source.organizeImports`、同期実行で conform.nvim との競合を回避)
- 外部ファイル変更の自動リロード (`checktime`)
- 空の `[No Name]` バッファを非表示時に自動削除 (`BufHidden`)
- Lazy popup のフォーカス喪失時に自動 close (`BufLeave`)
- snacks.nvim picker で frecency（頻度+新しさ）ベースのファイルソート

## TypeScript Inlay Hints

vtsls で TypeScript/JavaScript の inlay hints を設定済み:

- **パラメータ名**: リテラル引数にパラメータ名を表示
- **パラメータ型**: 関数パラメータの型を表示
- **変数型**: 変数の推論された型を表示
- **プロパティ宣言型**: プロパティの型を表示
- **関数戻り値型**: 関数の戻り値型を表示
- **enum メンバー値**: enum の値を表示

トグル: `<leader>uh`
