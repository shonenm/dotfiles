# dotfiles

macOS / Linux 用の開発環境設定ファイル。GNU Stow によるシンボリックリンク管理。

## 構成

```
dotfiles/
├── common/          # 共通設定（Mac/Linux両方で使用）
│   ├── nvim/        # Neovim設定
│   ├── zsh/         # Zsh共通設定 (.zshrc.common)
│   ├── starship/    # Starshipプロンプト
│   ├── sheldon/     # Zshプラグインマネージャー
│   ├── zsh-abbr/    # Zsh略語定義 (zsh-abbr)
│   ├── tmux/        # Tmux設定 (TokyoNight + Powerline)
│   ├── git/         # Git設定
│   ├── lazygit/     # LazyGit設定
│   ├── mise/        # mise (Node.js, Python等のバージョン管理)
│   ├── ghostty/     # Ghosttyターミナル
│   ├── aerospace/   # AeroSpace (タイリングWM)
│   ├── sketchybar/  # SketchyBar (ステータスバー)
│   ├── vscode/      # VS Code設定
│   └── ...
├── mac/             # macOS専用設定
│   ├── zsh/         # .zshrc (macOS用)
│   ├── ssh/         # SSH設定 (1Password Agent)
│   ├── karabiner/   # Karabiner-Elements
│   ├── raycast/     # Raycast設定
│   └── borders/     # JankyBorders
├── linux/           # Linux専用設定
│   ├── zsh/         # .zshrc (Linux用)
│   └── ssh/         # SSH設定 (1Password Agent)
├── scripts/         # セットアップ・ユーティリティスクリプト
│   ├── mac.sh       # macOSパッケージインストール
│   ├── linux.sh     # Linuxパッケージインストール
│   ├── claude-status.sh  # Claude Code通知連携
│   ├── ai-notify.sh      # AI通知ヘルパー
│   └── pomodoro.sh       # ポモドーロタイマー
├── templates/       # AI CLI設定テンプレート
│   ├── claude-settings.json
│   ├── codex-config.toml
│   └── gemini-settings.json
├── docs/            # ドキュメント
│   ├── neovim.md
│   ├── neovim-troubleshooting.md
│   ├── tmux.md
│   ├── sketchybar-aerospace.md
│   ├── claude-beacon.md
│   ├── git-config.md
│   ├── starship.md
│   ├── modern-cli-tools.md
│   ├── install.md
│   ├── 1password-integration.md
│   └── patches/        # ローカルパッチ管理
└── install.sh       # メインインストーラー
```

## 前提条件

- **1Password CLI** (`op`) - シークレット管理に必要
- **Git** - dotfilesのクローン
- **curl** - パッケージインストール

## インストール

### macOS

```bash
# dotfilesをクローン
git clone https://github.com/shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 1Password CLIにサインイン
eval $(op signin)

# インストール実行
./install.sh
```

### Linux (Ubuntu/Debian)

```bash
# 前提パッケージをインストール
sudo apt update && sudo apt install -y curl git

# dotfilesをクローン
git clone https://github.com/shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 1Password CLIにサインイン
eval $(op signin)

# インストール実行
./install.sh
```

### Docker環境

```bash
# コンテナ内で実行
cd ~/dotfiles
eval $(op signin)
./install.sh -y
exec zsh
```

## インストールされるツール

### macOS (Homebrew)

| カテゴリ | ツール                                                                        |
| -------- | ----------------------------------------------------------------------------- |
| Shell    | zsh, starship, sheldon, atuin, zoxide                                         |
| Editor   | neovim                                                                        |
| Git      | lazygit, gh                                                                   |
| CLI      | eza, bat, ripgrep, fd, fzf, jq, yazi, tealdeer, procs, sd, dust, bottom, rip2 |
| Dev      | mise, uv                                                                      |
| Terminal | ghostty, tmux                                                                 |
| Window   | aerospace, sketchybar, borders                                                |
| Apps     | raycast, karabiner-elements                                                   |

### Linux (apt/curl)

| カテゴリ | ツール                                                          |
| -------- | --------------------------------------------------------------- |
| System   | build-essential, zsh, tmux, jq, stow, rsync                     |
| Editor   | neovim                                                          |
| CLI      | ripgrep, fzf, eza, bat, tealdeer, procs, sd, dust, bottom, rip2 |
| Dev      | mise, starship, sheldon, zoxide, atuin, uv, dotenvx             |
| Font     | UDEV Gothic Nerd Font                                           |

## 主要な設定

### Zsh

- **プラグインマネージャー**: Sheldon
- **略語展開**: zsh-abbr (エイリアスの代替、履歴に展開後コマンドが残る)
- **プロンプト**: Starship (Draculaテーマ)
- **履歴検索**: Atuin
- **ディレクトリ移動**: Zoxide

### Neovim

- **ベース**: LazyVim
- **プラグインマネージャー**: lazy.nvim
- **LSP**: mason.nvim
- 詳細は `docs/neovim.md` を参照

### Tmux

- **テーマ**: TokyoNight (透過 + Powerline風角丸デザイン)
- **ステータスバー**: CPU/メモリ使用率、Gitブランチ、日時
- **キーバインド** (prefix: `C-Space`):

  | キー | 機能 |
  |------|------|
  | `t` | ペインタイトル編集 |
  | `T` | ウィンドウ名編集 |
  | `C-h/C-l` | ウィンドウ間移動 |
  | `h/j/k/l` | ペイン移動 |
  | `H/J/K/L` | ペインリサイズ |
  | `\|` / `-` | 縦/横分割 |
  | `r` | 設定リロード |

### AeroSpace + SketchyBar

- **AeroSpace**: タイリングウィンドウマネージャー
- **SketchyBar**: カスタマイズ可能なステータスバー
  - ワークスペース表示
  - アプリアイコン
  - Day Progress (1日の進捗)
  - Claude Code通知バッジ
- 詳細は `docs/sketchybar-aerospace.md` を参照

### Git

- ユーザー情報は `.gitconfig.local` で管理
- 初回セットアップ時に1Passwordから取得
- 詳細は `docs/git-config.md` を参照

### SSH

- 1Password SSH Agentを使用
- ホスト固有の設定は `~/.ssh/config.d/` に配置

## カスタマイズ

### ローカル設定

以下のファイルはdotfilesに含まれず、ローカルで管理：

- `~/.ssh/config.d/*` - SSH接続先設定
- `~/.zshrc.local` - マシン固有のZsh設定（あれば読み込まれる）
- `~/.gitconfig.local` - Git ユーザー情報（name, email）

### 新しい設定を追加

```bash
# 例: foo というアプリの設定を追加
mkdir -p common/foo/.config/foo
# 設定ファイルを配置
cp ~/.config/foo/config.toml common/foo/.config/foo/

# stowでリンク
cd ~/dotfiles
stow -t ~ -d common foo
```

## トラブルシューティング

### stowでコンフリクトが発生

既存ファイルがある場合、`install.sh`が自動でバックアップ：

```
~/.dotfiles_backup/YYYYMMDD_HHMMSS/
```

### 1Password認証エラー

```bash
eval $(op signin)
```

### フォントが表示されない

Nerd Font対応フォント（UDEV Gothic NF等）をインストールし、ターミナルで設定。

## ライセンス

MIT
