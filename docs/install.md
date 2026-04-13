# install.sh

dotfiles のセットアップスクリプト。

## 使い方

```bash
./install.sh            # 対話モード (sudo 利用可前提)
./install.sh -y         # 自動モード（確認スキップ）
./install.sh --no-sudo  # sudoless 環境 (pixi ベースの user-scope install)
```

sudoless 環境 (共有サーバー等) での運用詳細は [install-no-sudo.md](./install-no-sudo.md) を参照。

## 実行内容

### 1. 1Password CLI チェック

- `op` コマンドがインストールされているか確認
- 未インストールの場合は自動インストール
  - Mac: Homebrew
  - Linux + sudo: apt
  - Linux + `--no-sudo`: tarball を `~/.local/bin/op` に展開 (`cache.agilebits.com` から最新版取得、失敗時は 2.33.1 fallback)
- サインイン状態を確認（未サインインの場合は中断）

### 2. Homebrew インストール (Mac のみ)

- Homebrew がなければインストール

### 3. 環境セットアップ

OS に応じたセットアップスクリプトを実行:

| OS | スクリプト | 内容 |
|----|-----------|------|
| Mac | `scripts/mac.sh` | Homebrew パッケージ (Brewfile)、cargo ツール (quay, cargo-update)、gh 拡張機能、Aerospace、SketchyBar 等 |
| Linux (sudo) | `scripts/linux.sh` | apt/apk パッケージ、GitHub release バイナリを `/usr/local/bin` に、cargo ツール等 |
| Linux (`--no-sudo`) | `scripts/linux.sh` | **pixi (conda-forge) でシステムパッケージ** (`config/pixi-packages.txt`)、GitHub release バイナリを `~/.local/bin` に、その他は curl_pipe や user-scope cargo 等 |

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

### 6. tmux プラグインセットアップ

TPM と tmux-which-key、tmux-thumbs を自動セットアップ:

1. **TPM インストール** - `~/.tmux/plugins/tpm` がなければ自動 clone
2. **プラグインインストール** - `tpm/bin/install_plugins` で全プラグインをインストール
3. **tmux-which-key 設定** - dotfiles の `config.yaml` をプラグインディレクトリにシンボリックリンク
4. **メニュービルド** - Python で which-key メニューを生成
5. **tmux-thumbs ビルド** - `cargo` があれば Rust バイナリをビルド（TPM はソースを clone するだけでビルドしないため）

### 7. AI CLI 設定生成

Claude / Codex / Gemini の設定ファイルを生成:

- `~/.claude/settings.json` (テンプレートから `__HOME__` を置換して生成)
- `~/.claude/skills/` (Stow symlink がある場合はスキップ、なければ `common/claude/.claude/skills/` からコピー)
- `~/.codex/config.toml` (テンプレートから生成)
- `~/.gemini/settings.json` (テンプレートから生成)

1Password から Webhook URL を取得してキャッシュ。

Claude Code API フォールバック用の OpenRouter API キーキャッシュも実行。詳細: [Claude Code API Fallback](./claude-fallback.md)

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

mise は Node.js, Python, Go 等のランタイムに加え、npm パッケージ（`npm:cspell` 等）や CLI ツール（`cloudflared` 等）も管理する。`mise install` で一括インストールされる。

## CI

`.github/workflows/ci.yml` で以下を自動実行:

- **ShellCheck**: `scripts/` 配下の全 `.sh` ファイルを静的解析
- **Stow Dry Run**: `common/` の全パッケージで stow コンフリクト検出
