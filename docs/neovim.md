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
| copilot.lua       | GitHub Copilot                  |
| flash.nvim        | 高速カーソル移動                |
| mini.ai           | テキストオブジェクト拡張        |
| mini.pairs        | 括弧自動補完                    |
| mini.surround     | 囲み文字操作                    |
| dial.nvim         | インクリメント/デクリメント拡張 |
| yanky.nvim        | ヤンク履歴                      |
| ts-comments.nvim  | コメントトグル                  |
| inc-rename.nvim   | インラインリネーム              |
| persistence.nvim  | セッション保存・復元            |

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

| プラグイン   | 役割           |
| ------------ | -------------- |
| conform.nvim | フォーマッター |
| nvim-lint    | リンター       |

### Git

| プラグイン    | 役割                    |
| ------------- | ----------------------- |
| gitsigns.nvim  | Git 差分表示・hunk 操作       |
| vim-fugitive   | Git コマンド統合              |
| diffview.nvim  | サイドバイサイド diff・履歴   |

### 検索・診断

| プラグイン         | 役割                          |
| ------------------ | ----------------------------- |
| grug-far.nvim      | プロジェクト全体の検索・置換  |
| todo-comments.nvim | TODO/FIXME コメントハイライト |
| trouble.nvim       | 診断・エラー一覧表示          |

### 言語固有

| プラグイン         | 役割                    |
| ------------------ | ----------------------- |
| rustaceanvim       | Rust 開発支援           |
| crates.nvim        | Cargo.toml クレート情報 |
| venv-selector.nvim | Python 仮想環境選択     |

### ターミナル・外部連携

| プラグイン         | 役割                         |
| ------------------ | ---------------------------- |
| toggleterm.nvim    | フローティングターミナル     |
| vim-tmux-navigator | Neovim ⇔ tmux シームレス移動 |

### Markdown

| プラグイン            | 役割                             |
| --------------------- | -------------------------------- |
| markdown-preview.nvim | ブラウザプレビュー               |
| render-markdown.nvim  | バッファ内 Markdown レンダリング |

## 無効化したプラグイン

| プラグイン     | 理由                   |
| -------------- | ---------------------- |
| catppuccin     | tokyonight を使用      |
| neotest        | 未使用                 |
| neotest-golang | 未使用                 |
| neotest-python | 未使用                 |
| nvim-nio       | neotest 依存（未使用） |

## カスタム設定ファイル

```
common/nvim/.config/nvim/lua/plugins/
├── alpha.lua          # スタートスクリーン設定
├── colorscheme.lua    # カラースキーム設定
├── copilot.lua        # Copilot 設定
├── disabled.lua       # プラグイン無効化
├── explorer.lua       # ファイルエクスプローラー・snacks設定
├── git.lua            # Git 関連設定
├── hlchunk.lua        # インデントガイド設定
├── diffview.lua       # Git diff 表示設定
├── hlslens.lua        # 検索マッチ表示設定
├── scrollbar.lua      # スクロールバー設定
└── tmux-navigator.lua # tmux 連携設定
```

## キーバインド

LazyVim のデフォルトキーバインドを使用。`<leader>` は `Space`。

主要なキーバインド:

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

詳細: <https://www.lazyvim.org/keymaps>
