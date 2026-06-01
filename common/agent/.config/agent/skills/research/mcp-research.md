---
name: mcp-research
description: MCPサーバーを選択し、必要なtoolだけを使って調査します。
user-invocable: true
---

# MCP Research

MCP (Model Context Protocol) tools は、ローカル検索やWeb検索よりも優れたコンテキストを提供する場合にのみ使用します。

## Rules

- **Prefer read-only tools.** Write操作は原則ask。
- **Use the smallest relevant MCP server.** 目的に合った最小限のサーバーを選ぶ。
- **Do not enable broad servers** unless necessary.
- **Do not send secrets or private source content** to remote MCP servers.
- **Prefer local MCP servers** for business-sensitive data.
- **Summarize** what MCP tools were used and why.

## Available MCP Servers

| Server | Purpose | Permission | Default |
|--------|---------|------------|---------|
| `context7` | Library documentation lookup | allow | enabled |
| `playwright` | Browser automation, web fetch fallback | ask | disabled |
| `filesystem-readonly` | Read-only project file access | ask | disabled |

## Usage

### Context7 (docs research)

Use `mcp_context7_*` tools to look up library/package documentation when the local codebase doesn't have reference docs.

```
/skill:mcp-research context7 で React の useCallback の使い方を調べて
```

### Playwright (browser)

Use `mcp_playwright_*` tools for UI testing, JavaScript-rendered page capture, or when Jina Reader fails.

```
/skill:mcp-research playwright で https://example.com を開いてスクリーンショットを取って
```

### Filesystem (read-only)

Use `mcp_filesystem*` tools for bulk file listing or search that bash tools can't handle efficiently.

## Permission Policy

| Level | Scope |
|-------|-------|
| ALLOW | docs search, public web search, read-only local inspection |
| ASK | browser automation, file operations, external API calls |
| DENY | write operations, secret access, shell execution from MCP |

## Notes

- MCP tools consume context tokens. Use them sparingly.
- Results may be truncated to ~8000 characters.
- All MCP calls are audit-logged to `~/.pi/research/mcp-audit.jsonl`.
