#!/usr/bin/env bash
# block-tmp.sh - PreToolUse(Bash) guard
# Claude が実行する Bash command が /tmp を literal で触れたら deny する。
# dotfiles は /tmp 依存を撤廃し XDG (XDG_RUNTIME_DIR/XDG_CACHE_HOME/XDG_STATE_HOME)
# に統一済み。docker 共有は $DOTFILES_SHARED_DIR 経由で literal /tmp を含まない。
# ponytail: literal /tmp path のみ deny。tmp 文字列・$TMPDIR・/var/tmp は素通し。
set -euo pipefail

input="$(cat)"

# Bash 以外は対象外
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[[ "$tool" != "Bash" ]] && exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ -z "$cmd" ]] && exit 0

# literal /tmp path のみ検出 (/tmp/ , /tmp 末尾)。tmp 単語・$TMPDIR・/var/tmp 等は素通し。
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:]"'"'"'=:(`>])/tmp(/|$|[[:space:]"'"'"'):;,)|&>])'; then
  echo "Blocked: /tmp への直接アクセスは禁止。XDG ディレクトリを使用してください (\$XDG_RUNTIME_DIR / \$XDG_CACHE_HOME / \$XDG_STATE_HOME)。一時ファイルは mktemp (TMPDIR 尊重) を使用。docker 共有は \$DOTFILES_SHARED_DIR。" >&2
  exit 2
fi

exit 0
