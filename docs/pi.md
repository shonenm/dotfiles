# pi-coding-agent (OpenCode Go + Codex)

[pi](https://pi.dev/) はミニマルな terminal coding harness。MCP / sub-agents / permission popup / plan mode を持たず、CLI extensions と skills で組み立てる思想。dotfiles では OpenCode Go と Codex のサブスクリプションで動かす前提で構築している。

参考: [OpenCode Go + pi-coding-agent のすゝめ](https://zenn.dev/kimuson/articles/pi-coding-agent-with-opencode-go)

## 構成

| 要素 | 役割 | 配置 |
| --- | --- | --- |
| pi CLI | エージェント本体 | `config/packages.npm.txt` の `@earendil-works/pi-coding-agent` (npm global) |
| AGENTS.md | グローバル指示書 | `common/pi/.pi/agent/AGENTS.md` → `~/.pi/agent/AGENTS.md` |
| pueue | バックグラウンドタスク・並列 delegation 用キュー | `config/Brewfile` (mac), `packages.linux.{apt,alpine}.txt` (linux) |

## セットアップ

### 1. install.sh で pi 本体を入れる

```bash
cd ~/dotfiles
./install.sh
```

`install_npm_packages` が `@earendil-works/pi-coding-agent` を含めて global install する。`stow` で `common/pi/` がリンクされ `~/.pi/agent/AGENTS.md` が配置される。

確認:

```bash
pi --version
ls -la ~/.pi/agent/AGENTS.md  # dotfiles へのシンボリックリンクであること
```

### 2. サブスクリプション認証

`pi` を起動し `/login` で認証する。

```bash
pi
> /login
# OpenCode Go を選択 → ブラウザで OAuth
> /login
# ChatGPT (Codex) を選択 → ブラウザで OAuth
```

認証情報は `~/.pi/credentials.json` に保存される (gitignore 済み、stow 対象外)。

サブスクリプションのおすすめ組合せ:

- **OpenCode Go ($10/月)** をメイン
  - `deepseek-v4-pro`, `kimi-k2.6`, `glm-5.1` 等の Open Model にアクセス
- **Codex ($20 or $100/月)** をフォールバックの Frontier モデル枠
  - `gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex-spark` 等
- Claude Pro/Max は pi 経由だと利用規約上 extra usage 課金になるため非推奨

### 3. pueue デーモンを起動

並列 delegation や長時間プロセスを pi 経由で扱う場合 pueue デーモンが必要。

```bash
pueued -d        # daemonize
pueue status
```

systemd / launchd 自動起動を組む場合は別途設定 (TODO)。

## 使い方

### 対話モード

```bash
pi
```

`AGENTS.md` の指示に従い、必要に応じてサブエージェント (別 pi インスタンス) を spawn する設計。

### 非対話モード (`-p`)

```bash
pi --model 'opencode-go/deepseek-v4-pro:high' \
   --fallback-models 'openai-codex/gpt-5.4:low' \
   -p '<instructions>'
```

### 並列 delegation (pueue)

```bash
pueue add -i --print-task-id -- "pi --model 'opencode-go/deepseek-v4-pro:high' -p '<instruction>' < /dev/null"
pueue wait <task-id>
pueue log <task-id>
```

## Web Research Layer

pi 本体に WebFetch / WebSearch ツールは存在しないが、dotfiles の拡張により **search → fetch → cache → cite → answer** のプロトコルで調査を行う。

### Architecture

```
web_search (discovery)
  ↓
web_fetch (source retrieval)
  ↓
web_cache_write (persist)
  ↓
web_citation_add (track)
  ↓
web_citation_list (summarize)
```

### Extensions

| Extension | 役割 | バックエンド |
|-----------|------|-------------|
| `web-router.ts` | 検索ルーティング | SearXNG → DuckDuckGo → Jina |
| `web-fetch.ts` | URL コンテンツ取得 | Jina Reader → Playwright → Raw |
| `web-cache.ts` | ローカルキャッシュ | `~/.pi/research/sources/<hash>.md` |
| `citation-store.ts` | 引用元管理 | `~/.pi/research/citations.jsonl` |
| `secret-guard.ts` | セキュリティガード | 3段階: allow / ask / deny |
| `audit-log.ts` | 使用ログ | `~/.pi/research/audit.log.jsonl` |
| `statusline.ts` | フッター表示 | リサーチstats (q:f:c) |

### Skills

| Skill | 用途 |
|-------|------|
| `deep-research` | マルチソース調査、クロスリファレンス |
| `docs-research` | ドキュメント調査（バージョン対応） |
| `github-research` | clone-first ソースコード調査 |

### セキュリティ

3-tier web permission:

- **allow**: 公開パッケージ名、公開エラーメッセージ、公開ドキュメントクエリ
- **ask**: スタックトレース、ファイルパス、リポジトリ固有の質問
- **deny**: シークレット、認証情報、プライベートソース全文、顧客データ

### キャッシュ

| ソース種別 | TTL |
|-----------|-----|
| 公式ドキュメント | 7日 |
| GitHub | 30日 |
| ブログ | 7日 |
| ニュース | 毎回refresh |

### SearXNG (ローカル検索)

API key不要、レート制限なしのself-hosted検索エンジン。

```bash
cd common/pi/services
docker compose -f docker-compose.searxng.yml up -d
```

起動後、`web-router` が自動的にSearXNGを第1優先の検索バックエンドとして使用する。

### ステータスライン表示

```text
↑12.3k ↓4.5k $0.023 45k/128k (35%)  web q:3 f:5 c:8  main  kimi-k2.6
```

- `web q:3 f:5 c:8` = 検索3回、取得5回、キャッシュヒット8回
- コンテキスト使用率は 60%未満=緑、60-80%=黄、80%超=赤

## カスタマイズ

### モデル選択を変更する

`common/pi/.pi/agent/AGENTS.md` の "Model selection" セクションを編集。プロバイダ / モデル名 / effort を変えれば次回起動から反映される (シンボリックリンクなので即時反映)。

### 拡張機能

pi packages 経由で extensions / skills を追加:

```bash
pi install npm:@foo/pi-tools
pi list
```

dotfiles 管理にしたい場合は `common/pi/.pi/agent/AGENTS.md` に `/skill:<name>` の利用方針を追記し、パッケージ自体は `pi install` でローカル管理する (`~/.pi/packages/` は stow 対象外)。

## 関連

- `config/packages.npm.txt` - pi 本体の npm パッケージ
- `common/pi/.pi/agent/AGENTS.md` - グローバル指示書
- `common/pi/.stow-local-ignore` - ランタイムファイル除外
