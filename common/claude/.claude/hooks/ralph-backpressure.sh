#!/usr/bin/env bash
# Ralph v2 Backpressure Hook (PostToolUse)
# Write/Edit/MultiEdit 後に型チェック/lint/テストを自動実行し、
# エラーを additionalContext として Claude に即時フィードバック。
# 依存: jq
set -euo pipefail

# jq が使えない場合はフェイルオープン
if ! command -v jq &>/dev/null; then
  exit 0
fi

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

# プロジェクトルート検出: file_path から上方向に package.json または .git を探索
find_project_root() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    dir="$(dirname "$dir")"
    if [[ -f "$dir/package.json" ]] || [[ -d "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
  done
  return 1
}

project_root="$(find_project_root "$file_path" || echo "")"

# 拡張子を取得
ext="${file_path##*.}"
basename_file="$(basename "$file_path")"

errors=""

# エラー収集ヘルパー
append_error() {
  local label="$1" output="$2"
  if [[ -n "$output" ]]; then
    errors="${errors}[${label}]\n${output}\n\n"
  fi
}

case "$ext" in
  ts|tsx)
    # tsc --noEmit
    if [[ -n "$project_root" ]] && [[ -f "$project_root/package.json" ]]; then
      tsc_output=""
      if [[ -f "$project_root/node_modules/.bin/tsc" ]]; then
        tsc_output="$(cd "$project_root" && timeout 10 ./node_modules/.bin/tsc --noEmit --pretty false 2>&1)" || true
      elif command -v npx &>/dev/null; then
        tsc_output="$(cd "$project_root" && timeout 10 npx tsc --noEmit --pretty false 2>&1)" || true
      fi
      append_error "tsc" "$tsc_output"

      # eslint --fix (修正後に残るエラーのみ報告)
      if [[ -f "$project_root/node_modules/.bin/eslint" ]]; then
        cd "$project_root"
        timeout 10 ./node_modules/.bin/eslint --fix "$file_path" &>/dev/null || true
        eslint_output="$(timeout 10 ./node_modules/.bin/eslint --no-fix "$file_path" --format compact 2>&1)" || true
        append_error "eslint" "$eslint_output"
      fi

      # prettier --write
      if [[ -f "$project_root/node_modules/.bin/prettier" ]]; then
        timeout 5 "$project_root/node_modules/.bin/prettier" --write "$file_path" &>/dev/null || true
      fi

      # 対応するテストファイルを実行
      test_file=""
      dir="$(dirname "$file_path")"
      stem="$(basename "$file_path" ".$ext")"
      for candidate in \
        "${dir}/${stem}.test.${ext}" \
        "${dir}/${stem}.spec.${ext}" \
        "${dir}/__tests__/${stem}.test.${ext}" \
        "${dir}/__tests__/${stem}.spec.${ext}"; do
        if [[ -f "$candidate" ]]; then
          test_file="$candidate"
          break
        fi
      done
      if [[ -n "$test_file" ]]; then
        test_output=""
        if [[ -f "$project_root/node_modules/.bin/vitest" ]]; then
          test_output="$(cd "$project_root" && timeout 15 ./node_modules/.bin/vitest run "$test_file" --reporter=verbose 2>&1)" || true
        elif [[ -f "$project_root/node_modules/.bin/jest" ]]; then
          test_output="$(cd "$project_root" && timeout 15 ./node_modules/.bin/jest "$test_file" --no-coverage 2>&1)" || true
        fi
        # テスト成功時は報告しない
        if [[ $? -ne 0 ]] && [[ -n "$test_output" ]]; then
          append_error "test ($test_file)" "$test_output"
        fi
      fi
    fi
    ;;
  py)
    # py_compile
    if command -v python3 &>/dev/null; then
      py_output="$(timeout 10 python3 -m py_compile "$file_path" 2>&1)" || true
      append_error "py_compile" "$py_output"
    elif command -v python &>/dev/null; then
      py_output="$(timeout 10 python -m py_compile "$file_path" 2>&1)" || true
      append_error "py_compile" "$py_output"
    fi
    # ruff --fix
    if command -v ruff &>/dev/null; then
      timeout 5 ruff check --fix "$file_path" &>/dev/null || true
      ruff_output="$(timeout 5 ruff check "$file_path" 2>&1)" || true
      append_error "ruff" "$ruff_output"
    fi
    ;;
  sh|bash)
    if command -v shellcheck &>/dev/null; then
      sc_output="$(timeout 10 shellcheck "$file_path" 2>&1)" || true
      append_error "shellcheck" "$sc_output"
    fi
    ;;
  sql)
    # supabase/migrations/ 配下なら supabase db lint
    if [[ "$file_path" == *"supabase/migrations/"* ]] && command -v supabase &>/dev/null; then
      sql_output="$(timeout 10 supabase db lint 2>&1)" || true
      append_error "supabase db lint" "$sql_output"
    fi
    ;;
  json)
    # jq による構文検証
    json_output="$(jq empty "$file_path" 2>&1)" || true
    append_error "json syntax" "$json_output"
    ;;
  *)
    # サポート外の拡張子はスキップ
    exit 0
    ;;
esac

# エラーがなければスキップ
if [[ -z "$errors" ]]; then
  exit 0
fi

# 出力が長すぎる場合は切り詰める
max_lines=50
line_count="$(printf '%b' "$errors" | wc -l)"
if [[ "$line_count" -gt "$max_lines" ]]; then
  errors="$(printf '%b' "$errors" | head -n "$max_lines")"
  errors="${errors}\n... (truncated, ${line_count} total lines)"
fi

printf '{"additionalContext":"[Ralph Backpressure] Errors detected:\\n%s"}\n' \
  "$(printf '%b' "$errors" | jq -Rs . | sed 's/^"//;s/"$//')"
