# install.sh

dotfiles のセットアップスクリプト。

## 使い方

```bash
./install.sh      # 対話モード
./install.sh -y   # 自動モード（確認スキップ）
```

## 実行内容

### 1. 1Password CLI チェック

- `op` コマンドがインストールされているか確認
- 未インストールの場合は自動インストール（Mac: Homebrew / Linux: apt）
- サインイン状態を確認（未サインインの場合は中断）

### 2. Homebrew インストール (Mac のみ)

- Homebrew がなければインストール

### 3. 環境セットアップ

OS に応じたセットアップスクリプトを実行:

| OS | スクリプト | 内容 |
|----|-----------|------|
| Mac | `scripts/mac.sh` | Homebrew パッケージ (Brewfile)、cargo ツール (quay, cargo-update)、gh 拡張機能、Aerospace、SketchyBar 等 |
| Linux | `scripts/linux.sh` | apt/apk パッケージ、GitHub release バイナリ、cargo ツール等（`config/tools.linux.bash` で定義） |

### 4. Dotfiles リンク (stow)

`common/` と OS 固有ディレクトリを `$HOME` にシンボリックリンク:

```
common/
├── bat/      → ~/.config/bat/
├── gh-dash/  → ~/.config/gh-dash/
├── git/      → ~/.gitconfig
├── mise/     → ~/.config/mise/
├── nvim/     → ~/.config/nvim/
├── starship/ → ~/.config/starship.toml
├── tmux/     → ~/.config/tmux/
└── zsh/      → ~/.zshrc, ~/.zprofile
```

### 5. tmux テーマ再生成 (Linux のみ)

Powerline 文字のエンコーディング問題を修正:

```bash
scripts/regenerate-tmux-theme.sh
```

git clone 時に特殊文字（U+E0B6, U+E0B4）が正しくコピーされない問題への対処。

### 6. AI CLI 設定生成

Claude / Codex / Gemini の設定ファイルを生成:

- `~/.claude/settings.json`
- `~/.codex/config.toml`
- `~/.gemini/settings.json`

1Password から Webhook URL を取得してキャッシュ。

## 完了後

```bash
source ~/.zshrc   # シェル設定を反映
mise install      # mise 管理ツールをインストール
```

## mise タスク

インストール後に利用可能な mise タスク:

```bash
mise run update    # brew upgrade + sheldon update + tldr update
mise run doctor    # 必要ツールの存在確認 + stow リンク健全性チェック
mise run lint      # shellcheck で scripts/*.sh を静的解析
```

## CI

`.github/workflows/ci.yml` で以下を自動実行:

- **ShellCheck**: `scripts/` 配下の全 `.sh` ファイルを静的解析
- **Stow Dry Run**: `common/` の全パッケージで stow コンフリクト検出
