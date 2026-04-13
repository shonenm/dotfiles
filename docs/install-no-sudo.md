# No-Sudo Install Mode

sudo 権限のないリモート Linux ホスト (共有サーバー、管理された開発環境、一部コンテナ等) でも dotfiles をセットアップするためのモード。

## Usage

```bash
# 明示的に no-sudo モードで実行
./install.sh --no-sudo

# sudo モードを強制 (自動検出を上書き)
./install.sh --with-sudo

# デフォルト: auto-detect
./install.sh
```

## 自動検出の仕組み

`scripts/utils.sh` の `detect_sudo_mode` が以下の順でチェック:

1. `EUID == 0` (既に root) → sudo モード (root で apt 実行可能)
2. `sudo` バイナリが PATH にあるか → 無ければ NO_SUDO
3. `sudo -n true` が成功するか (非対話で sudo が通るか: NOPASSWD or ticket 有効) → 通らなければ NO_SUDO

いずれも `install.sh` から明示フラグが渡されていなければ自動判定に任せる。

## NO_SUDO モードでの動作差分

### システムパッケージ

| 項目 | sudo モード | no-sudo モード |
|------|-------------|----------------|
| 提供元 | `apt` (or `apk`) | **pixi** (conda-forge) |
| 設定ファイル | `config/packages.linux.apt.txt` | `config/pixi-packages.txt` |
| インストール先 | `/usr/bin`, `/usr/local/bin` | `~/.pixi/bin` |

pixi は `curl -fsSL https://pixi.sh/install.sh \| sh` でユーザースコープに入る単一バイナリ。conda-forge からプリビルドを取得するので高速。

### Modern CLI tools (github_release 系)

`scripts/linux.sh:_install_github_release` の install 先が以下のように切り替わる:

- sudo モード: `$SUDO install /usr/local/bin/`
- no-sudo モード: `install ~/.local/bin/` (SUDO なし)

### apt_repo 系 tool (gh, eza, bat, postgresql)

no-sudo モードでは **pixi 経由で導入** される (`config/pixi-packages.txt` に含める)。`install_modern_tools` のディスパッチャで `method=apt_repo && NO_SUDO=true` の組み合わせは skip される。

### Neovim

tarball を `~/.local/opt/nvim-linux-<ARCH>` に展開、`~/.local/bin/nvim` symlink を作る (`_install_neovim_tarball` helper)。sudo モード時は従来通り `/opt` + `/usr/local/bin`。

### 1Password CLI

- sudo モード: apt (`1password-cli` パッケージ) で `/usr/bin/op`
- no-sudo モード: `cache.agilebits.com` から tarball を DL し `~/.local/bin/op` に展開 (`install.sh:_install_1password_cli_user_scope`)。バージョンは `OP_CLI_VERSION` 環境変数で上書き可能 (既定 2.34.0)

### Default Shell

- sudo モード: `/etc/shells` 追記 + `chsh -s /bin/zsh`
- no-sudo モード: `~/.profile` に以下を追記 (marker で冪等化):
  ```sh
  # dotfiles: exec zsh -l (no-sudo mode)
  if [ -z "$ZSH_VERSION" ] && [ -t 0 ] && command -v zsh >/dev/null 2>&1; then
    exec zsh -l
  fi
  ```
  SSH ログインで bash → zsh exec に切り替わる。`chsh` が使えない環境の標準的な代替手法。

## 前提条件 (ホスト側に必要なもの)

no-sudo モードでも最低限以下はホスト側に存在している必要がある (通常の開発ホストなら標準で入っている):

- `bash` (≥ 4)
- `git`
- `curl`
- `unzip` (1Password CLI の zip 展開用。pixi 経由で補うことも可)

これらが無い場合は管理者に一度だけインストールを依頼する。

## 制限 / 注意点

### conda-forge パッケージの CONDA_PREFIX リーク

pixi global で入れた executable は `CONDA_PREFIX` 環境変数が設定されて起動する。一部 Python 系 tool は conda 環境だと誤認して挙動が変わる可能性がある。問題が出た場合は対象パッケージのメンテナに `etc/pixi/<exe>/global-ignore-conda-prefix` marker file の追加を依頼するか、手動で unset する。

### PATH 優先順位

`~/.local/bin` と `~/.pixi/bin` が `/usr/local/bin` より前に来る必要がある。zsh の場合は `common/zsh/.zshrc.common` で既に PATH 先頭に追加済み。

### 一部の機能は無効化される

- `chsh` でデフォルトシェル変更は行わない (`.profile` fallback で代替)
- `/etc/shells` 編集は行わない
- `systemd` ユニット登録などシステムレベル連携は諦める (必要ならユーザー systemd = `--user` を使う)

### macOS は対象外

macOS は Homebrew が cask (GUI app)、3rd party tap 、macOS 専用ツール (macmon 等) を提供する必要があり、pixi では代替不可。Mac は常に sudo モード相当 (Homebrew) で動作する。

## Verification

セットアップ後に以下を確認:

```bash
# pixi が入り、パッケージがインストールされているか
pixi --version
pixi global list

# ツール check
command -v tmux stow gh eza bat jq op zsh

# ログインシェルが zsh に切り替わるか (新しいセッションで)
ssh <host>
echo $ZSH_VERSION  # 空でない値が出れば OK
```

## Troubleshooting

### pixi が PATH に出ない

`install.sh` 実行後は新しいシェルを開くか `source ~/.zshrc` で PATH を再ロード。`export PATH="$HOME/.pixi/bin:$PATH"` を手動で追加することも可。

### `sudo -n true` が意図せず成功する (誤検出)

sudo ticket が前のコマンドで有効化されていると auto-detect が「sudo 使える」と判定する。`sudo -k` で ticket を破棄してから再実行、または `--no-sudo` を明示。

### 1Password CLI のダウンロードが失敗

`OP_CLI_VERSION` 環境変数で別バージョンを指定:

```bash
OP_CLI_VERSION=2.30.0 ./install.sh --no-sudo
```

最新版は <https://app-updates.agilebits.com/product_history/CLI2> で確認。

## 関連ドキュメント

- [install.md](./install.md) — 通常の install 手順
- [rcon.md](./rcon.md) — リモート接続コマンド (no-sudo ホストでの運用前提)
