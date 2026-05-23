# Agent Shared Configuration Layer

Claude Code と pi で共有する設定（MCP、スキル、知識）を一元管理するレイヤー。
**ファイル共有ではなく仕様共有**を原則とする。

## Architecture

```
~/.config/agent/           ← 共有設定
├── mcp.json               ← MCPサーバー設定（統合）
├── skills/                ← Agent Skills Standard 準拠
│   ├── github/            ← commit, pr, issue, conflict-resolve
│   ├── research/          ← deep, docs, github, dependency, mcp
│   ├── quality/           ← quality-assure, safe-refactor, pr-review
│   └── debug/             ← incident-debug
└── knowledge/             ← ツール非依存の知識・原則
    ├── communication.md
    ├── security.md
    └── web-research.md

docs/specs/agent-infrastructure.md  ← 正準仕様書
  「すべてのエージェントは以下を実装すること」
   ├─ Permission Gate
   ├─ Protected Paths
   ├─ Audit Log
   ├─ Status Line
   ├─ Web Research
   └─ MCP Gateway
```

## 共有するもの・しないもの

| 共有する | 共有しない（ツール固有） |
|----------|------------------------|
| MCP 設定（標準プロトコル） | プロンプトテンプレート（構文が非互換） |
| スキル（Agent Skills Standard） | パスベースルール（glob 構文が非互換） |
| 知識・原則（プレーン Markdown） | コマンド定義（標準化されていない） |
| 仕様書（docs/specs/） | フック/拡張実装（機構が異なる） |

## 新エージェント追加手順

1. `docs/specs/agent-infrastructure.md` を読む
2. ツールのネイティブ機構で各コンポーネントを実装
3. ポリシーは仕様書に従う
4. 実装完了後、仕様書の Status テーブルを更新
5. 共有スキルは `~/.config/agent/skills/` を参照パスに追加

## 移行履歴

- 2026-05-23: `common/mcp/` + Claude MCP → `common/agent/` に統合
- pi skills/prompts → agent/skills/ に移行（prompts は pi 固有のため後日差し戻し）
- rules/ → knowledge/ に改名（制御ルールは除外）
- `docs/specs/agent-infrastructure.md` 新設
