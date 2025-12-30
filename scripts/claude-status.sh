#!/bin/bash
# Claude Code 状態管理スクリプト（複数セッション対応 + aerospace 連携）
# Usage:
#   claude-status.sh set <project> <status> [session_id] [tty]
#   claude-status.sh get <project>
#   claude-status.sh list
#   claude-status.sh clear <project>
#   claude-status.sh cleanup
#   claude-status.sh find-workspace <project>

set -euo pipefail

STATUS_DIR="/tmp/claude_status"
STALE_THRESHOLD=3600  # 1時間以上更新なしは削除

# aerospace でウィンドウからプロジェクトのワークスペースを検索
find_workspace() {
  local project="$1"

  # aerospace がなければスキップ
  command -v aerospace &>/dev/null || return

  local result

  # 1. VS Code ウィンドウを検索（プロジェクト名またはコンテナ名でマッチング）
  result=$(aerospace list-windows --all --json 2>/dev/null | \
    jq -r --arg proj "$project" '
      .[] |
      select(.["app-name"] == "Code") |
      select(
        (.["window-title"] | contains("— " + $proj + " [")) or
        (.["window-title"] | contains("— " + $proj + " —")) or
        (.["window-title"] | contains("開発コンテナー: " + $proj + " @"))
      ) |
      .["window-id"]
    ' 2>/dev/null | head -1)

  # 2. VS Code が見つからなければターミナルウィンドウを検索
  if [[ -z "$result" ]]; then
    result=$(aerospace list-windows --all --json 2>/dev/null | \
      jq -r --arg proj "$project" '
        .[] |
        select(.["app-name"] | test("Ghostty|Terminal|iTerm|WezTerm|Alacritty|kitty"; "i")) |
        select(.["window-title"] == $proj) |
        .["window-id"]
      ' 2>/dev/null | head -1)
  fi

  if [[ -n "$result" ]]; then
    # ウィンドウIDからワークスペースを取得（全ワークスペースを検索）
    local all_workspaces
    all_workspaces=$(aerospace list-workspaces --all 2>/dev/null)
    for ws in $all_workspaces; do
      if aerospace list-windows --workspace "$ws" --json 2>/dev/null | \
         jq -e --arg wid "$result" '.[] | select(.["window-id"] == ($wid | tonumber))' &>/dev/null; then
        echo "$ws"
        return
      fi
    done
  fi
}

# 現在フォーカス中のプロジェクトを取得
get_focused_project() {
  command -v aerospace &>/dev/null || return

  local focused
  focused=$(aerospace list-windows --focused --json 2>/dev/null)

  local app_name
  app_name=$(echo "$focused" | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  local title
  title=$(echo "$focused" | jq -r '.[0]["window-title"] // ""' 2>/dev/null)

  case "$app_name" in
    "Code")
      # VS Code: コンテナ名またはプロジェクト名を抽出
      local container_name
      container_name=$(echo "$title" | sed -n 's/.*開発コンテナー: \(.*\) @.*/\1/p')
      if [[ -n "$container_name" ]]; then
        echo "$container_name"
      else
        echo "$title" | sed -n 's/.*— \([^ []*\).*/\1/p'
      fi
      ;;
    "Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      # ターミナル: ウィンドウタイトルからディレクトリ名を抽出
      basename "$title" 2>/dev/null
      ;;
  esac
}

# 状態を設定
set_status() {
  local project="$1"
  local status="$2"
  local session_id="${3:-}"
  local tty="${4:-}"

  mkdir -p "$STATUS_DIR"

  # 通知対象のステータス（idle, permission, complete）で、すでにそのプロジェクトにフォーカス中なら通知しない
  if [[ "$status" == "idle" || "$status" == "permission" || "$status" == "complete" ]]; then
    local focused_project
    focused_project=$(get_focused_project 2>/dev/null || echo "")
    if [[ "$focused_project" == "$project" ]]; then
      # フォーカス中なので通知不要、既存の通知があれば削除
      rm -f "$STATUS_DIR/${project}.json"
      if command -v sketchybar &>/dev/null; then
        sketchybar --trigger claude_status_change &>/dev/null || true
      fi
      return
    fi
  fi

  # ワークスペースを検索
  local workspace
  workspace=$(find_workspace "$project" 2>/dev/null || echo "")

  cat > "$STATUS_DIR/${project}.json" <<EOF
{
  "status": "$status",
  "project": "$project",
  "workspace": "$workspace",
  "session_id": "$session_id",
  "tty": "$tty",
  "updated": $(date +%s)
}
EOF

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi
}

# 状態を取得
get_status() {
  local project="$1"
  local file="$STATUS_DIR/${project}.json"

  if [[ -f "$file" ]]; then
    cat "$file"
  else
    echo "{}"
  fi
}

# 全セッションをリスト
list_status() {
  [[ ! -d "$STATUS_DIR" ]] && echo "[]" && return

  local files=("$STATUS_DIR"/*.json)
  if [[ ! -e "${files[0]}" ]]; then
    echo "[]"
    return
  fi

  cat "$STATUS_DIR"/*.json 2>/dev/null | jq -s '.'
}

# 状態をクリア
clear_status() {
  local project="$1"
  rm -f "$STATUS_DIR/${project}.json"

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi
}

# 古いセッションをクリーンアップ
cleanup() {
  [[ ! -d "$STATUS_DIR" ]] && return

  local now
  now=$(date +%s)

  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local updated
    updated=$(jq -r '.updated // 0' "$f" 2>/dev/null || echo "0")
    if (( now - updated > STALE_THRESHOLD )); then
      rm -f "$f"
    fi
  done

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi
}

# メイン
case "${1:-}" in
  set)
    set_status "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    ;;
  get)
    get_status "${2:-}"
    ;;
  list)
    list_status
    ;;
  clear)
    clear_status "${2:-}"
    ;;
  cleanup)
    cleanup
    ;;
  find-workspace)
    find_workspace "${2:-}"
    ;;
  *)
    echo "Usage: claude-status.sh <set|get|list|clear|cleanup|find-workspace> [args]" >&2
    exit 1
    ;;
esac
