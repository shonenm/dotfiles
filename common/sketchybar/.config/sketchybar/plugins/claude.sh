#!/bin/bash
# Claude Code Status Plugin for SketchyBar
# Updates workspace/app badges based on Claude session status (window-id based)

source "$CONFIG_DIR/plugins/colors.sh"

STATUS_DIR="/tmp/claude_status"

# バッジ色（service mode と同じオレンジ）
BADGE_COLOR="$SERVICE_MODE_COLOR"

# VS Code / ターミナルにフォーカスした時、そのウィンドウの通知を解除
handle_focus_change() {
  local focused
  focused=$(aerospace list-windows --focused --json 2>/dev/null)

  local app_name
  app_name=$(echo "$focused" | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  local window_id
  window_id=$(echo "$focused" | jq -r '.[0]["window-id"] // ""' 2>/dev/null)

  # VS Code またはターミナルアプリの場合のみ処理
  case "$app_name" in
    "Code"|"Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      ;;
    *)
      return
      ;;
  esac

  [[ -z "$window_id" ]] && return

  # そのウィンドウの状態ファイルがあれば削除（session_id付きファイルも含む）
  rm -f "$STATUS_DIR"/window_${window_id}_*.json 2>/dev/null
}

# バッジを更新（ワークスペース + アプリ）
update_badges() {
  local focused_ws
  focused_ws=$(aerospace list-workspaces --focused 2>/dev/null)

  # アクティブなワークスペースを取得
  local workspaces
  workspaces=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)

  # 通知を収集（bash 3.2互換のため連想配列は使わない）
  # ワークスペースごとの通知数
  local ws_counts=""
  # アプリごとの通知数（フォーカス中WSのみ）
  local app_counts=""

  if [[ -d "$STATUS_DIR" ]]; then
    for f in "$STATUS_DIR"/window_*.json; do
      [[ -f "$f" ]] || continue
      local file_ws file_st file_app
      file_ws=$(jq -r '.workspace // ""' "$f" 2>/dev/null)
      file_st=$(jq -r '.status // "none"' "$f" 2>/dev/null)
      file_app=$(jq -r '.app_name // ""' "$f" 2>/dev/null)

      # 対象ステータスのみ
      [[ "$file_st" == "idle" || "$file_st" == "permission" || "$file_st" == "complete" ]] || continue

      if [[ "$file_ws" == "$focused_ws" ]]; then
        # フォーカス中のワークスペース → アプリバッジ用
        if [[ -n "$file_app" ]]; then
          app_counts="$app_counts|$file_app"
        fi
      else
        # 他のワークスペース → ワークスペースバッジ用
        ws_counts="$ws_counts|$file_ws"
      fi
    done
  fi

  # ワークスペースバッジを更新
  for ws in $workspaces; do
    local total=0
    # ws_counts から該当ワークスペースをカウント
    local remaining="$ws_counts"
    while [[ "$remaining" == *"|$ws"* ]]; do
      ((total++))
      remaining="${remaining/|$ws/}"
    done

    if [[ $total -eq 0 ]]; then
      sketchybar --set "space.${ws}_badge" \
        label="" \
        label.drawing=off \
        background.drawing=off 2>/dev/null
    else
      sketchybar --set "space.${ws}_badge" \
        label="$total" \
        label.drawing=on \
        label.color=0xffffffff \
        label.width=14 \
        label.align=center \
        label.y_offset=1 \
        background.drawing=on \
        background.color="$BADGE_COLOR" 2>/dev/null
    fi
  done

  # フォーカス中WSの通知がある場合はそのWSのバッジをクリア
  if [[ -n "$app_counts" ]]; then
    sketchybar --set "space.${focused_ws}_badge" \
      label="" \
      label.drawing=off \
      background.drawing=off 2>/dev/null
  fi

  # アプリバッジを更新（フォーカス中ワークスペースのアプリ）
  local focused_apps
  focused_apps=$(aerospace list-windows --workspace "$focused_ws" --format '%{app-name}' 2>/dev/null | sort -u)

  for app in $focused_apps; do
    local app_total=0
    local remaining="$app_counts"
    while [[ "$remaining" == *"|$app"* ]]; do
      ((app_total++))
      remaining="${remaining/|$app/}"
    done

    # アイテム名（スペースとドットをアンダースコアに）
    local item_name="app.$(echo "$app" | tr ' .' '_')_badge"

    if [[ $app_total -eq 0 ]]; then
      sketchybar --set "$item_name" \
        label="" \
        label.drawing=off \
        background.drawing=off 2>/dev/null
    else
      sketchybar --set "$item_name" \
        label="$app_total" \
        label.drawing=on \
        label.color=0xffffffff \
        background.drawing=on \
        background.color="$BADGE_COLOR" 2>/dev/null
    fi
  done
}

# メイン処理
main() {
  # フォーカス/ワークスペース変更時、通知解除を処理
  if [[ "$SENDER" == "front_app_switched" || "$SENDER" == "aerospace_workspace_change" ]]; then
    handle_focus_change
  fi

  # バッジを更新
  update_badges
}

main
