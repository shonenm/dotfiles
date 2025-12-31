#!/bin/bash
# Claude Code Status Plugin for SketchyBar
# Updates workspace badges based on Claude session status (window-id based)

STATUS_DIR="/tmp/claude_status"

# バッジ色（service mode と同じオレンジで固定）
BADGE_COLOR="0xffff6600"

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

# 全ワークスペースのバッジを更新
update_workspace_badges() {
  # アクティブなワークスペースを取得
  local workspaces
  workspaces=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)

  # 各ワークスペースのバッジを更新
  for ws in $workspaces; do
    # このワークスペースの通知数をカウント（bash 3.2互換）
    local total=0
    if [[ -d "$STATUS_DIR" ]]; then
      for f in "$STATUS_DIR"/window_*.json; do
        [[ -f "$f" ]] || continue
        local file_ws file_st
        file_ws=$(jq -r '.workspace // ""' "$f" 2>/dev/null)
        file_st=$(jq -r '.status // "none"' "$f" 2>/dev/null)

        [[ "$file_ws" != "$ws" ]] && continue
        [[ "$file_st" == "idle" || "$file_st" == "permission" || "$file_st" == "complete" ]] && ((total++))
      done
    fi

    if [[ $total -eq 0 ]]; then
      # 通知なし: 空表示（固定幅スペースは維持）
      sketchybar --set "space.${ws}_badge" \
        label="" \
        label.drawing=off \
        background.drawing=off 2>/dev/null
    else
      # 1件以上: 数字表示
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
}

# メイン処理
main() {
  # フォーカス/ワークスペース変更時、通知解除を処理
  if [[ "$SENDER" == "front_app_switched" || "$SENDER" == "aerospace_workspace_change" ]]; then
    handle_focus_change
  fi

  # バッジを更新
  update_workspace_badges
}

main
