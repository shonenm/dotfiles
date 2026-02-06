# Database 開発環境

Docker PostgreSQL を使った DB 開発ワークフロー。Neovim + tmux 統合。

## ツール一覧

| ツール | 用途 |
|--------|------|
| `pgcli` | PostgreSQL インタラクティブクライアント（オートコンプリート、シンタックスハイライト） |
| `dblab` | TUI データベースクライアント（スキーマブラウジング、クエリ実行） |
| `postgresql@17` | psql, pg_dump, pg_restore 等のクライアントツール群 |
| `vim-dadbod-ui` | Neovim 上の DB UI（クエリ実行、結果表示） |
| `sql-formatter` | SQL フォーマッター（PostgreSQL 方言対応） |

## インストール

### macOS

```bash
brew bundle --file=config/Brewfile --no-lock
mise use -g npm:sql-formatter
```

### Linux

```bash
./install.sh  # pgcli, dblab, postgresql-client を自動インストール
mise use -g npm:sql-formatter
```

## Docker PostgreSQL テンプレート

```yaml
# docker-compose.yml
services:
  db:
    image: postgres:17-alpine
    container_name: postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro  # 初期化SQL（任意）

volumes:
  postgres_data:
```

起動:

```bash
docker compose up -d
```

## 接続方法

デフォルト接続先: `postgresql://postgres:postgres@localhost:5432/postgres`

### pgcli (CLI)

```bash
# 直接接続
pgcli postgresql://postgres:postgres@localhost:5432/postgres

# 環境変数を使用
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/postgres"
pgcli $DATABASE_URL

# 省略形（zsh-abbr）
pg  # → pgcli に展開
```

### dblab (TUI)

```bash
# 直接接続
dblab --url postgresql://postgres:postgres@localhost:5432/postgres

# 環境変数を使用
dblab --url $DATABASE_URL

# 省略形（zsh-abbr）
dbl  # → dblab に展開
```

### psql (標準クライアント)

```bash
psql postgresql://postgres:postgres@localhost:5432/postgres
```

## Neovim 統合

### vim-dadbod-ui

| キー | 動作 |
|------|------|
| `<leader>db` | DBUI パネルのトグル |
| `<leader>df` | DBUI バッファ検索 |
| `<leader>dl` | 直前のクエリ情報 |
| `<leader>S` | クエリ実行（DBUI デフォルト） |

DBUI 内での操作:
- `o` / `Enter`: 展開・選択
- `R`: リフレッシュ
- `d`: 削除
- `A`: 新規接続追加

### DB 接続設定（プロジェクト固有）

プロジェクトルートに `.lazy.lua` を作成し、接続情報を設定:

```lua
-- .lazy.lua（gitignore 対象）
vim.g.dbs = {
  { name = "local", url = "postgresql://postgres:postgres@localhost:5432/postgres" },
  { name = "dev", url = "postgresql://user:pass@dev.example.com:5432/mydb" },
}
```

**重要**: `.lazy.lua` は `.gitignore` に追加し、接続情報をリポジトリにコミットしない。

```gitignore
# .gitignore
.lazy.lua
```

### pgcli / dblab フローティング起動

| キー | 動作 |
|------|------|
| `<leader>dp` | pgcli をフローティングターミナルで起動 |
| `<leader>de` | dblab をフローティングターミナルで起動 |

環境変数 `DATABASE_URL` があればそちらを使用、なければデフォルト接続先にフォールバック。

### SQL フォーマット

`.sql` ファイル保存時に `sql-formatter` で自動フォーマット（PostgreSQL 方言）。

sql-formatter のインストール:

```bash
mise use -g npm:sql-formatter
```

### SQL 補完

DBUI で DB 接続後、`.sql` ファイル編集時にテーブル名・カラム名・キーワード補完が有効になる（blink.cmp 経由）。

## tmux 統合

| キー | 動作 |
|------|------|
| `prefix + P` | pgcli をポップアップで起動（80% × 80%） |

環境変数 `DATABASE_URL` があればそちらを使用、なければデフォルト接続先にフォールバック。

## ワークフロー例

### 1. DB コンテナ起動

```bash
docker compose up -d
```

### 2. スキーマ確認（dblab）

Neovim: `<leader>de` → dblab でテーブル構造を確認。

### 3. クエリ作成（vim-dadbod-ui）

1. `<leader>db` で DBUI を開く
2. 接続を選択（`.lazy.lua` で設定済み）
3. 新規クエリバッファを作成
4. SQL を記述、`<leader>S` で実行
5. 結果は下部に表示

### 4. インタラクティブ操作（pgcli）

`<leader>dp` で pgcli を起動し、対話的にクエリを実行。オートコンプリートで効率的に操作。

### 5. バックアップ・リストア

```bash
# バックアップ
pg_dump postgresql://postgres:postgres@localhost:5432/postgres > backup.sql

# リストア
psql postgresql://postgres:postgres@localhost:5432/postgres < backup.sql
```

## 環境変数設定

プロジェクトの `.envrc`（direnv）または `.env` で `DATABASE_URL` を設定:

```bash
# .envrc
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/mydb"
```

```bash
direnv allow
```

これにより、tmux ポップアップや Neovim のフローティングターミナルが自動的に正しい DB に接続する。

## トラブルシューティング

### pgcli が見つからない

```bash
brew install pgcli
```

### dblab が見つからない

```bash
brew install dblab
```

### sql-formatter が見つからない

```bash
mise use -g npm:sql-formatter
```

### PostgreSQL クライアントツールが見つからない

```bash
brew install postgresql@17
echo 'export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"' >> ~/.zshrc
```

### DBUI で接続エラー

1. Docker コンテナが起動しているか確認: `docker compose ps`
2. 接続 URL が正しいか確認
3. `:DBUIAddConnection` で手動追加を試す
