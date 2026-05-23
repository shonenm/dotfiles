# pi MCP Layer

MCP (Model Context Protocol) は AI エージェントと外部システムを標準インターフェースで接続するプロトコルです。
pi は MCP を本体に直結せず、**Gateway/Adapter 層**を介して安全に必要なものだけ露出します。

## Architecture

```
Pi / OpenCode
  ↓
MCP Gateway (mcp-gateway.ts)
  ├─ permission gate (allow/ask/deny)
  ├─ audit log
  ├─ secret guard
  ├─ tool allowlist
  └─ context trimming
  ↓
Approved MCP Servers (stdio or HTTP)
  ├─ context7 (docs)
  ├─ playwright (browser)
  ├─ filesystem-readonly
  └─ (extensible per project)
```

## Config

### Sources (merged, later overrides earlier)

| Priority | Path | Scope |
|----------|------|-------|
| 1 (lowest) | `~/.config/mcp/mcp.json` | Global, all projects |
| 2 | `.mcp.json` | Project root |
| 3 (highest) | `.pi/mcp.json` | Pi-specific overrides |

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

## Permission Policy

| Level | Scope | Example |
|-------|-------|---------|
| **ALLOW** | 安全なread-only操作 | docs検索、公開Web検索、ローカル検査、git status/diff/log |
| **ASK** | 要確認操作 | GitHub issue/PR操作、ブラウザ自動化、ファイル書き込み、DBクエリ |
| **DENY** | 禁止操作 | production DB write、シークレット読み取り、.envアクセス、MCP経由シェル実行 |

## Extensions

| Extension | 役割 |
|-----------|------|
| `mcp-gateway.ts` | MCPサーバー管理、JSON-RPC通信、ツール登録、permission/audit統合 |

## Skills

| Skill | 用途 |
|-------|------|
| `mcp-research` | MCPツールの選択・使用ガイドライン |

## Audit

すべてのMCP呼び出しはログに記録されます。

- ログ: `~/.pi/research/mcp-audit.jsonl`
- 統計: `~/.pi/research/mcp-stats.json`

```jsonl
{"timestamp":"2026-05-23T...","server":"context7","tool":"search","args":"...","status":"success","elapsedMs":234}
```

## Default Enabled Servers

| Server | Purpose | Permission |
|--------|---------|------------|
| `context7` | Library documentation lookup | allow |

`playwright`, `filesystem-readonly` はデフォルト無効（プロジェクトごとに opt-in）。

## Security Notes

- MCP server は `npx -y` で起動するため、supply-chain リスクに注意
- バージョンは `@latest` ではなく固定を推奨
- remote MCP サーバーは極力避け、ローカル/社内サーバーを優先
- すべてのMCP呼び出しは permission gate + audit log を通過
- 結果はデフォルト8000文字でtruncate（context膨張防止）
