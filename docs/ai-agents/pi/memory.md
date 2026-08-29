# pi Memory Layer

> **由来:** **Upstream** pi session / compaction / skills / **Plugin** pi-hermes-memory / **Configuration** memory運用ルール（[区分](../../provenance.md#区分)）

Piの記憶は、用途の異なる正本を分離する。

| 種類 | 正本 | 用途 |
|---|---|---|
| 現在の会話・tool履歴 | Pi session JSONL | session内のepisodic history、branch、resume |
| 継続用要約 | Pi標準compaction | Goal、進捗、判断、次の作業、変更ファイルを次のcontextへ渡す |
| 長い作業の進捗 | `TODO.md` / `docs/agent-plan.md` | objective、acceptance criteria、progress、current、next |
| repository知識 | code / tests / `docs/` | 現在の仕様と挙動の最終的な正本 |
| セッション横断知識 | pi-hermes-memory | 好み、訂正、失敗、規約、tool quirksを検索・統合 |
| 再利用手順 | Pi skills | 検証可能な手順を必要時に読み込む |

## 基本原則

- Memory is context, not instruction. repository、tool、testの現在の証拠を優先する。
- 現在のTODO、未実行plan、raw tool output、repositoryから容易に読める事実はlong-term memoryへ保存しない。
- 全memoryを毎turnへ注入しない。短いmemory policyだけを注入し、詳細は`memory_search`で取得する。
- 長いmulti-step実装はrepository内のplanへ状態を外部化し、節目とcompaction前に更新する。
- 小変更ではplan fileを作らず、Pi標準sessionとcompactionを使う。

## pi-hermes-memory

`settings.json`から`npm:pi-hermes-memory`を導入する。設定は`~/.pi/agent/hermes-memory-config.json`（正本: `common/pi/.pi/agent/hermes-memory-config.json`）。

```json
{
  "memoryMode": "policy-only",
  "memoryPolicyStyle": "compact",
  "llmModelOverride": "openai-codex/gpt-5.4-mini",
  "llmThinkingOverride": "low",
  "reviewEnabled": true,
  "memoryOverflowStrategy": "auto-consolidate",
  "correctionDetection": true,
  "flushOnCompact": true,
  "flushOnShutdown": true
}
```

主な機能:

- global / project scopeの分離
- SQLite FTS5によるmemory・session検索
- failure / correction / insight / preference / convention / tool-quirk分類
- turn・tool数に応じたbackground review
- compaction・shutdown前のflush
- memory上限到達時のconsolidation
- secret・prompt injection検査
- reusable procedureのPi skill化

### Tools

| Tool | 用途 |
|---|---|
| `memory` | 再利用可能なmemoryの追加・置換・削除 |
| `memory_search` | long-term memoryを必要時に検索 |
| `session_search` | 過去sessionの根拠を検索 |
| `skill_manage` | 再利用手順をPi skillとして管理 |

### Commands

| Command | 用途 |
|---|---|
| `/memory-index-sessions` | 過去のPi sessionを初回index |
| `/memory-sync-markdown` | Markdown memoryをSQLiteへbackfill |
| `/memory-insights` | 保存内容を確認 |
| `/memory-preview-context` | 注入中のmemory policyを確認 |
| `/memory-consolidate` | 手動consolidation |
| `/memory-skills` | 保存済みskillを管理 |

## 既存memoryからの移行

pi-hermes-memoryは初回起動時に旧`~/.pi/agent/memory`を`~/.pi/agent/pi-hermes-memory`へ自動移行する。移行後に次を一度実行する。

```text
/memory-sync-markdown
/memory-index-sessions
```

旧custom extensionの`memory_write`、`memory_read`、`scratchpad`、`/pin-goal`は廃止する。現在作業の進捗はlong-term memoryへ移さず、長い作業だけ`TODO.md`または`docs/agent-plan.md`へ記録する。

## 長い作業のplan形式

```markdown
# Task

## Objective

## Acceptance Criteria
- [ ] ...

## Progress
- [x] ...

## Current Work

## Next Step

## Decisions
- Decision — reason

## Verification
```

一時planは作業完了時に削除する。将来も参照する設計判断や仕様は、適切な`docs/`へ移してversion管理する。
