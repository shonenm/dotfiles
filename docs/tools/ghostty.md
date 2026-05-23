# Ghostty

TokyoNight テーマ + 背景画像。macOS 統合対応のモダンターミナル。

## 基本設定

| 設定 | 値 | 備考 |
|------|-----|------|
| Font | UDEV Gothic NFLG | 日本語対応 Nerd Font |
| Font size | 12 | - |
| Font feature | `-calt -liga -dlig` | リガチャ無効 |
| Theme | tokyonight | - |
| Cursor | block, invert | 反転色カーソル |
| Shell integration | zsh | cursor, sudo, title |

## クリップボード

| 設定 | 値 | 備考 |
|------|-----|------|
| clipboard-read | allow | アプリからの読み取り許可 |
| clipboard-write | allow | アプリからの書き込み許可 |
| copy-on-select | clipboard | 選択時に自動コピー |

### キーバインド

| キー | 動作 |
|------|------|
| `Cmd+C` | クリップボードにコピー |
| `Cmd+V` | クリップボードから貼り付け |

### copy-on-select について

`copy-on-select = clipboard` により、マウスでテキストを選択するだけで自動的にシステムクリップボードにコピーされる。`Cmd+C` を押す必要がない。

tmux の OSC52 と併用することで、SSH 経由でも選択→コピーがシームレスに動作する。

## 背景画像

| 設定 | 値 |
|------|-----|
| background-image | `~/.config/ghostty/backgrounds/background.jpeg` |
| background-image-fit | cover |
| background-image-opacity | 0.2 |
| background-opacity | 1.0 |

## ウィンドウ (macOS)

| 設定 | 値 | 備考 |
|------|-----|------|
| window-padding-x | 12 | 左右パディング |
| window-padding-y | 8 | 上下パディング |
| macos-titlebar-style | transparent | タイトルバー透過 |
| macos-option-as-alt | true | Option を Alt として扱う |

## キーバインド

### Split 操作

| キー | 動作 |
|------|------|
| `Ctrl+Shift+H` | 左の Split に移動 |
| `Ctrl+Shift+J` | 下の Split に移動 |
| `Ctrl+Shift+K` | 上の Split に移動 |
| `Ctrl+Shift+L` | 右の Split に移動 |
| `Cmd+Shift+Enter` | Split を自動方向で作成 |
| `Cmd+Shift+M` | Split ズーム切替 |
| `Cmd+Shift+W` | Split を閉じる |

### Tab 操作

| キー | 動作 |
|------|------|
| `Cmd+Shift+T` | 新規タブ |
| `Cmd+Shift+H` | 前のタブ |
| `Cmd+Shift+L` | 次のタブ |

### その他

| キー | 動作 |
|------|------|
| `Shift+Enter` | Claude Code 用改行（`\x1b\r`） |
| `Cmd+Backspace` | 行頭まで削除（`\x15`） |
| `Ctrl+Backspace` | 単語削除（`\x17`） |
| `Cmd+Shift+R` | 設定リロード |
| `Cmd+Enter` | unbind（フルスクリーン無効） |

## マウス

| 設定 | 値 |
|------|-----|
| mouse-hide-while-typing | true |

## ファイル構成

```
common/ghostty/.config/ghostty/
├── config              # メイン設定
└── backgrounds/
    └── background.jpeg # 背景画像
```
