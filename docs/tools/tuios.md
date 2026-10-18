# TUIOS

> **由来:** **Upstream** [TUIOS](https://github.com/Gaurav-Gosain/tuios) / **Configuration** `common/tuios/`・`mac/tuios/` / **Custom** `scripts/tui`のproject picker・space巡回・Neovim navigation（[区分](../provenance.md#区分)）

TUIOS 0.10.1の標準機能を中心に、local / remote session、layout、AI表示、復元を管理する。既存tmuxは引き続き利用できる。

## 導入と起動

macOSは`config/Brewfile`、Linuxのsudo / no-sudo両経路は`config/mise-linux.toml`で導入する。Linuxは0.10.1を固定する。

```bash
./install.sh
tui                          # 最後に使ったsessionへ接続。初回はnativeが作成
tui attach work --cwd ~/work  # 指定sessionを作成・再接続
tui pick                     # ghq / zoxideからプロジェクトを選択
```

`tui`をTUIOS内で実行するとnative session switcherを開く。新しいGhosttyウィンドウでは、そのまま`tui`で起動する。

`install.sh`は次を設定する。

- 共通設定とmacOS用hosts設定をStowでlink。
- `config.toml`がなければ空ファイルを作成し、`config.d`を読み込めるようにする。
- `config.d/10-shell.toml`へshell resolverの絶対パスを生成。既存`tmux-default-shell`のzsh / nix-user-chroot選択を共有する。user binをPATHへ追加し、popup commandもlogin shellで実行する。
- `tuios integration install claude-code pi`でupstreamのhookを更新。Claudeの既存hook・status line、Piの他extensionを維持する。

`config.toml`はmachine-localな設定画面・hosts登録用。ここで設定した値は`config.d`より優先する。`tuios config origin KEY --json`で設定元を確認できる。

## キー操作

prefixは`Ctrl+Space`。表はprefixの後に押すキー。

| キー | 操作 |
|---|---|
| `c` | 空きworkspaceへshellを開く |
| `n` / `p`、`Ctrl+l` / `Ctrl+h` | 使用中workspaceを次 / 前へ |
| `1`〜`8` | workspaceを選択 |
| `9` | Gitルートのproject sessionへ |
| `T` / `t` | workspace名 / pane名を変更 |
| `X` / `x` | workspace / paneを閉じる |
| `\|` / `-` | 左右 / 上下に分割 |
| `H` / `J` / `K` / `L` | paneを5セル単位でリサイズ |
| `z`、prefix不要の`Ctrl+z` | sidebarを残してzoom |
| `v` / `[` | vi copy mode。`y`で`clipboard-copy`へ渡す |
| `u` / `Ctrl+u` | scrollbackブラウザー |
| `e` | native hints |
| `s` / `f` | native session switcher |
| `Ctrl+f` / `/` | native pane navigator。検索と画面preview |
| `F` | project picker。remoteは候補通知後に`prefix s`で選択 |
| `Ctrl+g` | native spaceへ登録、作成、解除 |
| `Tab` | 直前のsession |
| `a` / `i`、続けて`Tab` | Inboxから全agentのAgents viewへ |
| `A` / `b` | session / agent sidebar |
| `Ctrl+a` | Agents設定。integrationの確認・更新 |
| `o` / `O` | 要応答 / 完了したagentへ |
| `Ctrl+v` | native diff review |
| `S` | paneへの同時入力を切り替え |
| `l`、続けて`s` / `l` | native layoutの保存 / 読込 |
| `N` | localの空きworkspaceへClaude / Neovim / shellを開く |
| `r` / `?` / `d` | 再読込 / help / detach |
| `:` | command palette |

prefix不要の`Ctrl+h/j/k/l`はpane移動。Neovimの内部splitを先に移動し、端でTUIOSへ移動を返す。tmux内では既存vim-tmux-navigatorを使う。

zoom中に分割すると、追加paneがzoomの下に隠れる。`prefix z`で配置全体を表示する。

## Session・project picker

既存sessionはnative switcherで選ぶ。名前の絞り込み、作成、rename、削除、linked remoteへの切替を備える。pane navigatorはsession / workspace / paneのツリーと画面previewを表示する。

project pickerはhome、dotfiles、ghq、zoxideのディレクトリ一覧を扱う。選択後はnativeの`switch-session --create --cwd`へ渡す。同名checkoutの衝突を避けるため、session名はディレクトリ名とパスのhashで作る。

TUIOS内のshellの`Alt+s`はproject picker。通常のshell・tmux内は既存seshを使う。

## Spaceによるグループ管理

所属・保存・sidebar表示はnative spaceを使う。`prefix Ctrl+g`で登録する。

| prefix不要のキー | 操作 |
|---|---|
| `Ctrl+Alt+h` / `Ctrl+Alt+l` | 同じspaceのsessionを前 / 次へ |
| `Ctrl+Alt+j` / `Ctrl+Alt+k` | 次 / 前のspaceへ |
| `Alt+h/l/j/k` | 上と同じ。AeroSpaceとの競合時はCtrl付きキーを使う |

localでは移動先spaceの最終利用時刻が新しいsessionへ切り替える。時刻は秒単位で、同時刻なら名前順の先頭を選ぶ。巡回処理はnativeのsession一覧・space属性を読み、独自の状態ファイルを作らない。rename後のsession名もnativeから取得する。

remote表示中はpopupに切替候補のsession名を表示する。`Enter`で閉じ、`prefix s`の標準pickerから選択して確定する。TUIOS 0.10.1のhost-command fenceを維持し、remote popupからlocal画面を自動で切り替える要求を標準UIへの案内に変える。project pickerも同じ導線を使う。

project picker、space設定、巡回はpopup型commandとしてsessionのホストで実行する。各ホストにもdotfilesの更新と`install.sh`を適用する。shell型commandはMacで実行されるため、`N`の固定雛形はlocal向け。

spaceはホストごとの分類。同名spaceが複数ホストにあっても別グループで、global sessionはspaceへ所属しない。

## Remote hosts

Mac用の`20-hosts.toml`でSSH aliasの`ailab`と`pi-500`を登録する。native sidebar / switcherからlocalとremoteを同じ画面で管理する。

```bash
tuios hosts                           # 接続状態とdaemon version
tuios hosts sync ailab --start         # binaryを揃え、未起動daemonを開始
tuios new --host ailab work            # remoteに永続sessionを作成して表示
tuios attach --host ailab work         # 既存remote sessionを表示
```

`hosts sync --start`は既存daemonを維持する。更新済みbinaryへ切り替えるdaemon再起動は、そこで動く全paneのprogramを終了する操作なので、作業の切れ目に行う。

長時間のClaude / Piはremote側のsessionへ置く。Macの端末を閉じてもremoteで実行が続く。local sessionへremote paneを混ぜる`new-window --host`は、一時的に並べる用途に使う。混在paneの切断保持は既定10分で、local daemon再起動後の復元先はlocal shellになる。

従来の`rcon`は[tmux + Docker経路](../infrastructure/rcon.md)として維持する。containerへの自動入場・cwd継承はこの経路を利用する。TUIOSのhost登録はSSHホストが対象。

## Layout・プロジェクト起動

`prefix l s`で名前付きlayoutを保存し、`prefix l l`で選ぶ。既存paneのprocessを再利用し、不足paneを作成、余剰paneを最小化する。保存先は`~/.config/tuios/layouts/`。

project選択だけならnative session作成で十分。初回にエディタやagentも開きたいプロジェクトには、標準の`.tuios.tape`を置く。`autorun = "ask"`で内容を確認して実行する。command paletteのproject tape reviewから操作する。

`prefix N`は既存`dev.tape`のlocal向け雛形。全workspace使用中は中止し、既存programへの誤入力を防ぐ。

## AI表示

`prefix a`または`prefix i`でInboxを開き、`Tab`でAgents viewへ切り替える。local / 他session / linked remoteのagentを一覧表示し、検索、filter、sort、返信、paneへの移動をnativeに任せる。

- Claude Codeのpreviewはtranscriptから会話・tool callを表示。
- Piのpreviewはturn要約・最終message・mailが中心。
- `tuios integration status claude-code pi --json`でhookの更新状態を確認。
- `tuios doctor agents`で検出・integrationを診断。

upstream integrationを更新したら、新しく起動したharnessで反映する。既存会話はそのまま継続できる。新しいUIを使うときはdetachして`tui`で再接続する。

## 復元

native daemonがsession、space、layout、cwd、履歴を保存する。`resume_agents = "ask"`で、再起動後にClaude / Piの会話再開をInboxから選ぶ。Claudeは`--resume`、Piは`--session`で会話へ戻る。

普段はdetachでprocessを維持する。OS / daemon再起動後は保存状態から新しいshellを起動する。Neovimの未保存bufferや実行途中のjobは各program側で保存・再開する。`kill-session`は保存状態も削除する。

## Popup

`j`はscratch shell、`g`はlazygit、`k`は`nvim .`、`G`はlive-pr、`P`はpgcli、`Q`はquay、`Space`はnative file search。

scratchは同じキーで表示を切り替え、processを保持する。cwdは最初に開いた位置を使う。remote sessionではそのホスト上で実行する。

## 検証

```bash
python3 scripts/test-tui.py
tuios keybinds doctor
```

テストは隔離した設定を使用し、nativeのキー割当、project選択、space巡回、hook再導入、Neovim移動を確認する。実TUIでのlayout・復元の検証は専用daemon、remote検証は専用sessionで行い、稼働中の作業sessionを維持する。
