#!/usr/bin/env bash
# claude-cwd-changed.sh - CwdChanged hook
# ディレクトリ変更時に .envrc を読み込み、以降の Bash ツール実行用の
# 環境変数を CLAUDE_ENV_FILE に書き出す。direnv がある場合はそちらを優先。
# 依存: jq (オプション), direnv (オプション)
set -euo pipefail

# CLAUDE_ENV_FILE が設定されていなければ何もしない
[[ -z "${CLAUDE_ENV_FILE:-}" ]] && exit 0

# stdin から new_cwd を取得
if command -v jq &>/dev/null; then
  NEW_CWD=$(jq -r '.new_cwd // empty' 2>/dev/null) || exit 0
else
  # jq がなければ grep で簡易パース
  INPUT=$(cat)
  NEW_CWD=$(echo "$INPUT" | grep -oP '"new_cwd"\s*:\s*"\K[^"]+' 2>/dev/null) || exit 0
fi

[[ -z "$NEW_CWD" || ! -d "$NEW_CWD" ]] && exit 0

ENVRC="${NEW_CWD}/.envrc"
[[ ! -f "$ENVRC" ]] && exit 0

# direnv が使える場合は direnv exec で正確な環境を取得
if command -v direnv &>/dev/null; then
  TMPFILE=$(mktemp)
  trap 'rm -f "$TMPFILE"' EXIT

  # direnv exec で環境変数を列挙
  if direnv exec "$NEW_CWD" env > "$TMPFILE" 2>/dev/null; then
    # shell 内部変数・direnv 管理変数を除外してエクスポート
    while IFS='=' read -r key rest; do
      # 空キー・制御変数・direnv 管理変数をスキップ
      case "$key" in
        ''|_|SHLVL|OLDPWD|PWD|HOME|USER|SHELL|TERM*|DIRENV_*|BASH_*|ZSH_*) continue ;;
      esac
      # キー名が正当な識別子でなければスキップ
      [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      printf 'export %s=%s\n' "$key" "$(printf '%q' "$rest")" >> "$CLAUDE_ENV_FILE"
    done < "$TMPFILE"
  fi
else
  # direnv がなければ .envrc の単純な export 行のみ抽出
  grep -E '^export [A-Za-z_][A-Za-z0-9_]*=' "$ENVRC" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true
fi
