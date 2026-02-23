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
| nvim-scrollbar              | スクロールバー・診断/Git マーカー（高視認性設定） |
| treesitter-context          | 関数/クラスコンテキスト表示             |
| rainbow-delimiters.nvim     | ブラケットペアカラー化                  |
| dropbar.nvim                | VS Code風ブレッドクラムナビゲーション（cwd相対パス表示） |
| tiny-inline-diagnostic.nvim | インライン診断表示（ERROR/WARN/INFO のみ） |
| snacks.scroll               | スムーズスクロール（無効化：長押し時に重い問題） |
| wrapped.nvim                | Neovim 使用統計ダッシュボード                    |

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
| nvim-lint    | リンター（CSpell（HINT severity）, Mypy, ESLint） |

### Git

| プラグイン        | 役割                                        |
| ----------------- | ------------------------------------------- |
| gitsigns.nvim     | Git 差分表示・hunk 操作・インライン blame   |
| vim-fugitive      | Git コマンド統合                            |
| codediff.nvim     | サイドバイサイド diff・履歴・stage・commit・マルチrepo |
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
| typst-preview.nvim     | Typst ブラウザプレビュー    |
| fancy-cat (external)   | ターミナル内 PDF ビューア (Kitty graphics, hot-reload) |

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

| プラグイン         | 役割                                                    |
| ------------------ | ------------------------------------------------------- |
| snacks.nvim (image)| ターミナル内画像表示（Kitty Graphics Protocol、SSH対応）|

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
| `lang.typst`         | Typst (Tinymist LSP + typst-preview + typstyle) |

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
| image.nvim       | snacks.nvim image に置き換え |

## カスタム設定ファイル

```
common/nvim/.config/nvim/lua/plugins/
├── alpha.lua              # スタートスクリーン設定
├── avante.lua             # Claude AI 統合 (avante.nvim)
├── buffer.lua             # バッファ管理 (mini.bufremove)
├── colorscheme.lua        # カラースキーム設定
├── copilot.lua            # Copilot 設定
├── dadbod.lua             # データベース (DBUI + pgcli/dblab toggleterm)
├── dap.lua                # DAP カスタム設定 (Docker attach, Playwright debug)
├── codediff.lua           # Git diff 表示設定 (カーソル追従 + debounce)
├── disabled.lua           # プラグイン無効化
├── dotenv.lua             # .env ファイルサポート
├── explorer.lua           # ファイルエクスプローラー・snacks設定 (frecency, --no-ignore-vcs)
├── git.lua                # Git 関連設定 (fugitive, lazygit, lazydocker)
├── gh-dash.lua            # GitHub Dashboard TUI (gh-dash.nvim)
├── git-conflict.lua       # コンフリクト解決設定
├── git-worktree.lua       # telescope-repo (サブモジュール/リポジトリ切替)
├── gitsigns.lua           # Git 行blame設定 (GitLens相当)
├── graphql.lua            # GraphQL LSP + treesitter
├── hlchunk.lua            # インデントガイド設定
├── hlslens.lua            # 検索マッチ表示設定
├── image.lua              # 画像表示設定（snacks.nvim image、SSH対応）
├── kulala.lua             # HTTP クライアント設定
├── lint.lua               # CSpell リンター設定 (HINT severity, mise で自動インストール)
├── lualine.lua            # ステータスライン強化 (リポジトリ全体diff, Copilot, LSP名)
├── multicursor.lua        # マルチカーソル (vim-visual-multi)
├── noice.lua              # メッセージ表示最適化 (種類別ルーティング)
├── scroll.lua             # スクロール設定（snacks.scroll 無効化）
├── neotest.lua            # テストランナー設定 (4アダプター, monorepo対応)
├── overseer.lua           # タスクランナー設定 (タスク出力表示強化)
├── package-info.lua       # package.json バージョン表示 (pnpm)
├── pdf.lua                # PDF ビューア (fancy-cat, tmux detach trick)
├── python-tools.lua       # Python ツール (Ruff + Mypy + basedpyright extraPaths)
├── rainbow-delimiters.lua # ブラケットペアカラー化
├── remote.lua             # リモート/コンテナ開発 (remote-nvim)
├── scrollbar.lua          # スクロールバー設定
├── session.lua            # セッション管理設定
├── solidity.lua           # Solidity 開発支援 (LSP, treesitter, forge fmt)
├── tiny-inline-diagnostic.lua # インライン診断表示 (virtual_text 置換)
├── tmux-navigator.lua     # tmux 連携設定
├── typst.lua              # Typst LSP 設定 (Tinymist: exportPdf=onType)
├── typescript-enhanced.lua # vtsls 設定 (import preferences)
├── dropbar.lua            # ブレッドクラムナビゲーション
└── wrapped.lua            # Neovim 使用統計ダッシュボード
```

## キーバインド

LazyVim のデフォルトキーバインドを使用。`<leader>` は `Space`。

### スクロール

| キー   | 動作                              |
| ------ | --------------------------------- |
| `C-d`  | 1/4画面スクロール（下）           |
| `C-u`  | 1/4画面スクロール（上）           |
| `C-f`  | 1画面スクロール（下）             |
| `C-b`  | 1画面スクロール（上）             |

### Insert モード (Emacs スタイル)

| キー  | 動作           |
| ----- | -------------- |
| `C-a` | 行頭へ移動     |
| `C-e` | 行末へ移動     |
| `C-f` | 1文字右へ      |
| `C-b` | 1文字左へ      |
| `C-p` | 前の行へ       |
| `C-n` | 次の行へ       |
| `C-d` | 1文字削除      |
| `C-k` | 行末まで削除   |

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
| `<leader>gd` | CodeDiff 開く（マルチrepo自動検出） |
| `<leader>gf` | ファイル履歴                     |
| `<leader>gF` | コミット履歴                     |
| `<leader>gH` | GH Dash（GitHub Dashboard）      |
| `<leader>gR` | リポジトリ/サブモジュール切替    |

### CodeDiff 内操作

| キー    | 動作                          |
| ------- | ----------------------------- |
| `<Tab>` | Explorer ↔ Diffview 切替      |
| `-`     | ファイル stage/unstage トグル |
| `S`     | 全ファイル stage              |
| `U`     | 全ファイル unstage            |
| `X`     | 変更を破棄 (restore)          |
| `cc`    | Git commit (fugitive)         |
| `ca`    | Git commit --amend            |
| `R`     | エクスプローラー更新          |
| `]r`    | 次のリポジトリタブへ          |
| `[r`    | 前のリポジトリタブへ          |
| `q`     | CodeDiff を閉じる             |

**Diff ビュー内操作:**

| キー    | 動作                                       |
| ------- | ------------------------------------------ |
| `gs`    | Hunk stage（diff ビュー自動更新）          |
| `gr`    | Hunk reset（diff ビュー自動更新）          |
| `gu`    | Hunk unstage（staged view のみ）           |
| `]c`    | 次の hunk へ                               |
| `[c`    | 前の hunk へ                               |
| `do`    | diff obtain (get)                          |
| `dp`    | diff put                                   |
| `<Tab>` | Explorer に戻る                            |

`gs`/`gr` は gitsigns コマンド実行後に diff キャッシュを無効化し、仮想バッファ・実ファイルバッファ・diff 計算結果を自動再読み込みする。ビジュアルモードでの範囲選択にも対応。`gu` は staged diff view（HEAD vs `:0`）でカーソル位置のハンクを `git apply --reverse --cached` で個別 unstage する。

`<leader>gd` はワークスペース内の全 git リポジトリ（parent・submodule・独立 clone）を自動探索し、変更のあるリポジトリごとに CodeDiff タブを開く。複数タブがある場合、ヘルプラインにリポジトリ一覧が表示され、`]r`/`[r` でタブ間を移動できる。

stage/restore/reset 等で全ての変更が解消されると（unstaged・staged・conflicts がすべて空）、CodeDiff タブは自動的に閉じる。revision 比較・ファイル履歴では発動しない。

**コンフリクト解消操作** (git-conflict.nvim):

| キー  | 動作                     |
| ----- | ------------------------ |
| `co`  | Choose ours（自分の変更）|
| `ct`  | Choose theirs（相手の変更）|
| `cb`  | Choose both（両方採用）  |
| `c0`  | Choose none（両方削除）  |
| `]x`  | 次のコンフリクトへ       |
| `[x`  | 前のコンフリクトへ       |
| `cv`  | 3-way ↔ inline 切替     |

コンフリクトがあるファイルを diffview で表示中、ヘルプラインにこれらのキーマップが表示される。

`cv` で 3-way ビュー（theirs | ours | result）と inline ビュー（1 ペインに conflict マーカー付き）を切り替え可能。inline ビューでは git-conflict.nvim がマーカーを検出・ハイライトし、`co`/`ct`/`cb`/`c0` で個別解決できる。inline モード中に explorer で別ファイルを選択すると自動的に 3-way に復帰する。

**ファイル一覧の表示形式:**
```
├─  codediff.lua  src/plugins/    3 M
                                  ^ ^
                              ハンク数 ステータス
```
- ハンク数: 各ファイルの変更ハンク数を表示（1以上の場合のみ）
- ステータス: M(変更), A(追加), D(削除), ??(未追跡)

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

### データベース

| キー         | 動作                     |
| ------------ | ------------------------ |
| `<leader>db` | DBUI トグル              |
| `<leader>df` | DBUI バッファ検索        |
| `<leader>dl` | 直前のクエリ情報         |
| `<leader>dp` | pgcli（フローティング）  |
| `<leader>de` | dblab（フローティング）  |

DBUI 内での操作:
- `<leader>S`: クエリ実行
- `o` / `Enter`: 展開・選択
- `R`: リフレッシュ

詳細: [docs/database.md](database.md)

### Typst / PDF

| キー         | 動作                                       |
| ------------ | ------------------------------------------ |
| `<leader>cp` | PDF プレビュー (fancy-cat, Typst ファイル用) |
| `<leader>cP` | メインファイルピン                         |

- Typst ファイルで `<leader>cp` → 対応する PDF を fancy-cat で開く
- tmux 内: `tmux detach -E` で一時的に tmux を離脱し Ghostty の生ターミナルで fancy-cat を実行（Kitty graphics protocol 対応）、終了後に自動 reattach
- tmux 外: fancy-cat を直接起動
- fancy-cat 未インストール時は `open` (macOS) / `xdg-open` (Linux) にフォールバック

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
- 外部ファイル変更の自動リロード (`checktime` + `fs_event` によるバックグラウンド監視)
  - `FocusGained` / `BufEnter` / `CursorHold` 時にチェック
  - tmux 別ペイン等で外部変更があった場合、フォーカスしなくても即時反映
- 空の `[No Name]` バッファを非表示時に自動削除 (`BufHidden`)
- Lazy popup のフォーカス喪失時に自動 close (`BufLeave`)
- snacks.nvim picker で frecency（頻度+新しさ）ベースのファイルソート
- snacks.nvim picker で `--no-ignore-vcs` により `.gitignore` されたファイルも表示（`~/.config/fd/ignore` で node_modules 等は除外）
- `:ProfileStart` / `:ProfileStop` でカーソル移動等のプロファイリング（`/tmp/nvim-profile.log` に出力）
- LazyVim デフォルトの `lazyvim_wrap_spell` を無効化（日本語テキストが SpellBad 扱いされるのを防止）
- **大きいファイル最適化**: 100KB 以上のファイルを開いた際、syntax / filetype / swapfile / undofile / fold を自動無効化（リモート環境での遅延対策）

## カーソル視認性

モード別にカーソルの色と形状を変更。vscode.nvim lualine テーマと色を統一。

| モード | 色 | 形状 |
|--------|-----|------|
| Normal/Command | 青 `#0a7aca` | ブロック |
| Insert | 緑 `#4EC9B0` | 縦線 |
| Visual | 黄 `#ffaf00` | ブロック |
| Replace | 赤 `#f44747` | 横線 |

- ブリンク: 700ms待機 → 400ms消灯 → 250ms点灯
- `ColorScheme` autocmd で色を設定（カラースキーム変更後も維持）
- `CursorLine` / `CursorLineNr` も強調表示

## ステータスライン (lualine)

LazyVim デフォルトをベースに以下をカスタマイズ:

| セクション | 内容 |
|-----------|------|
| `lualine_b` | branch + **リポジトリ全体 diff サマリ** |
| `lualine_x` | profiler, **Copilot ステータス**, noice, dap, lazy updates |
| `lualine_y` | **LSP サーバー名**, encoding（非utf-8時のみ）, fileformat（非unix時のみ）, progress, location |

- Copilot ステータスは ok=緑, pending=黄, error=赤 のアイコン表示（未ロード時は非表示）
- LSP サーバー名は copilot を除外し、アクティブな言語サーバーのみ表示（例: `vtsls`, `basedpyright`）
- リポジトリ全体の変更ファイル数・追加行・削除行を常時表示（30秒ごと + 保存時・フォーカス復帰時に更新）

## Inlay Hints

LSP inlay hints はグローバルで無効化済み（`vim.g.lazyvim_inlay_hints = false`）。
