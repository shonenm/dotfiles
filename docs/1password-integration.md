# 1Password 連携

dotfilesのセットアップと日常利用で1Passwordをシークレット管理に活用。

## 概要

- **インストール必須**: dotfilesのセットアップに1Password CLIが必要
- **SSH Agent**: 1Password DesktopアプリのSSH Agentを利用
- **シークレット取得**: `op read` でWebhook URL、APIトークン等を取得
- **Git設定**: ユーザー名/メールアドレスを1Passwordから取得

## 利用しているシークレット

| 用途 | 1Password参照 |
|------|---------------|
| Claude Webhook | `op://Personal/Claude Webhook/password` |
| Codex Webhook | `op://Personal/Codex Webhook/password` |
| Gemini Webhook | `op://Personal/Gemini Webhook/password` |
| GitHub Token | `op://Personal/GitHub/token` |
| Git Username | `op://Personal/Git Config/username` |
| Git Email | `op://Personal/Git Config/email` |

## セットアップ

### 1. 1Password CLIのインストール

インストールスクリプトが自動でインストール:

```bash
# Mac
brew install 1password-cli

# Linux (apt)
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list
sudo apt update && sudo apt install -y 1password-cli
```

### 2. サインイン

```bash
eval $(op signin)
```

### 3. dotfilesインストール

```bash
./install.sh
```

インストール時に以下が実行される:
1. 1Password CLIの存在確認（なければインストール）
2. サインイン状態の確認
3. Webhookキャッシュの作成
4. セットアップ通知の送信

## SSH Agent連携

1Password DesktopアプリのSSH Agentを利用してSSH鍵を管理。

### 設定

**Mac** (`~/.ssh/config`):
```
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

**Linux** (`~/.ssh/config`):
```
Host *
  IdentityAgent "~/.1password/agent.sock"
```

### 1Password側の設定

1. 1Password Desktop アプリを開く
2. Settings > Developer > SSH Agent を有効化
3. SSH鍵を1Passwordに保存

### 使い方

```bash
# 通常通りSSHを使用（1Passwordが認証を代行）
ssh user@host
git push origin main
```

Touch ID / 生体認証で承認。

## GitHub CLI連携

シェル起動時に自動でGitHub CLIトークンを設定:

```bash
# .zshrc.common で自動実行
export GH_TOKEN="$(op read 'op://Personal/GitHub/token' 2>/dev/null)"
```

### 使い方

```bash
# 認証不要で使用可能
gh repo list
gh pr create
```

## Git設定

1Passwordからユーザー名/メールアドレスを取得してGit設定:

```bash
# 手動実行
setup_git_from_op
```

実行結果:
```
Git config updated: Your Name <your@email.com>
```

## Webhook連携

AI CLI（Claude/Codex/Gemini）のSlack通知用Webhook URLを1Passwordで管理。

### キャッシュの仕組み

```
1Password
    ↓ op read (初回のみ)
~/.local/share/ai-notify/<tool>_webhook (キャッシュ)
    ↓ 読み込み
ai-notify.sh → Slack通知
```

- 初回: 1Passwordから取得してキャッシュ
- 2回目以降: キャッシュから読み込み（高速）
- キャッシュ更新: `ai-notify.sh --refresh-cache`

### コマンド

```bash
# セットアップ（キャッシュ作成 + 通知送信）
ai-notify.sh --setup claude

# キャッシュ更新（通知なし）
ai-notify.sh --refresh-cache

# キャッシュ削除
ai-notify.sh --clear-cache
```

## ヘルパースクリプト

### op-helper.sh

シンプルなシークレット取得ヘルパー:

```bash
# 使い方
./scripts/op-helper.sh "op://Vault/Item/field"

# スクリプト内で使用
source scripts/op-helper.sh
secret=$(op_get "op://Personal/API Key/password")
```

### シェル関数

`.zshrc.common` で定義:

```bash
# 単純な取得
op_secret "op://Vault/Item/field"

# 環境変数にエクスポート
export_op_secret "MY_API_KEY" "op://Personal/API Key/password"
```

## 1Passwordアイテムの構成例

### Claude Webhook
```
Vault: Personal
Item: Claude Webhook
Field: password = https://hooks.slack.com/services/xxx/yyy/zzz
```

### Git Config
```
Vault: Personal
Item: Git Config
Fields:
  - username = Your Name
  - email = your@email.com
```

### GitHub
```
Vault: Personal
Item: GitHub
Field: token = ghp_xxxxxxxxxxxx
```

## トラブルシューティング

### op: command not found

```bash
# Mac
brew install 1password-cli

# Linux
# 上記のaptコマンドを実行
```

### You are not currently signed in

```bash
eval $(op signin)
```

### error: cannot read secret

1Passwordアプリで該当アイテムが存在するか確認:
```bash
op item list --vault Personal
```

### SSH Agent接続エラー

1. 1Password Desktopアプリが起動しているか確認
2. Settings > Developer > SSH Agent が有効か確認
3. ソケットファイルの存在確認:
   ```bash
   # Mac
   ls -la ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

   # Linux
   ls -la ~/.1password/agent.sock
   ```

### キャッシュが古い

```bash
ai-notify.sh --clear-cache
ai-notify.sh --refresh-cache
```

## セキュリティ

- シークレットはGitにコミットされない
- Webhookはローカルにキャッシュ（`~/.local/share/ai-notify/`、権限600）
- SSH鍵は1Password内に保存（ローカルに秘密鍵なし）
- Touch ID / 生体認証で保護
