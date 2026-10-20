# TUIOS

> **由来:** **Upstream** [TUIOS](https://github.com/Gaurav-Gosain/tuios) / **Configuration** `common/tuios/`・`mac/tuios/` / **Custom** `scripts/tui`のproject picker・space設定と巡回・dock agents・sidebar usage・theme / pane入替picker・dock status・Neovim navigation・ssh/fzf/tmuxへのキー委譲・`tui rcon` container session（[区分](../provenance.md#区分)）

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

設定を反映するには`prefix d`でdetachして`tui`で再接続する。daemonとsession内のprogramは維持される。

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
| `X` / `x` | workspace / paneを閉じる。tmuxの`confirm-before`と同じく`y`の1キーで確定し、それ以外は閉じない。remote sessionではpopupがそのホストの`~/dotfiles`で動くため、ホスト側も`git pull`（`dotsync`）で揃える |
| `\|` / `-` | 左右 / 上下に分割 |
| `H` / `J` / `K` / `L` | paneを5セル単位でリサイズ |
| `z`、prefix不要の`Ctrl+z` | sidebarを残してzoom。zoom中はfocus枠線が紫 |
| `v` / `[` | vi copy mode。`y`で`clipboard-copy`へ渡す。`Esc`は選択中なら解除、それ以外は終了 |
| `u` / `Ctrl+u` | copy modeへ入る。tmuxは入ると同時に半ページ上へ移動するが、TUIOS 0.10.1は1キーに2操作を割り当てられないため、続けて`Ctrl+u`で半ページ上へ移動する。scrollbackブラウザーのキー割り当ては外した |
| `e` | native hints |
| `s` / `f` | native session switcher。local / remoteのsessionを選択 |
| `Ctrl+f` / `/` | native pane navigator。全sessionのpaneを画面カードで一覧（tmux.expose相当） |
| `m` | 入れ替える2つのpaneをfzfで順に選ぶ（src → dst、tmux-swap-pickerと同じ）。候補はfocus中paneを含むworkspace内のpaneで、paneタイトルと同じ`番号: 名前`。最小化したpaneは除く |
| `y` | themeをfzfで選ぶ。このclientだけに一時適用し、設定ファイルは変えない |
| `F` | project picker。remoteは候補通知後に`prefix s`で選択 |
| `Ctrl+s` | native spaceへ登録、作成、解除 |
| `Tab` | 直前のsession。ホストをまたいで戻れる |
| `a` / `i`、続けて`Tab` | Inboxから全agentのAgents viewへ |
| `A` / `b` | session / agent sidebar |
| `Ctrl+a` | Agents設定。integrationの確認・更新 |
| `o` / `O` | 要応答 / 完了したagentへ |
| `Ctrl+v` | native diff review |
| `S` | paneへの同時入力を切り替え |
| `l`、続けて`s` / `l` | native layoutの保存 / 読込 |
| `N` | localの空きworkspaceへClaude / Neovim / shellを開く |
| `r` / `?` / `d` | 再読込（実行中はfocus枠線が橙） / help / detach |
| `:` | command palette |

prefix不要の`Ctrl+h/j/k/l`はpane移動。TUIOS 0.10.1は端で反対側へwrapしない（[upstream #895](https://github.com/Gaurav-Gosain/tuios/issues/895)）。Neovimの内部splitを先に移動し、端でTUIOSへ移動を返す。tmux内では既存vim-tmux-navigatorを使う。

TUIOS内のzshで`ssh`・`fzf`・`tmux`を実行している間は、`Ctrl+h/j/k/l`をそのprogramへ渡す（tmuxの`@vim_navigator_pattern`相当）。preexecでnvim navigatorの状態をactiveにし、終了後のpromptで戻す。端でのTUIOSへの返却はないため、実行中のpane移動はprefixやWindow modeで行う。コマンドラインから起動したprogramだけが対象で、`Ctrl+t`などのZLE widgetから開いたfzfは対象外。

TUIOS 0.10.1未対応のため移植していないもの：

- 入れ子用に外側のキーバインドをまとめて止めるモード（tmuxのF12）。leaderは2回押すとpaneへ送られる。
- 端末タイトルへfocus中paneのcwd名を出す設定（tmuxの`set-titles`）。
- copy modeの`Ctrl+u/d`を4行スクロールへ割り当てること。copy modeの移動キーは固定で、`Ctrl+u/d`は半画面移動。

zoom中に分割すると、追加paneがzoomの下に隠れる。`prefix z`で配置全体を表示する。

## Window管理モード

`Alt+Esc`でWindow modeへ入る。`prefix Esc`は何もしない（割り当てがないとEscがpaneへ渡るため、no-opのcommandを置いている）。TUIOSのwindowはterminal paneと同じもので、Ghostty内のwindow配置を操作するモードになる。キーボードで別paneへ移動してもWindow modeを維持し、`Enter` / `i`で入力を始める。

| Window mode中のキー | 操作 |
|---|---|
| `Tab` / `Shift+Tab` | 次 / 前のwindowを選択 |
| `h/j/k/l` | その方向のwindowへfocus。自由配置ではsnap |
| `n` | 新しいwindowを開く |
| `N` | ホストを選んでsessionを作成 |
| `m` / `M` | 最小化 / すべて復元 |
| `z` | zoom |
| `t` | タイル配置 / 自由配置を切替 |
| `r` | window名を変更 |
| `Enter` / `i` | 選んだwindowへ入力 |

Window modeの`w` / `x`（確認なしでwindowを閉じる）は外している。閉じるときは確認付きの`prefix x`を使う。

自由配置ではwindowを重ね、タイトルバーをドラッグして移動する。タイル配置では別paneの中央へdropすると入れ替わり、端へdropするとその方向へ組み直す。`prefix t`は名前変更、Window modeの`t`は配置切替という違いに注意する。

## Session・project picker

既存sessionはnative switcherで選ぶ。名前の絞り込み、作成、rename、削除、linked remoteへの切替を備える。pane navigatorはsession / workspace / paneのツリーと画面previewを表示する。

| prefix不要のキー | 操作 |
|---|---|
| `Ctrl+Alt+h` / `Ctrl+Alt+l` | 同じホスト内のsessionを前 / 次へ。spaceをまたぐ |
| `Ctrl+Alt+j` / `Ctrl+Alt+k` | localの次 / 前のspaceへ |
| `Alt+h/l` | 同じホスト内のsessionを前 / 次へ。AeroSpace使用時はCtrl付きキーを使う |

sessionの前後移動はnative actionへ直接割り当て、shellやcommand popupを起動しない。ホスト巡回キーはTUIOS 0.10.1にない（[upstream #896](https://github.com/Gaurav-Gosain/tuios/issues/896)）。ホストをまたぐ移動は`prefix s`でホスト名またはsession名を検索して`Enter`で確定し、`prefix Tab`で元のsessionへ戻る。`Ctrl+Alt+j/k`はlocalのspace巡回用で、`Alt+j/k`はAeroSpaceとの競合を避けて割り当てない。

project pickerはhome、dotfiles、ghq、zoxideのディレクトリ一覧を扱う。選択後はnativeの`switch-session --create --cwd`へ渡す。同名checkoutの衝突を避けるため、session名はディレクトリ名とパスのhashで作る。

TUIOS内のshellの`Alt+s`はproject picker。通常のshell・tmux内は既存seshを使う。

## Space

spaceは関連するsessionをまとめるTUIOS標準の分類名。所属・保存・sidebar表示をnativeで管理する。localのspace巡回だけhelperで補い、独自の分類や状態ファイルは持たない。既存sessionのspace所属はそのまま維持する。

- **所属変更・作成・解除**：`prefix Ctrl+s`のpicker。shellからは`tui space`。
- **別spaceのsessionへ移動**：`Alt+Esc`でWindow modeへ入り、`s`でsidebarへfocus。`j/k`または矢印で目的のspace内のsessionを選び、`Enter`で移動する。
- **名前からsessionを選択**：`prefix s`の標準switcher。ホストをまたぐ移動もここへまとめる。

spaceの見出しは分類表示で、移動先にはその中のsessionを選ぶ。`Ctrl+Alt+h/l`はspaceで絞らず、同じホスト内のsessionを巡回する。

`Ctrl+Alt+j/k`はspace名順で次 / 前へ巡回する。未所属も巡回先に含め、移動先では最終利用時刻が新しいsessionを選ぶ。同時刻ならsession名順の先頭を選ぶ。spaceが1つなら移動しない。

巡回はpopupなしのlocal shell commandで実行する。keybindingからclientのPIDを渡し、nativeの`list-clients`で現在のsessionを取得して`switch-session --client`でそのclientだけを動かす。rename前の環境変数や別clientの表示sessionには依存しない。

remote表示中のspace巡回はTUIOS 0.10.1の標準APIでは行えないため、`prefix s`またはsidebarでsessionを選ぶ。`Ctrl+Alt+j/k`はlocal専用で、host-command fenceを迂回しない。

project pickerでremoteの切替先を選んだ場合はpopupにsession名を表示する。`Enter`で閉じ、`prefix s`の標準pickerから選択して確定する。TUIOS 0.10.1のhost-command fenceを維持し、remote popupからlocal画面を自動で切り替える要求を標準UIへの案内に変える。通常のsession移動とホストをまたぐ移動はnative actionで直接処理する。

project pickerとspace設定はpopup型commandとしてsessionのホストで実行する。各ホストにもdotfilesの更新と`install.sh`を適用する。shell型commandはMacで実行されるため、`prefix N`の固定雛形はlocal向け。

spaceはホストごとの分類。同名spaceが複数ホストにあっても別のspaceで、global sessionはspaceへ所属しない。

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

TUIOSのhost登録はSSHホストが対象。Docker containerへ入るsessionは`tui rcon`で作る。

## Container session

`tui rcon`は`~/.config/rcon/targets`（`host:container`形式）からfzfで選ぶ。`tui rcon ailab:myproject-dev`のように直接指定もできる。このマシンのcontainerは`local:<container>`と書く。containerなしの`host`は、そのホストの`main` sessionを開く。

- container名（`:` `.`は`-`）のsessionを作成・表示する。作成前に、sessionのホストの`${XDG_STATE_HOME:-~/.local/state}/tuios-rcon/<session>`へcontainer名を書く。remoteへは`[hosts]`の`addr`でSSHして書く。
- pane shell（`tmux-default-shell`）はこのファイルがあると`tmux-docker-enter`で入る。分割・新規pane・daemon再起動後の復元も同じ。containerが停止中ならホストshellになる。
- 新規paneのcwdは、同じsessionで最後にpromptを出したpaneのcontainer内cwdを使う。container側zshrcのhookがpaneごとのcwdを`tmux-pane-state`へ書く（[前提](../infrastructure/rcon.md#cwd-引き継ぎの前提条件)）。別paneへfocusを移しただけで分割すると、直前にpromptを出したpaneのcwdになる。
- `g` / `G` / `P` / `Q`のpopupは、focus中paneのcontainer内cwdで`tmux-popup-in-container`から実行する。

登録の解除はstate fileを削除する。session名を変えると登録は外れる。

TUIOS 0.10.1未対応のため、次の部分をhelperで補う。

- session単位のdefault command・user optionがない。登録はstate fileに置く。
- 新規paneのshell起動時には新しいpaneへfocusが移っており、分割元paneを取得できない。cwdの継承はprocessのcwdを使うため、container内のcdは反映されない。

従来の`rcon`は[tmux + Docker経路](../infrastructure/rcon.md)として引き続き使える。

## Layout・プロジェクト起動

`prefix l s`で名前付きlayoutを保存し、`prefix l l`で選ぶ。既存paneのprocessを再利用し、不足paneを作成、余剰paneを最小化する。保存先は`~/.config/tuios/layouts/`。

project選択だけならnative session作成で十分。初回にエディタやagentも開きたいプロジェクトには、標準の`.tuios.tape`を置く。`autorun = "ask"`で内容を確認して実行する。command paletteのproject tape reviewから操作する。

`prefix N`は既存`dev.tape`のlocal向け雛形。全workspace使用中は中止し、既存programへの誤入力を防ぐ。

## 表示

tmuxの`pane-border-status`と`pane-active-border-style`に合わせる。

- 枠線の色はtokyonightを元にした`themes/tokyonight-tmux.json`で決める。focus中は青`#7aa2f7`、copy modeは赤`#f7768e`、同時入力（multifocus）は緑`#73daca`、focus外は`#3b4261`。`border_focused_color`はmodeの色を上書きして消すため設定しない。focus外の色はthemeで指定すると背景とのコントラスト補正で明るくなるため、`border_unfocused_color`で固定する。Window modeはtheme標準の`accent_bright`。zoom（紫`#bb9af7`）とreload（橙`#ff9e64`）はTUIOS 0.10.1未対応のため、`prefix z` / `Ctrl+z` / `prefix r`を`tui mode zoom|reload`に置き換え、focus枠線の色だけ違うtheme（`tokyonight-tmux-zoom` / `-reload`）をclientへ一時適用する。設定ファイルは書き換えない。Window modeの`z`やpaneを閉じてzoomが解けた場合は、次のzoom / reloadまで紫が残る。prefix（黄）は押下を拾う手段がなく、dockのmode表示で判別する。
- pane上端に`番号: タイトル`を表示し、window buttonは隠す。TUIOS 0.10.1は`shared_borders`有効時にtitleを描画しないため無効にしている。
- focus外paneの`dim_unfocused`は使わない。TUIOS 0.10.1はtheme設定時に既定背景のセルへthemeの背景色を塗るため、背景透過が消える。代わりに枠線の色でfocusとmodeを示す。
- sidebarのsession一覧はTUIOS標準のsessions欄だけを使う。session行の状態glyphとrepo / branchのgroupingは標準表示。
- sidebar最下部の`usage`はtmux sidebarのUSAGEと同じAI使用量で、`tui usage`が`ai-usage`（claude / codex / gemini / cursor / grok）を並列に呼んで30秒ごとに描く。リミット消化ペースの色（青=使い切り、緑=ペース良好、黄・橙=余り気味、赤=使い切れない見込み）は`tmux-agent-sidebar.sh`と同じ判定。
- dockの`󰚩 N ●●`は`tui dock agents`の出力で、表示中sessionのagent数と状態色（黄=作業中、赤=要応答/エラー、緑=完了、紫=hang、灰=待機）を3秒ごとに表示する。agentがいなければcellを隠す。
- hangはtmuxの`tmux-agent-hang-watch.sh`相当。`working`のまま`AGENT_HANG_THRESHOLD`秒（既定120）hookのreportがないpaneを紫で示す。hookはtool呼び出しごとに`working`を再reportし`evidence_age_ms`を更新するため、これをheartbeatとして使う。画面出力は生存扱いにしない。常駐watcherは置かず、dock cellの3秒周期で判定する。表示はdockのみで、TUIOS標準のrail glyph・Inbox・通知は`working`のまま（hook経由のagentの無応答検知はTUIOS 0.10.1未対応）。1つのtoolが長時間動く間やtool呼び出しのない長い思考中も同じくhangと推定される。
- dockの右側はtmuxの`status-right`相当。CPU・RAM（標準）、GPU、`/`の使用率、focus中paneのbranch、`月/日 時:分`の時計、ホスト名を並べる。GPU・ストレージ・branchは`tui dock gpu|storage|branch`の出力で、tmuxと同じ閾値色を使う。GPUはmacOSの`macmon`かLinuxの`nvidia-smi`があるときだけ表示する。dock commandにはfocus中paneのcwdが渡らないため、branchは`tuios list-agents -s $TUIOS_SESSION`のfocus中paneから引く。remote sessionのbranchはTUIOS 0.10.1未対応で表示しない。mode・prefix・copyの表示はdock標準のpillを使う。

## AI表示

`prefix a`または`prefix i`でInboxを開き、`Tab`でAgents viewへ切り替える。local / 他session / linked remoteのagentを一覧表示し、検索、filter、sort、返信、paneへの移動をnativeに任せる。

- Claude Codeのpreviewはtranscriptから会話・tool callを表示。
- Piのpreviewはturn要約・最終message・mailが中心。
- `tuios integration status claude-code pi --json`でhookの更新状態を確認。
- `tuios doctor agents`で検出・integrationを診断。
- SketchyBar / Slack通知はtmuxと同じ`ai-notify.sh`を使う。`after-focus-change` hookでfocusしたpaneの通知を消す。詳細は[Claude Beacon](../ai-agents/claude/claude-beacon.md#scriptstmux-claude-focussh)。hookの変更は`tuios kill-server`後に反映される。

upstream integrationを更新したら、新しく起動したharnessで反映する。既存会話はそのまま継続できる。新しいUIを使うときはdetachして`tui`で再接続する。

## 復元

native daemonがsession、space、layout、cwd、履歴を保存する。`resume_agents = "ask"`で、再起動後にClaude / Piの会話再開をInboxから選ぶ。Claudeは`--resume`、Piは`--session`で会話へ戻る。

普段はdetachでprocessを維持する。OS / daemon再起動後は保存状態から新しいshellを起動する。Neovimの未保存bufferや実行途中のjobは各program側で保存・再開する。`kill-session`は保存状態も削除する。

例外として、paneで動いていた`ralph-crew daemon`は`tmux-default-shell`が復元時に再実行する。TUIOSはshell以外のprogramを自動で再起動しないため、daemon側がpane IDごとに起動コマンドを記録する。詳細は[Ralph Crew](../ai-agents/ralph/crew.md#tuios-内で使う)。

## Popup

`j`はscratch shell、`g`はlazygit、`k`は`nvim .`、`G`はlive-pr、`P`はpgcli、`Q`はquay、`Space`はnative file search。

scratchは同じキーで表示を切り替え、processを保持する。cwdは最初に開いた位置を使う。remote sessionではそのホスト上で実行する。[container session](#container-session)では`g` / `G` / `P` / `Q`をcontainer内で実行する。

## 検証

```bash
python3 scripts/test-tui.py
tuios keybinds doctor
```

テストは隔離した設定を使用し、nativeの移動キー、Window mode設定、project選択、space設定、hook再導入、Neovim移動を確認する。実TUIでのlayout・復元の検証は専用daemon、remote検証は専用sessionで行い、稼働中の作業sessionを維持する。
