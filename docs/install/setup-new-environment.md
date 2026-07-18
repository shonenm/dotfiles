# 新環境セットアップ

環境別の差分と、新しいツールをdotfilesへ登録する場所をまとめる。基本手順は[インストールガイド](index.md)を正本とする。

## macOS

```bash
xcode-select --install
git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
op signin       # 完了時に案内された場合のみ
./install.sh    # secret依存設定を反映
```

## Linux（sudoあり）

```bash
sudo apt update && sudo apt install -y git curl
git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
op signin       # 完了時に案内された場合のみ
./install.sh
```

## Linux（no-sudo）

```bash
git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --no-sudo
~/.local/bin/op signin
./install.sh --no-sudo
```

ホスト要件とtmuxのsource buildについては[No-Sudo Install Mode](install-no-sudo.md)を参照する。

## Docker container

ホストのdotfilesをread-only bind mountし、container用スクリプトを実行する。

```yaml
services:
  app:
    volumes:
      - $HOME/dotfiles:/home/${USERNAME:-devuser}/dotfiles:ro
```

```bash
docker compose up -d --force-recreate app
docker exec app ~/dotfiles/scripts/install-in-container.sh
```

rcon targetも同時に設定する場合は `/d-setup-rcon-target <host>:<container> --apply` を利用できる。詳細は[rconセットアップ](../infrastructure/rcon-setup.md)。

## 日々の同期

```bash
dotsync
```

Macからリモートホストへpush / pullし、containerはbind mount経由で追従する。詳しくは[dotfiles同期](../infrastructure/dotfiles-sync.md)を参照。

## 新ツール追加時の登録先

取得方式を先に決め、既存の正本へ追加する。`scripts/mac.sh` / `scripts/linux.sh` へ個別ツールを直書きしない。

| 取得方式 | 追加先 |
|---|---|
| macOS Homebrew / cask | `config/Brewfile` |
| Linux標準パッケージ | `config/packages.linux.apt.txt`、必要なら `config/packages.linux.alpine.txt` |
| no-sudoでも必要なsystem相当パッケージ | `config/pixi-packages.txt` |
| Linux prebuilt release | `config/mise-linux.toml`（aqua / github backend） |
| Linux公式installer | `config/tools.linux.bash`（`curl_pipe`） |
| Linux cargo tool | `config/tools.linux.bash`（`cargo`） |
| Linux apt repository追加 | `config/tools.linux.bash`（`apt_repo`）とno-sudo代替 |
| 言語runtime・全OS共通mise tool | `common/mise/.config/mise/config.toml` |
| npm CLI | `config/packages.npm.txt` |

aptとpixiの対応が必要なパッケージは次で確認する。

```bash
scripts/check-package-duplication.sh
```

新しい取得方式を増やす前に、既存のBrew / pixi / mise / curl / cargo経路で扱えないか確認する。

## 確認

```bash
mise run doctor
scripts/check-package-duplication.sh
scripts/check-markdown-links.py
```

環境固有の未対応事項は、将来計画ではなく該当する運用文書の「制限」として記録する。
