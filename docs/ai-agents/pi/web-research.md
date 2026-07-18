# pi Web Research Layer

`web-tools.ts` が、検索・取得・cache・citationを1つのextensionとして提供する。

## プロトコル

```text
web_search
  → web_cache_lookup
  → web_fetch
  → web_cache_write
  → web_citation_add
  → web_citation_list
```

検索結果のsnippetだけで回答せず、参照したsourceを取得してcitationへ記録する。

## Toolとbackend

| Tool | Backend / 保存先 |
|---|---|
| `web_search` | SearXNG `http://localhost:8899` → Jina Search |
| `web_fetch` | Jina Reader → raw HTTP fetch |
| `web_cache_lookup` / `web_cache_write` | `~/.pi/research/sources/` |
| `web_citation_add` / `web_citation_list` | `~/.pi/research/citations.jsonl` |

利用統計は `~/.pi/research/stats.json`、auditは `~/.pi/research/audit.log.jsonl` に保存する。

## セキュリティ

- queryと書き込み内容から既知のsecret形式を検出して拒否
- fetch先のschemeをHTTP(S)に限定
- DNS解決後のloopback、private、link-local addressを拒否
- shellを介さずcurlへargument arrayを渡す

redirect後の最終接続先はcurl側の挙動に依存するため、private情報を含むURLを渡さない。

## SearXNG

```bash
cd ~/dotfiles/common/pi/services
docker compose -f docker-compose.searxng.yml up -d
curl -fsS 'http://localhost:8899/search?q=test&format=json' >/dev/null
```

停止:

```bash
docker compose -f docker-compose.searxng.yml down
```

SearXNGが停止している場合はJinaへfallbackする。Jina API keyは任意で、設定する場合は `JINA_API_KEY` を使う。

## Skills

共有skillの `deep-research`、`docs-research`、`github-research` がこのtoolchainを利用する。正本は `common/agent/.config/agent/skills/`。
