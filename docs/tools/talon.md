# Talon

> **由来:** **Upstream** Talon 本体 (`cask "talon"`) / **Configuration** `mac/talon/` / **Custom** `mac/talon/.talon/user/aqua_pop.py`、`scripts/talon`、`rex.py` / `rex.talon` / `settings.talon`、`common/rex/.config/rex/voice.lua`

macOS のみ。キーボードを使わずに Aqua Voice の音声入力を開始・送信するため、Talon のノイズ認識（ポップ音）を使う。Rex が前面のときは、英語の音声コマンドで pane と tab を操作する。

## 動作

`aqua_pop.py` はポップ音で次のキーを交互に送る。

| 状態 | 操作 | 送るキー | Aqua Voice の動作 |
|---|---|---|---|
| 録音していない | 0.5 秒以内の間隔で 2 回ポップ（回数は変更可） | `F12` | hands-free で入力開始 |
| 録音中 | 1 回ポップ | `F10` | 送信 |

Talon のポップ検出には感度設定がなく、物音でも反応するため、開始だけ連続したポップを要求する。回数は `talon pops N` で変え（既定 2、Talon の再起動や `aqua_pop.py` の reload で 2 に戻る）、ポップの間隔は `aqua_pop.py` の `POP_WINDOW` で変える。
Aqua Voice の録音状態は外部から取得できないため、状態は Talon 側で交互に切り替えるだけである。Esc や「送信して」で入力を終えると順序がずれるので、空打ちのポップを 1 回入れて戻す。

## セットアップ

1. `install.sh` で Talon を導入し、`mac/talon` を stow する。
2. Talon を起動し、マイクとアクセシビリティを許可する。
3. Aqua Voice の Settings > Keybindings で Activate Hands-Free を `F12`、Send を `F10` に登録し、Settings > Send Command を Auto にする。Auto はアプリ・ドメイン・入力欄ごとに送信キーを選ぶ（Gmail や GitHub は `⌘+Enter`、ターミナルは `Enter`、メモや Word は送信しない）。Aqua Voice はキー設定をアカウント側に保存し、起動時に `settings.json` を上書きするため、ファイルではなく設定画面から登録する。
4. Rex の音声コマンドを使う場合は、Talon のメニューバー > Speech Recognition で Conformer を選んで導入する。ポップ音の検出だけなら不要。

## Rex の音声コマンド

`rex.talon` は、Rex が前面にあり、Aqua Voice が録音中でなく、`talon` でその段階まで有効にしたときだけ反応する。Rex 以外が前面のときは何を言っても動かない。Talon のコマンド認識（Conformer）は英語のみのため、コマンドは英単語にしている。

| 発話 | 動作 |
|---|---|
| `zoom` | focus 中の pane を zoom / 解除（`pane.zoom`） |
| tab 名 | その tab を開き、layout 順で最初に OSC 7501 の program status を報告した pane（agent）へ focus する。agent がなければ tab を開くだけ |
| 同じ tab 名をもう一度 | その tab の中で、focus 中の agent の次の agent へ移る（最後まで行くと最初に戻る） |

tab 名は local と `rex hosts` の全 host から集め、Talon の起動時と Rex に戻ったときに更新する。記号は空白、数字は英単語として読み（`slot-1` は `slot one`）、複数の session にある tab 名は `personal dotfiles` のように session 名を付けて呼ぶ。

Conformer は発話を必ず文法のどれかに当てはめるため、コマンドや tab 名を個別の文法にすると、関係ない発話や聞き取れなかった名前が近い名前に寄せられる。そこで `rex.talon` は発話を `<phrase>` で全部受け、`rex.py` が `zoom` か tab 名と文字列の類似度（`difflib`、0.7 以上）で一致したときだけ動かす。判定結果は Talon のログに `rex phrase:` で出る。英語として読めない名前（`aether` を「エーテル」と読むなど）は大きく崩れて聞き取られ、拾えないことが多い。Talon 標準の字幕は全部の発話を大きく表示するため `settings.talon` で止め、`rex.py` が実行したコマンドだけを画面中央に小さく出す。`settings.talon` は言い終わりを待つ時間（`speech.timeout`）も既定の 0.3 秒から 0.2 秒にしている。

tab の取得は `voice.lua` の `dotfiles_voice_tabs` を `rex do` で script として実行する。local の tab へは `rex do dotfiles_voice_go` で直接移る。remote の tab へは、`rex do` から呼ぶ init.lua の action が host への接続を持たないため、`dotfiles_voice_target` で行き先を Rex server に預けてから `cmd+ctrl+alt+shift+v` を送り、Rex app の key 入力として `dotfiles_voice_go` を起動する。app から起動した action は app が張っている host への接続を使うので、remote host の tab でも 0.5 秒ほどで移る（`rex do` が毎回 ssh で繋ぐと 1.3 秒ほどかかる）。

録音状態は `aqua_pop.py` が `user.aqua_recording` tag で持つ。ポップ音の順序がずれると tag も逆になり、録音していないのに Rex のコマンドが効かなくなるので、空打ちのポップで戻す。録音を始めるときは、Aqua Voice の入力が copy mode の key として解釈されないよう、Rex が前面なら copy mode を抜けてから `F12` を送る。

## 音声操作の段階

`talon` で音声操作を段階的に切り替える。周りに人がいるときは `pop`、いないときは `tabs` のように使い分ける。

| 段階 | 有効になるもの |
|---|---|
| `off` | なし。音声認識を止め、ポップ音でも Aqua Voice の録音を始めない（録音中だった場合の送信はする） |
| `pop` | ポップ音での Aqua Voice の開始・送信 |
| `rex` | `pop` + Rex の `zoom` |
| `tabs` | `rex` + tab 名での移動 |

```bash
talon            # 現在の段階を表示
talon pop
talon tabs
talon off
talon pops      # 録音開始に要るポップ音の回数を表示
talon pops 3
```

段階は Talon の再起動や `rex.py` の reload で `pop` に戻る。Talon の REPL（`~/.talon/bin/repl`）経由で `user.talon_voice_level` を呼ぶため、Talon が起動している必要がある。Raycast から使う場合は、Settings > Extensions > Script Commands > Add Directories で `~/dotfiles/scripts` を追加すると、段階を選べる「Talon Voice Level」が出る（Raycast の見出しを持つファイルだけが登録される）。
