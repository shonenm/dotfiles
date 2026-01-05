#!/bin/bash
# Claude Code Status Plugin for SketchyBar
# Updates workspace/app badges based on Claude session status (window-id based)

source "$CONFIG_DIR/plugins/colors.sh"

STATUS_DIR="/tmp/claude_status"
FOCUS_STATE_FILE="/tmp/sketchybar_window_focus"

# バッジ色
BADGE_COLOR="$SERVICE_MODE_COLOR"
BADGE_COLOR_DIM="$DIM_BADGE_COLOR"

# tmux情報を考慮して通知を削除するヘルパー関数
# 引数: window_id [tmux_session] [tmux_window]
# session/windowが指定されればそれを使用、なければ現在位置を取得
remove_notifications_for_window() {
  local target_window_id="$1"
  local target_session="${2:-}"
  local target_window="${3:-}"

  # 引数がなければ現在のtmux位置を取得
  if [[ -z "$target_session" || -z "$target_window" ]]; then
    target_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")
    target_window=$(tmux display-message -p '#I' 2>/dev/null || echo "")
  fi

  for f in "$STATUS_DIR"/window_${target_window_id}_*.json; do
    [[ -f "$f" ]] || continue
    local notif_session notif_window
    notif_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
    notif_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

    if [[ -z "$notif_session" || -z "$notif_window" ]]; then
      # tmux情報なし → 削除OK
      rm -f "$f"
    elif [[ -n "$target_session" && -n "$target_window" ]]; then
      # tmux情報あり → 指定位置と一致する場合のみ削除
      if [[ "$notif_session" == "$target_session" && "$notif_window" == "$target_window" ]]; then
        rm -f "$f"
      fi
    fi
  done
}

# 5秒タイマーを開始（既存タイマーはキャンセル）
start_clear_timer() {
  local window_id="$1"

  # 既存タイマーをキャンセル
  if [[ -f "$FOCUS_STATE_FILE" ]]; then
    local prev_pid
    prev_pid=$(cut -d: -f3 "$FOCUS_STATE_FILE" 2>/dev/null)
    [[ -n "$prev_pid" ]] && kill "$prev_pid" 2>/dev/null
  fi

  local now
  now=$(date +%s)

  # 現在のtmux位置を記録（タイマー実行時に使用）
  local cur_session cur_window
  cur_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  cur_window=$(tmux display-message -p '#I' 2>/dev/null || echo "")

  # 5秒後に自動消去するバックグラウンドタイマーを開始
  (
    sleep 5
    # tmux情報を考慮して削除
    for f in "$STATUS_DIR"/window_${window_id}_*.json; do
      [[ -f "$f" ]] || continue
      local notif_session notif_window
      notif_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
      notif_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

      if [[ -z "$notif_session" || -z "$notif_window" ]]; then
        rm -f "$f"
      elif [[ "$notif_session" == "$cur_session" && "$notif_window" == "$cur_window" ]]; then
        rm -f "$f"
      fi
    done
    sketchybar --trigger claude_status_change 2>/dev/null
  ) &
  local timer_pid=$!

  # tmux位置も保存（2秒ルールで使用）
  echo "${window_id}:${now}:${timer_pid}:${cur_session}:${cur_window}" > "$FOCUS_STATE_FILE"
}

# ウィンドウフォーカス変更時の3段階ロジック
handle_focus_change() {
  local focused
  focused=$(aerospace list-windows --focused --json 2>/dev/null)

  local app_name
  app_name=$(echo "$focused" | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  local window_id
  window_id=$(echo "$focused" | jq -r '.[0]["window-id"] // ""' 2>/dev/null)

  local now
  now=$(date +%s)

  # 前回のフォーカス状態を読み込み、タイマー処理
  if [[ -f "$FOCUS_STATE_FILE" ]]; then
    local prev_state prev_window_id prev_ts prev_pid prev_session prev_tmux_window
    prev_state=$(cat "$FOCUS_STATE_FILE" 2>/dev/null)
    prev_window_id=$(echo "$prev_state" | cut -d: -f1)
    prev_ts=$(echo "$prev_state" | cut -d: -f2)
    prev_pid=$(echo "$prev_state" | cut -d: -f3)
    prev_session=$(echo "$prev_state" | cut -d: -f4)
    prev_tmux_window=$(echo "$prev_state" | cut -d: -f5)

    local elapsed=$((now - prev_ts))

    # 同じウィンドウなら何もしない（重複イベント対策）
    if [[ "$prev_window_id" == "$window_id" ]]; then
      return
    fi

    # 前回のタイマーをキャンセル（ウィンドウが変わった場合のみ）
    [[ -n "$prev_pid" ]] && kill "$prev_pid" 2>/dev/null

    # ウィンドウが変わった場合の2秒ルール
    if [[ $elapsed -ge 2 ]]; then
      # 2秒以上滞在 → 前ウィンドウの通知を消す（保存されたtmux位置を使用）
      remove_notifications_for_window "$prev_window_id" "$prev_session" "$prev_tmux_window"
    fi
  fi

  # VS Code/ターミナル以外のアプリに切り替えた場合はタイマー不要
  case "$app_name" in
    "Code"|"Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      ;;
    *)
      # 非対象アプリ → フォーカス状態をクリアして終了
      rm -f "$FOCUS_STATE_FILE" 2>/dev/null
      return
      ;;
  esac

  [[ -z "$window_id" ]] && return

  # 新しいウィンドウの5秒タイマーを開始
  start_clear_timer "$window_id"
}

# 通知が来た時、フォーカス中のウィンドウならタイマーを（再）開始
handle_notification_arrived() {
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

  # フォーカス中のウィンドウに通知があるかチェック
  if ls "$STATUS_DIR"/window_${window_id}_*.json &>/dev/null; then
    local should_start_timer=true

    # Terminal系アプリでtmuxが動作している場合、tmux位置も確認
    case "$app_name" in
      "Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
        # tmuxサーバーが動作しているかチェック（$TMUX変数に依存しない）
        local current_session current_window
        current_session=$(tmux display-message -p '#S' 2>/dev/null)
        current_window=$(tmux display-message -p '#I' 2>/dev/null)
        if [[ -n "$current_session" && -n "$current_window" ]]; then

          # この window_id の通知で tmux 情報を持つものがあるかチェック
          for f in "$STATUS_DIR"/window_${window_id}_*.json; do
            [[ -f "$f" ]] || continue
            local notif_session notif_window
            notif_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
            notif_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

            if [[ -n "$notif_session" && -n "$notif_window" ]]; then
              # tmux情報がある通知 → 現在のtmux位置と一致するかチェック
              if [[ "$notif_session" != "$current_session" || "$notif_window" != "$current_window" ]]; then
                should_start_timer=false
                break
              fi
            fi
          done
        fi
        ;;
    esac

    if [[ "$should_start_timer" == "true" ]]; then
      start_clear_timer "$window_id"
    fi
  fi
}

# バッジを更新（ワークスペース + アプリ）
update_badges() {
  local focused_ws
  focused_ws=$(aerospace list-workspaces --focused 2>/dev/null)

  # フォーカス中のアプリを取得
  local focused_app
  focused_app=$(aerospace list-windows --focused --json 2>/dev/null | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

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
      local file_ws file_st file_app file_tmux_session
      file_ws=$(jq -r '.workspace // ""' "$f" 2>/dev/null)
      file_st=$(jq -r '.status // "none"' "$f" 2>/dev/null)
      file_app=$(jq -r '.app_name // ""' "$f" 2>/dev/null)
      file_tmux_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)

      # 対象ステータスのみ
      [[ "$file_st" == "idle" || "$file_st" == "permission" || "$file_st" == "complete" ]] || continue

      if [[ "$file_ws" == "$focused_ws" ]]; then
        # フォーカス中のワークスペース → アプリバッジ用
        # ただし、フォーカス中のアプリでtmux情報がある場合はtmux側に委譲
        if [[ -n "$file_app" ]]; then
          if [[ "$file_app" == "$focused_app" && -n "$file_tmux_session" ]]; then
            # tmux側で表示するのでスキップ
            :
          else
            app_counts="$app_counts|$file_app"
          fi
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

  # タイマーがアクティブかチェック（薄い色を使うかどうか）
  local current_badge_color="$BADGE_COLOR"
  if [[ -f "$FOCUS_STATE_FILE" ]]; then
    local timer_pid
    timer_pid=$(cut -d: -f3 "$FOCUS_STATE_FILE" 2>/dev/null)
    if [[ -n "$timer_pid" ]] && kill -0 "$timer_pid" 2>/dev/null; then
      current_badge_color="$BADGE_COLOR_DIM"
    fi
  fi

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
        background.color="$current_badge_color" 2>/dev/null
    fi
  done
}

# メイン処理
main() {
  if [[ "$SENDER" == "front_app_switched" || "$SENDER" == "aerospace_workspace_change" ]]; then
    handle_focus_change
  elif [[ "$SENDER" == "claude_status_change" ]]; then
    handle_notification_arrived
  fi

  # バッジを更新
  update_badges
}

main
