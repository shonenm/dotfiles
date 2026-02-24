---
name: ralph
description: 自律的反復開発ループを開始します。完了条件を満たすまで Claude が自動的に作業を繰り返します。
user-invocable: true
disable-model-invocation: true
arguments: "<prompt> [--max-iterations N] [--promise TEXT]"
hooks:
  Stop:
    - hooks:
        - type: command
          command: "bash -c '$HOME/.claude/hooks/ralph-stop-hook.sh'"
  PostToolUse:
    - matcher: "Write|Edit|MultiEdit"
      hooks:
        - type: command
          command: "bash -c '$HOME/.claude/hooks/ralph-backpressure.sh'"
          timeout: 10
---

# Ralph - 自律的反復開発ループ

完了条件を満たすまで Claude が自動的に作業を繰り返す開発ループを開始します。

## 引数

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `<prompt>` | (必須) | 実行するタスクの説明 |
| `--max-iterations N` | 50 | 最大反復回数 |
| `--promise TEXT` | RALPH_COMPLETE | 完了時に出力するプロミス文字列 |

### 使用例

```
/ralph "Create a REST API with CRUD operations" --max-iterations 20 --promise "DONE"
/ralph "Fix the authentication bug in src/auth.ts"
/ralph "Add unit tests for the utils module" --max-iterations 10
```

## 手順

### 1. 引数パース

ユーザーの入力から以下を抽出:

- `prompt`: タスクの説明 (引用符で囲まれた部分、またはフラグ以外のすべてのテキスト)
- `--max-iterations`: 数値。省略時は 50
- `--promise`: 文字列。省略時は "RALPH_COMPLETE"

### 2. 状態ファイルの作成

以下の Bash コマンドで状態ファイルを作成する。`CLAUDE_SESSION_ID` 環境変数を使用:

```bash
jq -n \
  --arg prompt "<パースしたprompt>" \
  --arg completion_promise "<パースしたpromise>" \
  --argjson max_iterations <パースしたmax_iterations> \
  --argjson iteration 0 \
  --argjson no_progress_count 0 \
  --arg last_diff_hash "" \
  '{
    prompt: $prompt,
    completion_promise: $completion_promise,
    max_iterations: $max_iterations,
    iteration: $iteration,
    no_progress_count: $no_progress_count,
    last_diff_hash: $last_diff_hash
  }' > "/tmp/ralph_${CLAUDE_SESSION_ID}.json"
```

状態ファイルの作成に成功したことを確認し、ユーザーに Ralph ループの開始を通知する:

```
Ralph loop started.
- Task: <prompt>
- Max iterations: <max_iterations>
- Completion promise: <promise>
- State file: /tmp/ralph_<session_id>.json
```

### 3. タスク実行

以下のガイドラインに従ってタスクを実行する:

- テスト駆動: 可能な限りテストを先に書き、実装後にテストを実行して検証する
- 自己検証: 各ステップで自分の出力を検証する。型チェック、lint、テスト実行を活用
- 段階的実装: 大きなタスクは小さなステップに分割し、各ステップで動作確認を行う
- エラー対応: PostToolUse hook からのバックプレッシャー (型エラー/lint エラー) に即座に対応する

### 4. 完了

タスクが完了したら、以下を実行:

1. すべてのテストが通ることを確認
2. 変更のサマリーを出力
3. プロミス文字列を出力する (Stop hook がこれを検知してループを終了する):

```
<completion_promise>
```

これにより Stop hook が状態ファイルをクリーンアップし、ループが正常終了する。

## ループの仕組み

Ralph は Claude Code の Stop hook を使用してループを実現する:

1. Claude が作業を完了して停止しようとするたびに Stop hook が実行される
2. Stop hook は状態ファイルを確認し、タスクが未完了であれば `decision: "block"` を返す
3. これにより Claude は停止せずに作業を継続する
4. 完了条件 (プロミス文字列の検出、最大反復回数到達、進捗なし3回連続) を満たすとループが終了する

## 中断

ループを中断するには `/ralph-cancel` を実行する。
