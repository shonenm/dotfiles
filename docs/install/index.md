# インストールガイド

`install.sh` がmacOS / Linux / no-sudo Linux共通の入口である。

## モード

```bash
./install.sh            # 対話モード
./install.sh -y         # パッケージ導入の確認を省略
./install.sh --no-sudo  # sudoなしLinux向け
./install.sh --skip-1p  # secretを使わないcontainer向け
```

## 初回セットアップ

### 1. リポジトリを取得

```bash
git clone https://github.com/shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

macOSでは先にCommand Line Toolsを導入する。

```bash
xcode-select --install
```

Linuxでは最低限Gitとcurlを用意する。no-sudoモードの追加要件は[専用ガイド](install-no-sudo.md#前提条件-ホスト側に必要なもの)を参照。

### 2. install.shを実行

```bash
./install.sh
# sudoを使えないLinuxのみ:
./install.sh --no-sudo
```

macOSではHomebrewを先に導入し、その後1Password CLIとパッケージを導入する。1Passwordへ未サインインの場合は既存のsecret cacheを保持し、credentialが必要な登録・更新だけをスキップしてStowと通常のセットアップを継続する。

### 3. 1Passwordへサインインして再実行

初回実行の完了メッセージでサインインを求められた場合だけ実施する。

```bash
op signin
./install.sh             # 初回と同じオプションで再実行
```

no-sudo環境では `~/.local/bin/op signin` を実行し、再実行にも `--no-sudo` を付ける。2回目の実行でMCP token、通知Webhookなどのsecret依存設定が反映される。

## install.shの責務

1. macOSのHomebrewを準備
2. 1Password CLIを確認・導入
3. OS別パッケージを導入
4. 移動・削除済みskillの壊れたlinkを除去し、`common/` とOS別packageを `stow --restow --no-folding` でlink
5. tmux theme、TPM、プラグインを設定
6. Pi packageを導入
7. Claude Code / Codex / Gemini / Cursor / Command Code設定を生成
8. 取得可能なsecretを反映

## パッケージ定義の正本

| 対象 | 正本 |
|---|---|
| macOS Homebrew | `config/Brewfile` |
| Linux apt / apk | `config/packages.linux.{apt,alpine}.txt` |
| no-sudo Linux | `config/pixi-packages.txt` |
| Linux prebuilt CLI | `config/mise-linux.toml` |
| Linux installer / cargo / apt repository | `config/tools.linux.bash` |
| 言語runtime・共通mise tool | `common/mise/.config/mise/config.toml` |
| npm CLI | `config/packages.npm.txt` |

新しいツールの追加方法は[新環境セットアップ](setup-new-environment.md#新ツール追加時の登録先)を参照。

## 完了後

```bash
exec zsh
mise install
mise run doctor
```

## CI

GitHub Actionsで以下を検証する。

- ShellCheck
- apt / pixi対応表
- tracked Markdownのローカルリンク
- `common/` のStow dry-run

## 関連文書

- [No-Sudo Install Mode](install-no-sudo.md)
- [新環境セットアップ](setup-new-environment.md)
- [1Password連携](../configuration/1password-integration.md)
- [Claude Code API fallback](../ai-agents/claude/claude-fallback.md)
