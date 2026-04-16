---
name: d-ralph-resume
description: 完了した Ralph セッションのアーカイブから状態を復元し、追加タスクを定義して再実行可能にします。
user-invocable: true
disable-model-invocation: true
arguments: "<prompt>"
---

# Ralph Resume - アーカイブからの継続

完了済み Ralph セッションのアーカイブを読み込み、追加タスクを定義して新しい状態ファイルを生成します。

## 引数

| 引数 | 説明 |
|------|------|
| `<prompt>` | (任意) 追加タスクの説明。指定時は対話なしで状態ファイルを生成 |

### 使用例

```
/d-ralph-resume
/d-ralph-resume "エラーハンドリングを追加する"
/d-ralph-resume "テストカバレッジを改善する" --max-iterations 10
```

## 手順

### Step 1: アーカイブの特定と読み込み

最新のアーカイブファイルを特定する:

```bash
ARCHIVE="$(ls -t /tmp/ralph/state/archive_*.json 2>/dev/null | head -1)"
if [ -z "$ARCHIVE" ]; then
  echo "No Ralph archive found in /tmp/"
  exit 1
fi
echo "Latest archive: $ARCHIVE"
cat "$ARCHIVE" | jq .
```

アーカイブが見つからない場合はユーザーに報告して終了する。

### Step 2: アーカイブ内容の表示

アーカイブの内容をユーザーに提示する:

```markdown
## 前回のセッション

### 完了済みタスク
- T-1: <name> (done)
- T-2: <name> (done)
- ...

### 受入条件
- AC-1: <description> (verified: true/false)
- ...

### エラー
- <error messages if any>

### コンテキストレポート
<context_report summary>
```

### Step 3: 追加タスクの定義

引数 `<prompt>` が指定されている場合:
- プロンプトの内容を分析し、適切なタスクと（必要なら）ACを自動生成する
- Step 4 へ直接進む

引数が指定されていない場合:
- ユーザーと対話して追加タスクを定義する
- 必要に応じて追加の受入条件も定義する
- ユーザーが承認したら Step 4 へ進む

注意: task_graph にコミットタスクを含めない。ユーザーが明示的にコミットを要求した場合のみ含める。

### Step 4: 状態ファイルの生成

アーカイブの内容と新規タスクを統合して新しい状態ファイルを生成する。

生成ルール:
- 既存の完了済みタスク (status: "done") はそのまま保持
- 新タスクの ID は既存の最大 T-N + 1 から連番
- 新ACの ID は既存の最大 AC-N + 1 から連番 (AC-T, AC-L 等の特殊IDは除外して数値のみカウント)
- `context_report` は元のレポートを保持
- リセットするフィールド: `phase: "implementation"`, `iteration: 0`, `stall_hashes: []`, `errors: []`
- `max_iterations` はデフォルト 25 (引数 `--max-iterations N` で上書き可能)
- `created_at` は現在時刻で更新

```bash
SESSION_HASH="$(echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5sum 2>/dev/null | cut -c1-12 || echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5 2>/dev/null | cut -c1-12)"
mkdir -p /tmp/ralph/state
STATE_FILE="/tmp/ralph/state/${SESSION_HASH}.json"

# jq で状態ファイルを生成
# - アーカイブの task_graph (done タスクを保持) + 新タスクを追加
# - アーカイブの acceptance_criteria (verified 状態を保持) + 新ACを追加
# - context_report を保持
# - phase, iteration, stall_hashes, errors をリセット

echo "$STATE_FILE" > /tmp/ralph/state/latest
```

### Step 5: ユーザーへの案内

```
状態ファイルを生成しました: <STATE_FILE>
- 前回の完了済みタスク: N 件 (保持)
- 新規タスク: M 件
- 受入条件: X 件 (既存) + Y 件 (新規)

`/d-ralph` で実装を開始できます。
```
