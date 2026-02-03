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
│   ├── bat/         # bat設定 (テーマ・構文マッピング)
│   ├── fd/          # fd設定 (グローバルignore)
│   ├── tmux/        # Tmux設定 (TokyoNight + Powerline)
│   ├── git/         # Git設定
│   ├── lazygit/     # LazyGit設定
│   ├── gh-dash/     # gh-dash設定 (GitHub Dashboard TUI)
│   ├── quay/        # quay設定 (ポートマネージャー接続先)
│   ├── mise/        # mise (Node.js, Python, Go等のバージョン管理)
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
│   ├── pomodoro.sh       # ポモドーロタイマー
│   ├── tmux-session-color.sh    # tmuxセッションカラー管理
│   └── tmux-session-preview.sh  # fzfセッション切替プレビュー
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

| カテゴリ | ツール                                                                                    |
| -------- | ----------------------------------------------------------------------------------------- |
| Shell    | zsh, starship, sheldon, atuin, zoxide                                                     |
| Editor   | neovim                                                                                    |
| Git      | lazygit, gh, gh-dash, ghq, git-absorb, gitleaks                                           |
| CLI      | lsd, eza, bat, ripgrep, fd, fzf, jq, yazi, tealdeer, procs, sd, dust, bottom, rip2, xh, ouch, glow, viddy, doggo, grex, quay |
| Dev      | mise, uv, direnv, just, watchexec, hyperfine, topgrade, cargo-update                      |
| Terminal | ghostty, tmux                                                                             |
| Window   | aerospace, sketchybar, borders                                                            |
| Apps     | raycast, karabiner-elements                                                               |

### Linux (apt/curl)

| カテゴリ | ツール                                                          |
| -------- | --------------------------------------------------------------- |
| System   | build-essential, zsh, tmux, jq, stow, rsync                     |
| Editor   | neovim                                                          |
| CLI      | lsd, ripgrep, fzf, eza, bat, tealdeer, procs, sd, dust, bottom, rip2, quay, cargo-update |
| Git      | lazygit, ghq                                                    |
| Dev      | mise, starship, sheldon, zoxide, atuin, uv, dotenvx             |
| Font     | UDEV Gothic Nerd Font                                           |

## 主要な設定

### Zsh

- **プラグインマネージャー**: Sheldon (zsh-completions, forgit, zsh-abbr, zsh-syntax-highlighting, zsh-autosuggestions)
- **略語展開**: zsh-abbr (エイリアスの代替、履歴に展開後コマンドが残る)
- **プロンプト**: Starship (Draculaテーマ)
- **履歴検索**: Atuin (fuzzy検索、workspace対応、secrets_filter)
- **ディレクトリ移動**: Zoxide
- **環境変数自動ロード**: direnv (`.envrc` によるプロジェクト別環境変数)
- **fzfテーマ**: TokyoNight カラー統一

### Neovim

- **ベース**: LazyVim
- **プラグインマネージャー**: lazy.nvim
- **LSP**: mason.nvim
- 詳細は `docs/neovim.md` を参照

### Tmux

- **テーマ**: TokyoNight (透過 + Powerline風角丸デザイン)
- **ステータスバー**: CPU/RAM/GPU/Storage 使用率、Gitブランチ、日時
- **キーバインド** (prefix: `C-Space`):

  | キー | 機能 |
  |------|------|
  | `t` | ペインタイトル編集 |
  | `T` | ウィンドウ名編集 |
  | `C-h/C-l` | ウィンドウ間移動 |
  | `h/j/k/l` | ペイン移動 |
  | `H/J/K/L` | ペインリサイズ |
  | `\|` / `-` | 縦/横分割 |
  | `f` | fzfセッション切替 (プレビュー付き) |
  | `j` | Scratchpad (永続セッション、トグル) |
  | `Space` | tmux-thumbs (ヒントベーステキスト選択) |
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
- **forgit**: fzf ベースの Git 操作強化（interactive add/diff/log/stash）
- **ghq**: リポジトリ管理ツール（`~/ghq` 配下に統一管理）
- `repo` 関数で ghq + fzf によるリポジトリ移動
- 詳細は `docs/git-config.md` を参照

### SSH

- 1Password SSH Agentを使用
- ホスト固有の設定は `~/.ssh/config.d/` に配置
- `rcon` でリモート接続（SSH + Docker + tmux）をワンコマンド実行（引数なしで fzf 選択、`rcon host:container` で直接指定、既存セッションに自動アタッチ）

## カスタマイズ

### ローカル設定

以下のファイルはdotfilesに含まれず、ローカルで管理：

- `~/.ssh/config.d/*` - SSH接続先設定
- `~/.config/rcon/targets` - rcon ターゲット一覧（`host:container` or `host`、1行1ターゲット）
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
