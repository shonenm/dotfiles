#!/bin/bash
# Claude Code Status Plugin for SketchyBar
# Displays Claude Code session status with aerospace workspace integration

STATUS_DIR="/tmp/claude_status"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# VS Code にフォーカスした時、そのプロジェクトの通知を解除
handle_focus_change() {
  # フォーカス中のウィンドウを取得
  local focused
  focused=$(aerospace list-windows --focused --json 2>/dev/null)

  local app_name
  app_name=$(echo "$focused" | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  # VS Code 以外は無視
  [[ "$app_name" != "Code" ]] && return

  local title
  title=$(echo "$focused" | jq -r '.[0]["window-title"] // ""' 2>/dev/null)

  # コンテナ名を抽出 (例: "開発コンテナー: syntopic-dev @ remote" → "syntopic-dev")
  local container_name
  container_name=$(echo "$title" | sed -n 's/.*開発コンテナー: \(.*\) @.*/\1/p')

  # コンテナ名があればそれを使用、なければプロジェクト名
  local proj
  if [[ -n "$container_name" ]]; then
    proj="$container_name"
  else
    # "— projectname [" のパターンでプロジェクト名を抽出
    proj=$(echo "$title" | sed -n 's/.*— \([^ []*\).*/\1/p')
  fi

  [[ -z "$proj" ]] && return

  # そのプロジェクトの状態ファイルがあれば削除
  if [[ -f "$STATUS_DIR/${proj}.json" ]]; then
    rm -f "$STATUS_DIR/${proj}.json"
  fi
}

# 状態がないか、全て none の場合は非表示
has_active_status() {
  [[ ! -d "$STATUS_DIR" ]] && return 1

  local found=0
  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local st
    st=$(jq -r '.status // "none"' "$f" 2>/dev/null)
    if [[ "$st" == "idle" || "$st" == "permission" ]]; then
      found=1
      break
    fi
  done

  [[ $found -eq 1 ]]
}

# アクティブな待機セッションをカウント
count_sessions() {
  local idle_count=0
  local permission_count=0

  [[ ! -d "$STATUS_DIR" ]] && echo "0 0" && return

  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local st
    st=$(jq -r '.status // "none"' "$f" 2>/dev/null)

    case "$st" in
      idle) ((idle_count++)) ;;
      permission) ((permission_count++)) ;;
    esac
  done

  echo "$idle_count $permission_count"
}

# プロジェクト一覧を取得（ワークスペース付き）
get_project_list() {
  [[ ! -d "$STATUS_DIR" ]] && return

  for f in "$STATUS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local st proj ws
    st=$(jq -r '.status // "none"' "$f" 2>/dev/null)
    proj=$(jq -r '.project // "unknown"' "$f" 2>/dev/null)
    ws=$(jq -r '.workspace // ""' "$f" 2>/dev/null)

    [[ "$st" == "idle" || "$st" == "permission" ]] || continue

    if [[ -n "$ws" ]]; then
      echo "${ws}:${proj}"
    else
      echo "$proj"
    fi
  done
}

# メイン処理
main() {
  # フォーカス/ワークスペース変更時、通知解除を処理
  if [[ "$SENDER" == "front_app_switched" || "$SENDER" == "aerospace_workspace_change" ]]; then
    handle_focus_change
  fi

  if ! has_active_status; then
    # アクティブなセッションなし - アイテムを非表示
    sketchybar --set claude drawing=off
    return
  fi

  read -r idle_count permission_count <<< "$(count_sessions)"
  local total=$((idle_count + permission_count))

  # プロジェクトリスト（最初の2つまで表示）
  local projects
  projects=$(get_project_list | head -2 | tr '\n' ' ' | sed 's/ $//')

  # 色とアイコンを決定
  local icon_color label

  if (( permission_count > 0 )); then
    # 承認待ちあり - オレンジ
    icon_color="0xffffb86c"
  else
    # 入力待ちのみ - 黄色
    icon_color="0xfff1fa8c"
  fi

  # ラベル: 数字 + プロジェクト名（短縮）
  if (( total == 1 )); then
    label="$projects"
  else
    label="$total"
  fi

  sketchybar --set claude \
    drawing=on \
    icon.color="$icon_color" \
    label="$label" \
    label.color="$icon_color"
}

main
