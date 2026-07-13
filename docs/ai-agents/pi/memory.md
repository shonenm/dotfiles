# pi Memory Layer

セッション間知識継承のための永続化層。pi-memory 互換の Markdown フォーマットを採用。

## Architecture

```
セッション開始
  ├─ /pin-goal の pinned note を inject
  ├─ SCRATCHPAD.md の未完了項目を inject
  ├─ 今日の daily log 末尾を inject
  └─ MEMORY.md を inject（middle-truncate）
  → 合計最大 8K chars

セッション中
  memory_write  → MEMORY.md または daily log に追記
  memory_read   → 任意のメモリファイルを読み取り
  memory_search → 全ファイルをキーワード検索
  scratchpad    → SCRATCHPAD.md のチェックリストを操作

セッション終了 / compaction
  → 未完了 scratchpad 項目を daily log に handoff 記録
```

## Files

```
~/.pi/agent/memory/
├── MEMORY.md              # 長期記憶: 事実・決定・設定・教訓
├── SCRATCHPAD.md           # チェックリスト: やるべきこと・覚えておくこと
└── daily/                  # 日次ログ
    ├── 2026-05-23.md       # 作業メモ・handoff 記録
    └── 2026-05-24.md
```

全ファイルがプレーン Markdown のため、手動編集・git 管理が可能。

## Tools

| Tool | 用途 | ターゲット |
|------|------|-----------|
| `memory_write` | メモリに書き込み | `long_term` (MEMORY.md) / `daily` (今日のログ) |
| `memory_read` | メモリを読み取り | `mem` / `daily` / `list` (日次一覧) |
| `memory_search` | キーワード検索 | 全ファイルを部分一致検索 |
| `scratchpad` | チェックリスト操作 | `add` / `done` / `undo` / `clear` / `list` |

## Context Injection

セッション開始時に以下の優先順位で注入（合計 ~8K chars）：

| Priority | Source | Budget |
|:--------:|--------|:------:|
| 0 | `/pin-goal` の pinned note | 1K |
| 1 | 未完了 scratchpad 項目 | 2K |
| 2 | 今日の daily log (末尾) | 3K |
| 3 | MEMORY.md (middle-truncate) | 4K |

注入は `pi.sendMessage()` で行い、会話履歴には表示されない（`display: false`）。`/goal` は `pi-goal` package の autonomous goal mode 用に予約し、軽量な固定コンテキストは `/pin-goal` を使う。

## Handoff

セッション終了時・compaction 時に、未完了 scratchpad 項目を daily log に自動記録：

```markdown
<!-- HANDOFF 2026-05-24T15:30:00.000Z -->
## Session Handoff (2026-05-24T15:30)
**Open scratchpad items:**
- [ ] Fix auth bug
- [ ] Review PR #42
```

## qmd (Optional)

`qmd` をインストールすると semantic/vector 検索が利用可能になる：

```bash
bun install -g https://github.com/tobi/qmd
```

qmd がある場合、`memory_search` が BM25 + ベクトル + ハイブリッドの3モードに対応する（`pi-memory` パッケージと同様の挙動）。

## Extension

| Extension | 役割 |
|-----------|------|
| `memory.ts` | 全メモリツール + 自動 inject/handoff |

## 他の Memory 実装との比較

| | pi-memory (community) | Codex Native | 本実装 |
|---|---|---|---|
| **形式** | Markdown | Markdown | Markdown |
| **検索** | qmd (BM25/vector/hybrid) | なし（要約を注入） | 部分一致 + qmd optional |
| **注入** | 毎ターン（snapshot方式） | セッション開始時 | セッション開始時 |
| **要約** | handoff 自動記録 | LLM バッチ要約 | handoff 自動記録 |
| **ファイル** | MEMORY.md + daily/ + SCRATCHPAD.md | MEMORY.md + memory_summary.md | 同左（pi-memory互換） |
| **依存** | qmd + Bun (optional) | gpt-5.4-mini | ゼロ依存 |
