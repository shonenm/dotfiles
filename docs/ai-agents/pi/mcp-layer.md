# pi MCP Layer

> **由来:** **Upstream** MCP・各MCP server / **Configuration** 共有MCP定義・権限設定 / **Custom** mcp-gateway拡張（[区分](../../provenance.md#区分)）

piは `mcp-gateway.ts` を介してstdio MCP serverをpi toolとして登録する。MCP toolの実行可否は `pi-permission-system` が一元的に判断する。

## フロー

```text
LLM
  → mcp_<server>_<tool>
  → pi-permission-system
  → mcp-gateway.ts
  → upstream MCP（stdio JSON-RPC、完全な結果）
  → shaper（登録済みの要約／tail。未登録は本文をそのまま）
  → budget（文字予算。超過時はoverflow。JSONならキー一覧とサイズ）
  → model
```

## 設定

後勝ちでmergeする。

1. `~/.config/agent/mcp.json` — pi / Command Code用global設定
2. `<project>/.mcp.json` — project設定
3. `<project>/.pi/mcp.json` — pi override

Claude Codeは `common/claude/.config/claude/mcp.json` を別の正本とし、`install.sh` が `claude mcp add-json --scope user` で登録する。Cursorは共有mcp.jsonの有効serverを `~/.cursor/mcp.json` へ生成する。

```json
{
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "server-command",
      "args": [],
      "description": "purpose",
      "enabled": true,
      "maxResultSize": 8000,
      "shapes": {
        "get_pipeline_status": "summary",
        "get_logs": "tail",
        "list_pipelines": "summary"
      }
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
- 文字予算: server設定の `maxResultSize`、既定8000文字。これはslice用の窓ではなく、JSONを途中で切らないための予算
- 予算超過、またはshaperが事実を省略したときは完全な本文を `~/.pi/research/mcp-overflow/<timestamp>-<uuid>.json` に保存する。モデルへは `truncated`、byte数、overflowパスを含むJSONを返す。JSONを文字数で切らない
- 未登録toolの巨大JSONはキー一覧とサイズだけを本文に載せ、値はoverflowへ残す。小さい結果はそのまま通す
- shaperは `shapes` でserver/toolごとに指定でき、コードにはWoodpeckerの `summary` / `tail` の既定値がある
- shaped results are complete for their shape。`truncated=true` の場合はoverflowを読むか `get_logs` / `detail=full` を使い、省略されたworkflowを失敗なしと解釈しない
- auditへ書く引数は既知のsecret形式をredact

## Skill

MCP serverの選択には共有skill `mcp-research` を使う。正本は `common/agent/.config/agent/skills/mcp-research/SKILL.md`。

関連: [共有設定レイヤー](agent-layer.md)
