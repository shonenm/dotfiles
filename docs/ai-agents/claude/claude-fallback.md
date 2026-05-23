# Claude Code API Fallback

Anthropic API障害時にOpenRouter経由でClaude Codeを使うための切替機構。

## 背景

Maxサブスクリプション(OAuth認証)利用時、Anthropic API障害でClaude Codeが使えなくなる。LiteLLMプロキシ方式はOAuthトークン転送未対応のため機能しない。

## アーキテクチャ

```
通常時:
  claude (wrapper) -> フラグなし -> command claude -> Anthropic API (Subscription/OAuth)

障害時 (claude-fallback on 実行後):
  claude (wrapper) -> フラグあり -> ANTHROPIC_BASE_URL + ANTHROPIC_API_KEY を設定
    -> command claude -> OpenRouter API (従量課金)
```

`.zshrc.common` の `claude()` ラッパー関数がフラグファイルの有無で動的に環境変数を切り替える。

## セットアップ

```bash
# install.sh で自動実行される。手動の場合:
claude-fallback.sh setup
```

## 使い方

### 障害発生時

```bash
# 1. フォールバックモードに切替
claude-fallback.sh on

# 2. 前のセッションを再開
claude -c
```

### 復旧後

```bash
claude-fallback.sh off
# 次回の claude 起動からサブスクリプション認証に復帰
```

### 状態確認

```bash
claude-fallback.sh status
```

## コマンド

| コマンド | 説明 |
|---------|------|
| `setup` | 1PasswordからOpenRouter APIキーを取得してキャッシュ |
| `on` | フォールバックモード有効化 + Slack通知 |
| `off` | フォールバックモード無効化 + Slack通知 |
| `status` | 現在のモード表示 + Anthropic APIヘルスチェック |

## ファイル構成

```
scripts/claude-fallback.sh              # 管理スクリプト
common/zsh/.zshrc.common                # claude() ラッパー関数
```

### 状態ファイル

`~/.local/share/claude-fallback/` に以下が格納される:

- `active` - フラグファイル(存在=フォールバックモード)
- `env` - OpenRouter APIキーキャッシュ(chmod 600)

## コンテキスト引き継ぎ

Claude Codeは会話履歴をローカルに保存しているため、`claude -c` でセッションを再開できる。APIエンドポイントが変わってもモデル名は同じなので問題ない。

## 通知

モード切替時にSlack通知を送信:

- `fallback` - フォールバックモード有効化時
- `recovered` - フォールバックモード無効化時

## 制約

- OpenRouter追加コスト: フォールバック時のみ発生
- 手動切替: 障害検知は自動ではない
