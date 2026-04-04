#!/usr/bin/env bash
# ralph-precompact.sh - PreCompact hook
# stdout がコンパクト指示に追記されるため、アクティブな Ralph セッションの
# 状態ファイルパスを出力し、コンパクト後もループが継続できるようにする。
# 依存: jq
set -euo pipefail

SESSION_HASH="$(echo "${CLAUDE_SESSION_ID:-}" | md5sum 2>/dev/null | cut -c1-12 \
  || echo "${CLAUDE_SESSION_ID:-}" | md5 2>/dev/null | cut -c1-12)"

[[ -z "$SESSION_HASH" ]] && exit 0

ACTIVE_FILE="/tmp/ralph/state/active_${SESSION_HASH}"
[[ ! -f "$ACTIVE_FILE" ]] && exit 0

STATE_FILE="$(cat "$ACTIVE_FILE")"
[[ ! -f "$STATE_FILE" ]] && exit 0

# jq が使えない場合はフェイルオープン
if ! command -v jq &>/dev/null; then
  echo "Ralph state file: ${STATE_FILE}"
  exit 0
fi

PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null)
PENDING=$(jq '[.task_graph[] | select(.status == "pending")] | length' "$STATE_FILE" 2>/dev/null)
DONE=$(jq '[.task_graph[] | select(.status == "done")] | length' "$STATE_FILE" 2>/dev/null)

cat <<EOF
IMPORTANT: An active Ralph autonomous loop exists.
State file: ${STATE_FILE}
Phase: ${PHASE}
Tasks: ${DONE} done, ${PENDING} pending

After compaction, resume the Ralph loop by reading the state file above and
continuing from where you left off.
EOF
