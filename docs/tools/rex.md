# Rex

> **由来:** **Upstream** [Rex](https://www.superlogical.com/rex/docs) / **Configuration** `common/rex/` / **Custom** `scripts/rex-tools` の prefix menu・floating popup・メタデータ一覧・project picker・layout preset（[区分](../provenance.md#区分)）

Mac の Rex native session 用。既存の tmux / TUIOS と remote 環境は変更しない。Rex Beta 0.1.0 build 1591 の server API で検証している。GUI の floating layer 描画は別途確認が必要。

## 導入

Rex Beta は利用者が公式の配布から導入する。installer に beta token やダウンロード URL を保存しない。

`install.sh` は他の common package と同じく `common/rex` を自動列挙して Stow する。既に dotfiles を導入済みなら、この package だけ反映できる。

```bash
stow -d common -t ~ --no-folding rex
rex config check
rex config reload
```

正本は `common/rex/.config/rex/init.lua`。既存の独自 `~/.config/rex/init.lua` がある場合は、上書きせず内容を統合する。`rex-tools` は `~/dotfiles/scripts` から実行する。Python 3 と、各 popup の対象 command が必要。project / layout picker は既存の fzf を使う。

通常の prefix 操作は Rex client が直接実行する。補助の操作一覧 menu や project picker から CLI 経由で session 切替などを実行する場合は、Rex Settings → Rex Server → **Remote Control** が必要。dotfiles はこの許可を自動変更しない。

remote Rex は対象外。helper はネットワークの `REX_SERVER` を拒否する。別ホストの cwd をローカル cwd とみなしたり、ローカルの統計を remote の値として表示したりしない。

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
| `N` | 新しい tab に Neovim / Claude / shell の雛形 |
| `c` / `n` / `p` | 新規 / 次 / 前の tab |
| `s` / `f` | Rex 標準 session picker |
| `a` | Rex 標準 Activity の toggle |
| `z` | zoom |
| `\|` / `-` | 左右 / 上下分割 |
| `Ctrl+h/j/k/l` | pane 移動 |
| `H/J/K/L` | pane resize |
| `r` | 設定 reload |

prefix 不要の `Ctrl+h/j/k/l` は設定しない。Neovim 内部 split を優先する既存 navigator は Rex 未対応なので、入力を奪わず prefix 経由で外側を移動する。

## Popup の保持と終了

popup は呼出元 block ごとに一つ。現在の block の cwd を API で取得し、同じ session / window に作成する。cwd が不明なら home へ勝手に切り替えずエラーにする。container 内 cwd の引き継ぎは未対応。

同じ popup を再度呼ぶと detach し、さらに呼ぶと同じ block を再表示する。scratch の shell や Neovim の未保存 buffer は終了しない。command 自体を終了すると Rex が block を片付ける。

block の識別は `dotfiles-popup/<kind>/<呼出元block ID>` という label を使う。手動で popup label を変更しない。呼出元を削除した場合、隠れた popup は自動削除しない。未保存作業があり得るため、`rex block ls` で確認してから明示的に閉じる。

再表示は API の制約により一度 tiled split に戻してから浮かせる。呼出元に短時間の resize が入る。tmux と全く同じ描画・focus 挙動は保証しない。

## メタデータ一覧

`prefix A`、または command palette の **Dotfiles: Metadata**。`q` / Esc で閉じ、`r` で手動更新、`j/k` で scroll。表示中は取得完了から30秒ごとに更新する。専用 daemon は起動しない。取得中に閉じた場合は先に pane を隠し、実行中の取得処理が timeout / 完了すると process も終了する。

| tmux header / sidebar の情報 | Rex での扱い |
|---|---|
| session / tab / pane、agent activity | Rex native を優先 |
| host・取得時刻・呼出元 cwd | 一覧上部 |
| CPU / RAM / GPU / disk | 既存 `tmux-*.sh` の結果から tmux 書式を除いて表示 |
| branch・ahead/behind・変更ファイル数・追加削除行 | 既存 `tmux-git-status.sh` を再利用。untracked は含まない |
| AI 使用量 | 既存 `ai-usage` の Claude / Codex / Gemini / Cursor / Grok 出力を再利用 |
| program status の補足 | 全 local session の OSC 7501 state・kind・message・報告時刻 |
| group / space | 未対応と表示 |
| container 内 cwd | 未対応と表示 |
| heartbeat hang / agent resume | 未対応と表示。古い status を hang と断定しない |
| COPY / SYNC 等の tmux mode | Rex の状態として表示しない。PREFIX 待機の自動表示はしない |

統計はこの Mac 全体の値。Git は一覧 popup でなく呼出元 pane の cwd。取得失敗や値がない項目は0にしない。GPU 等は既存 helper が値を返さなければ表示対象なし。秘密情報や token を一覧へ出さず、使用量取得の認証処理は既存 command に任せる。

## Project と layout

project の session 名は basename とパスの hash。既存 session は再利用する。project の `.tmux` を Rex に送信・実行しない。session 作成後の GUI 切替には Remote Control が必要。

layout preset は `$XDG_DATA_HOME/rex/layouts/`、未設定なら `~/.local/share/rex/layouts/` に保存する。runtime の preset は Stow 対象外。保存時に既存名は上書きしない。

適用は tiled layer の分割構造が一致する場合だけ、比率を復元する。block ID が変わっていても構造が同じなら適用できる。pane の追加・破棄や command 再起動はしない。floating popup は保存対象外。

## 検証

```bash
python3 scripts/test-rex-tools.py
# この設定を reload 済みの local Rex で keymap を検査し、専用 session を作成・削除する
REX_TEST_INTEGRATION=1 python3 scripts/test-rex-tools.py
rex config check ~/dotfiles/common/rex/.config/rex/init.lua
scripts/check-markdown-links.py
scripts/check-package-duplication.sh
```

integration test は読み込み済みの native prefix keymap（単独 prefix の popup binding がないことを含む）、scratch の block ID / PID が toggle 後も一致すること、layout の比率往復、PREFIX がサイズ変更通知（SIGWINCH）で終了せず Esc で終了することを確認する。ユーザーの session へ入力しない。GUI の表示、キー入力、Remote Control を必要とする client action は実画面でも確認する。
