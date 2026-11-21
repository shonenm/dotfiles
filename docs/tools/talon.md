# Talon

> **由来:** **Upstream** Talon 本体 (`cask "talon"`) / **Configuration** `mac/talon/` / **Custom** `mac/talon/.talon/user/aqua_pop.py`

macOS のみ。キーボードを使わずに Aqua Voice の音声入力を開始・送信するため、Talon のノイズ認識（ポップ音）を使う。

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
3. Aqua Voice の Settings > Keybindings で Activate Hands-Free を `F12`、Send を `F10` に登録する。Aqua Voice はキー設定をアカウント側に保存し、起動時に `settings.json` を上書きするため、ファイルではなく設定画面から登録する。
