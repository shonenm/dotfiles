---
name: mcp-research
description: MCPサーバーを選択し、必要なtoolだけを使って調査します。
user-invocable: true
---

# MCP Research

MCP toolは、local read / web researchより対象serverの情報が適している場合だけ使う。

## Rules

- `~/.config/agent/mcp.json` を確認し、`enabled: false` のserverを使える前提にしない。
- sessionに登録された `mcp_<server>_<tool>` だけを利用する。
- 最小のserver・toolを選び、取得範囲を絞る。
- write、外部投稿、browser操作はpermission policyに従う。
- secret、credential、private source全文をremote serverへ送らない。
- 利用したserverと目的を結果に記載する。

## 現在のglobal設定

| Server | 状態 | 用途 |
|---|---|---|
| `woodpecker-ci` | enabled | CI build・repository状態の確認 |
| `tmux` | disabled | tmux session操作 |
| `serena` | disabled | project code navigation |
| `token-optimizer` | disabled | context最適化 |

projectの `.mcp.json` / `.pi/mcp.json` でserverが追加・overrideされるため、固定一覧ではなく実際のregistered toolを優先する。

## 手順

1. local toolや専用skillで解決できない理由を確認する。
2. `/mcp` または登録tool一覧で接続中serverを確認する。
3. read-onlyの最小toolを1回実行する。
4. 結果が大きい場合はqueryを絞り、同じ全件取得を繰り返さない。
5. writeが必要なら実行前に目的と影響範囲を明示する。

## Permission / Audit

MCP toolの `allow` / `ask` / `deny` はpiのpermission policyが決める。gatewayはresultを既定8000文字に制限し、呼び出しを `~/.pi/research/mcp-audit.jsonl` へ記録する。
