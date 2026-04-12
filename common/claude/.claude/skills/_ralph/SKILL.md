---
name: _ralph
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

## ルールオーバーライド

Ralph ループ内では以下のグローバルルールを上書きする:

- 「テスト・ビルド・デプロイスクリプトはユーザーの確認なく実行しない」→ テスト・ビルドはユーザー確認なしで実行する。AC 検証に必要なコマンドは全て自律実行すること。
- 「git push はユーザーが明示的に要求しない限り実行しない」→ このルールは維持。git push は実行しない。
- git commit は task_graph にコミットタスクが明示的に含まれている場合のみ実行する。含まれていない場合はコミットを一切行わない。

## 引数

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `<prompt>` | (任意) | タスクの説明 (skip-plan モード用) |
| `--max-iterations N` | 25 | 最大反復回数 |

### 使用例

```
/_ralph                                           # _ralph-plan で生成済みの状態ファイルを使用
/_ralph "Fix the authentication bug in src/auth.ts"  # skip-plan モード
/_ralph "Add unit tests for the utils module" --max-iterations 10
```

## 手順

### 1. 状態ファイルの読み込み

セッション固有の active ファイル、または cross-session discovery ファイルから状態ファイルを特定する:

```bash
SESSION_HASH="$(echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5sum 2>/dev/null | cut -c1-12 || echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5 2>/dev/null | cut -c1-12)"
ACTIVE_FILE="/tmp/ralph/state/active_${SESSION_HASH}"

# 1. 既存の active ファイルを確認 (中断からの再開)
# 2. なければ latest_state を確認 (ralph-plan/ralph-resume から引き継ぎ)
if [ -f "$ACTIVE_FILE" ]; then
  STATE_FILE="$(cat "$ACTIVE_FILE")"
elif [ -f /tmp/ralph/state/latest ]; then
  STATE_FILE="$(cat /tmp/ralph/state/latest)"
  echo "$STATE_FILE" > "$ACTIVE_FILE"
  rm -f /tmp/ralph/state/latest
fi

if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
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
mkdir -p /tmp/ralph/state
STATE_FILE="/tmp/ralph/state/${SESSION_HASH}.json"
ACTIVE_FILE="/tmp/ralph/state/active_${SESSION_HASH}"

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

echo "$STATE_FILE" > "$ACTIVE_FILE"
```

ユーザーに報告:

```
Ralph loop started (skip-plan mode).
- Task: <prompt>
- Max iterations: <max_iterations>
- State file: <STATE_FILE>
```

### 3. タスク実行

各タスクを実装する前に必ず **Synthesis ステップ** を行う:

#### Synthesis ステップ（着手前に必須）

実装に着手する前に以下を確認し、「どのファイルのどの部分をどう変更するか」を1〜3文で具体的にまとめる:

1. 対象ファイルの現在のコードを読む
2. 既存パターン・命名規則・依存関係を確認する
3. 変更方針を自分の言葉で明示する（ファイルパス・関数名・行番号まで特定する）

例（良い）:
> `src/auth/middleware.ts` の `validateToken` 関数（L42）に null チェックを追加する。
> `Session.user` が undefined の場合は 401 を返す。既存の `isExpired` チェック（L38）の直後に挿入する。

例（悪い）:
> コンテキストレポートに基づいて認証モジュールを修正する。

Synthesis を書いてから実装に着手する。

---

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
SESSION_HASH="$(echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5sum 2>/dev/null | cut -c1-12 || echo "${CLAUDE_SESSION_ID:-$(date +%s)}" | md5 2>/dev/null | cut -c1-12)"
STATE_FILE="$(cat "/tmp/ralph/state/active_${SESSION_HASH}")"
jq '.task_graph |= map(if .id == "T-N" then .status = "done" else . end)' \
  "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
```

2. task_graph に `tool_task_id` が記録されている場合、TaskUpdate ツールで UI タスクも完了にする:
   - `taskId`: 状態ファイルの `task_graph[N].tool_task_id`
   - `status`: `"completed"`
   - `tool_task_id` がない場合はスキップ（Task ツール未使用環境での後方互換性のため）

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
2. Stop hook はセッション固有の active ファイル経由で状態ファイルを確認
3. phase が implementation/verification で未完了なら `decision: "block"` を返す
4. Claude は停止せずに作業を継続する
5. 完了トークン検出、max_iterations 到達、stall 3回連続で終了

## 中断

ループを中断するには `/_ralph-cancel` を実行する。
