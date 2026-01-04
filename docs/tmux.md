# tmux

TokyoNight Night テーマを使用した tmux 設定。透過背景対応。

## キーバインド

### Prefix

`Ctrl+j`（デフォルトの `Ctrl+b` から変更）

### Pane / Window 操作

| キー | 動作 |
|------|------|
| `\|` | 水平分割 |
| `-` | 垂直分割 |
| `h/j/k/l` | Pane 移動 |
| `H/J/K/L` | Pane リサイズ（リピート可） |
| `Ctrl+h/l` | Window 切替 |
| `t` | Pane タイトル設定 |
| `T` | Window リネーム |
| `r` | 設定リロード |
| `m` | MOVE モード |
| `S` | SYNC モード切替 |

### Copy Mode (vi スタイル)

| キー | 動作 |
|------|------|
| `v` | 選択開始 |
| `Ctrl+v` | 矩形選択 |
| `y` | コピー |
| `Enter/Esc` | キャンセル |
| `Ctrl+u/d` | 4行スクロール |

マウスドラッグでも自動コピー（pbcopy 連携）。

## ステータスバー

```
[Session]  [Window1] [Window2]...  [MODE] [Git Branch] [Date Time] [Host]
```

### モード表示

| モード | 色 | 条件 |
|--------|-----|------|
| COPY | 赤 | Copy mode 中 |
| MOVE | マゼンタ | MOVE mode 中 |
| SYNC | ティール | Pane 同期中 |
| PREFIX | 黄 | Prefix 入力後 |
| NORMAL | 青 | 通常 |

Pane 枠線もモードに応じて色が変化。

## MOVE モード

`prefix + m` で MOVE モードに入る。prefix なしで連続移動可能。

| キー | 動作 |
|------|------|
| `h/j/k/l` | Pane 移動 |
| `Ctrl+h/l` | Window 切替 |
| `Enter/Esc` | モード終了 |

有効時:
- ステータスバーに `MOVE` 表示（マゼンタ）
- Pane 枠線がマゼンタに変化

## SYNC モード

`prefix + S` で全 Pane に同じ入力を送信。複数サーバーの同時操作に便利。

有効時:
- ステータスバーに `SYNC` 表示（ティール）
- Pane 枠線がティールに変化
- テキストが明るくなる

## テーマ再生成

Powerline 文字が表示されない場合:

```bash
scripts/regenerate-tmux-theme.sh
tmux source ~/.config/tmux/tmux.conf
```

Linux 環境では `install.sh` 実行時に自動で再生成される。

**重要**: `tokyonight.tmux` を直接編集せず、`regenerate-tmux-theme.sh` を編集して再生成すること。

## ファイル構成

```
common/tmux/.config/tmux/
├── tmux.conf          # メイン設定
├── tokyonight.tmux    # テーマ（生成ファイル）
└── claude-hooks.tmux  # Claude 通知連携

scripts/
├── regenerate-tmux-theme.sh  # テーマ再生成
├── tmux-claude-badge.sh      # 通知バッジ表示
└── tmux-claude-focus.sh      # 通知自動消去
```

## プラグイン

- **tmux-resurrect**: セッション保存・復元
- **tmux-continuum**: 自動復元
- **tmux-yank**: クリップボード連携
