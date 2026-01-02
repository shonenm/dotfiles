#!/bin/bash
# Claude Code 状態管理スクリプト（複数セッション対応 + aerospace/tmux 連携）
# Usage:
#   claude-status.sh set <project> <status> [session_id] [tty] [window_id] [container_name] [tmux_session] [tmux_window_index]
#   claude-status.sh get <window_id>
#   claude-status.sh list
#   claude-status.sh clear <window_id>
#   claude-status.sh clear-tmux <tmux_session> <tmux_window_index>
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

# コンテナ名からウィンドウIDを検索（Pattern 2, 4用: DEVCONTAINER_NAME）
find_window_by_container() {
  local container_name="$1"

  command -v aerospace &>/dev/null || return
  [[ -z "$container_name" ]] && return

  # " @" suffix で完全一致（syntopic-dev と syntopic-dev-review を区別）
  aerospace list-windows --all --json 2>/dev/null | \
    jq -r --arg name "$container_name" '
      .[] | select(.["app-name"] == "Code") |
      select(.["window-title"] | contains("開発コンテナー: " + $name + " @")) |
      .["window-id"]
    ' 2>/dev/null | head -1
}

# プロジェクト名からウィンドウIDを検索（Pattern 3用、Pattern 1のフォールバック）
find_window_by_project() {
  local project="$1"

  command -v aerospace &>/dev/null || return

  # リモートプレフィックス除去 (host:project → project)
  local search_project="${project#*:}"

  local result=""

  # 1. VS Code: ワークスペース名で検索
  result=$(aerospace list-windows --all --json 2>/dev/null | \
    jq -r --arg proj "$search_project" '
      .[] | select(.["app-name"] == "Code") |
      select(
        (.["window-title"] | contains("— " + $proj + " [")) or
        (.["window-title"] | contains("— " + $proj + " —"))
      ) | .["window-id"]
    ' 2>/dev/null | head -1)

  # 2. ターミナル: タイトル完全一致
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

# window_id から app_name を取得
get_app_name_by_window_id() {
  local window_id="$1"
  command -v aerospace &>/dev/null || return
  [[ -z "$window_id" ]] && return

  aerospace list-windows --all --json 2>/dev/null | \
    jq -r --arg wid "$window_id" '
      .[] | select(.["window-id"] == ($wid | tonumber)) | .["app-name"]
    ' 2>/dev/null | head -1
}

# 状態を設定
set_status() {
  local project="$1"
  local status="$2"
  local session_id="${3:-}"
  local tty="${4:-}"
  local window_id="${5:-}"
  local container_name="${6:-}"
  local tmux_session="${7:-}"
  local tmux_window_index="${8:-}"

  mkdir -p "$STATUS_DIR"

  # window_id 取得優先順位:
  # 1. container_name → VS Code "開発コンテナー: $NAME @" 検索 (Pattern 2, 4)
  # 2. project名 → VS Code/Terminal 検索 (Pattern 3)
  # 3. focused window (Pattern 1)

  if [[ -z "$window_id" && -n "$container_name" ]]; then
    window_id=$(find_window_by_container "$container_name" 2>/dev/null || echo "")
  fi

  if [[ -z "$window_id" ]]; then
    window_id=$(find_window_by_project "$project" 2>/dev/null || echo "")
  fi

  if [[ -z "$window_id" ]]; then
    window_id=$(get_focused_window_id 2>/dev/null || echo "")
  fi

  # window_id がまだ空なら終了（識別できない）
  if [[ -z "$window_id" ]]; then
    return
  fi

  # 重複通知チェック: 同じwindow_id + statusの通知が2秒以内にあればスキップ
  local now_sec
  now_sec=$(date +%s)
  for existing_file in "$STATUS_DIR"/window_${window_id}_*.json; do
    [[ -f "$existing_file" ]] || continue
    local existing_status existing_updated
    existing_status=$(jq -r '.status // ""' "$existing_file" 2>/dev/null || echo "")
    existing_updated=$(jq -r '.updated // 0' "$existing_file" 2>/dev/null || echo "0")
    if [[ "$existing_status" == "$status" ]] && (( now_sec - existing_updated < 2 )); then
      return
    fi
  done

  # 注意: フォーカス中のウィンドウでも通知ファイルを作成する
  # claude.sh の handle_notification_arrived() が6秒タイマーで消去を管理

  # ワークスペースを検索
  local workspace
  workspace=$(find_workspace "$window_id" 2>/dev/null || echo "")

  # app_name を取得
  local app_name
  app_name=$(get_app_name_by_window_id "$window_id" 2>/dev/null || echo "")

  # window_${window_id}_${timestamp}.json 形式でユニークに
  local timestamp
  timestamp=$(date +%s%N)

  cat > "$STATUS_DIR/window_${window_id}_${timestamp}.json" <<EOF
{
  "status": "$status",
  "project": "$project",
  "window_id": "$window_id",
  "workspace": "$workspace",
  "app_name": "$app_name",
  "session_id": "$session_id",
  "tty": "$tty",
  "tmux_session": "$tmux_session",
  "tmux_window_index": "$tmux_window_index",
  "updated": $(date +%s)
}
EOF

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi

  # tmux通知（セッションがある場合のみ）
  if [[ -n "$tmux_session" ]]; then
    tmux refresh-client -S 2>/dev/null || true
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
  # session_id付きファイルも含めて削除
  rm -f "$STATUS_DIR"/window_${window_id}_*.json

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi
}

# tmuxウィンドウの通知を消去
clear_tmux_window() {
  local tmux_session="$1"
  local tmux_window_index="$2"

  [[ -z "$tmux_session" || -z "$tmux_window_index" ]] && return
  [[ ! -d "$STATUS_DIR" ]] && return

  for f in "$STATUS_DIR"/window_*.json; do
    [[ -f "$f" ]] || continue
    local file_session file_window
    file_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
    file_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

    if [[ "$file_session" == "$tmux_session" && "$file_window" == "$tmux_window_index" ]]; then
      rm -f "$f"
    fi
  done

  # SketchyBar 通知
  if command -v sketchybar &>/dev/null; then
    sketchybar --trigger claude_status_change &>/dev/null || true
  fi

  # tmuxを更新
  tmux refresh-client -S 2>/dev/null || true
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

  # window_id キャッシュファイルもクリーンアップ（1時間以上前のもの）
  for f in /tmp/claude_window_*; do
    [[ -f "$f" ]] || continue
    local file_mtime
    file_mtime=$(stat -f %m "$f" 2>/dev/null || echo "0")
    if (( now - file_mtime > STALE_THRESHOLD )); then
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
    set_status "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}" "${9:-}"
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
  clear-tmux)
    clear_tmux_window "${2:-}" "${3:-}"
    ;;
  *)
    echo "Usage: claude-status.sh <set|get|list|clear|clear-tmux|cleanup|find-workspace> [args]" >&2
    exit 1
    ;;
esac
