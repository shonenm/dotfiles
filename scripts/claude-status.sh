#!/bin/bash
# Claude Code 状態管理スクリプト（複数セッション対応 + aerospace 連携）
# Usage:
#   claude-status.sh set <project> <status> [session_id] [tty] [window_id]
#   claude-status.sh get <window_id>
#   claude-status.sh list
#   claude-status.sh clear <window_id>
#   claude-status.sh cleanup
#   claude-status.sh find-workspace <window_id>

set -euo pipefail

STATUS_DIR="/tmp/claude_status"
STALE_THRESHOLD=3600  # 1時間以上更新なしは削除

# aerospace でウィンドウIDからワークスペースを検索
find_workspace() {
  local window_id="$1"

  # aerospace がなければスキップ
  command -v aerospace &>/dev/null || return

  # window_id が空なら終了
  [[ -z "$window_id" ]] && return

  # ウィンドウIDからワークスペースを取得（全ワークスペースを検索）
  local all_workspaces
  all_workspaces=$(aerospace list-workspaces --all 2>/dev/null)
  for ws in $all_workspaces; do
    if aerospace list-windows --workspace "$ws" --json 2>/dev/null | \
       jq -e --arg wid "$window_id" '.[] | select(.["window-id"] == ($wid | tonumber))' &>/dev/null; then
      echo "$ws"
      return
    fi
  done
}

# プロジェクト名からウィンドウIDを検索（Pattern 2-4用フォールバック）
find_window_by_project() {
  local project="$1"

  command -v aerospace &>/dev/null || return

  # リモートプレフィックス除去 (host:project → project)
  local search_project="${project#*:}"

  local result=""

  # 1. VS Code: コンテナ名で検索
  result=$(aerospace list-windows --all --json 2>/dev/null | \
    jq -r --arg proj "$search_project" '
      .[] | select(.["app-name"] == "Code") |
      select(.["window-title"] | contains("開発コンテナー: " + $proj + " @")) |
      .["window-id"]
    ' 2>/dev/null | head -1)

  # 2. VS Code: プロジェクト名で検索
  if [[ -z "$result" ]]; then
    result=$(aerospace list-windows --all --json 2>/dev/null | \
      jq -r --arg proj "$search_project" '
        .[] | select(.["app-name"] == "Code") |
        select(
          (.["window-title"] | contains("— " + $proj + " [")) or
          (.["window-title"] | contains("— " + $proj + " —"))
        ) | .["window-id"]
      ' 2>/dev/null | head -1)
  fi

  # 3. ターミナル: タイトルで検索
  if [[ -z "$result" ]]; then
    result=$(aerospace list-windows --all --json 2>/dev/null | \
      jq -r --arg proj "$search_project" '
        .[] |
        select(.["app-name"] | test("Ghostty|Terminal|iTerm|WezTerm|Alacritty|kitty"; "i")) |
        select(.["window-title"] == $proj) |
        .["window-id"]
      ' 2>/dev/null | head -1)
  fi

  echo "$result"
}

# 現在フォーカス中のウィンドウIDを取得
get_focused_window_id() {
  command -v aerospace &>/dev/null || return

  local focused
  focused=$(aerospace list-windows --focused --json 2>/dev/null)

  local app_name
  app_name=$(echo "$focused" | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  # VS Code またはターミナルアプリの場合のみwindow-idを返す
  case "$app_name" in
    "Code"|"Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      echo "$focused" | jq -r '.[0]["window-id"] // ""' 2>/dev/null
      ;;
  esac
}

# 状態を設定
set_status() {
  local project="$1"
  local status="$2"
  local session_id="${3:-}"
  local tty="${4:-}"
  local window_id="${5:-}"

  mkdir -p "$STATUS_DIR"

  # window_id が空なら取得を試みる
  if [[ -z "$window_id" ]]; then
    # まずプロジェクト名からウィンドウ検索（Pattern 2-4用、より正確）
    window_id=$(find_window_by_project "$project" 2>/dev/null || echo "")
  fi

  # フォールバック: フォーカス中のウィンドウを使用（Pattern 1用）
  if [[ -z "$window_id" ]]; then
    window_id=$(get_focused_window_id 2>/dev/null || echo "")
  fi

  # window_id がまだ空なら終了（識別できない）
  if [[ -z "$window_id" ]]; then
    return
  fi

  # 通知対象のステータス（idle, permission, complete）で、すでにそのウィンドウにフォーカス中なら通知しない
  if [[ "$status" == "idle" || "$status" == "permission" || "$status" == "complete" ]]; then
    local focused_window_id
    focused_window_id=$(get_focused_window_id 2>/dev/null || echo "")
    if [[ "$focused_window_id" == "$window_id" ]]; then
      # フォーカス中なので通知不要、既存の通知があれば削除
      rm -f "$STATUS_DIR/window_${window_id}.json"
      if command -v sketchybar &>/dev/null; then
        sketchybar --trigger claude_status_change &>/dev/null || true
      fi
      return
    fi
  fi

  # ワークスペースを検索
  local workspace
  workspace=$(find_workspace "$window_id" 2>/dev/null || echo "")

  cat > "$STATUS_DIR/window_${window_id}.json" <<EOF
{
  "status": "$status",
  "project": "$project",
  "window_id": "$window_id",
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
  local window_id="$1"
  local file="$STATUS_DIR/window_${window_id}.json"

  if [[ -f "$file" ]]; then
    cat "$file"
  else
    echo "{}"
  fi
}

# 全セッションをリスト
list_status() {
  [[ ! -d "$STATUS_DIR" ]] && echo "[]" && return

  local files=("$STATUS_DIR"/window_*.json)
  if [[ ! -e "${files[0]}" ]]; then
    echo "[]"
    return
  fi

  cat "$STATUS_DIR"/window_*.json 2>/dev/null | jq -s '.'
}

# 状態をクリア
clear_status() {
  local window_id="$1"
  rm -f "$STATUS_DIR/window_${window_id}.json"

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

  for f in "$STATUS_DIR"/window_*.json; do
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
    set_status "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
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
