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

| プラグイン      | 役割                                   |
| --------------- | -------------------------------------- |
| tokyonight.nvim | カラースキーム（デフォルト）           |
| vscode.nvim     | VS Code Dark Modern テーマ             |
| alpha-nvim      | スタートスクリーン                     |
| ascii.nvim      | ASCII アート（alpha用）                |
| bufferline.nvim | タブ/バッファライン                    |
| lualine.nvim    | ステータスライン                       |
| noice.nvim      | コマンドライン・通知UI改善             |
| nui.nvim        | UI コンポーネントライブラリ            |
| mini.icons      | ファイルアイコン                       |
| which-key.nvim  | キーバインドヘルプ表示                 |
| snacks.nvim     | ユーティリティ集（ファイルピッカー等） |
| hlchunk.nvim    | インデントガイド・チャンクハイライト   |
| nvim-hlslens    | 検索マッチ数・位置表示                 |
| nvim-scrollbar  | スクロールバー・診断/Git マーカー      |

### エディタ機能

| プラグイン        | 役割                            |
| ----------------- | ------------------------------- |
| blink.cmp         | 補完エンジン                    |
| friendly-snippets | スニペット集                    |
| flash.nvim        | 高速カーソル移動                |
| mini.ai           | テキストオブジェクト拡張        |
| mini.pairs        | 括弧自動補完                    |
| mini.surround     | 囲み文字操作                    |
| dial.nvim         | インクリメント/デクリメント拡張 |
| yanky.nvim        | ヤンク履歴                      |
| ts-comments.nvim  | コメントトグル                  |
| inc-rename.nvim   | インラインリネーム              |
| vim-visual-multi  | マルチカーソル編集              |
| harpoon2          | 高速ファイルナビゲーション      |
| nvim-ufo          | モダンコードフォールディング    |
| resession.nvim    | セッション管理（保存・復元・削除） |

### AI

| プラグイン        | 役割                                  |
| ----------------- | ------------------------------------- |
| copilot.lua       | GitHub Copilot（インライン補完）      |
| CopilotChat.nvim  | Copilot Chat（対話型コードレビュー等）|
| avante.nvim       | Claude AI 統合（対話型コーディング）  |

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
| nvim-lint    | リンター（CSpell, Mypy）               |

### Git

| プラグイン    | 役割                    |
| ------------- | ----------------------- |
| gitsigns.nvim    | Git 差分表示・hunk 操作       |
| vim-fugitive     | Git コマンド統合              |
| diffview.nvim    | サイドバイサイド diff・履歴   |
| git-conflict.nvim| コンフリクト解決支援          |

### GitHub

| プラグイン | 役割                                |
| ---------- | ----------------------------------- |
| octo.nvim  | GitHub PR/Issue 管理（レビュー等）  |

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

### ターミナル・外部連携

| プラグイン         | 役割                                       |
| ------------------ | ------------------------------------------ |
| toggleterm.nvim    | フローティングターミナル                   |
| vim-tmux-navigator | Neovim ⇔ tmux シームレス移動               |
| remote-nvim.nvim   | リモート/コンテナ開発（Dev Containers 相当）|

### Markdown

| プラグイン            | 役割                             |
| --------------------- | -------------------------------- |
| markdown-preview.nvim | ブラウザプレビュー               |
| render-markdown.nvim  | バッファ内 Markdown レンダリング |

### メディア

| プラグイン | 役割                                         |
| ---------- | -------------------------------------------- |
| image.nvim | ターミナル内画像表示（Kitty Graphics Protocol） |

### テスト

| プラグイン          | 役割                             |
| ------------------- | -------------------------------- |
| neotest             | テストランナー UI                |
| neotest-jest        | Jest アダプター (BFF)            |
| neotest-vitest      | Vitest アダプター (Web)          |
| neotest-python      | pytest アダプター (Agents)       |
| neotest-playwright  | Playwright アダプター (E2E)      |

### デバッグ

| プラグイン            | 役割                           |
| --------------------- | ------------------------------ |
| nvim-dap              | Debug Adapter Protocol 実装    |
| nvim-dap-ui           | DAP UI フロントエンド          |
| nvim-dap-virtual-text | デバッグ変数のバーチャルテキスト |
| nvim-dap-go           | Go デバッガー (delve)          |
| nvim-dap-python       | Python デバッガー (debugpy)    |

### タスクランナー・HTTP

| プラグイン   | 役割                                          |
| ------------ | --------------------------------------------- |
| overseer.nvim| タスクランナー (.vscode/tasks.json, Make 対応) |
| kulala.nvim  | HTTP クライアント (.http ファイル)              |

### データベース

| プラグイン            | 役割                  |
| --------------------- | --------------------- |
| vim-dadbod            | データベースクライアント |
| vim-dadbod-ui         | データベース UI       |
| vim-dadbod-completion | データベース補完      |

## 無効化したプラグイン

| プラグイン       | 理由                      |
| ---------------- | ------------------------- |
| catppuccin       | tokyonight を使用         |
| neotest-golang   | macOS で SIGKILL 発生     |
| persistence.nvim | resession.nvim に置き換え |

## カスタム設定ファイル

```
common/nvim/.config/nvim/lua/plugins/
├── alpha.lua          # スタートスクリーン設定
├── avante.lua         # Claude AI 統合 (avante.nvim)
├── colorscheme.lua    # カラースキーム設定
├── copilot.lua        # Copilot 設定
├── dap.lua            # DAP カスタム設定 (Docker attach)
├── diffview.lua       # Git diff 表示設定
├── disabled.lua       # プラグイン無効化
├── dotenv.lua         # .env ファイルサポート
├── explorer.lua       # ファイルエクスプローラー・snacks設定
├── git.lua            # Git 関連設定 (fugitive, lazygit)
├── git-conflict.lua   # コンフリクト解決設定
├── gitsigns.lua       # Git 行blame設定
├── graphql.lua        # GraphQL LSP + treesitter
├── hlchunk.lua        # インデントガイド設定
├── hlslens.lua        # 検索マッチ表示設定
├── image.lua          # 画像表示設定
├── kulala.lua         # HTTP クライアント設定
├── lint.lua           # CSpell リンター設定
├── multicursor.lua    # マルチカーソル (vim-visual-multi)
├── neotest.lua        # テストランナー設定 (4アダプター)
├── overseer.lua       # タスクランナー設定
├── python-tools.lua   # Python ツール (Ruff formatter + Mypy)
├── remote.lua         # リモート/コンテナ開発 (remote-nvim)
├── scrollbar.lua      # スクロールバー設定
├── session.lua        # セッション管理設定
└── tmux-navigator.lua # tmux 連携設定
```

## キーバインド

LazyVim のデフォルトキーバインドを使用。`<leader>` は `Space`。

### 基本操作

| キー         | 動作                     |
| ------------ | ------------------------ |
| `<leader>ff` | ファイル検索             |
| `<leader>fg` | Grep 検索                |
| `<leader>e`  | ファイルエクスプローラー |
| `<leader>gg` | LazyGit                  |
| `gd`         | 定義へジャンプ           |
| `gr`         | 参照一覧                 |
| `K`          | ホバードキュメント       |
| `<leader>cr` | リネーム                 |
| `<leader>ca` | コードアクション         |

### マルチカーソル

| キー           | 動作                     |
| -------------- | ------------------------ |
| `Ctrl+n`       | 次の一致にカーソル追加   |
| `Ctrl+Shift+Down` | 下にカーソル追加     |
| `Ctrl+Shift+Up`   | 上にカーソル追加     |
| `Ctrl+Shift+l` | 全一致を選択             |
| `Ctrl+x`       | 現在の一致をスキップ     |

### AI

| キー           | 動作                     |
| -------------- | ------------------------ |
| `<leader>aa`   | Avante: AI に質問        |
| `<leader>ae`   | Avante: コード編集       |
| `<leader>ar`   | Avante: リフレッシュ     |

### Git / GitHub

| キー           | 動作                     |
| -------------- | ------------------------ |
| `<leader>gs`   | Git status               |
| `<leader>gb`   | Git blame                |
| `<leader>gd`   | Diffview 開く            |
| `<leader>gf`   | ファイル履歴             |

### タスク・テスト・デバッグ

| キー           | 動作                     |
| -------------- | ------------------------ |
| `<leader>or`   | タスク実行 (Overseer)    |
| `<leader>ot`   | タスクリスト表示         |
| `<leader>hr`   | HTTP リクエスト実行      |

### リモート開発

| キー           | 動作                     |
| -------------- | ------------------------ |
| `<leader>Rs`   | Remote: 接続開始         |
| `<leader>Ri`   | Remote: 情報表示         |
| `<leader>Rx`   | Remote: 接続停止         |
| `<leader>Rl`   | Remote: ログ表示         |

詳細: <https://www.lazyvim.org/keymaps>
