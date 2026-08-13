# インストールガイド

> **由来:** **Upstream** GNU Stow・package managers / **Configuration** package宣言・Stow配置 / **Custom** install.sh・install補助処理（[区分](../provenance.md#区分)）

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

## 運用コマンド

```bash
dots apply             # 現在の宣言とlockfileを反映
dots update            # fast-forward後、mise.lockを更新して必要ならcommitし、依存を反映
dots check             # CIと同じ検証
dots doctor            # toolとStow linkを診断
dots lock              # maintainer向け: mise lockfileを更新
```

`mise run apply|update|check|doctor|lock`も同じ`dots`入口を呼ぶ。初回完了後は`exec zsh`でshellを再起動する。

## Version固定と更新

- mise tool: `common/mise/.config/mise/mise.lock`にmacOS / Linux、x86_64 / arm64のversion・download URL・checksumを固定
- npm CLI: `config/packages.npm.txt`にversionを固定
- GitHub Actions: commit SHAを固定
- 更新: `dots update`はfast-forward後にmise.lockを更新し、変わった場合はmise.lockだけをcommitする（pushしない）。`dots lock`はlock更新のみ。週次workflowもlockfileを更新する。原則3日以上経過したreleaseだけを対象とし、自作toolはtool単位で待機期間を無効化する
- 適用: `dots apply`はコミット済みlockfileを各環境へ反映する。`dots update`はlock更新後に同じapplyを行う

## CI

GitHub Actionsとローカルの`dots check`は、`scripts/check`を正本としてShellCheck、installer/config test、package parity、Markdown/provenance、Stow dry-runを実行する。

## 関連文書

- [No-Sudo Install Mode](install-no-sudo.md)
- [新環境セットアップ](setup-new-environment.md)
- [1Password連携](../configuration/1password-integration.md)
- [Claude Code API fallback](../ai-agents/claude/claude-fallback.md)
