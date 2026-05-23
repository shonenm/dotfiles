# Pi Local Services

Optional local services for the pi web research layer.

## SearXNG (self-hosted search)

Free, private web search. No API key required.

```bash
# Start
docker compose -f docker-compose.searxng.yml up -d

# Verify
curl -s 'http://localhost:8888/search?q=test&format=json' | head -5

# Stop
docker compose -f docker-compose.searxng.yml down
```

Once running, the `web-router` extension will automatically use SearXNG as the primary search backend, falling back to DuckDuckGo and Jina if unavailable.

## Configuration

- Settings: `services/searxng/settings.yml`
- Rate limiter: `services/searxng/limiter.toml`
- Access: `http://localhost:8888`
