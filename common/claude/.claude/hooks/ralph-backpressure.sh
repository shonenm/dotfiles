#!/usr/bin/env bash
# Ralph Backpressure Hook (PostToolUse)
# Write/Edit 後に型チェック/lint を自動実行し、エラーを additionalContext として返す。
# 依存: jq
set -euo pipefail

# stdin から hook JSON を読み取る
input="$(cat)"

# tool_input.file_path を取得
file_path="$(echo "$input" | jq -r '.tool_input.file_path // empty')"

if [[ -z "$file_path" ]]; then
  exit 0
fi

# ファイルが存在しない場合はスキップ (削除操作等)
if [[ ! -f "$file_path" ]]; then
  exit 0
fi

# 拡張子を取得
ext="${file_path##*.}"

check_output=""
check_cmd=""

case "$ext" in
  ts|tsx)
    # package.json が存在するプロジェクトのみ
    project_dir="$file_path"
    while [[ "$project_dir" != "/" ]]; do
      project_dir="$(dirname "$project_dir")"
      if [[ -f "$project_dir/package.json" ]]; then
        if [[ -f "$project_dir/node_modules/.bin/tsc" ]]; then
          check_cmd="$project_dir/node_modules/.bin/tsc --noEmit --pretty false"
          check_output="$(cd "$project_dir" && timeout 10 $check_cmd 2>&1)" || true
        elif command -v npx &>/dev/null; then
          check_cmd="npx tsc --noEmit --pretty false"
          check_output="$(cd "$project_dir" && timeout 10 $check_cmd 2>&1)" || true
        fi
        break
      fi
    done
    ;;
  py)
    if command -v python3 &>/dev/null; then
      check_cmd="python3 -m py_compile"
      check_output="$(timeout 10 python3 -m py_compile "$file_path" 2>&1)" || true
    elif command -v python &>/dev/null; then
      check_cmd="python -m py_compile"
      check_output="$(timeout 10 python -m py_compile "$file_path" 2>&1)" || true
    fi
    ;;
  sh|bash)
    if command -v shellcheck &>/dev/null; then
      check_cmd="shellcheck"
      check_output="$(timeout 10 shellcheck "$file_path" 2>&1)" || true
    fi
    ;;
  *)
    # サポート外の拡張子はスキップ
    exit 0
    ;;
esac

# チェックコマンドが存在しない場合はスキップ
if [[ -z "$check_cmd" ]]; then
  exit 0
fi

# エラーがなければスキップ
if [[ -z "$check_output" ]]; then
  exit 0
fi

# エラーを additionalContext として返す
# 出力が長すぎる場合は先頭を切り詰める
max_lines=50
line_count="$(echo "$check_output" | wc -l)"
if [[ "$line_count" -gt "$max_lines" ]]; then
  check_output="$(echo "$check_output" | head -n "$max_lines")"
  check_output="${check_output}
... (truncated, ${line_count} total lines)"
fi

printf '{"additionalContext":"[Ralph Backpressure] %s errors in %s:\\n%s"}\n' \
  "$check_cmd" "$file_path" "$(echo "$check_output" | jq -Rs .| sed 's/^"//;s/"$//')"
