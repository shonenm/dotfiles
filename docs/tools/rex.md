# Rex

> **由来:** **Upstream** [Rex](https://www.superlogical.com/rex/docs) / **Plugin** rexurrect（session 保存・復元） / **Configuration** `common/rex/` / **Custom** `scripts/rex-tools` の prefix menu・floating popup・メタデータ一覧・project picker・layout preset・pane swap picker、`scripts/rex-plugins` の plugin 取得、`next_ready.lua` の agent pane 巡回（[区分](../provenance.md#区分)）

Mac の Rex native session 用。既存の tmux / TUIOS と remote 環境は変更しない。Rex Beta 0.1.0 build 1591 の server API で検証している。GUI の floating layer 描画は別途確認が必要。

## 導入

Rex Beta は利用者が公式の配布から導入する。installer に beta token やダウンロード URL を保存しない。

`install.sh` は他の common package と同じく `common/rex` を自動列挙して Stow する。既に dotfiles を導入済みなら、この package だけ反映できる。

```bash
stow -d common -t ~ --no-folding rex
rex config check
rex config reload
```

正本は `common/rex/.config/rex/init.lua`。既存の独自 `~/.config/rex/init.lua` がある場合は、上書きせず内容を統合する。`rex-tools` は `~/dotfiles/scripts` から実行する。Python 3 と、各 popup の対象 command が必要。project / layout / swap picker は既存の fzf を使う。

通常の prefix 操作は Rex client が直接実行する。補助の操作一覧 menu や project picker から CLI 経由で session 切替などを実行する場合は、Rex Settings → Rex Server → **Remote Control** が必要。dotfiles はこの許可を自動変更しない。

helper はネットワークの `REX_SERVER` を拒否し、別ホストの cwd をローカル cwd とみなしたり、ローカルの統計を remote の値として表示したりしない。Rex の host（`rex hosts`）の session では、`init.lua` が server の host 接続（`rex.server`）で host 側に短命の pane を開き、host の `~/dotfiles/scripts/rex-tools popup` に任せる。cwd・toggle・label は手元と同じ処理になる。CLI の `rex -S` は呼出ごとに ssh 接続を張り直し、不安定なため使わない。host にも dotfiles と各 command が必要。no-sudo の host は `~/.profile` の zsh 切替が floating pane の command を捨てないこと（[Default Shell](../install/install-no-sudo.md#default-shell)）。

## Prefix は Rex 標準キーシーケンス

`Ctrl+Space` と次のキーは Rex client 内で受け取る。prefix のたびに Python / terminal popup を起動しないため、その起動待ちによる連続入力の取りこぼしを避ける。Esc で待機を解除する。popup command 自体の起動時間は残る。

`Ctrl+Space` を2回押すと terminal に Ctrl+Space を送る。tmux / TUIOS を内側に置く場合はこの送信操作を使う。

操作一覧は `Ctrl+Space → ?` または command palette の **Dotfiles: Prefix Menu** で開く。prefix 待機の自動表示は行わない。Rex は同じキーで sequence 開始と即時 action 実行を両立できないため、一覧 popup の表示を通常の入力経路から外している（[公式仕様](https://www.superlogical.com/rex/docs/customize/key-sequences)）。

| prefix 後のキー | 動作 |
|---|---|
| `?` | 操作一覧 popup（通常操作には不要） |
| `g` | lazygit、80% × 80% |
| `G` | live-pr、85% × 85% |
| `k` | `nvim .`、90% × 90% |
| `P` | pgcli。pane の起動環境の `DATABASE_URL`、未設定なら既存 tmux と同じ localhost 接続先 |
| `Q` | quay、80% × 80% |
| `j` | 永続 scratch shell、80% × 80% |
| `A` | メタデータ一覧、80% × 80% |
| `F` | ghq / zoxide / home / dotfiles から project 選択 |
| `l` | layout の保存・適用 |
| `m` | 同じ window の pane を2つ fzf で選び、位置を入れ替える（tmux の `prefix m` と同じ）。floating layer の pane も候補に含め、dotfiles の popup と上の layer に完全に隠れた pane は除く |
| `N` | 新しい tab に Neovim / Claude / shell の雛形 |
| `c` / `n` / `p` | 新規 / 次 / 前の tab |
| `s` / `f` | Rex 標準 session picker |
| `a` | Rex 標準 Activity の toggle |
| `z` | zoom |
| `\|` / `-` | 左右 / 上下分割 |
| `Ctrl+h/j/k/l` | pane 移動（prefix なしでも可） |
| `H/J/K/L` | pane resize |
| `r` | 設定 reload |
| `v` / `[` | pane の scrollback を tmux の copy mode で開く（[rex-tmux-copy](https://github.com/tomarrell/rex-tmux-copy)、[Plugin](#plugin) で管理）。`v` / `V` / `Ctrl+v` で選択、`y` で OSC 52 にコピー、`Enter` / `q` で閉じる。`u` / `d` は半ページ、`Ctrl+u` / `Ctrl+d` は4行スクロール |
| `Ctrl+u` | copy mode を開き半ページ戻る |

prefix 不要の `Ctrl+Option+h/l` は前後の tab、`Ctrl+Option+k/j` は前後の session へ移動する。tab 移動は session 内で循環し、端の tab からは反対の端へ移る（隣の session へは進まない）。tmux の session group を Rex の session、group 内の tmux session を tab に対応させ、tmux の `C-M-hjkl` と同じ指使いで tab 移動と session 移動を区別する。

prefix 不要の `Ctrl+h/j/k/l` は [vim-rex-navigator](https://github.com/paul-enz/vim-rex-navigator)（[Plugin](#plugin) で管理）で pane 移動する。前面が vim / nvim の pane ではキーを Neovim に渡し、Neovim は内部 split を先に移動して端で `rex focus` を呼ぶ（`common/nvim/.config/nvim/lua/plugins/tmux-navigator.lua`）。前面が ssh の pane（rcon のリモート nvim / tmux）でもキーを渡す。plugin は渡す先を vim / nvim に固定しているため、`init.lua` で binding の前にこの判定を挟んでいる。Rex 内でローカルの tmux / tuios を動かす運用は想定しない。plugin 同梱の Neovim 側 mapping は既存の tuios / snacks explorer 対応を上書きするため使わない。

`Cmd+U` は対応が必要な pane へ、手元と Rex の host（`rex hosts`）の全 session を横断して移動する（`common/rex/.config/rex/next_ready.lua`、Rex Beta Discord で grindlemire が公開した action を取り込んだもの）。OSC 7501 の program status を読み、blocked → error → done / idle の順、同じ状態なら古い順に巡回する。Claude Code は応答を終えると done ではなく idle を報告するため、idle を done と同じに扱う。続けて押すと次の pane へ進む。done / idle / error は表示済みの pane を飛ばし、blocked は対応するまで残る。表示済みの判定は client が pane の size を要求した時刻で行うため、見ている間に終わった pane は一度別の pane を見るまで対象に残る。

## Popup の保持と終了

popup は呼出元 block ごとに一つ。現在の block の cwd を API で取得し、同じ session / window に作成する。cwd が不明なら home へ勝手に切り替えずエラーにする。container 内 cwd の引き継ぎは未対応。

同じ popup を再度呼ぶと detach し、さらに呼ぶと同じ block を再表示する。scratch の shell や Neovim の未保存 buffer は終了しない。command 自体を終了すると Rex が block を片付ける。

block の識別は `dotfiles-popup/<kind>/<呼出元block ID>` という label を使う。手動で popup label を変更しない。呼出元を削除した場合、隠れた popup は自動削除しない。未保存作業があり得るため、`rex block ls` で確認してから明示的に閉じる。

再表示は API の制約により一度 tiled split に戻してから浮かせる。呼出元に短時間の resize が入る。tmux と全く同じ描画・focus 挙動は保証しない。

## メタデータ一覧

`prefix A`、または command palette の **Dotfiles: Metadata**。固定 header に project / host / cwd / 取得時刻を表示し、本文を **GIT / SYSTEM / AI USAGE / AGENTS** に分ける。使用量は列揃えした数値とバー、agent は状態別の色で表示する。狭い画面では縦並び。色が使えなくてもラベルと数値は残る。

`q` / Esc で閉じ、`r` で手動更新、`j/k` で本文を scroll。`d` で agent の報告時刻と未対応項目の説明を表示する。内部 block ID は通常画面に出さない。

再表示時は snapshot cache を最初に描画する。30秒以内なら再取得せず、古ければ前回値を残して裏で更新する。header の経過秒数・更新中・取得失敗表示で鮮度を区別し、失敗しても前回値を消さない。初回だけは取得中表示になる。表示中は30秒間隔、または `r` で更新し、system / Git / provider の取得は並列に行う。既存 helper 自身の cache も引き続き使う。

snapshot は `$XDG_CACHE_HOME/rex/metadata/`（既定 `~/.cache/rex/metadata/`）に session / 呼出元 block / popup 起動 cwd ごとに保存する。private なファイル権限（0600）で atomic に置き換え、Stow / Git の対象にしない。30秒以内の再表示は snapshot なので、その間の呼出元 cwd 変更などをすぐ反映したい場合は `r` を押す。

専用 daemon は起動しない。取得中に閉じた場合は先に pane を隠し、実行中の取得処理が timeout / 完了すると process も終了する。

| tmux header / sidebar の情報 | Rex での扱い |
|---|---|
| session / tab / pane、agent activity | Rex native を優先 |
| host・取得時刻・呼出元 cwd | 一覧上部 |
| CPU / RAM / GPU / disk | 既存 `tmux-*.sh` の結果から tmux 書式を除いて表示 |
| branch・ahead/behind・変更ファイル数・追加削除行 | 既存 `tmux-git-status.sh` を再利用。untracked は含まない |
| AI 使用量 | 既存 `ai-usage` の Claude / Codex / Gemini / Cursor / Grok 出力を再利用 |
| program status の補足 | 全 local session の OSC 7501 state・kind・message。報告時刻は `d` |
| group / space | 詳細画面で未対応と表示 |
| container 内 cwd | 詳細画面で未対応と表示 |
| heartbeat hang / agent resume | 詳細画面で未対応と表示。古い status を hang と断定しない |
| COPY / SYNC 等の tmux mode | Rex の状態として表示しない。PREFIX 待機の自動表示はしない |

統計はこの Mac 全体の値。Git は一覧 popup でなく呼出元 pane の cwd。取得失敗や値がない項目は0にしない。GPU 等は既存 helper が値を返さなければ表示対象なし。秘密情報や token を一覧へ出さず、使用量取得の認証処理は既存 command に任せる。

## Project と layout

project の session 名は basename とパスの hash。既存 session は再利用する。project の `.tmux` を Rex に送信・実行しない。session 作成後の GUI 切替には Remote Control が必要。

layout preset は `$XDG_DATA_HOME/rex/layouts/`、未設定なら `~/.local/share/rex/layouts/` に保存する。runtime の preset は Stow 対象外。保存時に既存名は上書きしない。

適用は tiled layer の分割構造が一致する場合だけ、比率を復元する。block ID が変わっていても構造が同じなら適用できる。pane の追加・破棄や command 再起動はしない。floating popup は保存対象外。

## Server 再起動後の復元

[rexurrect](https://github.com/cemcatik/rexurrect)（macOS のみ、`config/Brewfile`）で session を保存し、Rex server の再起動後に戻す。Rex 自身の復元は tab と pane の配置だけなので、rexurrect が scrollback・cwd・最後のコマンドと Claude Code の会話を補う。

| 役割 | 場所 |
|---|---|
| 15分ごとの保存（launchd agent） | `install.sh` が `rexurrect autosave install` を実行 |
| server 起動時の復元 | `common/rex/.config/rex/init.lua` の `auto-restore`。`rex config reload` では復元しない |
| block ごとの最後のコマンド | `common/zsh/.zshrc.common` が Rex 内でだけ recorder を読み込む |
| Claude Code の会話 ID | `templates/claude-settings.json` の `SessionStart` hook が `rexurrect report claude` を実行 |

復元した pane には最後のコマンドを入力するだけで実行しない。Claude Code が動いていた pane には `claude --resume <会話 ID>` を入力するので、Enter で再開する。Rex が自前で戻した session は scrollback を持たないため、rexurrect が自分の snapshot から作り直して置き換える。snapshot は `~/.local/state/rexurrect/`（直近10件）、手動操作は `rexurrect list` / `rexurrect restore --dry-run` / `rexurrect restore --session <label>`。設定は `~/.config/rexurrect/config.toml` で、既定のまま使う。

## Plugin

Rex に plugin manager はない。community の plugin は `init.lua` から `require` する Lua module として配布される。dotfiles では取得元と commit を manifest で固定する。

| 対象 | 場所 |
|---|---|
| 正本（取得元・commit） | `common/rex/.config/rex/plugins.txt` |
| 取得先（runtime、Stow / Git 対象外） | `$XDG_DATA_HOME/rex/plugins/<name>/`、未設定なら `~/.local/share/rex/plugins/` |
| 読み込みと設定 | `common/rex/.config/rex/init.lua` の `plugin("<module>", opts)` |

manifest は1行1 plugin で `name owner/repo commit [Lua ディレクトリ]`。Lua ディレクトリを省略すると repo 直下の `init.lua` を `name` で `require` する。`lua/<module>/init.lua` のような配置なら `lua` を指定する。

```bash
rex-plugins sync            # manifest の commit に揃える（install.sh も rex があれば実行）
rex-plugins update [NAME]   # 既定ブランチ HEAD に manifest を更新して sync
rex config reload
```

追加は manifest に1行足して `rex-plugins sync` し、`init.lua` に `plugin("<module>")` を書く。plugin の読み込みに失敗しても設定全体は止めず、Rex の log に警告して読み飛ばす。manifest から外した plugin の取得先は消さず、`sync` が `unlisted` と報告する。中身を確認してから手で削除する。

copy mode は開いた時点の snapshot で、表示位置は scrollback の末尾から始まる。vim など全画面 program では現在の画面だけになる。pane の実行先 machine に tmux 3.2 以上が必要で、copy mode 内の key は tmux 時代に合わせて `common/rex/.config/rex/tmux-copy.conf` で上書きしており、plugin はこれを pane の実行先 machine の `~/.config/rex/tmux-copy.conf` から読む。`prefix Ctrl+u` は plugin の action を包み、起動 command に `REX_TMUX_COPY_HALFPAGE=1` を付けて copy mode 開始時に半ページ戻す。

plugin が別の binary を必要とする場合、binary は [新ツール追加時の登録先](../install/setup-new-environment.md#新ツール追加時の登録先) に従って登録する。manifest は Lua module だけを扱う。`leaf rex install` のように `~/.config/rex/init.lua` を書き換える installer は Stow 先の正本を変更するため使わない。

## 検証

```bash
python3 scripts/test-rex-tools.py
# この設定を reload 済みの local Rex で keymap を検査し、専用 session を作成・削除する
REX_TEST_INTEGRATION=1 python3 scripts/test-rex-tools.py
rex config check ~/dotfiles/common/rex/.config/rex/init.lua
scripts/check-markdown-links.py
scripts/check-package-duplication.sh
```

integration test は読み込み済みの native prefix keymap（単独 prefix の popup binding がないことを含む）、scratch の block ID / PID が toggle 後も一致すること、layout の比率往復、PREFIX がサイズ変更通知（SIGWINCH）で終了せず Esc で終了すること、manifest の plugin が `init.lua` から読み込まれ未取得 plugin で設定が止まらないことを確認する。ユーザーの session へ入力しない。GUI の表示、キー入力、Remote Control を必要とする client action は実画面でも確認する。
