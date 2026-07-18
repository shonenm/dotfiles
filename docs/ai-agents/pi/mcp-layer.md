# pi MCP Layer

piは `mcp-gateway.ts` を介してstdio MCP serverをpi toolとして登録する。MCP toolの実行可否は `pi-permission-system` が一元的に判断する。

## フロー

```text
LLM
  → mcp_<server>_<tool>
  → pi-permission-system
  → mcp-gateway.ts（result上限・secret redaction・audit）
  → MCP server（stdio JSON-RPC）
```

## 設定

後勝ちでmergeする。

1. `~/.config/agent/mcp.json` — pi / Command Code用global設定
2. `<project>/.mcp.json` — project設定
3. `<project>/.pi/mcp.json` — pi override

Claude Codeは `common/claude/.config/claude/mcp.json` を別の正本とし、`install.sh` が `claude mcp add-json --scope user` で登録する。

```json
{
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "server-command",
      "args": [],
      "description": "purpose",
      "enabled": true,
      "maxResultSize": 8000
    }
  }
}
```

pi gatewayのtransportはstdioのみ。remote MCPの実需要がないため、Streamable HTTPは実装しない。

## Permission

MCP gateway自身は確認dialogを持たない。tool名 `mcp_*` に対する `allow` / `ask` / `deny` は `~/.pi/agent/pi-permissions.jsonc` とpiのsession modeで決まる。YOLO modeの永続設定は `~/.pi/agent/permission-system.json`。

## Auditと制限

- audit: `~/.pi/research/mcp-audit.jsonl`
- stats: `~/.pi/research/mcp-stats.json`
- result上限: server設定の `maxResultSize`、既定8000文字
- auditへ書く引数は既知のsecret形式をredact

## Skill

MCP serverの選択には共有skill `mcp-research` を使う。正本は `common/agent/.config/agent/skills/mcp-research/SKILL.md`。

関連: [共有設定レイヤー](agent-layer.md)
