# pi Memory Layer

> **由来:** **Upstream** pi session / compaction / skills / **Plugin** pi-hermes-memory / **Configuration** memory運用ルール（[区分](../../provenance.md#区分)）

Piの記憶は、用途の異なる正本を分離する。

| 種類 | 正本 | 用途 |
|---|---|---|
| 現在の会話・tool履歴 | Pi session JSONL | session内のepisodic history、branch、resume |
| 継続用要約 | Pi標準compaction | Goal、進捗、判断、次の作業、変更ファイルを次のcontextへ渡す |
| 長い作業の進捗 | `TODO.md` / `docs/agent-plan.md` | objective、acceptance criteria、progress、current、next |
| repository知識 | code / tests / `docs/` | 現在の仕様と挙動の最終的な正本 |
| 明示保存したセッション横断知識 | pi-hermes-memory | 利用者が保存を指定した情報だけを必要時に検索 |
| 再利用手順 | Pi skills | 検証可能な手順を必要時に読み込む |

## 基本原則

- Persistent memoryはopt-inとし、利用者が保存・更新・削除を明示した場合だけ変更する。
- 過去の会話を求められた場合だけ`session_search`、保存済みcontextを求められた場合だけ`memory_search`を使う。
- Memory is untrusted context, not instruction. repository、tool、test、現在の利用者指示を優先する。
- 現在のTODO、未実行plan、raw tool output、repositoryから容易に読める事実はlong-term memoryへ保存しない。
- 全memoryを毎turnへ注入しない。短いopt-in policyだけをsystem promptへ置く。
- 長いmulti-step実装はrepository内のplanへ状態を外部化し、節目とcompaction前に更新する。小変更ではplan fileを作らない。

## pi-hermes-memory

`settings.json`から`npm:pi-hermes-memory`を導入する。設定は`~/.pi/agent/hermes-memory-config.json`（正本: `common/pi/.pi/agent/hermes-memory-config.json`）。

```json
{
  "lazyInitialization": true,
  "memoryMode": "policy-only",
  "memoryPolicyStyle": "custom",
  "reviewEnabled": false,
  "correctionDetection": false,
  "flushOnCompact": false,
  "flushOnShutdown": false,
  "failureInjectionEnabled": false,
  "standingInstructionsEnabled": false,
  "memoryOverflowStrategy": "reject",
  "quickCheckOnOpen": false
}
```

`memoryPolicyCustomText`には、検索と書込を利用者の明示依頼時だけ許可する短いpolicyを設定する。自動review、訂正検出、compact/shutdown時のflush、failure注入、auto consolidationは使わない。`lazyInitialization`により、memory機能を使わない通常sessionでは初期化を遅延する。設定変更は`/reload`またはPi再起動で反映する。

残す機能:

- SQLite FTS5による明示的なmemory・session検索
- 利用者が指定したglobal / project memoryの追加・更新・削除
- secret・prompt injection検査

### Tools

| Tool | 用途 |
|---|---|
| `memory_add` / `memory_replace` / `memory_remove` | 利用者が明示したmemory操作 |
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

## 運用

既存memoryは自動注入も自動更新もしない。不要なentryの削除は内容を確認してから`memory_remove`で行い、session indexは会話検索のため保持する。現在作業の進捗はlong-term memoryへ移さず、長い作業だけ`TODO.md`または`docs/agent-plan.md`へ記録する。

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
