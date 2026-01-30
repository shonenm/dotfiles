# tmux

TokyoNight Night テーマ + 透過背景。Ghostty / Neovim 統合対応。

## 基本設定

| 設定 | 値 | 備考 |
|------|-----|------|
| Prefix | `Ctrl+Space` | デフォルト `Ctrl+b` から変更 |
| Mouse | ON | ドラッグ選択、スクロール対応 |
| Clipboard | OSC52 | SSH 経由でもコピー可能 |
| Passthrough | ON | Kitty graphics protocol（image.nvim 等） |
| Base index | 1 | Window/Pane 番号が 1 から開始 |
| Escape time | 0 | ESC 遅延なし（Neovim 対応） |
| Renumber | ON | Window 削除時に自動採番 |
| Activity | ON | 非アクティブ Window の変更を検知 |
| Terminal title | `#{b:pane_current_path}` | aerospace ウィンドウ検出用 |

## キーバインド

全て `prefix` 付き（特記がない限り）。

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

### Copy Mode (vi スタイル)

| キー | 動作 |
|------|------|
| `prefix + v` | Copy Mode に入る |
| `prefix + u` / `prefix + C-u` | Copy Mode に入り即スクロールアップ |
| `v` | 選択開始 |
| `Ctrl+v` | 矩形選択切替 |
| `y` | コピー |
| `Enter` / `Esc` | キャンセル |
| `Ctrl+u` / `Ctrl+d` | 4 行スクロール |
| マウスドラッグ | 自動コピー → pbcopy（Copy Mode 終了） |

## ステータスバー

位置: 上部（`status-position top`）、透過背景。

```
 Session   1 zsh  2 nvim   MODE   branch  01/30 15:00   host
```

### 右側セグメント

| セグメント | アイコン | 色 | 内容 |
|------------|----------|-----|------|
| モード | なし | モード別 | OFF / COPY / SYNC / PREFIX / NORMAL |
| Git branch |  | 緑 `#9ece6a` | カレントディレクトリのブランチ名 |
| 日時 |  | 青 `#7aa2f7` | `MM/DD HH:MM` |
| ホスト |  | 水色 `#7dcfff` | ホスト名（太字） |

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
- アクティブ: 青背景 `#7aa2f7` + 太字 + 角丸
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

## テーマ再生成

Powerline 文字が表示されない場合:

```bash
scripts/regenerate-tmux-theme.sh
tmux source ~/.config/tmux/tmux.conf
```

Linux 環境では `install.sh` 実行時に自動で再生成される。

**重要**: `tokyonight.tmux` を直接編集せず、`regenerate-tmux-theme.sh` を編集して再生成すること。Powerline 文字が git 操作で破損する可能性があるため。

> **Note**: OFF インジケーター（F12 ネストセッション）は `tokyonight.tmux` に直接追加されている。`regenerate-tmux-theme.sh` を実行すると上書きされるため、スクリプト側への反映が必要。

## ファイル構成

```
common/tmux/.config/tmux/
├── tmux.conf          # メイン設定
├── tokyonight.tmux    # テーマ（生成ファイル）
└── claude-hooks.tmux  # Claude 通知 Hook

scripts/
├── regenerate-tmux-theme.sh  # テーマ再生成
├── tmux-claude-badge.sh      # 通知バッジ表示
└── tmux-claude-focus.sh      # 通知自動消去
```

## プラグイン (TPM)

| プラグイン | 用途 |
|------------|------|
| tmux-sensible | 共通の推奨設定 |
| vim-tmux-navigator | Neovim ⇔ tmux シームレス移動 |
| tmux-resurrect | セッション保存・復元（Pane 内容含む） |
| tmux-continuum | 自動復元（`@continuum-restore on`） |
| tmux-yank | クリップボード連携 |

Resurrect 設定:
- `@resurrect-capture-pane-contents on` — Pane の表示内容も保存
- `@resurrect-strategy-nvim session` — Neovim セッションも復元
