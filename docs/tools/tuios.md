# TUIOS

> **由来:** **Upstream** [TUIOS](https://github.com/Gaurav-Gosain/tuios) / **Configuration** `common/tuios/` / **Custom** `scripts/tui`・Neovim navigation（[区分](../provenance.md#区分)）

既存tmuxを残した並行移行の第1段階。ローカルのキー操作、sessionグループ、popup、Claude / Piの状態表示をTUIOS 0.10.0で再構成する。`tbrowser`などの追加はまだ行わない。

## 導入と起動

macOSは`config/Brewfile`、Linuxのsudo / no-sudo両経路は`config/mise-linux.toml`で導入する。`install.sh`はStowに加えて次を設定する。

- `~/.config/tuios/config.d/dotfiles.toml`に共通設定をlink。
- `config.toml`がなければ空ファイルを作成。0.10.0はこのファイルがないと`config.d`を読み込まない。
- `config.d/10-shell.toml`にshell resolverの絶対パスを生成。既存の`tmux-default-shell`を共有し、zsh / nix-user-chrootの選択を維持する。tmuxコマンドは呼ばない。
- `tuios integration install claude-code pi`でupstreamのhookを導入。Claudeの既存hookとstatus line、Piの既存extensionは残す。Claude設定のテンプレート生成後に毎回実行する。

```bash
./install.sh

tui                         # mainを作成、または再接続
tui attach work --cwd ~/work # 指定sessionを作成、または再接続
tui pick                    # session / ghq / zoxideから選択
```

Ghosttyの起動設定は変更しない。tmuxの内側から重ねて起動せず、新しいGhosttyウィンドウのshellで`tui`を実行する。tmuxの既存paneは移されず、そのまま稼働する。戻る場合はTUIOSをdetachし、従来どおり`tmux attach`する。

## 対応関係

| tmux | TUIOS |
|---|---|
| session | session |
| window | workspace |
| pane | window |
| session group | space |
| popup用session | scratch pane |
| resurrect / continuum | daemonの保存・復元 |

workspaceは1〜9の固定枠。sessionは必要に応じて作成する。既存tmuxのsessionやgroupを自動importする処理はない。プロジェクトsession名はディレクトリ名とパスのhashで作り、同名checkoutの衝突を避ける。

## キー操作

prefixは従来と同じ`Ctrl+Space`。以下は特記しない限りprefixの後に押す。0.10.0には開発版のtmux presetがないため、個別に割り当てる。

| キー | 操作 |
|---|---|
| `c` | 空きworkspaceを作成しshellを開く |
| `n` / `p`、`Ctrl+l` / `Ctrl+h` | 使用中workspaceを次 / 前へ |
| `1`〜`8` | workspaceを選択 |
| `9` | 現在のGitルートに対応するsessionへ |
| `T` / `t` | workspace名 / pane名を変更 |
| `X` / `x` | workspace / paneを閉じる |
| `\|` / `-` | 左右 / 上下に分割し、cwdを継承 |
| `H` / `J` / `K` / `L` | paneをリサイズ。従来の2セルではなく5セル単位 |
| `z`、prefix不要の`Ctrl+z` | zoom |
| `v` / `[` | vi copy mode。`y`は既存`clipboard-copy`へ渡す |
| `u` / `Ctrl+u` | scrollbackブラウザー |
| `e` | native hints |
| `s` / `f` | native session switcher |
| `Ctrl+f` / `F` | session / ghq / zoxide picker |
| `Ctrl+g` | 現sessionをspaceへ登録、作成、解除 |
| `Tab` | 直前のsession |
| `a` | Inbox |
| `A` / `b` | session / agent sidebar |
| `o` / `O` | 要応答 / 完了したagentへ |
| `Ctrl+v` | native diff review |
| `S` | paneへの同時入力を切り替え |
| `l`、続けて`s` / `l` | native layoutを保存 / 読み込み |
| `N` | 空きworkspaceにClaude / Neovim / shellを開く |
| `r` / `?` / `d` | 設定再読込 / help / detach |
| `:` | command palette |

prefix不要の`Ctrl+h/j/k/l`はpane移動。Neovimでは先に内部splitを移動し、端に達したときだけOSC 7777でTUIOSへ移動を返す。tmux内では既存のvim-tmux-navigatorを使う。

`Alt+h/l`は同じspaceのsessionを前後に巡回し、`Alt+j/k`はspace間を移動する。移動先spaceでは最後に使ったsessionを選ぶ。TUIOS内のshellでは`Alt+s`が`tui pick`を開く。tmux内・通常のshellでは従来のsesh動作を残す。

## Popup

| キー | 内容 |
|---|---|
| `j` | native scratch shell |
| `g` | lazygit |
| `k` | `nvim .` |
| `G` | live-pr |
| `P` | pgcli。既存と同じ`DATABASE_URL`既定値 |
| `Q` | quay |
| `Space` | native file search |

shell以外のpopupもnative scratchで実装する。同じキーで表示を切り替え、プロセスを保持する。cwdは最初に開いた位置を使う。native scratch shellは別のworkspaceからも呼べる。popupの中でもprefixがTUIOSの操作に使われる。

`N`は`dev.tape`を実行する。全workspaceが使用中なら実行せず、稼働中のprogramへコマンドを誤入力しない。

## Agent状態

ClaudeとPiの状態変換・hook更新はupstreamに任せる。新しく起動したClaude / Piで反映する。現在進行中の会話を再起動する必要はない。

- Claudeの従来の通知やtmux hookは残す。tmux外でno-opになる既存処理を変更しない。
- PiのTUIOS extensionはinstallerが生成する。dotfiles側へupstream実装を複製しない。
- 状態はTUIOSのsidebar / Inbox / attention jumpへ表示する。既存のtmux agent indexやsidebar用paneは使わない。
- SSH切断・client detachではdaemon上のprocessが続く。OS再起動後の復元はprocessの継続ではない。会話の再開はnative resume機能で行う。

## 未移行部分

現時点で全面移行完了とは扱わない。

- `rcon`は従来のhost tmux + Docker経路を維持する。TUIOSへの切り替えにはremote側導入に加えて、Docker内からホストdaemonへhookを届けるsocket共有とcwd継承の検証が必要。
- tmuxの`F12` nested mode、任意2 paneのfzf swap、sticky zoom、セッションaccent color、既存layout preset、smugの任意YAMLは移植していない。TUIOS互換APIの`swap-pane`も0.10.0では非対応であり、成功するようには見せない。
- native layout / hints / reviewの操作体系はtmux pluginと同一ではない。既存のtmux scriptをTUIOS上でそのまま呼ばない。
- モバイル接続、ブラウザー、terminal-browser、Webサーバーの導入は別段階とする。

`config.toml`はmachine-localな設定画面・hosts登録用に残す。ここで変更した値は`config.d`より優先する。共通設定へ戻す場合は該当するlocal overrideを削除する。

## 検証

```bash
python3 scripts/test-tui.py
tuios keybinds doctor
```

テストは別の設定ディレクトリを使い、稼働中のtmux / TUIOS sessionを操作しない。daemon未起動時に`ls --json`が終了コード3で保存済みsession一覧を返す仕様と、引数なし`tui`の起動経路も検証する。Neovimはpluginの自動導入を伴わない最小設定で、内部移動・端でのOSC送信・従来tmuxコマンドの呼び分けを検証する。
