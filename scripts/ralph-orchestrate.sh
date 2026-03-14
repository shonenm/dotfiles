#!/usr/bin/env bash
# ralph-orchestrate.sh - Ralph worker lifecycle management
#
# Uses wt-lib.sh to create worktrees + tmux windows for each worker,
# launches independent claude processes, and polls for completion.
set -euo pipefail

# shellcheck source=wt-lib.sh
source "$(dirname "$0")/wt-lib.sh"

readonly RESULTS_DIR="/tmp/ralph_results"
readonly WORKERS_DIR="/tmp/ralph_workers"
readonly PROMPTS_DIR="/tmp/ralph_prompts"

# --- Subcommands ---

cmd_init() {
  rm -rf "$RESULTS_DIR" "$WORKERS_DIR" "$PROMPTS_DIR"
  mkdir -p "$RESULTS_DIR" "$WORKERS_DIR" "$PROMPTS_DIR"
  wt_info "Initialized: $RESULTS_DIR, $WORKERS_DIR, $PROMPTS_DIR"
}

cmd_launch() {
  local task_id="${1:-}"
  local prompt_file="${2:-}"
  local model="sonnet"

  # Parse --model flag
  shift 2 2>/dev/null || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model) model="${2:-sonnet}"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$task_id" ]] && { wt_error "Usage: ralph-orchestrate.sh launch <task-id> <prompt-file> [--model MODEL]"; return 1; }
  [[ -z "$prompt_file" ]] && { wt_error "prompt-file is required"; return 1; }
  [[ -f "$prompt_file" ]] || { wt_error "prompt file not found: $prompt_file"; return 1; }

  wt_check_git || return 1

  local branch="ralph/${task_id}"

  # Create worktree + tmux window via wt-lib
  local worktree_path
  worktree_path="$(wt_create "$branch")" || return 1

  local window_name
  window_name="$(wt_window_name "$branch")"

  local status_file="${RESULTS_DIR}/${task_id}.status"

  # Build the command to run in the worker window
  # claude -p reads the prompt, runs autonomously, then exits
  # Exit code is written to .status file for poll detection
  local prompt_abs
  prompt_abs="$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")"
  local cmd="claude -p \"\$(cat '${prompt_abs}')\" --model ${model} 2>&1; echo \$? > '${status_file}'"

  # Send command to the worker's tmux window
  tmux send-keys -t "$window_name" "$cmd" Enter

  # Record worker metadata
  local worker_json="${WORKERS_DIR}/${task_id}.json"
  cat > "$worker_json" <<WORKER_EOF
{
  "task_id": "${task_id}",
  "branch": "${branch}",
  "worktree": "${worktree_path}",
  "window": "${window_name}",
  "model": "${model}",
  "prompt_file": "${prompt_abs}",
  "started": $(date +%s)
}
WORKER_EOF

  wt_success "Launched worker: $task_id in $window_name (model: $model)"
}

cmd_status() {
  local task_id="${1:-}"

  if [[ -n "$task_id" ]]; then
    _worker_status "$task_id"
  else
    local has_workers=false
    for worker_file in "$WORKERS_DIR"/*.json; do
      [[ -f "$worker_file" ]] || continue
      has_workers=true
      local tid
      tid="$(jq -r '.task_id' "$worker_file")"
      local st
      st="$(_worker_status "$tid")"
      printf "  %-20s %s\n" "$tid" "$st"
    done
    if [[ "$has_workers" == false ]]; then
      wt_info "No workers found"
    fi
  fi
}

_worker_status() {
  local task_id="$1"
  local status_file="${RESULTS_DIR}/${task_id}.status"
  local result_file="${RESULTS_DIR}/${task_id}.md"

  if [[ -f "$status_file" ]]; then
    local exit_code
    exit_code="$(cat "$status_file")"
    if [[ "$exit_code" == "0" ]]; then
      if [[ -f "$result_file" ]]; then
        echo "done"
      else
        echo "done (no result file)"
      fi
    else
      echo "failed (exit: $exit_code)"
    fi
  else
    echo "running"
  fi
}

cmd_poll() {
  local interval=10
  local timeout=600

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="${2:-10}"; shift 2 ;;
      --timeout) timeout="${2:-600}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local start
  start="$(date +%s)"

  wt_info "Polling workers (interval: ${interval}s, timeout: ${timeout}s)..."

  while true; do
    local all_done=true
    local summary=""

    for worker_file in "$WORKERS_DIR"/*.json; do
      [[ -f "$worker_file" ]] || continue
      local tid
      tid="$(jq -r '.task_id' "$worker_file")"
      local status_file="${RESULTS_DIR}/${tid}.status"

      if [[ ! -f "$status_file" ]]; then
        all_done=false
        summary="${summary}  ${tid}: running\n"
      else
        local exit_code
        exit_code="$(cat "$status_file")"
        if [[ "$exit_code" == "0" ]]; then
          summary="${summary}  ${tid}: done\n"
        else
          summary="${summary}  ${tid}: failed (exit: ${exit_code})\n"
        fi
      fi
    done

    if [[ "$all_done" == true ]]; then
      wt_success "All workers completed"
      printf '%b' "$summary" >&2
      return 0
    fi

    local elapsed
    elapsed="$(( $(date +%s) - start ))"
    if [[ "$elapsed" -ge "$timeout" ]]; then
      wt_error "Timeout after ${timeout}s. Current status:"
      printf '%b' "$summary" >&2
      return 1
    fi

    sleep "$interval"
  done
}

cmd_cleanup() {
  local task_id="${1:-}"
  [[ -z "$task_id" ]] && { wt_error "Usage: ralph-orchestrate.sh cleanup <task-id>"; return 1; }

  wt_check_git || return 1
  wt_delete "ralph/${task_id}" || true
  rm -f "${WORKERS_DIR}/${task_id}.json"
  wt_info "Cleaned up worker: $task_id"
}

cmd_cleanup_all() {
  wt_check_git || return 1

  for worker_file in "$WORKERS_DIR"/*.json; do
    [[ -f "$worker_file" ]] || continue
    local tid
    tid="$(jq -r '.task_id' "$worker_file")"
    wt_delete "ralph/${tid}" 2>/dev/null || true
  done

  rm -rf "$WORKERS_DIR"
  wt_info "Cleaned up all workers"
  wt_info "Results preserved in: $RESULTS_DIR"
}

# --- Main ---

case "${1:-}" in
  init)        cmd_init ;;
  launch)      shift; cmd_launch "$@" ;;
  status)      cmd_status "${2:-}" ;;
  poll)        shift; cmd_poll "$@" ;;
  cleanup)     cmd_cleanup "${2:-}" ;;
  cleanup-all) cmd_cleanup_all ;;
  help|*)
    cat <<EOF
ralph-orchestrate.sh - Ralph worker lifecycle management

Usage:
  ralph-orchestrate.sh init                              Initialize work directories
  ralph-orchestrate.sh launch <task-id> <prompt-file> [--model MODEL]
                                                         Launch worker in tmux window
  ralph-orchestrate.sh status [task-id]                  Check worker status
  ralph-orchestrate.sh poll [--interval N] [--timeout N] Wait for all workers
  ralph-orchestrate.sh cleanup <task-id>                 Remove worker worktree
  ralph-orchestrate.sh cleanup-all                       Remove all worker worktrees
EOF
    ;;
esac
