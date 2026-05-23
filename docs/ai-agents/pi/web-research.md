# pi Web Research Layer

pi 本体に WebFetch / WebSearch ツールは存在しないが、dotfiles の拡張により **search → fetch → cache → cite → answer** のプロトコルで調査を行う。

## Architecture

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

## Extensions

| Extension | 役割 | バックエンド |
|-----------|------|-------------|
| `web-router.ts` | 検索ルーティング | SearXNG → DuckDuckGo → Jina |
| `web-fetch.ts` | URL コンテンツ取得 | Jina Reader → Playwright → Raw |
| `web-cache.ts` | ローカルキャッシュ | `~/.pi/research/sources/<hash>.md` |
| `citation-store.ts` | 引用元管理 | `~/.pi/research/citations.jsonl` |
| `secret-guard.ts` | セキュリティガード | 3段階: allow / ask / deny |
| `audit-log.ts` | 使用ログ | `~/.pi/research/audit.log.jsonl` |
| `statusline.ts` | フッター表示 | リサーチstats (q:f:c) |

## Skills

| Skill | 用途 |
|-------|------|
| `deep-research` | マルチソース調査、クロスリファレンス |
| `docs-research` | ドキュメント調査（バージョン対応） |
| `github-research` | clone-first ソースコード調査 |

## セキュリティ

3-tier web permission:

- **allow**: 公開パッケージ名、公開エラーメッセージ、公開ドキュメントクエリ
- **ask**: スタックトレース、ファイルパス、リポジトリ固有の質問
- **deny**: シークレット、認証情報、プライベートソース全文、顧客データ

## キャッシュ

| ソース種別 | TTL |
|-----------|-----|
| 公式ドキュメント | 7日 |
| GitHub | 30日 |
| ブログ | 7日 |
| ニュース | 毎回refresh |

## SearXNG (ローカル検索)

API key不要、レート制限なしのself-hosted検索エンジン。

```bash
cd common/pi/services
docker compose -f docker-compose.searxng.yml up -d
```

起動後、`web-router` が自動的にSearXNGを第1優先の検索バックエンドとして使用する。

## ステータスライン表示

```text
↑12.3k ↓4.5k $0.023 45k/128k (35%)  web q:3 f:5 c:8  main  kimi-k2.6
```

- `web q:3 f:5 c:8` = 検索3回、取得5回、キャッシュヒット8回
- コンテキスト使用率は 60%未満=緑、60-80%=黄、80%超=赤
