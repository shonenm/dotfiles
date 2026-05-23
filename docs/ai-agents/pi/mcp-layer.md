# pi MCP Layer

MCP (Model Context Protocol) は AI エージェントと外部システムを標準インターフェースで接続するプロトコルです。
pi は MCP を本体に直結せず、**Gateway/Adapter 層**を介して安全に必要なものだけ露出します。

## Architecture

```
Pi
  ↓
MCP Gateway (mcp-gateway.ts)
  ├─ permission gate (allow/ask/deny)
  ├─ audit log (~/.pi/research/mcp-audit.jsonl)
  └─ context trimming (8KB default)
  ↓
MCP Server (stdio JSON-RPC)
```

## Config

共有 MCP 設定は `~/.config/agent/mcp.json` で一元管理。Claude/pi 両方が参照する。
詳細は [agent-layer.md](agent-layer.md) を参照。

### Format

```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "package-name@version"],
      "description": "What this server does",
      "permission": "allow|ask|deny",
      "enabled": true,
      "maxResultSize": 8000
    }
  }
}
```

### Override order (low→high)
1. `~/.config/agent/mcp.json` — global shared
2. `.mcp.json` — project
3. `.pi/mcp.json` — pi-specific

## Extensions

| Extension | 役割 |
|-----------|------|
| `mcp-gateway.ts` | MCPサーバー管理、JSON-RPC通信、ツール登録、permission/audit統合 |

## Skills

| Skill | 用途 |
|-------|------|
| `mcp-research` | MCPツールの選択・使用ガイドライン (in `~/.config/agent/skills/research/`) |

## Permission Policy

| Level | Scope |
|-------|-------|
| ALLOW | docs search, public web search, read-only local inspection, git status/diff/log |
| ASK | GitHub issue/PR comment, browser automation, local file write, DB query |
| DENY | production DB write, secret read, .env read, shell from MCP |

## Audit

- ログ: `~/.pi/research/mcp-audit.jsonl`
- 統計: `~/.pi/research/mcp-stats.json`
