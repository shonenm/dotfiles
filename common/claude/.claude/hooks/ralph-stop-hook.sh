#!/usr/bin/env bash
# Ralph v2 Stop Hook
# stdin から JSON を受け取り、ループ継続/終了を判定する。
# 状態ファイルはセッション固有の active ファイル経由で発見する。
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

# セッション固有の active ファイルから状態ファイルのパスを取得
# CLAUDE_SESSION_ID が利用可能ならセッション単位でスコーピング
# 利用不可の場合は旧マニフェストにフォールバック
active_file=""
state_file=""

if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
  _session_hash="$(echo "$CLAUDE_SESSION_ID" | md5sum 2>/dev/null | cut -c1-12 || echo "$CLAUDE_SESSION_ID" | md5 2>/dev/null | cut -c1-12)"
  active_file="/tmp/ralph/state/active_${_session_hash}"
  if [[ -f "$active_file" ]]; then
    state_file="$(cat "$active_file")"
  fi
else
  # フォールバック: 旧マニフェスト (CLAUDE_SESSION_ID 非対応環境)
  active_file="/tmp/ralph/state/session_manifest"
  if [[ -f "$active_file" ]]; then
    state_file="$(cat "$active_file")"
  fi
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

# archive: cleanup 前に状態ファイルを保存
archive() {
  mkdir -p /tmp/ralph/state
  local archive_file
  archive_file="/tmp/ralph/state/archive_$(date +%Y%m%d_%H%M%S).json"
  cp "$state_file" "$archive_file"
}

# cleanup: 状態ファイルと active ファイルを削除
cleanup() {
  rm -f "$state_file"
  rm -f "$active_file"
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

# 判定 3: last_assistant_message に completion_token を含む
# ただし全 AC が verified でなければ block (AC が空の場合は通過)
last_message="$(echo "$input" | jq -r '.last_assistant_message // ""')"
if [[ -n "$last_message" ]] && echo "$last_message" | grep -qF "$completion_token"; then
  total_ac="$(echo "$state" | jq '[.acceptance_criteria[]?] | length')"
  unverified_ac="$(echo "$state" | jq '[.acceptance_criteria[]? | select(.verified != true)] | length')"
  if [[ "$total_ac" -gt 0 ]] && [[ "$unverified_ac" -gt 0 ]]; then
    # AC 未検証 → completion_token を無視して block
    unverified_list="$(echo "$state" | jq -r '[.acceptance_criteria[]? | select(.verified != true) | .id] | join(", ")')"
    iteration=$((iteration + 1))
    state="$(echo "$state" | jq --argjson iter "$iteration" '.iteration = $iter')"
    update_state "$state"
    printf '{"decision":"block","reason":"RALPH_COMPLETE rejected: unverified ACs: %s. Verify all ACs before completing. Iteration %d/%d."}\n' \
      "$unverified_list" "$iteration" "$max_iterations"
    exit 0
  fi
  archive
  cleanup
  exit 0
fi

# 判定 4: iteration >= max_iterations → エラー記録 → cleanup → exit 0
if [[ "$iteration" -ge "$max_iterations" ]]; then
  state="$(echo "$state" | jq --arg reason "Max iterations ($max_iterations) reached" \
    '.errors += [$reason]')"
  update_state "$state"
  archive
  cleanup
  exit 0
fi

# 判定 5: stall detection (task 完了数の変化で判定)
# git diff --stat ベースの旧実装は read-only タスク (research/verification) で
# コード変更がなくても stall と誤判定していた。task_graph の完了数を見ることで
# 「タスクが進んでいるか」という本質的な進捗を正確に捉える。
current_done_count="$(echo "$state" | jq '[.task_graph[]? | select(.status == "done")] | length')"
last_done_count="$(echo "$state" | jq '.last_done_count // 0')"
stall_count="$(echo "$state" | jq '.stall_hashes | length')"

if [[ "$current_done_count" -gt "$last_done_count" ]]; then
  # タスク完了数が増加 → 進捗あり、stall_hashes リセット
  state="$(echo "$state" | jq --argjson n "$current_done_count" '.last_done_count = $n | .stall_hashes = []')"
  stall_count=0
else
  # 変化なし → stall カウント増加
  state="$(echo "$state" | jq '.stall_hashes += ["stall"]')"
  stall_count=$((stall_count + 1))
fi

if [[ "$stall_count" -ge 3 ]]; then
  state="$(echo "$state" | jq '.errors += ["No progress detected for 3 consecutive iterations"]')"
  update_state "$state"
  archive
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
