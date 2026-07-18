# pi Local Services

pi Web Research Layerで任意利用するローカルservice。

## SearXNG

```bash
# 起動
docker compose -f docker-compose.searxng.yml up -d

# 確認
curl -fsS 'http://localhost:8899/search?q=test&format=json' | head -5

# 停止
docker compose -f docker-compose.searxng.yml down
```

- 公開先: `127.0.0.1:8899`
- SearXNG設定: `searxng/settings.yml`
- rate limiter: `searxng/limiter.toml`
- pi側実装: `../.pi/agent/extensions/web-tools.ts`

SearXNGが利用できない場合、`web-tools.ts` はJina Searchへfallbackする。詳細は [`docs/ai-agents/pi/web-research.md`](../../../docs/ai-agents/pi/web-research.md)。
