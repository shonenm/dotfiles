# Claude Code アカウント切替

> **由来:** **Upstream** Claude Code の `CLAUDE_CONFIG_DIR` / **Custom** `claude-as` ラッパー（[区分](../../provenance.md#区分)）

複数の Claude アカウントを、毎回 `/login` し直さずに使い分けるための仕組み。

## 使い方

```bash
claude            # 既定アカウント (~/.claude)
claude-as work    # work アカウント。初回のみ起動後に /login でブラウザ認証する
claude-as work -c # 引数はそのまま claude に渡る
```

2 回目以降は `claude-as <name>` だけで、そのアカウントで起動する。

## 仕組み

`.zshrc.common` の `claude-as()` が `CLAUDE_CONFIG_DIR` を `${XDG_STATE_HOME:-~/.local/state}/claude-accounts/<name>` にして `claude()` ラッパーを呼ぶ。

| 項目 | 扱い |
|------|------|
| 認証情報 | 分離。macOS は Keychain の `Claude Code-credentials-<設定ディレクトリの hash>`、Linux は `<dir>/.credentials.json` |
| `.claude.json` | 分離。初回に `~/.claude.json` から `oauthAccount` を除いてコピーする (MCP・trust 設定を引き継ぐ) |
| その他の `~/.claude` 配下 | `~/.claude` への symlink で共有。設定・skills・hooks・プラグイン・会話履歴が共通になる |

symlink は起動ごとに作るため、`~/.claude` に後から増えた項目も追従する。

## 使用量表示

`ai-usage claude` は既定アカウントに続けて `claude-accounts/` 配下の全アカウントを名前順に出す。label は `utokyo current` / `utokyo weekly` のように名前を前置する。tmux sidebar・tuios の `tui usage`・rex の Metadata ポップアップはこの出力をそのまま表示する。

## 制約

- `.claude.json` は初回コピー後は独立する。既定アカウントで追加した MCP サーバーは自動では反映されない
- 起動時にアカウントが決まり、セッション途中では切り替わらない
- リミット到達時の自動切替は行わない
- 未ログインのアカウントは使用量が `--` になる。不要なら `claude-accounts/<name>` を削除する
- `ai-usage` は token を refresh しないため、しばらく起動していないアカウントは access token の期限切れで `--` になる。`claude-as <name>` で一度起動すると戻る
