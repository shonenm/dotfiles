#!/usr/bin/env bash
# Ralph Stop Hook
# stdin から JSON を受け取り、ループ継続/終了を判定する。
# 依存: jq, git
set -euo pipefail

# stdin から hook JSON を読み取る
input="$(cat)"

# stop_hook_active チェック (最重要)
# stop_hook_active=true の場合、状態ファイルがなければ即 exit 0
# これにより Ralph 以外のコンテキストで無限ループを防止
stop_hook_active="$(echo "$input" | jq -r '.stop_hook_active // false')"

# セッション ID の取得
session_id="${CLAUDE_SESSION_ID:-}"
if [[ -z "$session_id" ]]; then
  # session_id が取得できない場合は通常停止
  exit 0
fi

state_file="/tmp/ralph_${session_id}.json"

# 判定 1: stop_hook_active=true で状態ファイルなし → 即 exit 0
if [[ "$stop_hook_active" == "true" ]] && [[ ! -f "$state_file" ]]; then
  exit 0
fi

# 判定 2: 状態ファイルなし → exit 0 (Ralph 非稼働)
if [[ ! -f "$state_file" ]]; then
  exit 0
fi

# 以降は状態ファイルが存在する場合のロジック
state="$(cat "$state_file")"
completion_promise="$(echo "$state" | jq -r '.completion_promise')"
max_iterations="$(echo "$state" | jq -r '.max_iterations')"
iteration="$(echo "$state" | jq -r '.iteration')"
no_progress_count="$(echo "$state" | jq -r '.no_progress_count')"
last_diff_hash="$(echo "$state" | jq -r '.last_diff_hash')"

# cleanup: 状態ファイルを削除
cleanup() {
  rm -f "$state_file"
}

# 判定 3: last_assistant_message に completion_promise を含む → cleanup → exit 0
last_message="$(echo "$input" | jq -r '.last_assistant_message // ""')"
if [[ -n "$last_message" ]] && echo "$last_message" | grep -qF "$completion_promise"; then
  cleanup
  exit 0
fi

# 判定 4: iteration >= max_iterations → cleanup → exit 0
if [[ "$iteration" -ge "$max_iterations" ]]; then
  cleanup
  printf '{"decision":"block","reason":"Max iterations (%s) reached. Stopping Ralph loop."}\n' "$max_iterations"
  # max iterations 到達でも block で理由を伝えてから停止
  # 実際にはこの後 cleanup しているので次回は状態ファイルなしで exit 0
  cleanup
  exit 0
fi

# 判定 5: no-progress 検知
current_diff_hash="$(git diff --stat 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1 || echo "no-git")"
# md5sum が使えない環境 (macOS) では md5 を使う
if [[ "$current_diff_hash" == "no-git" ]] || [[ -z "$current_diff_hash" ]]; then
  current_diff_hash="$(git diff --stat 2>/dev/null | md5 2>/dev/null || echo "unknown")"
fi

if [[ "$current_diff_hash" == "$last_diff_hash" ]]; then
  no_progress_count=$((no_progress_count + 1))
else
  no_progress_count=0
fi

if [[ "$no_progress_count" -ge 3 ]]; then
  cleanup
  exit 0
fi

# 判定 6: 未完了 → iteration++, 状態更新, block で継続
iteration=$((iteration + 1))

# 状態ファイル更新
jq -n \
  --arg prompt "$(echo "$state" | jq -r '.prompt')" \
  --arg completion_promise "$completion_promise" \
  --argjson max_iterations "$max_iterations" \
  --argjson iteration "$iteration" \
  --argjson no_progress_count "$no_progress_count" \
  --arg last_diff_hash "$current_diff_hash" \
  '{
    prompt: $prompt,
    completion_promise: $completion_promise,
    max_iterations: $max_iterations,
    iteration: $iteration,
    no_progress_count: $no_progress_count,
    last_diff_hash: $last_diff_hash
  }' > "$state_file"

# block で Claude にループ継続を指示
printf '{"decision":"block","reason":"Ralph iteration %d/%d. Continue working on the task. When complete, include the text: %s"}\n' \
  "$iteration" "$max_iterations" "$completion_promise"
