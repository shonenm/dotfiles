# SketchyBar + AeroSpace 連携

macOSのタイリングウィンドウマネージャー AeroSpace と ステータスバー SketchyBar を連携させ、ワークスペースとアプリを可視化するシステム。

## 概要

- **ワークスペース表示**: 使用中のワークスペースのみ動的に表示
- **アプリ表示**: フォーカス中のワークスペースのアプリをアイコンで表示
- **モード表示**: AeroSpaceのバインディングモード（Main/Service/Pomodoro）を可視化
- **ポモドーロタイマー**: キーボードのみで操作可能なタイマー機能
- **レイアウトポップアップ**: 全ワークスペースの一覧をポップアップ表示
- **通知バッジ**: Claude Code等の通知をワークスペースごとに表示

## UI構成

```
┌────────────────────────────────────────────────────────────────┐
│ [MODE] │ [1] [2●] [T] │ [App] [App] [App]                     │
│  MAIN  │ Workspaces   │ Apps in workspace                     │
└────────────────────────────────────────────────────────────────┘
   左側
```

| 要素 | 説明 |
|------|------|
| **Mode Indicator** | 現在のモード（MAIN/SERVICE/POMO）をアイコンと色で表示 |
| **Workspaces** | 非空のワークスペースのみ表示、フォーカス中はハイライト、通知バッジ付き |
| **Apps** | 現在のワークスペースのアプリをアイコン表示 |

## モード表示

AeroSpaceには3つのバインディングモードがある：

### Main Mode（通常）

```
┌──────────────┐
│ 󰍹  MAIN     │  ← アクセントカラー（青）
└──────────────┘
```

- 通常の操作モード
- ウィンドウ操作、ワークスペース移動が可能

### Service Mode（設定）

```
┌──────────────┐
│ ⚙  SERVICE  │  ← 警告カラー（オレンジ）
└──────────────┘
```

Service Modeに入ると、UI全体がオレンジ色に変化：
- ワークスペースのボーダー
- アプリのボーダー
- フォーカス中のハイライト
- ウィンドウボーダー（JankyBorders）

さらに、右側にキーバインドヘルプが表示される：

```
┌─────────────────────────────────────────────────────────────┐
│ esc:exit  a:reload  r:reset  f:float  c:clear-badges  ⌫:close-others │
└─────────────────────────────────────────────────────────────┘
```

### Pomodoro Mode（タイマー）

```
┌──────────────┐
│ 󰔛  POMO     │  ← ポモドーロカラー（緑）
└──────────────┘
```

Pomodoro Modeに入ると、UI全体が緑色に変化。
ポモドーロタイマーをキーボードのみで操作可能。

右側にキーバインドヘルプが表示される：

```
┌────────────────────────────────────────────────────────────────┐
│ esc:exit  s:start/pause  r:reset  1:5m 2:15m 3:25m 4:45m 5:60m │
└────────────────────────────────────────────────────────────────┘
```

## ワークスペース表示

```
┌─────────────────────────┐
│ [1]  [2]  [T]  [C]     │
│      ↑                  │
│   フォーカス中          │
└─────────────────────────┘
```

- **非空のワークスペースのみ**表示（空は非表示）
- フォーカス中のワークスペースは**モードカラーでハイライト**
- **クリックでワークスペース移動**
- 通知がある場合は**バッジで件数表示**

### 通知バッジ

```
┌───────────┐
│ [1] ●2    │  ← ワークスペース1に2件の通知
└───────────┘
```

Claude Codeからの通知（permission, idle, complete）がワークスペースごとにバッジ表示される。

## アプリ表示

```
┌─────────────────────────────────┐
│ [󰈹]  [󰨞]  [󰙯]  [  Ghostty  ] │
│  ↑    ↑    ↑         ↑         │
│ Firefox VS Code Discord  フォーカス中 │
└─────────────────────────────────┘
```

- 現在のワークスペースにある**全アプリをアイコン表示**
- フォーカス中のアプリは**アイコン+ラベル+ハイライト**
- 1000以上のアプリに対応したアイコンマッピング

## レイアウトポップアップ

`alt+shift+/` で全ワークスペースの一覧をポップアップ表示：

```
┌────────────────────────────────────┐
│ 󰄯  1  │  Firefox  VS Code         │  ← フォーカス中
│ 󰄰  2  │  Slack  Discord           │
│ 󰄰  T  │  Ghostty                  │
│ 󰄰  C  │  Cron                     │
└────────────────────────────────────┘
```

- **全ワークスペースとアプリを一覧表示**
- フォーカス中は 󰄯、それ以外は 󰄰
- **クリックでワークスペース移動**
- **トグル動作**（再度押すと閉じる）

## キーバインド

### Main Mode

| キー | 動作 |
|------|------|
| `alt+1-9` | ワークスペース1-9に移動 |
| `alt+t/c/f/g/b/v` | ワークスペースT/C/F/G/B/Vに移動 |
| `alt+h/j/k/l` | フォーカス移動（左/下/上/右） |
| `alt+shift+h/j/k/l` | ウィンドウ移動 |
| `alt+shift+1-9` | ウィンドウをワークスペースに移動 |
| `alt+/` | レイアウト切替（tiles/accordion） |
| `alt+shift+/` | レイアウトポップアップ表示 |
| `alt+s` | SketchyBar表示/非表示 |
| `alt+tab` | 前のワークスペースに戻る |
| `alt+shift+;` | Service Modeに入る |
| `alt+shift+p` | Pomodoro Modeに入る |
| `ctrl+alt+←/→` | 非空ワークスペース間を移動 |

### Service Mode

| キー | 動作 |
|------|------|
| `esc` | Main Modeに戻る（設定リロード） |
| `a` | AeroSpace設定リロード |
| `r` | レイアウトリセット |
| `f` | フローティング/タイリング切替 |
| `c` | 全通知バッジをクリア |
| `backspace` | 他のウィンドウを全て閉じる |

### Pomodoro Mode

| キー | 動作 |
|------|------|
| `esc` | Main Modeに戻る |
| `s` | タイマー開始/一時停止 |
| `r` | タイマーリセット |
| `1` | 5分に設定 |
| `2` | 15分に設定 |
| `3` | 25分に設定 |
| `4` | 45分に設定 |
| `5` | 60分に設定 |
| `alt+shift+/` | レイアウトポップアップ表示 |

## 設定ファイル

### SketchyBar

```
~/.config/sketchybar/
├── sketchybarrc          # メイン設定
└── plugins/
    ├── workspaces.sh     # ワークスペース表示
    ├── workspace_apps.sh # アプリ表示
    ├── mode.sh           # モード表示
    ├── aerospace.sh      # ワークスペースフォーカス
    ├── show_layout.sh    # レイアウトポップアップ
    ├── claude.sh         # 通知バッジ
    ├── accent_color.sh   # カラー定義
    ├── icon_map.sh       # アプリアイコンマッピング
    ├── toggle_bar.sh     # バー表示切替
    └── pomodoro.sh       # ポモドーロタイマー表示
```

### AeroSpace

```
~/.config/aerospace/
└── aerospace.toml        # ウィンドウマネージャー設定
```

## イベントフロー

### ワークスペース変更時

```
AeroSpace (ワークスペース移動)
    ↓ exec-on-workspace-change
sketchybar --trigger aerospace_workspace_change
    ↓
workspaces.sh  → ワークスペースリスト更新
workspace_apps.sh → アプリリスト更新
claude.sh → バッジ更新
```

### モード変更時

```
AeroSpace (alt+shift+;)
    ↓ on-mode-changed
sketchybar --trigger aerospace_mode_change
    ↓
mode.sh → モード表示更新
        → 全UIカラー変更
        → キーバインドヘルプ表示/非表示
        → JankyBordersカラー変更
```

### フォーカス変更時

```
macOS (アプリフォーカス変更)
    ↓ front_app_switched
workspace_apps.sh → フォーカスアプリハイライト
claude.sh → エディタ/ターミナルなら通知クリア
```

## カラースキーム

| 用途 | 色 | 値 |
|------|-----|-----|
| アクセントカラー（Main Mode） | 青 | `0xff0055bb` |
| サービスカラー（Service Mode） | オレンジ | `0xffff6600` |
| ポモドーロカラー（Pomodoro Mode） | 緑 | `0xff28a745` |
| 背景 | 透明/ダーク | `0x00000000` / `0xff1e1f29` |
| テキスト | 白 | `0xffffffff` |

## パフォーマンス最適化

- **状態ファイルによる差分更新**
  - `/tmp/sketchybar_workspaces_state` - ワークスペース状態
  - `/tmp/sketchybar_apps_state` - アプリ状態
  - 変更がない場合はUI再構築をスキップ

- **動的アイテム管理**
  - 非空ワークスペースのみ表示
  - ワークスペース変更時のみアプリリスト更新

## トラブルシューティング

### SketchyBarが表示されない

```bash
# SketchyBarを再起動
brew services restart sketchybar

# 設定をリロード
sketchybar --reload
```

### ワークスペースが更新されない

```bash
# AeroSpaceの状態確認
aerospace list-workspaces --all

# 手動トリガー
sketchybar --trigger aerospace_workspace_change
```

### アイコンが表示されない

```bash
# sketchybar-app-font がインストールされているか確認
ls ~/Library/Fonts/ | grep -i sketchybar
```

### モード変更が反映されない

```bash
# AeroSpace設定リロード
aerospace reload-config

# 手動トリガー
sketchybar --trigger aerospace_mode_change
```
