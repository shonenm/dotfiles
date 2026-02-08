# tmux

TokyoNight Night テーマ + 透過背景。Ghostty / Neovim 統合対応。

## 基本設定

| 設定 | 値 | 備考 |
|------|-----|------|
| Prefix | `Ctrl+Space` | デフォルト `Ctrl+b` から変更 |
| Default command | `${SHELL}` | non-login shell（pane 起動高速化） |
| Mouse | ON | ドラッグ選択、スクロール対応 |
| Clipboard | OSC52 | SSH 経由でもコピー可能 |
| Focus events | ON | Neovim autoread 等に必要 |
| History limit | 50000 | スクロールバック行数 |
| Passthrough | ON | Kitty graphics protocol（image.nvim 等） |
| Base index | 1 | Window/Pane 番号が 1 から開始 |
| Escape time | 0 | ESC 遅延なし（Neovim 対応） |
| Renumber | ON | Window 削除時に自動採番 |
| Activity | ON | 非アクティブ Window の変更を検知 |
| Terminal title | `#{b:pane_current_path}` | aerospace ウィンドウ検出用 |
| Status interval | 5秒 | ステータスバー更新間隔（遅延対策） |

## キーバインド

全て `prefix` 付き（特記がない限り）。

### which-key メニュー

`prefix + Space` で which-key スタイルのキーバインドヘルプをポップアップ表示。nvim の which-key.nvim と同じ UX。

| キー | 動作 |
|------|------|
| `Space` | メニュー表示 |
| `p` | +Pane サブメニュー（分割、リサイズ、タイトル、sync）|
| `w` | +Window サブメニュー（作成、移動、削除）|
| `s` | +Session サブメニュー（切り替え、リネーム）|
| `o` | +Popup サブメニュー（lazygit, gh-dash 等）|

よく使うショートカットはトップレベルにも配置（`|`, `-`, `g`, `G`, `j`, `f`, `F`, `v`, `r`, `?`）。

### Pane / Window 操作

| キー | 動作 |
|------|------|
| `\|` | 水平分割（カレントパス維持） |
| `-` | 垂直分割（カレントパス維持） |
| `C-h/j/k/l` | Pane 移動（**prefix 不要**、vim-tmux-navigator） |
| `H/J/K/L` | Pane リサイズ（5 セル、リピート可） |
| `n / p` | 次/前 Window（リピート可、1 秒） |
| `C-l / C-h` | 次/前 Window（prefix 付き、プラグイン上書き） |
| `t` | Pane タイトル設定 |
| `T` | Window リネーム |
| `X` | Window 削除（確認あり） |
| `r` | 設定リロード |
| `S` | SYNC モード切替 |
| `F12` | ネストセッション切替（**prefix 不要**） |

### Floating Window (display-popup)

| キー | 動作 | サイズ |
|------|------|--------|
| `g` | lazygit（カレントパスで起動） | 80% × 80% |
| `G` | gh-dash（GitHub Dashboard） | 85% × 85% |
| `P` | pgcli（PostgreSQL クライアント） | 80% × 80% |
| `j` | Scratchpad シェル（永続 `scratch` セッション、トグル） | 80% × 80% |
| `f` | セッション切り替え（fzf + プレビュー） | 60% × 60% |
| `F` | ghq プロジェクト切り替え（fzf） | 60% × 60% |

- `-E` フラグにより、コマンド終了時に popup 自動クローズ
- `d` の pgcli は `$DATABASE_URL` 環境変数があれば使用、なければ `postgresql://postgres:postgres@localhost:5432/postgres` にフォールバック
- `G` の gh-dash は 85% サイズ（列が多いため lazygit より少し大きめ）
- `j` の Scratchpad は永続セッション (`scratch`) を使用。再度 `prefix + j` でトグル（セッション状態を維持）
- `f` はデフォルトの `find-window` を上書き
- `F` はプロジェクト名でセッションを作成（既存なら切り替え）。プロジェクトルートに `.tmux` ファイルがあれば新規セッション時に自動実行

### Copy Mode (vi スタイル)

| キー | 動作 |
|------|------|
| `prefix + v` | Copy Mode に入る |
| `prefix + u` / `prefix + C-u` | Copy Mode に入り即スクロールアップ |
| `v` | 選択開始 |
| `Ctrl+v` | 矩形選択切替 |
| `y` | コピー（OSC52 経由でクリップボードへ） |
| `Enter` / `Esc` | キャンセル |
| `Ctrl+u` / `Ctrl+d` | 4 行スクロール |
| マウスドラッグ | 自動コピー → OSC52（Copy Mode 終了） |

## ステータスバー

位置: 上部（`status-position top`）、透過背景。

```
 Session   1 zsh  2 nvim   CPU 12% | RAM 45% | GPU 8% | SSD 82%   MODE   branch  01/30 15:00   host
```

### 右側セグメント

| セグメント | アイコン | 色 | 内容 |
|------------|----------|-----|------|
| CPU |  | 閾値別（緑/黄/赤） | CPU 使用率（macOS: iostat / Linux: /proc/stat） |
| RAM |  | 閾値別（緑/黄/赤） | メモリ使用率（macOS: vm_stat / Linux: /proc/meminfo） |
| GPU |  | 閾値別（緑/黄/赤） | GPU 使用率（macOS: macmon / Linux: nvidia-smi） |
| Storage |  | 閾値別（紫/黄/赤） | ディスク使用率（80% 以上で表示） |
| モード | なし | モード別 | OFF / COPY / SYNC / PREFIX / NORMAL |
| Git branch |  | 緑 `#9ece6a` | カレントディレクトリのブランチ名 |
| 日時 |  | 青 `#7aa2f7` | `MM/DD HH:MM` |
| ホスト |  | 水色 `#7dcfff` | ホスト名（太字） |

### システム統計の閾値

| メトリクス | 低 (緑) | 中 (黄) | 高 (赤) |
|------------|---------|---------|---------|
| CPU | < 50% | 50-79% | ≥ 80% |
| RAM | < 70% | 70-89% | ≥ 90% |
| GPU | < 50% | 50-79% | ≥ 80% |
| Storage | 80-89% (紫) | 90-94% (黄) | ≥ 95% (赤) |

### モード表示

| モード | 色 | 条件 |
|--------|-----|------|
| OFF | オレンジ `#ff9e64` | ネストセッション（外側無効） |
| COPY | 赤 `#f7768e` | Copy Mode 中 |
| SYNC | ティール `#73daca` | Pane 同期中 |
| PREFIX | 黄 `#e0af68` | Prefix 入力後 |
| NORMAL | 青 `#7aa2f7` | 通常 |

### Window タブ

- 非アクティブ: グレー背景 `#3b4261` + 角丸
- アクティブ: セッション固有のアクセントカラー + 太字 + 角丸（後述「Per-session アクセントカラー」参照）
- Claude 通知バッジ: オレンジ `#ff6600` で件数表示（後述）

## ビジュアル設定

### Pane 枠線

- **スタイル**: 二重線（`pane-border-lines double`）
- **上部ラベル**: `ペイン番号: タイトル or コマンド名`
- **インジケーター**: 矢印 + 色の両方（`both`）

### Pane 枠線のモード色

| 条件 | 枠色 |
|------|------|
| Copy Mode | 赤 `#f7768e` |
| SYNC | ティール `#73daca` |
| Prefix | 黄 `#e0af68` |
| 通常 | 青 `#7aa2f7` |

### 透過設定

- 非アクティブ Pane: 文字を暗く（`fg=colour244`）、背景透過
- アクティブ Pane: 文字を明るく（`fg=colour255`）、背景透過
- ステータスバー: `bg=default`（Tmux 3.2+ 対応）

### Terminal 互換性

- **RGB**: `xterm-256color:RGB` で True Color 対応
- **Undercurl**: `Smulx` + `Setulc` オーバーライドで波線下線対応
- `$TERM` / `$TERM_PROGRAM` を環境変数として更新

## vim-tmux-navigator

`C-h/j/k/l` で Neovim ⇔ tmux Pane 間をシームレスに移動。prefix 不要。

Neovim 側にも `christoomey/vim-tmux-navigator` プラグインが必要。

## SYNC モード

`prefix + S` で全 Pane に同じ入力を送信。複数サーバーの同時操作に便利。

有効時:
- ステータスバーに `SYNC` 表示（ティール）
- Pane 枠線がティールに変化
- テキストが明るくなる（`fg=colour255`）

## ネストセッション (F12)

SSH 先の remote tmux を local tmux 内で使う場合、`F12` で外側 tmux のキーバインドを一括 OFF にする。

- `F12` 押下 → prefix 無効化、全キーストロークが内側 tmux にパススルー
- `F12` 再押下 → 外側 tmux のキーバインド復帰

OFF 中の視覚的変化:
- ステータスバーがグレーアウト（`fg=#545c7e, bg=#1a1b26`）
- モード表示が `OFF`（オレンジ `#ff9e64`）
- Window タブがグレー一色

参考: [samoshkin/tmux-config](https://github.com/samoshkin/tmux-config)

## Per-session アクセントカラー

セッション名のハッシュから自動的にアクセントカラーを決定し、セッション名バッジとアクティブ Window タブに適用。複数セッションを同時に開いた際の視認性を向上させる。

### カラーパレット（TokyoNight 準拠）

| 色 | Hex |
|-----|-----|
| Red/Pink | `#f7768e` |
| Orange | `#ff9e64` |
| Yellow | `#e0af68` |
| Green | `#9ece6a` |
| Teal | `#73daca` |
| Blue | `#7aa2f7` |
| Purple | `#bb9af7` |
| Cyan | `#7dcfff` |

### 仕組み

1. `session-created` Hook で `tmux-session-color.sh apply` を実行
2. セッション名を `cksum` でハッシュ化し、8 色から 1 色を決定
3. `@session_color` にセッション固有の色を保存
4. `status-left`（セッション名バッジ）と `window-status-current-format`（アクティブ Window タブ）を per-session で設定
5. `client-session-changed` / `client-attached` Hook で `refresh` を実行し、色を再適用

per-session 設定により、複数 Ghostty ウィンドウで異なるセッションを開いても各セッション固有の色が維持される。

### セッション切り替え

`prefix + f` で fzf ベースのセッション切り替え。各セッション名がアクセントカラーで ANSI 着色表示される。

## Claude Code 通知統合

tmux ステータスバーに Claude Code の状態を通知バッジとして表示。

### 仕組み

1. Claude Code が `/tmp/claude_status/workspace_*.json` にステータスを書き込む
2. `tmux-claude-badge.sh` がウィンドウごとの通知件数を角丸バッジで表示
3. `tmux-claude-focus.sh` がウィンドウ切替時に 5 秒タイマーで通知を自動消去

### バッジ表示

- 通知あり: オレンジ背景 `#ff6600` に件数（白太字）
- アクティブ Window: 暗めオレンジ `#cc5500`（目立ちすぎ防止）
- 対象ステータス: `idle` / `permission` / `complete`

### Hook

```
session-window-changed → tmux-claude-focus.sh
client-session-changed → tmux-claude-focus.sh
```

## ステータスバー最適化

リモートコンテナ環境でのキー入力遅延を防ぐため、以下の最適化を実施:

| 設定 | 値 | 備考 |
|------|-----|------|
| status-interval | 5秒 | 更新頻度を抑制（SSH環境での遅延対策） |
| history-limit | 10000 | スクロールバック行数（大量履歴による遅延対策） |
| スクリプトキャッシュ | 3秒 | CPU/RAM/GPU/Storage/Git branch すべてにキャッシュ適用 |
| キャッシュ場所 | `/tmp/tmux_sysstat/` | 一時ディレクトリに統一 |

キャッシュにより、status-interval (10秒) ごとの更新時にスクリプトが実行されても、3秒以内の再呼び出しはキャッシュから返却される。

## テーマ再生成

Powerline 文字が表示されない場合:

```bash
scripts/regenerate-tmux-theme.sh
tmux source ~/.config/tmux/tmux.conf
```

Linux 環境では `install.sh` 実行時に自動で再生成される。

**重要**: `tokyonight.tmux` を直接編集せず、`regenerate-tmux-theme.sh` を編集して再生成すること。Powerline 文字が git 操作で破損する可能性があるため。

## ファイル構成

```
common/tmux/.config/tmux/
├── tmux.conf          # メイン設定
├── tokyonight.tmux    # テーマ（生成ファイル）
├── claude-hooks.tmux  # Claude 通知 Hook
└── plugins/tmux-which-key/
    └── config.yaml    # which-key メニュー設定

scripts/
├── regenerate-tmux-theme.sh  # テーマ再生成
├── tmux-utils.sh             # 共通ユーティリティ（get_mtime: クロスプラットフォーム対応）
├── tmux-cpu.sh               # CPU 使用率取得（macOS: iostat / Linux: /proc/stat、3秒キャッシュ）
├── tmux-ram.sh               # RAM 使用率取得（macOS: vm_stat / Linux: /proc/meminfo、3秒キャッシュ）
├── tmux-gpu.sh               # GPU 使用率取得（macmon / nvidia-smi、3秒キャッシュ）
├── tmux-storage.sh           # ストレージ使用率取得（閾値超過時のみ表示、3秒キャッシュ）
├── tmux-git-branch.sh        # Git ブランチ名取得（パスごとに3秒キャッシュ）
├── tmux-claude-badge.sh      # 通知バッジ表示
├── tmux-claude-focus.sh      # 通知自動消去
├── tmux-session-color.sh     # Per-session アクセントカラー（apply / refresh / fzf-sessions）
├── tmux-popup-ghq.sh         # ghq プロジェクト切り替え（popup 用）
└── tmux-sync-toggle.sh       # SYNC モード切替（which-key から呼び出し）
```

## プラグイン (TPM)

| プラグイン | 用途 |
|------------|------|
| vim-tmux-navigator | Neovim ⇔ tmux シームレス移動 |
| tmux-resurrect | セッション保存・復元（Pane 内容含む） |
| tmux-continuum | 自動復元（`@continuum-restore on`） |
| tmux-thumbs | Vimium風ヒントベーステキスト選択（URL、パス、gitハッシュ等を即コピー） |
| tmux-which-key | which-key スタイルのキーバインドヘルプポップアップ |

Resurrect 設定:
- `@resurrect-capture-pane-contents on` — Pane の表示内容も保存
- Neovim セッション復元は resession.nvim が担当（tmux-resurrect の `@resurrect-strategy-nvim` は使用しない）

tmux-thumbs 設定:
- `prefix + t` (変更予定) でヒント表示
- 選択した文字列は `pbcopy` でクリップボードにコピー

tmux-which-key 設定:
- 設定ファイル: `plugins/tmux-which-key/config.yaml`（dotfiles で管理）
- `tmux.conf` でプラグインディレクトリへシンボリックリンクを自動作成
- TokyoNight テーマに合わせたスタイリング

以前使用していた tmux-sensible、tmux-yank、tmux-cpu は削除済み:
- tmux-sensible: 自前設定でカバー（`focus-events`、`history-limit` 等を明示指定）
- tmux-yank: OSC52 (`set-clipboard on`) で代替
- tmux-cpu: カスタムスクリプト (`tmux-cpu.sh`, `tmux-ram.sh`) で代替。Linux で sysstat 不要（`/proc/stat`, `/proc/meminfo` を直接読み取り）
