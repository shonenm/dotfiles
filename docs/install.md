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
| Mac | `scripts/mac.sh` | Homebrew パッケージ、gh 拡張機能、Aerospace、SketchyBar 等 |
| Linux | `scripts/linux.sh` | apt パッケージ、開発ツール等 |

### 4. Dotfiles リンク (stow)

`common/` と OS 固有ディレクトリを `$HOME` にシンボリックリンク:

```
common/
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
