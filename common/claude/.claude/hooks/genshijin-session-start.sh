#!/usr/bin/env bash
# genshijin SessionStart Hook
# プラグイン同梱 SKILL.md を additionalContext に注入し、
# 通常レベルの圧縮を全セッションで既定化する。
# プラグイン未インストール時はサイレントに exit。
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

SKILL_FILE=""
for candidate in \
  "$HOME"/.claude/plugins/cache/genshijin/genshijin/*/skills/genshijin/SKILL.md \
  "$HOME"/.claude/plugins/marketplaces/genshijin/skills/genshijin/SKILL.md
do
  [[ -f "$candidate" ]] || continue
  SKILL_FILE="$candidate"
  break
done

[[ -z "$SKILL_FILE" ]] && exit 0

instruction="以降このセッションの全応答に genshijin 通常レベルの圧縮ルールを既定適用する。コード・エラーメッセージ・コミット/PR 本文は圧縮対象外。ユーザーが「原始人やめて」「通常モード」と言うか /genshijin 丁寧|極限 で明示的に切り替えるまで維持。ルール本文:"

printf '%s\n\n%s' "$instruction" "$(cat "$SKILL_FILE")" \
  | jq -Rs '{additionalContext: .}'
