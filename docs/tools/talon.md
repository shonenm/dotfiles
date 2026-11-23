# Talon

> **由来:** **Upstream** Talon 本体 (`cask "talon"`) / **Configuration** `mac/talon/` / **Custom** `mac/talon/.talon/user/aqua_pop.py`、`rex.py` / `rex.talon` / `rex_agent.lua`

macOS のみ。キーボードを使わずに Aqua Voice の音声入力を開始・送信するため、Talon のノイズ認識（ポップ音）を使う。Rex が前面のときは、英語の音声コマンドで pane と session を操作する。

## 動作

`aqua_pop.py` はポップ音を検出するたびに次のキーを交互に送る。

| 回数 | 送るキー | Aqua Voice の動作 |
|---|---|---|
| 奇数回 | `F12` | hands-free で入力開始 |
| 偶数回 | `F10` | 送信 |

Aqua Voice の録音状態は外部から取得できないため、状態は Talon 側で交互に切り替えるだけである。Esc や「送信して」で入力を終えると順序がずれるので、空打ちのポップを 1 回入れて戻す。

## セットアップ

1. `install.sh` で Talon を導入し、`mac/talon` を stow する。
2. Talon を起動し、マイクとアクセシビリティを許可する。
3. Aqua Voice の Settings > Keybindings で Activate Hands-Free を `F12`、Send を `F10` に登録し、Settings > Send Command を Auto にする。Auto はアプリ・ドメイン・入力欄ごとに送信キーを選ぶ（Gmail や GitHub は `⌘+Enter`、ターミナルは `Enter`、メモや Word は送信しない）。Aqua Voice はキー設定をアカウント側に保存し、起動時に `settings.json` を上書きするため、ファイルではなく設定画面から登録する。
4. Rex の音声コマンドを使う場合は、Talon のメニューバー > Speech Recognition で Conformer を選んで導入する。ポップ音の検出だけなら不要。

## Rex の音声コマンド

`rex.talon` は Rex が前面にあり、Aqua Voice が録音中でないときだけ有効になる。Talon のコマンド認識（Conformer）は英語のみのため、コマンドは英単語にしている。

| 発話 | 動作 |
|---|---|
| `zoom` | focus 中の pane を zoom / 解除（`pane.zoom`） |
| `up` | copy mode に入り半ページ上へ（`pane.copy_mode.enter` + `half_page_up`） |
| `down` | copy mode で半ページ下へ |
| session 名 | その session を開き、layout 順で最初に OSC 7501 の program status を報告した pane（agent）へ focus する。agent がなければ session を開くだけ |

session 名は local と `rex hosts` の全 server から集め、Talon の起動時と Rex に戻ったときに更新する。記号は空白として読み（`syntopic-infra` は `syntopic infra`）、複数の host にある名前は `chronos personal` のように host 名を付けて呼ぶ。session の取得と移動は `rex_agent.lua` を `rex do` で実行し、各 host へ 1 回の接続で問い合わせる。remote host の session は 1〜2 秒かかる。

録音状態は `aqua_pop.py` が `user.aqua_recording` tag で持つ。ポップ音の順序がずれると tag も逆になり、録音していないのに Rex のコマンドが効かなくなるので、空打ちのポップで戻す。録音を始めるときは、Aqua Voice の入力が copy mode の key として解釈されないよう、Rex が前面なら copy mode を抜けてから `F12` を送る。

`up` / `down` は日常の発話にも含まれるため、Rex が前面のまま会話すると反応することがある。
