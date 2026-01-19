#!/bin/bash
# Claude Code Status Plugin for SketchyBar
# Updates workspace badges based on Claude session status (workspace-based)

source "$CONFIG_DIR/plugins/colors.sh"

STATUS_DIR="/tmp/claude_status"
FOCUS_STATE_FILE="/tmp/sketchybar_workspace_focus"

# Badge colors
BADGE_COLOR="$SERVICE_MODE_COLOR"
BADGE_COLOR_DIM="$DIM_BADGE_COLOR"

# Remove notifications for a workspace (considering tmux position)
remove_notifications_for_workspace() {
  local target_workspace="$1"
  local target_session="${2:-}"
  local target_window="${3:-}"

  for f in "$STATUS_DIR"/workspace_${target_workspace}_*.json; do
    [[ -f "$f" ]] || continue
    local notif_session notif_window
    notif_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
    notif_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

    if [[ -z "$notif_session" || -z "$notif_window" ]]; then
      # No tmux info in notification -> OK to delete
      rm -f "$f"
    elif [[ -z "$target_session" || -z "$target_window" ]]; then
      # Current tmux not detected (VS Code etc) -> OK to delete
      rm -f "$f"
    elif [[ "$notif_session" == "$target_session" && "$notif_window" == "$target_window" ]]; then
      # tmux position matches -> delete
      rm -f "$f"
    fi
  done
}

# Start 5-second timer (cancel existing timer)
start_clear_timer() {
  local workspace="$1"
  local app_name="${2:-}"

  # Cancel existing timer
  if [[ -f "$FOCUS_STATE_FILE" ]]; then
    local prev_pid
    prev_pid=$(cut -d: -f3 "$FOCUS_STATE_FILE" 2>/dev/null)
    [[ -n "$prev_pid" ]] && kill "$prev_pid" 2>/dev/null
  fi

  local now
  now=$(date +%s)

  # Record current tmux position (for timer execution)
  # Only use tmux info for terminal apps
  local cur_session="" cur_window=""
  case "$app_name" in
    "Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      cur_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")
      cur_window=$(tmux display-message -p '#I' 2>/dev/null || echo "")
      ;;
  esac

  # Start background timer for auto-clear after 5 seconds
  (
    sleep 5
    # Delete considering tmux info
    for f in "$STATUS_DIR"/workspace_${workspace}_*.json; do
      [[ -f "$f" ]] || continue
      local notif_session notif_window
      notif_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
      notif_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

      if [[ -z "$notif_session" || -z "$notif_window" ]]; then
        rm -f "$f"
      elif [[ -z "$cur_session" || -z "$cur_window" ]]; then
        rm -f "$f"
      elif [[ "$notif_session" == "$cur_session" && "$notif_window" == "$cur_window" ]]; then
        rm -f "$f"
      fi
    done
    sketchybar --trigger claude_status_change 2>/dev/null
  ) &
  local timer_pid=$!

  # Save workspace focus state
  echo "${workspace}:${now}:${timer_pid}:${cur_session}:${cur_window}" > "$FOCUS_STATE_FILE"
}

# 3-stage logic for window focus change
handle_focus_change() {
  local focused_ws
  focused_ws=$(aerospace list-workspaces --focused 2>/dev/null)

  local focused
  focused=$(aerospace list-windows --focused --json 2>/dev/null)

  local app_name
  app_name=$(echo "$focused" | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  local now
  now=$(date +%s)

  # Load previous focus state and handle timer
  if [[ -f "$FOCUS_STATE_FILE" ]]; then
    local prev_state prev_workspace prev_ts prev_pid prev_session prev_tmux_window
    prev_state=$(cat "$FOCUS_STATE_FILE" 2>/dev/null)
    prev_workspace=$(echo "$prev_state" | cut -d: -f1)
    prev_ts=$(echo "$prev_state" | cut -d: -f2)
    prev_pid=$(echo "$prev_state" | cut -d: -f3)
    prev_session=$(echo "$prev_state" | cut -d: -f4)
    prev_tmux_window=$(echo "$prev_state" | cut -d: -f5)

    local elapsed=$((now - prev_ts))

    # Same workspace -> do nothing (duplicate event handling)
    if [[ "$prev_workspace" == "$focused_ws" ]]; then
      return
    fi

    # Cancel previous timer (only when workspace changed)
    [[ -n "$prev_pid" ]] && kill "$prev_pid" 2>/dev/null

    # 2-second rule when workspace changed
    if [[ $elapsed -ge 2 ]]; then
      # Stayed 2+ seconds -> clear all notifications for prev workspace
      rm -f "$STATUS_DIR"/workspace_${prev_workspace}_*.json 2>/dev/null
      sketchybar --trigger claude_status_change 2>/dev/null
    fi
  fi

  [[ -z "$focused_ws" ]] && return

  # Start 5-second timer only for VS Code/terminals
  case "$app_name" in
    "Code"|"Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      start_clear_timer "$focused_ws" "$app_name"
      ;;
    *)
      # Non-target app: just update focus state (for 2-second rule)
      echo "${focused_ws}:${now}:::" > "$FOCUS_STATE_FILE"
      ;;
  esac
}

# When notification arrives, (re)start timer if focused workspace has notifications
handle_notification_arrived() {
  local focused_ws
  focused_ws=$(aerospace list-workspaces --focused 2>/dev/null)

  local focused
  focused=$(aerospace list-windows --focused --json 2>/dev/null)

  local app_name
  app_name=$(echo "$focused" | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  # Only process for VS Code or terminal apps
  case "$app_name" in
    "Code"|"Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      ;;
    *)
      return
      ;;
  esac

  [[ -z "$focused_ws" ]] && return

  # Check if focused workspace has notifications
  if ls "$STATUS_DIR"/workspace_${focused_ws}_*.json &>/dev/null; then
    local should_start_timer=true

    # For terminal apps with tmux, also check tmux position
    case "$app_name" in
      "Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
        local current_session current_window
        current_session=$(tmux display-message -p '#S' 2>/dev/null)
        current_window=$(tmux display-message -p '#I' 2>/dev/null)
        if [[ -n "$current_session" && -n "$current_window" ]]; then
          # Check notifications with tmux info
          for f in "$STATUS_DIR"/workspace_${focused_ws}_*.json; do
            [[ -f "$f" ]] || continue
            local notif_session notif_window
            notif_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
            notif_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

            if [[ -n "$notif_session" && -n "$notif_window" ]]; then
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
      start_clear_timer "$focused_ws" "$app_name"
    fi
  fi
}

# Update badges (workspace + app)
update_badges() {
  local focused_ws
  focused_ws=$(aerospace list-workspaces --focused 2>/dev/null)

  # Get focused app
  local focused_app
  focused_app=$(aerospace list-windows --focused --json 2>/dev/null | jq -r '.[0]["app-name"] // ""' 2>/dev/null)

  # Get active workspaces
  local workspaces
  workspaces=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)

  # Collect notifications (bash 3.2 compatible - no associative arrays)
  local ws_counts=""
  local app_counts=""

  # Get current tmux position for terminal apps (once outside loop)
  local current_tmux_session="" current_tmux_window=""
  case "$focused_app" in
    "Ghostty"|"Terminal"|"iTerm2"|"Alacritty"|"Warp"|"WezTerm"|"kitty")
      current_tmux_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")
      current_tmux_window=$(tmux display-message -p '#I' 2>/dev/null || echo "")
      ;;
  esac

  if [[ -d "$STATUS_DIR" ]]; then
    for f in "$STATUS_DIR"/workspace_*.json; do
      [[ -f "$f" ]] || continue
      local file_ws file_st file_tmux_session file_tmux_window
      file_ws=$(jq -r '.workspace // ""' "$f" 2>/dev/null)
      file_st=$(jq -r '.status // "none"' "$f" 2>/dev/null)
      file_tmux_session=$(jq -r '.tmux_session // ""' "$f" 2>/dev/null)
      file_tmux_window=$(jq -r '.tmux_window_index // ""' "$f" 2>/dev/null)

      # Only target statuses
      [[ "$file_st" == "idle" || "$file_st" == "permission" || "$file_st" == "complete" ]] || continue

      if [[ "$file_ws" == "$focused_ws" ]]; then
        # Focused workspace -> for app badges
        # Skip if tmux position matches current (directly viewing)
        if [[ -n "$file_tmux_session" && -n "$file_tmux_window" && \
              "$file_tmux_session" == "$current_tmux_session" && \
              "$file_tmux_window" == "$current_tmux_window" ]]; then
          :
        else
          app_counts="$app_counts|$file_ws"
        fi
      else
        # Other workspaces -> for workspace badges
        ws_counts="$ws_counts|$file_ws"
      fi
    done
  fi

  # Update workspace badges
  for ws in $workspaces; do
    local total=0
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

  # Clear focused workspace badge if it has app notifications
  if [[ -n "$app_counts" ]]; then
    sketchybar --set "space.${focused_ws}_badge" \
      label="" \
      label.drawing=off \
      background.drawing=off 2>/dev/null
  fi

  # Update app badges (apps in focused workspace)
  local focused_apps
  focused_apps=$(aerospace list-windows --workspace "$focused_ws" --format '%{app-name}' 2>/dev/null | sort -u)

  # Check if timer is active (for dim color)
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
    while [[ "$remaining" == *"|$focused_ws"* ]]; do
      ((app_total++))
      remaining="${remaining/|$focused_ws/}"
    done

    # Item name (replace space and dot with underscore)
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

# Main
main() {
  if [[ "$SENDER" == "front_app_switched" || "$SENDER" == "aerospace_workspace_change" ]]; then
    handle_focus_change
  elif [[ "$SENDER" == "claude_status_change" ]]; then
    handle_notification_arrived
  fi

  # Update badges
  update_badges
}

main
