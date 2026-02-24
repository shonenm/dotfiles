#!/usr/bin/env bash
# Ralph v2 Session Context Hook (SessionStart)
# セッション開始時にプロジェクト情報を自動収集し additionalContext で返す。
# 依存: jq, git
set -euo pipefail

# jq が使えない場合はフェイルオープン
if ! command -v jq &>/dev/null; then
  exit 0
fi

context=""

append() {
  local label="$1" content="$2"
  if [[ -n "$content" ]]; then
    context="${context}## ${label}\n${content}\n\n"
  fi
}

# プロジェクト構造 (tree -L 2, node_modules 等除外)
if command -v tree &>/dev/null; then
  tree_output="$(tree -L 2 --dirsfirst -I 'node_modules|.git|dist|build|.next|__pycache__|.venv|coverage' 2>/dev/null | head -50)" || true
  append "Project Structure" "$tree_output"
fi

# Git 情報
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  branch="$(git branch --show-current 2>/dev/null || echo "detached")"
  log="$(git log --oneline -10 2>/dev/null)" || true
  uncommitted="$(git diff --stat 2>/dev/null)" || true
  staged="$(git diff --staged --stat 2>/dev/null)" || true

  git_info="Branch: ${branch}"
  if [[ -n "$log" ]]; then
    git_info="${git_info}\n\nRecent commits:\n${log}"
  fi
  if [[ -n "$uncommitted" ]]; then
    git_info="${git_info}\n\nUncommitted changes:\n${uncommitted}"
  fi
  if [[ -n "$staged" ]]; then
    git_info="${git_info}\n\nStaged changes:\n${staged}"
  fi
  append "Git" "$git_info"
fi

# package.json サマリー
if [[ -f "package.json" ]]; then
  pkg_info=""
  scripts="$(jq -r '.scripts // {} | to_entries[] | "  \(.key): \(.value)"' package.json 2>/dev/null | head -20)" || true
  deps="$(jq -r '.dependencies // {} | keys[]' package.json 2>/dev/null)" || true
  dev_deps="$(jq -r '.devDependencies // {} | keys[]' package.json 2>/dev/null)" || true

  if [[ -n "$scripts" ]]; then
    pkg_info="Scripts:\n${scripts}"
  fi
  if [[ -n "$deps" ]]; then
    pkg_info="${pkg_info}\n\nDependencies: $(echo "$deps" | tr '\n' ', ' | sed 's/,$//')"
  fi
  if [[ -n "$dev_deps" ]]; then
    pkg_info="${pkg_info}\n\nDevDependencies: $(echo "$dev_deps" | tr '\n' ', ' | sed 's/,$//')"
  fi
  append "package.json" "$pkg_info"
fi

# Supabase 情報
if [[ -d "supabase/migrations" ]]; then
  migrations="$(ls -1 supabase/migrations/ 2>/dev/null | tail -10)" || true
  tables=""
  if [[ -f "supabase/database.types.ts" ]] || [[ -f "src/database.types.ts" ]]; then
    types_file="$(ls supabase/database.types.ts src/database.types.ts 2>/dev/null | head -1)"
    if [[ -n "$types_file" ]]; then
      tables="$(grep -oP '(?<=")[a-z_]+(?="\s*:\s*\{)' "$types_file" 2>/dev/null | sort -u | head -30)" || true
    fi
  fi
  supabase_info=""
  if [[ -n "$migrations" ]]; then
    supabase_info="Recent migrations:\n${migrations}"
  fi
  if [[ -n "$tables" ]]; then
    supabase_info="${supabase_info}\n\nTables: $(echo "$tables" | tr '\n' ', ' | sed 's/,$//')"
  fi
  append "Supabase" "$supabase_info"
fi

# tsconfig.json 設定
if [[ -f "tsconfig.json" ]]; then
  ts_info="$(jq -r '{target: .compilerOptions.target, module: .compilerOptions.module, strict: .compilerOptions.strict, moduleResolution: .compilerOptions.moduleResolution} | to_entries[] | select(.value != null) | "  \(.key): \(.value)"' tsconfig.json 2>/dev/null)" || true
  append "tsconfig.json" "$ts_info"
fi

# コンテキストがなければスキップ
if [[ -z "$context" ]]; then
  exit 0
fi

printf '{"additionalContext":"[Session Context]\\n%s"}\n' \
  "$(printf '%b' "$context" | jq -Rs . | sed 's/^"//;s/"$//')"
