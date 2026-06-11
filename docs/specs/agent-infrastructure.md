# Agent Infrastructure Specification

すべてのコーディングエージェント（Claude Code / pi / Codex / Cursor / Command Code）が実装すべき基盤コンポーネントの仕様。
**実装方法はツール固有だが、振る舞いとポリシーは統一する。**

## Design Principle

> **Specify once, implement natively.**
> 仕様はこのファイルに集約し、実装は各ツールのネイティブ機構（hooks / extensions / plugins）で行う。
> ファイル共有（symlink）ではなく、仕様共有（spec）で統一する。

## Components

### 1. Permission Gate

危険な操作を実行前に確認する。

| 項目 | 内容 |
|------|------|
| **Triggers** | `rm -rf`, `sudo`, `chmod 777`, `chown`, `docker system prune`, `kubectl delete`, `terraform apply`, `npm publish`, `git push --force`, `git reset --hard`, `DROP`, `DELETE FROM`, `TRUNCATE TABLE` |
| **Pi impl** | `extensions/permission-gate.ts` — `tool_call` event + `ctx.ui.confirm` |
| **Claude impl** | 検討中（`hooks/` で実装可能） |
| **Behavior** | ユーザーに確認ダイアログを表示。拒否時は理由をログに記録 |

### 2. Protected Paths

機密ファイル・生成ファイルへの書き込みを拒否する。

| 項目 | 内容 |
|------|------|
| **Protected** | `.env` files, `node_modules/`, `dist/`, `coverage/`, `.next/`, `.terraform/`, `*_rsa`, `*_ed25519`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `secrets.*`, `credentials.*`, `.ssh/`, `.aws/`, `.docker/` |
| **Pi impl** | `extensions/protected-paths.ts` — `write`/`edit` tool_call event |
| **Claude impl** | 検討中 |
| **Behavior** | 書き込みをブロックし、ユーザーに明示的な許可を求めるよう指示 |

### 3. Audit Log

全ツール呼び出しの記録。

| 項目 | 内容 |
|------|------|
| **Log path** | `~/.pi/research/audit.log.jsonl` |
| **Format** | `{"timestamp":"ISO8601","action":"tool_name","detail":"summary","error":null,"elapsedMs":123}` |
| **Pi impl** | `web-tools.ts` / `mcp-gateway.ts` 内蔵 |
| **Claude impl** | 検討中 |

### 4. Status Line

フッターにセッション状態を表示する。

| 項目 | 内容 |
|------|------|
| **Display** | トークン使用量 (in/out), コスト, コンテキスト容量 (%), git ブランチ, モデル名, web/MCP アクティビティ |
| **Gauge** | Unicodeブロックゲージ (████░░░░), 色は使用率連動 |
| **Pi impl** | `extensions/statusline.ts` — 3行マルチラインフッター, 3モード切替 (detailed/compact/off) |
| **Claude impl** | `hooks/statusline-command.sh` |

### 5. Web Research

**search → fetch → cache → cite → answer** プロトコル。

| 項目 | 内容 |
|------|------|
| **Search** | SearXNG (primary, localhost:8888) → Jina AI (fallback) |
| **Fetch** | Jina Reader (r.jina.ai) → raw curl |
| **Cache** | `~/.pi/research/sources/<sha256>.md` |
| **Citation** | `~/.pi/research/citations.jsonl` |
| **Stats** | `~/.pi/research/stats.json` |
| **Pi impl** | `extensions/web-tools.ts` (6ツール統合) |
| **Claude impl** | 検討中 |

### 8. Agent Delegation

サブエージェントによる並列作業の委譲。

| 項目 | 内容 |
|------|------|
| **Tools** | `delegate_agent`, `check_delegation`, `wait_delegation` |
| **Modes** | sync (blocking) / async (pueue background) |
| **Model tiers** | high (gpt-5.5), medium (deepseek-v4-pro), low (flash) |
| **Pi impl** | `extensions/agent-delegation.ts` — pueue + pi -p integration |


### 7. Memory Persistence

セッション間知識継承のための永続化層。

| 項目 | 内容 |
|------|------|
| **Storage** | JSON files in `~/.pi/research/memory/` |
| **Auto-save** | Session summary on shutdown |
| **Auto-inject** | Previous session context on startup |
| **LLM tools** | `memory_search`, `memory_save`, `memory_decide`, `memory_summary` |
| **Pi impl** | `extensions/memory.ts` — JSON-backed persistent store |


### 6. MCP Gateway

MCP サーバーへの安全な接続レイヤー。

| 項目 | 内容 |
|------|------|
| **Config** | `~/.config/agent/mcp.json` (共有) |
| **Permission** | 3段階: `allow` / `ask` / `deny` |
| **Audit** | `~/.pi/research/mcp-audit.jsonl` |
| **Stats** | `~/.pi/research/mcp-stats.json` |
| **Pi impl** | `extensions/mcp-gateway.ts` — JSON-RPC stdio client + tool registration. allow/ask/deny enforced via `tool_call` gate; protocol version negotiated (advertises latest). stdio only (HTTP deferred) |
| **Claude impl** | ネイティブ MCP 対応。`common/claude/.config/claude/mcp.json` を正本に install.sh が `claude mcp add-json --scope user` で登録 |

## Shared Configuration

ツール非依存で共有可能な設定は `~/.config/agent/` に集約する。

```
~/.config/agent/
├── mcp.json              ← MCP サーバー設定（標準プロトコル）
├── skills/               ← Agent Skills Standard 準拠
│   ├── github/           ← commit, pr, issue, conflict-resolve
│   ├── research/         ← deep-research, docs-research, github-research, mcp-research
│   ├── quality/          ← quality-assure, safe-refactor, pr-review
│   └── debug/            ← incident-debug
└── knowledge/            ← ツール非依存の知識・原則
    ├── communication.md  ← 言語・トーン
    ├── security.md       ← セキュリティポリシー
    └── web-research.md   ← 調査プロトコル
```

### 共有「しない」もの（ツール固有）

| 対象 | 理由 |
|------|------|
| プロンプトテンプレート | ツールごとに構文が異なる |
| パスベースルール | glob 構文が非互換（`paths:` / `globs:` / `applyTo:`） |
| コマンド定義 | 標準化されていない |
| フック定義 | イベント名・設定形式が全ツールで異なる |
| 権限・実行ポリシー | 完全にツール固有 |

## Implementation Status

| Component | Pi | Claude Code | Codex | Cursor |
|-----------|:--:|:-----------:|:-----:|:------:|
| Permission Gate | ✅ | — | — | — |
| Protected Paths | ✅ | — | — | — |
| Audit Log | ✅ | — | — | — |
| Status Line | ✅ | ✅ | — | — |
| Web Research | ✅ | — | — | — |
| MCP Gateway | ✅ | ✅ | — | — |
| Memory Persistence | ✅ | — | — | — |
| Agent Delegation | ✅ | — | — | — |
| Global Rules | — | ✅ | — | ✅ |
| Stop Notify (詳細は [agent-stop-notification.md](./agent-stop-notification.md)) | — | ✅ | △ | △ |
| CLI Statusline | — | ✅ | — | ✅ |
| tmux Usage Display | — | ✅ | ✅ | ✅ |

## Adding a New Agent

1. この仕様書の Components を読む
2. ツールのネイティブ機構で各コンポーネントを実装する
3. ポリシー（パターンリスト、権限レベル）は仕様書に従う
4. 実装完了後、Implementation Status テーブルを更新する
5. **使い回しが必要な部分は AI に依頼して変換する**（symlink や生成スクリプトは使わない）

## References

- [Agent Skills Standard](https://agentskills.io/specification)
- [Claude Code Hooks](https://code.claude.com/docs/hooks)
- [pi Extensions](https://pi.dev/docs/latest/extensions)
- [MCP Specification](https://modelcontextprotocol.io/)
- [AI Agent ルールの共通化をやめた](https://qiita.com/chibicco/items/cbf78dbf7abfd1a1caea) — symlink 一本化の失敗事例
