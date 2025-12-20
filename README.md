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
│   ├── tmux/        # Tmux設定
│   ├── git/         # Git設定
│   ├── lazygit/     # LazyGit設定
│   ├── mise/        # mise (Node.js, Python等のバージョン管理)
│   ├── ghostty/     # Ghosttyターミナル
│   ├── claude/      # Claude Code設定
│   ├── codex/       # OpenAI Codex設定
│   ├── gemini/      # Gemini CLI設定
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
├── scripts/         # セットアップスクリプト
│   ├── mac.sh       # macOSパッケージインストール
│   ├── linux.sh     # Linuxパッケージインストール
│   └── utils.sh     # ユーティリティ関数
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

| カテゴリ | ツール |
|----------|--------|
| Shell | fish, starship, sheldon, atuin, zoxide |
| Editor | neovim |
| Git | lazygit, gh |
| CLI | eza, bat, ripgrep, fd, fzf, jq, yazi |
| Dev | mise, uv |
| Apps | ghostty, raycast, karabiner-elements |

### Linux (apt/curl)

| カテゴリ | ツール |
|----------|--------|
| System | build-essential, zsh, tmux, jq, stow, rsync |
| Editor | neovim |
| CLI | ripgrep, fzf, eza, bat |
| Dev | mise, starship, sheldon, zoxide, atuin, uv, dotenvx |
| Font | UDEV Gothic Nerd Font |

## 主要な設定

### Zsh

- **プラグインマネージャー**: Sheldon
- **プロンプト**: Starship (Draculaテーマ)
- **履歴検索**: Atuin
- **ディレクトリ移動**: Zoxide

### Neovim

- **プラグインマネージャー**: lazy.nvim
- **LSP**: mason.nvim
- 詳細は `common/nvim/.config/nvim/README.md` を参照

### Git

- ユーザー情報は1Passwordから取得（手動実行）
  ```bash
  setup_git_from_op
  ```

### SSH

- 1Password SSH Agentを使用
- ホスト固有の設定は `~/.ssh/config.d/` に配置

## カスタマイズ

### ローカル設定

以下のファイルはdotfilesに含まれず、ローカルで管理：

- `~/.ssh/config.d/*` - SSH接続先設定
- `~/.zshrc.local` - マシン固有のZsh設定（あれば読み込まれる）

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
