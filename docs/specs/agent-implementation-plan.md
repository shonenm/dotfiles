# pi Harness Implementation Plan

全指摘事項を5PRで回収する実装計画。すべてのPRが独立してレビュー可能で、順序に依存しない。

---

## PR 1: Statusline Enhancement

### Scope
statusline.ts の視認性・情報量・カスタマイズ性の強化。

### Tasks
- [x] カラーセグメント表示 — トークン量は緑/黄/赤、costは青、gitブランチは紫
- [x] MCP stats 表示 — statusline に `MCP q:3 c:5` を追加（web stats と同形式）
- [x] コンテキスト使用率の視覚バー — `[====>    ] 45%` 形式のプログレスバー
- [x] 複数行レイアウト対応 — 情報量が多い場合の折り返し or 2行表示
- [x] /statusline コマンドで detailed/compact/off の3モード切替切替
- [x] mcp-stats.json 読み取りを statusline に統合
- [x] リファクタ: `~/.pi/research/stats.json` の統一フォーマット化（web + mcp 両方）

### Files
- `common/pi/.pi/agent/extensions/statusline.ts`
- `common/pi/.pi/research/stats.json` (format update)

---

## PR 2: Memory / Persistence Layer

### Scope
セッション間知識継承のための SQLite ベース永続化層。毎回 fresh start 状態を解消する。

### Tasks
- [x] `~/.pi/research/knowledge.db` — SQLite データベース新設
  - テーブル: `sessions` (id, name, cwd, started_at, summary)
  - テーブル: `knowledge` (id, key, value, source_session, created_at, ttl)
  - テーブル: `decisions` (id, context, decision, rationale, session_id)
- [x] `extensions/memory.ts` — 新規拡張
  - `session_start`: 前回セッションのサマリを inject
  - `session_shutdown`: 現在セッションのサマリを保存（LLM に要約を依頼）
  - `tool_execution_end`: 重要な決定を `decisions` テーブルに記録
- [x] LLM ツール: `memory_search` — knowledge.db を key/value 検索
- [x] LLM ツール: `memory_save` — 任意の知識を手動保存
- [x] AGENTS.md に Memory layer の使い方を追記

### Files
- `common/pi/.pi/agent/extensions/memory.ts` (new)
- `common/pi/.pi/agent/AGENTS.md` (update)

---

## PR 3: Sub-agents & Delegation Automation

### Scope
pi-subagents パッケージ導入 + AGENTS.md の delegation 自動化。現在の手動 `pi -p` を拡張機能化。

### Tasks
- [ ] `pi install git:github.com/earendil-works/pi-subagents` — パッケージ導入
- [ ] `extensions/agent-delegation.ts` — 新規拡張（pi-subagents 前提）
  - AGENTS.md の difficulty 定義に基づき自動で適切なモデル・effort を選択
  - pueue 連携: サブエージェントを `pueue add` で非同期実行
  - 完了検知: pueue の完了をポーリングし、結果を親セッションに inject
- [ ] LLM ツール: `delegate_agent` — 明示的な委譲用（task, model, effort 指定可）
- [ ] `skills/github/delegate.md` — delegation ワークフロースキル
- [ ] AGENTS.md の Agent Delegation セクション拡張（自動委譲ルール）

### Files
- `common/pi/.pi/agent/extensions/agent-delegation.ts` (new)
- `common/pi/.pi/agent/settings.json` (packages 追加)
- `common/pi/.pi/agent/AGENTS.md` (update)
- `common/agent/.config/agent/skills/github/delegate.md` (new)

---

## PR 4: Remote Control & Session Management

### Scope
外出先・別端末からのセッション継続 + セッション管理の強化。

### Tasks
- [ ] **Remote Control**
  - `extensions/remote-control.ts` — 新規拡張
  - pi RPC モードを活用: `pi --rpc` で TCP/UNIX socket 待受
  - `wt` + tmux 連携: リモート端末から tmux attach で既存セッションに接続
  - `/remote` コマンド: 現在のセッションの RPC エンドポイントを表示
  - `scripts/pi-remote` — リモート接続用ワンライナー
- [ ] **Session Management**
  - `extensions/session-manager.ts` — 新規拡張
  - `/sessions` コマンド: セッション一覧（fzf 選択 → resume）
  - `/session-name <name>` — セッション名の手動設定
  - セッション自動命名: git branch + 最初のプロンプト要約
  - `/session-export` / `/session-import` — JSONL の import/export
- [ ] **Quick Questions**
  - `extensions/quick-question.ts` — 新規拡張
  - `/q <question>` — 会話履歴を汚さずに質問 → 回答を notification 表示
  - 内部実装: 別 pi インスタンスを `-p` モードで起動し、結果のみ返す

### Files
- `common/pi/.pi/agent/extensions/remote-control.ts` (new)
- `common/pi/.pi/agent/extensions/session-manager.ts` (new)
- `common/pi/.pi/agent/extensions/quick-question.ts` (new)
- `scripts/pi-remote` (new)

---

## PR 5: Plan Mode + Todo + Package Migration + Remaining Gaps

### Scope
QoL 機能の追加と技術的負債の解消。

### Tasks
- [ ] **Plan Mode**
  - `extensions/plan-mode.ts` — 新規拡張
  - `/plan` コマンド: read-only モードに切り替え（write/edit/bash をブロック）
  - LLM に「実装せず計画だけ立案せよ」と指示
  - `/approve` — 計画を承認し write/edit/bash のブロックを解除
  - `/plan` プロンプトテンプレートと統合
- [ ] **Todo Management**
  - `extensions/todo-list.ts` — 新規拡張
  - LLM ツール: `todo_create`, `todo_update`, `todo_list`
  - TUI ウィジェット: セッション右上に TODO 進捗を常時表示（`ctx.ui.setWidget`）
  - セッション間 TODO 継承（knowledge.db 連携）
- [ ] **Package Migration**
  - 自作 `mcp-gateway.ts` → `pi-mcp-adapter` への移行方針を決定（互換性確認後）
  - 移行する場合: `pi install git:github.com/earendil-works/pi-mcp-adapter`
  - 移行しない場合: 自作 gateway の HTTP MCP (myproject) 対応を追加
- [ ] **Auto Research Loop**
  - `skills/research/deep-research.md` 強化
  - search → fetch → summarize → refine → search の自動反復ロジック
  - max iterations / timeout 付き
- [ ] **Audit Log UI**
  - `/audit` コマンド: `mcp-audit.jsonl` + `audit.log.jsonl` のサマリ表示
  - 日次/週次の使用統計を notification 表示
- [ ] **Add-dir support**
  - `extensions/add-dir.ts` — 新規拡張
  - `/add-dir <path>` — 追加ディレクトリを pi のコンテキストに読み込み
  - マルチリポジトリ作業のサポート

### Files
- `common/pi/.pi/agent/extensions/plan-mode.ts` (new)
- `common/pi/.pi/agent/extensions/todo-list.ts` (new)
- `common/pi/.pi/agent/extensions/add-dir.ts` (new)
- `common/pi/.pi/agent/extensions/mcp-gateway.ts` (update or deprecate)
- `common/agent/.config/agent/skills/research/deep-research.md` (update)

---

## Gap Coverage Matrix

| 指摘事項 | PR | 
|----------|:--:|
| Statusline 強化 | PR 1 |
| Memory / Persistence | PR 2 |
| Sub-agents | PR 3 |
| Delegation 自動化 | PR 3 |
| Remote Control | PR 4 |
| Session 管理 | PR 4 |
| Quick Questions | PR 4 |
| Plan Mode | PR 5 |
| Todo Management | PR 5 |
| Package Migration | PR 5 |
| Auto Research Loop | PR 5 |
| Audit Log UI | PR 5 |
| Add-dir | PR 5 |
