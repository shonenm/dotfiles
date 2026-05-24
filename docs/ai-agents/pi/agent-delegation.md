# pi Agent Delegation Layer

サブエージェントによる並列作業委譲の仕組み。pi-subagents（コミュニティ） + agent-delegation.ts（カスタム）の2層構成。

## Architecture

```
親セッション (pi)
  ├─ subagent (pi-subagents)        ← chain/parallel + TUI進捗
  │   └─ reviewer / scout / worker / oracle
  └─ delegate_agent (custom)        ← pueue非同期 + 自動モデル選択
      └─ pueue queue → pi -p → 結果回収
```

## Tools

### pi-subagents (community)

| Tool | 用途 |
|------|------|
| `subagent` | 単一/チェーン/並列実行。TUI進捗表示付き |

自然言語で委譲可能:
```
"Use reviewer to audit auth module for security issues"
"Use scout to explore how the payment flow works"
"Run parallel reviewers: one for correctness, one for tests"
```

### agent-delegation.ts (custom)

| Tool | 用途 |
|------|------|
| `delegate_agent` | sync/async (pueue) サブエージェント起動。難易度自動モデル選択 |
| `check_delegation` | pueue タスク状態確認 |
| `wait_delegation` | タスク完了待ち + 結果取得 |

## Built-in Agent Roles

| ロール | 用途 | 推奨難易度 | モデル |
|--------|------|:--:|--------|
| `reviewer` | コードレビュー、セキュリティ監査、品質チェック | high | gpt-5.5 / kimi-k2.6 |
| `scout` | コードベース探索、read-only調査、依存関係分析 | medium | deepseek-v4-pro |
| `worker` | 承認済み計画からの実装 | medium | deepseek-v4-pro |
| `oracle` | セカンドオピニオン、設計レビュー、前提検証 | high | gpt-5.5 / kimi-k2.6 |

## Model Auto-Selection

`delegate_agent` は difficulty に応じて自動的にモデルを選択する:

| Difficulty | Primary Model | Fallback |
|:----------:|---------------|----------|
| `high` | openai-codex/gpt-5.5:high | opencode-go/kimi-k2.6:high |
| `medium` | opencode-go/deepseek-v4-pro:high | openai-codex/gpt-5.4:low |
| `low` | opencode-go/deepseek-v4-flash:off | openai-codex/gpt-5.4-mini:off |

モデル・フォールバックは手動オーバーライド可能。

## Execution Modes

| Mode | 動作 | 用途 |
|------|------|------|
| **async** (default) | pueue でバックグラウンド実行。`check_delegation` + `wait_delegation` で結果回収 | 独立タスクの並列化 |
| **sync** | 完了までブロック。結果を直接返す | 依存関係のある逐次タスク |

## pueue Integration

非同期実行には pueue デーモンが必要:

```bash
pueued -d        # デーモン起動
pueue status     # 状態確認
pueue log <id>   # ログ確認
pueue wait <id>  # 完了待ち
```

セッション開始時に自動でデーモン起動を試みる。

## Audit

全委譲は `~/.pi/research/delegation.jsonl` に記録:

```json
{"timestamp":"2026-05-24T...","difficulty":"high","task":"review auth module","taskId":"0"}
```

## pi-subagents vs agent-delegation.ts

| | pi-subagents | agent-delegation.ts |
|---|---|---|
| **chain/parallel** | ✅ | ❌ |
| **TUI 進捗表示** | ✅ chain visualization | ❌ |
| **pueue 非同期** | ❌ | ✅ |
| **自動モデル選択** | ❌ | ✅ difficulty tiers |
| **audit log** | ❌ | ✅ delegation.jsonl |
| **check/wait** | ❌ | ✅ |
| **自然言語委譲** | ✅ | ✅ |
| **インストール** | `pi install npm:pi-subagents` | dotfiles 内蔵 |

両方インストールして併用するのが推奨構成。

## Extensions

| Extension | 役割 |
|-----------|------|
| `agent-delegation.ts` | pueue非同期実行 + 自動モデル選択 |
| `pi-subagents` (package) | chain/parallel実行 + TUI表示 |

## Skills

| Skill | 用途 |
|-------|------|
| `github-delegate` | 委譲ワークフローガイドライン |

## 使用例

```
# コードレビュー（非同期）
delegate_agent(task: "Use reviewer to audit src/auth/ for security issues", difficulty: "high")

# 並列レビュー
delegate_agent(task: "Review for correctness", difficulty: "high")
delegate_agent(task: "Review for performance", difficulty: "high")

# 結果確認
check_delegation()
wait_delegation(taskId: "0")
```
