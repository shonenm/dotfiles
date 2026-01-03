# Starship プロンプト設定

シェルプロンプトをカスタマイズするStarshipの設定。Draculaテーマベースのモダンなプロンプト。

## 概要

- **2行プロンプト**: 情報表示とコマンド入力を分離
- **Draculaテーマ**: 統一されたカラーパレット
- **Git連携**: ブランチ、ステータス、差分行数を表示
- **コンテキスト情報**: OS、ディレクトリ、実行時間、時刻、ユーザー名

## UI構成

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  󰉖 ~/dotfiles   main ⇡1  󰊤 +10/-5 ─────────────  25ms  󰙦 14:30   user │
│ ❯❯                                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
   ↑       ↑         ↑       ↑           ↑            ↑       ↑       ↑
  OS   Directory   Branch  Status    Metrics        Duration Time  Username
```

| 要素 | 説明 | 色 |
|------|------|-----|
| **OS** | OS アイコン（macOS: 󰊠） | 赤 |
| **Directory** | 現在のディレクトリ（2階層まで） | ピンク |
| **Git Branch** | 現在のブランチ名 | 緑 |
| **Git Status** | ahead/behind/diverged状態 | 緑（背景） |
| **Git Metrics** | 追加/削除行数 | シアン |
| **Duration** | コマンド実行時間（500ms以上） | オレンジ |
| **Time** | 現在時刻（HH:MM） | 紫 |
| **Username** | ユーザー名 | 黄 |
| **Character** | 入力プロンプト（❯❯） | 緑/赤 |

## モジュール詳細

### OS

```
┌──────────┐
│  󰊠      │  ← macOS
└──────────┘
```

OSを識別してアイコン表示。対応OS:
- macOS: 󰊠
- Linux: 󰌽
- Ubuntu: 󰕈
- Debian: 󰣚
- Arch: 󰣇
- Alpine, CentOS, Fedora

### Directory

```
┌────────────────────┐
│ 󰉖 ~/dotfiles      │
└────────────────────┘
```

- ホームディレクトリは `~/` 表示
- 2階層まで表示、それ以上は ` ` で省略
- 読み取り専用ディレクトリは 󱞵 アイコン付き

### Git Branch

```
┌─────────────────┐
│  main          │
└─────────────────┘
```

現在のGitブランチを表示。リポジトリ外では非表示。

### Git Status

```
┌────────────────────┐
│ ⇡1                │  ← リモートより1コミット先行
│ ⇣2                │  ← リモートより2コミット遅れ
│ ⇕⇡1⇣2             │  ← 分岐状態
└────────────────────┘
```

リモートとの差分状態を表示。

### Git Metrics

```
┌──────────────────┐
│ 󰊤 +10/-5        │
└──────────────────┘
```

現在の変更の追加行数と削除行数を表示。

### Command Duration

```
┌──────────────┐
│  25ms       │
└──────────────┘
```

500ms以上かかったコマンドの実行時間を表示。

### Time

```
┌────────────┐
│ 󰙦 14:30   │
└────────────┘
```

現在時刻を24時間形式で表示。

### Username

```
┌────────────┐
│  user     │
└────────────┘
```

現在のユーザー名を常時表示。

### Character

```
┌────────────┐
│ ❯❯        │  ← 成功時（緑）
│ ❯❯        │  ← エラー時（赤）
└────────────┘
```

前のコマンドの終了コードに応じて色が変化。

## カラーパレット（Dracula）

| 名前 | 色 | HEX | 用途 |
|------|-----|-----|------|
| foreground | 白 | `#F8F8F2` | テキスト |
| background | 暗灰 | `#282A36` | 背景 |
| current_line | 灰 | `#44475A` | 区切り線、ボックス背景 |
| primary | 黒 | `#1E1F29` | アイコン背景 |
| red | 赤 | `#FF5555` | OS |
| pink | ピンク | `#FF79C6` | ディレクトリ |
| green | 緑 | `#50FA7B` | Git Branch、成功 |
| cyan | シアン | `#8BE9FD` | Git Metrics |
| orange | オレンジ | `#FFB86C` | Duration |
| purple | 紫 | `#BD93F9` | Time |
| yellow | 黄 | `#F1FA8C` | Username |

## 設定ファイル

```
~/.config/starship.toml  ← dotfiles/common/starship/.config/starship.toml
```

### 構造

```toml
# フォーマット定義
format = """
$os\
$directory\
..."""

# パレット選択
palette = 'dracula'

# カラーパレット定義
[palettes.dracula]
foreground = '#F8F8F2'
...

# 各モジュール設定
[os]
[directory]
[git_branch]
...
```

## セットアップ

### インストール

```bash
# Starshipインストール
brew install starship

# dotfilesインストール
./install.sh
```

### シェル設定

zshrc に以下が必要（dotfilesに含まれる）:

```bash
eval "$(starship init zsh)"
```

## カスタマイズ

### ディレクトリ表示階層の変更

```toml
[directory]
truncation_length = 3  # 3階層まで表示
```

### 時刻フォーマットの変更

```toml
[time]
time_format = '%Y-%m-%d %H:%M:%S'  # 日付も表示
```

### モジュールの無効化

```toml
[git_metrics]
disabled = true  # Git Metricsを非表示
```

## トラブルシューティング

### アイコンが文字化けする

Nerd Font がインストールされていない:

```bash
# Nerd Fontのインストール
brew install --cask font-hack-nerd-font

# ターミナルのフォント設定で Nerd Font を選択
```

### プロンプトが表示されない

```bash
# Starshipの確認
which starship

# シェル設定の確認
grep starship ~/.zshrc
```

### Git情報が表示されない

```bash
# Gitリポジトリ内か確認
git status

# Starshipの設定確認
starship explain
```

### 色がおかしい

ターミナルが True Color をサポートしているか確認:

```bash
# True Colorテスト
printf "\x1b[38;2;255;100;0mTrue Color\x1b[0m\n"
```

## 関連ドキュメント

- [Starship公式ドキュメント](https://starship.rs/)
- [Dracula Theme](https://draculatheme.com/)
