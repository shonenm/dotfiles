# Modern CLI Tools

> **由来:** **Upstream** 各CLI・mise・pixi / **Configuration** package宣言・alias / **Custom** install補助処理（[区分](../provenance.md#区分)）

CLIの導入元とZsh aliasをまとめる。インストール対象の正本は設定ファイルであり、この文書には固定の全件一覧を複製しない。

## インストール元

| 環境・方式 | 正本 |
|---|---|
| macOS Homebrew | `config/Brewfile` |
| Linux apt / apk | `config/packages.linux.{apt,alpine}.txt` |
| no-sudo Linux | `config/pixi-packages.txt` |
| Linux CLI | `config/mise-linux.toml`（aqua / github / cargo backend） |
| Linux公式installer、cargo、apt repository | `config/tools.linux.bash` |
| 全OS共通mise tool | `common/mise/.config/mise/config.toml` |

```bash
dots apply             # macOS / Linux
# sudoなしLinuxの初回・再適用:
dots apply --no-sudo
```

mise toolは`common/mise/.config/mise/mise.lock`の固定version・URL・checksumから導入する。追加後は`dots lock`を実行する。Linuxで廃止済みの独自 `github_release` 処理は使用せず、prebuilt releaseはmiseへ登録する。

lockfileはhost非依存に保つ。`mise lock` / `mise install`は実行hostの現在platformにだけ`provenance_verified`を書き込むため、stowするとdotfiles repoがdirtyになり`dots update`が失敗する。git上の`mise.lock`はstowせず、`install.sh`が`~/.config/mise/mise.lock`へコピーする。`scripts/update-mise-lock`は`provenance_verified`行を除去し、`locked_verify_provenance = true`で各hostのinstall時にprovenanceを再検証する。host共通の`provenance = ...`行はダウングレード検知に残す。

## Zsh alias

`common/zsh/.zshrc.common` は、コマンドが存在する場合だけaliasを定義する。同名置換はインストール有無で切り替える必要があるためaliasに残し、コマンドの短縮形はzsh-abbrへ寄せている。

| 入力 | 実行されるtool |
|---|---|
| `ls`, `ll`, `la` | `lsd`、なければ `eza` |
| `grep` | `rg` |
| `find` | `fd` |
| `man` | `tldr` |
| `sed` | `sd` |
| `du` | `dust` |
| `top` | `btm` |
| `rm` | `rip` |
| `watch` | `viddy` |
| `dig` | `doggo` |
| `http` | `xh` |

`bat` と `procs` は導入されるが、`cat` と `ps` は置き換えない。元のコマンドを使う場合は `command rm` のようにaliasを回避する。

`rip` の削除先は `$GRAVEYARD=~/.local/share/graveyard`。30日を超えた項目は、必要なときに`graveyard-purge`で削除する。Zsh起動時にはgraveyardを走査しない。

## グローバルabbreviation

行内のどこでも展開する。正本は `common/zsh-abbr/.config/zsh-abbr/user-abbreviations`（`abbr -g`）。

| 略語 | 展開 |
|---|---|
| `L` | `| bat` |
| `G` | `| rg` |
| `C` | `| pbcopy` |
| `H` | `| head` |
| `T` | `| tail` |

例: `git log L`。

## Suffix alias

| 拡張子 | コマンド |
|---|---|
| `.md`, `.txt`, `.yaml`, `.yml`, `.toml`, `.json` | `nvim` |
| `.py` | `python` |
| `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp` | `open` |

## 設定ファイル

- fdのglobal ignore: `common/fd/.config/fd/ignore`
- bat: `common/bat/.config/bat/config`
- Atuin: `common/atuin/.config/atuin/config.toml`
- Atuin daemon (systemd user unit): `common/atuin/.config/systemd/user/atuin-daemon.service`
- Atuin daemon (macOS launchd): `templates/com.user.atuin-daemon.plist`（`install.sh` がstow後に登録）
- mise: `common/mise/.config/mise/config.toml`

新しいtoolの登録方法は[新環境セットアップ](../install/setup-new-environment.md#新ツール追加時の登録先)を参照する。

## Atuin daemon

`config.toml` で `enabled = true` のため、各ホストで atuin daemon が稼働している必要がある
(daemon が無いと zsh-autosuggestions の検索が失敗する)。

- `install.sh` がstow後にmacOSではLaunchAgentを再登録し、Linuxではsystemd user unitをenable・再起動する。
- zsh とservice managerでは `TMPDIR` が異なるため、socketは `~/.local/share/atuin/atuin.sock` に固定する。
- Linuxでsystemd user sessionが利用できない場合は、daemonを永続化できないためinstallを失敗扱いにする。
