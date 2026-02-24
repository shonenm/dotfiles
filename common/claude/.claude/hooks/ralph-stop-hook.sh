#!/usr/bin/env bash
# Ralph v2 Stop Hook
# stdin から JSON を受け取り、ループ継続/終了を判定する。
# 状態ファイルは /tmp/ralph_session_manifest 経由で発見する。
# 依存: jq, git
set -euo pipefail

# jq が使えない場合はフェイルオープン
if ! command -v jq &>/dev/null; then
  exit 0
fi

# stdin から hook JSON を読み取る
input="$(cat)"

# stop_hook_active チェック (最重要)
# stop_hook_active=true の場合、マニフェストまたは状態ファイルがなければ即 exit 0
# これにより Ralph 以外のコンテキストで無限ループを防止
stop_hook_active="$(echo "$input" | jq -r '.stop_hook_active // false')"

# マニフェストから状態ファイルのパスを取得
manifest="/tmp/ralph_session_manifest"
state_file=""
if [[ -f "$manifest" ]]; then
  state_file="$(cat "$manifest")"
fi

# 判定 1: stop_hook_active=true で状態ファイルなし → 即 exit 0
if [[ "$stop_hook_active" == "true" ]] && { [[ -z "$state_file" ]] || [[ ! -f "$state_file" ]]; }; then
  exit 0
fi

# 判定 2: 状態ファイルなし → exit 0 (Ralph 非稼働)
if [[ -z "$state_file" ]] || [[ ! -f "$state_file" ]]; then
  exit 0
fi

# 以降は状態ファイルが存在する場合のロジック
state="$(cat "$state_file")"
phase="$(echo "$state" | jq -r '.phase // "implementation"')"
completion_token="$(echo "$state" | jq -r '.completion_token // .completion_promise // "RALPH_COMPLETE"')"
max_iterations="$(echo "$state" | jq -r '.max_iterations')"
iteration="$(echo "$state" | jq -r '.iteration')"

# phase チェック: implementation/verification 以外は pass through
if [[ "$phase" != "implementation" ]] && [[ "$phase" != "verification" ]]; then
  exit 0
fi

# cleanup: 状態ファイルとマニフェストを削除
cleanup() {
  rm -f "$state_file"
  rm -f "$manifest"
}

# atomic な状態ファイル更新
update_state() {
  local new_state="$1"
  local tmp_file="${state_file}.tmp.$$"
  echo "$new_state" > "$tmp_file" && mv "$tmp_file" "$state_file"
}

# 進捗情報を生成
progress_info() {
  local total_tasks done_tasks pending_ac
  total_tasks="$(echo "$state" | jq '.task_graph | length // 0')"
  done_tasks="$(echo "$state" | jq '[.task_graph[]? | select(.status == "done")] | length')"
  pending_ac="$(echo "$state" | jq '[.acceptance_criteria[]? | select(.verified == false)] | length')"
  printf "Tasks: %d/%d done, Pending ACs: %d" "$done_tasks" "$total_tasks" "$pending_ac"
}

# 判定 3: last_assistant_message に completion_token を含む → cleanup → exit 0
last_message="$(echo "$input" | jq -r '.last_assistant_message // ""')"
if [[ -n "$last_message" ]] && echo "$last_message" | grep -qF "$completion_token"; then
  cleanup
  exit 0
fi

# 判定 4: iteration >= max_iterations → エラー記録 → cleanup → exit 0
if [[ "$iteration" -ge "$max_iterations" ]]; then
  state="$(echo "$state" | jq --arg reason "Max iterations ($max_iterations) reached" \
    '.errors += [$reason]')"
  update_state "$state"
  cleanup
  exit 0
fi

# 判定 5: stall detection (stall_hashes 配列で管理)
compute_diff_hash() {
  local hash
  hash="$(git diff --stat 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1 || true)"
  if [[ -z "$hash" ]]; then
    hash="$(git diff --stat 2>/dev/null | md5 2>/dev/null || echo "unknown")"
  fi
  echo "$hash"
}

current_diff_hash="$(compute_diff_hash)"
stall_hashes="$(echo "$state" | jq -r '.stall_hashes // []')"
stall_count="$(echo "$stall_hashes" | jq 'length')"
last_hash="$(echo "$stall_hashes" | jq -r '.[-1] // ""')"

if [[ "$current_diff_hash" == "$last_hash" ]]; then
  # 同一ハッシュ → stall_hashes に追加
  state="$(echo "$state" | jq --arg h "$current_diff_hash" '.stall_hashes += [$h]')"
  stall_count=$((stall_count + 1))
else
  # 変化あり → stall_hashes リセット
  state="$(echo "$state" | jq --arg h "$current_diff_hash" '.stall_hashes = [$h]')"
  stall_count=1
fi

if [[ "$stall_count" -ge 4 ]]; then
  # 4エントリ = 3回連続同一 (初回+3回)
  state="$(echo "$state" | jq '.errors += ["No progress detected for 3 consecutive iterations"]')"
  update_state "$state"
  cleanup
  exit 0
fi

# 判定 6: 未完了 → iteration++, 状態更新, block で継続
iteration=$((iteration + 1))
state="$(echo "$state" | jq --argjson iter "$iteration" '.iteration = $iter')"
update_state "$state"

progress="$(progress_info)"
printf '{"decision":"block","reason":"Ralph iteration %d/%d. %s. Continue working. When complete, output: %s"}\n' \
  "$iteration" "$max_iterations" "$progress" "$completion_token"
