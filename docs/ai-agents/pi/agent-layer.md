# Agent Shared Configuration Layer

Claude Code, pi, Codex の各コーディングエージェントで共有する設定（ルール、スキル、プロンプト、MCP）を一元管理するレイヤー。

## Architecture

```
~/.config/agent/           ← 共有設定（全エージェント）
├── mcp.json               ← MCPサーバー設定（統合）
├── rules/                 ← 共通ルール
│   ├── communication.md
│   ├── implementation.md
│   ├── problem-solving.md
│   ├── security.md
│   └── web-research.md
├── skills/                ← 共通スキル
│   ├── github/            ← commit, pr, issue, conflict-resolve
│   ├── research/          ← deep-research, docs-research, github-research, mcp-research
│   ├── quality/           ← quality-assure, safe-refactor, pr-review
│   └── debug/             ← incident-debug
└── prompts/               ← プロンプトテンプレート
    ├── plan.md
    ├── implement.md
    ├── commit.md
    └── review.md
```

## 各エージェントからの参照

| Agent | MCP | Rules | Skills | Prompts |
|-------|-----|-------|--------|---------|
| Claude | symlink: `~/.config/claude/mcp.json` → `~/.config/agent/mcp.json` | `~/.claude/rules/` (個別) + shared rules (CLAUDE.md経由) | `~/.config/agent/skills/` | — |
| pi | `~/.config/agent/mcp.json` (mcp-gateway.ts 経由) | AGENTS.md で参照 | settings.json の skills path | settings.json の prompts path |
| Codex | — | — | — | — |

## 設定ソースの優先順位

### MCP
1. (低) `~/.config/agent/mcp.json` — グローバル共有
2. `.mcp.json` — プロジェクト
3. (高) `.pi/mcp.json` — pi 上書き

### Skills / Prompts
pi の `settings.json` で指定されたパス順に解決（先勝ち）。

## スキル命名規則

- `github/*` — GitHub ワークフロー（commit, pr, issue, conflict-resolve）
- `research/*` — 調査系（deep, docs, github, dependency, mcp）
- `quality/*` — 品質保証（assure, safe-refactor, pr-review）
- `debug/*` — デバッグ・インシデント対応

## dotfiles でのパッケージ構成

```
common/agent/.config/agent/  → stow → ~/.config/agent/
```

`~/.config/agent/mcp.json` が Claude と pi の両方から参照される単一の MCP 設定となる。

## 移行履歴

- 2026-05-23: `common/mcp/` と `common/claude/.config/claude/mcp.json` を統合し `common/agent/.config/agent/mcp.json` に移行
- pi の skills/prompts を `common/agent/.config/agent/` に移行
- pi AGENTS.md を共有ルール参照にスリム化
