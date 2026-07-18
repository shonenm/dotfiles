# dotfiles

macOS / Linux の開発環境を GNU Stow で再現する設定リポジトリ。

## 対応環境

- macOS
- Ubuntu / Debian、Alpine Linux
- sudo を利用できない Linux
- 開発用 Docker container

## 構成

```text
common/     共通設定（Neovim、Zsh、tmux、Git、AI CLI など）
mac/        macOS 固有設定
linux/      Linux 固有設定
config/     Brew、apt、pixi、mise、npm のパッケージ宣言
scripts/    セットアップとユーザー向けコマンド
docs/       導入・運用・仕様ドキュメント
install.sh  共通インストーラー
```

全ドキュメントは [`docs/INDEX.md`](docs/INDEX.md) から参照できる。

## 前提条件

- Git
- curl
- macOSでは Command Line Tools（`xcode-select --install`）
- no-sudo Linuxでは bash 4以上と unzip

1Password CLI、Homebrew、各種CLIは可能な範囲で `install.sh` が導入する。

## インストール

```bash
git clone https://github.com/shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

初回実行時に1Passwordへ未サインインでも、secret依存処理をスキップしてStowまで完了する。実行後に表示される案内どおり、サインインして同じコマンドを再実行する。

```bash
op signin
./install.sh
```

sudoを利用できないLinuxでは、両方の実行に `--no-sudo` を付ける。

```bash
./install.sh --no-sudo
~/.local/bin/op signin
./install.sh --no-sudo
```

containerなどsecretを使わない環境では `--skip-1p` を指定できる。詳しい分岐と実行内容は[インストールガイド](docs/install/index.md)、no-sudo固有事項は[No-Sudo Install Mode](docs/install/install-no-sudo.md)を参照。

## 更新

```bash
cd ~/dotfiles
git pull
./install.sh
```

設定ファイルだけの変更はStow済みのシンボリックリンクへ即時反映される。パッケージ、生成設定、プラグインが変わった場合は `install.sh` を再実行する。

## 主な設定

| 分野 | 入口 |
|---|---|
| Neovim | [`docs/tools/neovim/overview.md`](docs/tools/neovim/overview.md) |
| tmux | [`docs/tools/tmux.md`](docs/tools/tmux.md) |
| Zsh | [`docs/tools/zsh-startup-optimization.md`](docs/tools/zsh-startup-optimization.md) |
| Git | [`docs/configuration/git-config.md`](docs/configuration/git-config.md) |
| CLIツール | [`docs/configuration/modern-cli-tools.md`](docs/configuration/modern-cli-tools.md) |
| Pi / Claude Codeなど | [`docs/INDEX.md#aiエージェント`](docs/INDEX.md#aiエージェント) |
| リモート接続（rcon） | [`docs/infrastructure/rcon.md`](docs/infrastructure/rcon.md) |

## ローカル専用ファイル

次のファイルはリポジトリで管理しない。

- `~/.zshrc.local`
- `~/.gitconfig.local`
- `~/.ssh/config.d/*`
- `~/.config/rcon/targets`
- 認証情報、履歴、キャッシュ

## ライセンス

MIT
