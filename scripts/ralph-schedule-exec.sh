#!/usr/bin/env bash
# ralph-schedule-exec.sh - One-shot executor for scheduled Claude TUI sessions
#
# Called by launchd (macOS) or at (Linux).
# Launches Claude TUI in a tmux window and injects /ralph with the prompt file.
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wt-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/ralph-lib.sh"

STATE_DIR="/tmp/ralph-schedule"
JOB_ID="${1:-}"

[[ -z "$JOB_ID" ]] && { echo "Usage: ralph-schedule-exec.sh <job-id>" >&2; exit 1; }

JOB_FILE="${STATE_DIR}/jobs/${JOB_ID}.json"
LOG_FILE="${STATE_DIR}/logs/${JOB_ID}.log"

# --- Logging ---

_log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '[%s] %s\n' "$ts" "$*" >> "$LOG_FILE"
}

_update_status() {
  local new_status="$1"
  jq --arg s "$new_status" '.status = $s' "$JOB_FILE" > "${JOB_FILE}.tmp" \
    && mv "${JOB_FILE}.tmp" "$JOB_FILE"
}

# --- Wait for TUI (same pattern as ralph-crew) ---

_wait_for_tui() {
  local pane_id="$1"
  local timeout="${2:-30}"
  local elapsed=0

  while [[ "$elapsed" -lt "$timeout" ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
    local content
    content="$(tmux capture-pane -t "$pane_id" -p 2>/dev/null || true)"
    if echo "$content" | grep -qE '❯|^\s*>|^╭|tips'; then
      return 0
    fi
  done
  return 1
}

# --- Validate ---

if [[ ! -f "$JOB_FILE" ]]; then
  echo "Job file not found: $JOB_FILE" >&2
  exit 1
fi

_log "Starting executor for job: $JOB_ID"
_update_status "running"

# --- Self-cleanup: launchd ---

scheduler="$(jq -r '.scheduler' "$JOB_FILE")"
if [[ "$scheduler" == "launchd" ]]; then
  plist_label="$(jq -r '.plist_label' "$JOB_FILE")"
  plist_path="$HOME/Library/LaunchAgents/${plist_label}.plist"
  launchctl bootout "gui/$(id -u)/${plist_label}" 2>/dev/null || true
  rm -f "$plist_path"
  _log "Self-cleanup: removed launchd job $plist_label"
fi

# --- Read metadata ---

tmux_session="$(jq -r '.tmux_session' "$JOB_FILE")"
tmux_window="$(jq -r '.tmux_window' "$JOB_FILE")"
project_dir="$(jq -r '.project_dir' "$JOB_FILE")"
worktree_path="$(jq -r '.worktree_path // empty' "$JOB_FILE")"
branch="$(jq -r '.branch // empty' "$JOB_FILE")"
base="$(jq -r '.base // empty' "$JOB_FILE")"
model="$(jq -r '.model // "sonnet"' "$JOB_FILE")"
prompt_file="$(jq -r '.prompt_file' "$JOB_FILE")"

# --- Ensure tmux session ---

if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
  tmux new-session -d -s "$tmux_session"
  _log "Created tmux session: $tmux_session"
fi

# --- Create worktree + tmux window ---

work_dir="$project_dir"

if [[ -n "$branch" ]]; then
  # Worktree mode
  if [[ -n "$worktree_path" ]] && [[ ! -d "$worktree_path" ]]; then
    cd "$project_dir"
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      git worktree add "$worktree_path" "$branch"
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
      git worktree add "$worktree_path" "$branch"
    else
      if [[ -n "$base" ]]; then
        git worktree add -b "$branch" "$worktree_path" "$base"
      else
        git worktree add -b "$branch" "$worktree_path"
      fi
    fi
    wt_copy_ignored "$project_dir" "$worktree_path"
    _log "Created worktree: $worktree_path"
  fi
  work_dir="${worktree_path:-$project_dir}"
fi

# Kill existing window if present, then create new one
if tmux list-windows -t "$tmux_session" -F '#{window_name}' 2>/dev/null | grep -qxF "$tmux_window"; then
  tmux kill-window -t "${tmux_session}:${tmux_window}" 2>/dev/null || true
fi
tmux new-window -t "$tmux_session" -n "$tmux_window" -c "$work_dir"
_log "Created tmux window: ${tmux_session}:${tmux_window}"

# --- Get pane ID ---

pane_id="$(tmux display-message -t "${tmux_session}:${tmux_window}" -p '#{pane_id}')"

# --- Setup worker permissions ---

ralph_setup_worker_settings "$work_dir"
_log "Worker settings configured: ${work_dir}/.claude/settings.local.json"

# --- Launch Claude TUI ---

tmux send-keys -t "$pane_id" "claude --model ${model}" Enter

if ! _wait_for_tui "$pane_id" 30; then
  _log "Timeout waiting for TUI (continuing anyway)"
fi

# --- Inject /ralph ---

tmux send-keys -t "$pane_id" "/ralph 'Read ${prompt_file} for task instructions and implement accordingly.' --skip-plan" Enter
_log "Dispatched /ralph for job: $JOB_ID"

_update_status "done"
_log "Executor completed for job: $JOB_ID"
