# Modern CLI Tools

CLIの導入元とZsh aliasをまとめる。インストール対象の正本は設定ファイルであり、この文書には固定の全件一覧を複製しない。

## インストール元

| 環境・方式 | 正本 |
|---|---|
| macOS Homebrew | `config/Brewfile` |
| Linux apt / apk | `config/packages.linux.{apt,alpine}.txt` |
| no-sudo Linux | `config/pixi-packages.txt` |
| Linux prebuilt CLI | `config/mise-linux.toml`（aqua / github backend） |
| Linux公式installer、cargo、apt repository | `config/tools.linux.bash` |
| 全OS共通mise tool | `common/mise/.config/mise/config.toml` |

```bash
./install.sh             # macOS / Linux
./install.sh --no-sudo   # sudoなしLinux
mise install             # mise管理toolを反映
```

Linuxで廃止済みの独自 `github_release` 処理は使用しない。prebuilt releaseはmiseへ登録する。

## Zsh alias

`common/zsh/.zshrc.common` は、コマンドが存在する場合だけaliasを定義する。

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

`rip` の削除先は `$GRAVEYARD=~/.local/share/graveyard`。30日を超えた項目はZsh起動時に削除する。

## グローバルalias

| Alias | 展開 |
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
- mise: `common/mise/.config/mise/config.toml`

新しいtoolの登録方法は[新環境セットアップ](../install/setup-new-environment.md#新ツール追加時の登録先)を参照する。
