---
name: ralph-plan
description: タスクの要件定義・設計・タスク分解をインタラクティブに行い、Ralph実装ループ用の状態ファイルを生成します。
user-invocable: true
disable-model-invocation: true
arguments: "<task-description>"
---

# Ralph Plan - インタラクティブ計画セッション

ユーザーとの対話を通じて要件定義・受入条件・設計・タスク分解を行い、`/ralph` で使用する状態ファイルを生成します。

このスキルは通常の対話セッションとして動作します（自律ループ機構は使用しません）。

## 引数

| 引数 | 説明 |
|------|------|
| `<task-description>` | 実装するタスクの説明 |

### 使用例

```
/ralph-plan "ユーザー認証機能を追加する"
/ralph-plan "APIのレスポンスキャッシュ層を実装する"
/ralph-plan docs/prd.md
```

## 手順

### Phase 0: Context Gathering

タスク説明を分析し、最大3つのサブエージェントを Task ツールで並列起動してコードベースを調査する。

起動するサブエージェント:

1. パターン調査エージェント:
   - 既存のアーキテクチャパターン
   - 命名規則
   - ディレクトリ構造
   - 類似機能の実装方法

2. 依存関係調査エージェント:
   - 関連パッケージ・内部モジュール
   - 型定義
   - Supabase スキーマ (該当する場合)
   - 外部 API インターフェース

3. テスト構造調査エージェント:
   - 既存テストのパターン (describe/it 構造、ファイル命名)
   - テストユーティリティ・ヘルパー
   - モック戦略 (MSW, vi.mock 等)
   - テストランナー設定

全エージェントの結果を統合し、コンテキストレポートとしてユーザーに提示する。

### Phase 1: Requirements & Acceptance Criteria

コンテキストレポートをもとに以下を生成し、ユーザーに提示する:

```markdown
## 機能要件
- FR-1: ...
- FR-2: ...

## 非機能要件
- NFR-1: ...

## スコープ外
- ...

## 受入条件
- AC-1: ...（検証方法: ...）
- AC-2: ...（検証方法: ...）
- AC-T: 全テストパス（検証方法: npm test）
- AC-L: tsc --noEmit エラー0（検証方法: npx tsc --noEmit）
```

注意:
- AC-T (全テストパス) と AC-L (tsc --noEmit エラー0) はデフォルトACとして必ず含める
- 全てのACは検証可能な形式で記述する (コマンドまたは手順を明記)
- ユーザーのフィードバックを受けて修正を繰り返す
- ユーザーが「OK」「承認」「LGTM」等で承認したら Phase 2 へ進む

### Phase 2: Design & Task Decomposition

要件 + コンテキストをもとに設計ドキュメントを生成する:

```markdown
## アーキテクチャ方針
- 既存パターンとの整合性: ...
- 採用するパターン: ...

## 変更対象ファイル
- 新規: ...
- 変更: ...

## データモデル変更
- (Supabase マイグレーション含む)

## API 設計
- (エンドポイント、リクエスト/レスポンス)

## リスク・懸念事項
- ...
```

設計承認後、atomic なタスクに分解し依存関係グラフを生成する:

```markdown
## タスクグラフ
- T-1: ... [deps: none] [files: ...]
- T-2: ... [deps: T-1] [files: ...]
- T-3: ... [deps: T-1] [files: ...]
- T-4: ... [deps: T-2, T-3] [files: ...]
```

各タスクに以下を明記:
- 完了条件
- 対象ファイル
- 依存するタスク

ユーザーのフィードバックを受けて修正し、承認を得る。

### Phase 3: 状態ファイル生成

ユーザーが設計とタスクグラフを承認したら、以下のコマンドで状態ファイルを生成する:

```bash
SESSION_HASH="$(echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5sum 2>/dev/null | cut -c1-12 || echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5 2>/dev/null | cut -c1-12)"
STATE_FILE="/tmp/ralph_${SESSION_HASH}.json"

# jq で状態ファイルを生成 (ACとタスクグラフは動的に構築)
# ... (Phase 1/2 の結果を JSON に変換)

echo "$STATE_FILE" > /tmp/ralph_session_manifest
```

状態ファイルのスキーマ:

```jsonc
{
  "session_id": "<hash>",
  "phase": "implementation",
  "max_iterations": 25,
  "iteration": 0,
  "created_at": "<ISO8601>",
  "acceptance_criteria": [
    {"id": "AC-1", "description": "...", "verified": false, "verification_command": "..."}
  ],
  "task_graph": [
    {"id": "T-1", "name": "...", "deps": [], "status": "pending", "completion_condition": "...", "files": ["..."]}
  ],
  "context_report": "<Phase 0 の調査結果サマリー>",
  "stall_hashes": [],
  "completion_token": "RALPH_COMPLETE",
  "errors": []
}
```

生成完了後、ユーザーに以下を案内する:

```
状態ファイルを生成しました: <STATE_FILE>
`/ralph` で実装を開始できます。
```
