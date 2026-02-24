---
name: ralph
description: 自律的反復開発ループを開始します。状態ファイルがあればタスクグラフに従い、なければ skip-plan モードで実行します。
user-invocable: true
disable-model-invocation: true
arguments: "<prompt>"
allowed-tools: Bash, Read, Write, Edit, MultiEdit, Glob, Grep, Task, WebFetch, WebSearch
hooks:
  PreToolUse:
    - matcher: "AskUserQuestion|EnterPlanMode"
      hooks:
        - type: command
          command: "echo '{\"decision\":\"block\",\"reason\":\"Ralph autonomous mode. Do not ask questions — make your own judgment and proceed.\"}' && exit 2"
  Stop:
    - hooks:
        - type: command
          command: "bash -c '$HOME/.claude/hooks/ralph-stop-hook.sh'"
          timeout: 15
  PostToolUse:
    - matcher: "Write|Edit|MultiEdit"
      hooks:
        - type: command
          command: "bash -c '$HOME/.claude/hooks/ralph-backpressure.sh'"
          timeout: 15
---

# Ralph - 自律的反復開発ループ

状態ファイルに基づいてタスクグラフを順に実装し、全受入条件を検証して完了する自律ループ。
ユーザーに対して一切質問しない。判断は全て自律で行う。

## 引数

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `<prompt>` | (任意) | タスクの説明 (skip-plan モード用) |
| `--max-iterations N` | 25 | 最大反復回数 |

### 使用例

```
/ralph                                           # ralph-plan で生成済みの状態ファイルを使用
/ralph "Fix the authentication bug in src/auth.ts"  # skip-plan モード
/ralph "Add unit tests for the utils module" --max-iterations 10
```

## 手順

### 1. 状態ファイルの読み込み

マニフェストファイル `/tmp/ralph_session_manifest` を確認:

```bash
if [ -f /tmp/ralph_session_manifest ]; then
  STATE_FILE="$(cat /tmp/ralph_session_manifest)"
  cat "$STATE_FILE"
fi
```

### 2a. 状態ファイルが存在する場合 (Plan モード)

状態ファイルの内容を読み込み、`task_graph` と `acceptance_criteria` を把握する。
ユーザーに以下を報告してから作業を開始:

```
Ralph loop started (plan mode).
- Tasks: <total_tasks> tasks
- ACs: <total_acs> acceptance criteria
- Max iterations: <max_iterations>
- State file: <STATE_FILE>
```

### 2b. 状態ファイルが存在しない場合 (Skip-plan モード)

引数からタスク説明と `--max-iterations` をパースし、最小限の状態ファイルを生成:

```bash
SESSION_HASH="$(echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5sum 2>/dev/null | cut -c1-12 || echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5 2>/dev/null | cut -c1-12)"
STATE_FILE="/tmp/ralph_${SESSION_HASH}.json"

jq -n \
  --arg sid "$SESSION_HASH" \
  --arg prompt "<パースしたprompt>" \
  --argjson max_iterations <パースしたmax_iterations> \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    session_id: $sid,
    phase: "implementation",
    max_iterations: $max_iterations,
    iteration: 0,
    created_at: $created_at,
    acceptance_criteria: [],
    task_graph: [],
    context_report: $prompt,
    stall_hashes: [],
    completion_token: "RALPH_COMPLETE",
    errors: []
  }' > "$STATE_FILE"

echo "$STATE_FILE" > /tmp/ralph_session_manifest
```

ユーザーに報告:

```
Ralph loop started (skip-plan mode).
- Task: <prompt>
- Max iterations: <max_iterations>
- State file: <STATE_FILE>
```

### 3. タスク実行

以下のガイドラインに従って実装する:

- task_graph が存在する場合: 依存関係 (`deps`) に従い、`status: "pending"` のタスクから順に実装
- task_graph が空の場合 (skip-plan): prompt に基づいて自律的にタスクを分解し実装
- テスト駆動: 可能な限りテストを先に書き、テストが通ることを確認してから次に進む
- 自己検証: 各ステップで型チェック、lint、テスト実行を活用
- 段階的実装: 小さなステップに分割し、各ステップで動作確認
- エラー対応: PostToolUse hook からのバックプレッシャーに即座に対応する
- 3回連続で同じエラーに遭遇した場合はアプローチを変更する
- task_graph に記載されていないファイルの変更は最小限にする

### 4. タスク完了時の処理

各タスク完了時に以下を実行:

1. 状態ファイルの該当タスクの status を `"done"` に更新:

```bash
STATE_FILE="$(cat /tmp/ralph_session_manifest)"
jq '.task_graph |= map(if .id == "T-N" then .status = "done" else . end)' \
  "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
```

2. atomic commit を作成:

```bash
git add -A && git commit -m "ralph: T-N <タスク名>"
```

### 5. 検証フェーズ

全タスク完了後 (または skip-plan でタスク実装完了後):

1. 状態ファイルの phase を `"verification"` に更新
2. acceptance_criteria の各 AC を検証:
   - `verification_command` が定義されていればそれを実行
   - 実行結果に基づいて `verified` を `true` / `false` に更新
3. 未達成の AC があれば修正作業を行い、再検証
4. 全 AC 通過で次のステップへ

### 6. 完了

全 AC 通過後:

1. 変更のサマリーを出力
2. 完了トークンを出力 (Stop hook がこれを検知してループを終了する):

```
RALPH_COMPLETE
```

## ループの仕組み

Ralph は Claude Code の Stop hook を使用してループを実現する:

1. Claude が停止しようとするたびに Stop hook が実行される
2. Stop hook はマニフェスト経由で状態ファイルを確認
3. phase が implementation/verification で未完了なら `decision: "block"` を返す
4. Claude は停止せずに作業を継続する
5. 完了トークン検出、max_iterations 到達、stall 3回連続で終了

## 中断

ループを中断するには `/ralph-cancel` を実行する。
