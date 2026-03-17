#!/usr/bin/env bash
# ralph-orchestrate.sh - Ralph worker lifecycle management
#
# Uses wt-lib.sh to create worktrees + tmux windows for each worker,
# launches independent claude processes, and polls for completion.
set -euo pipefail

# shellcheck source=wt-lib.sh
source "$(dirname "$0")/wt-lib.sh"

readonly RESULTS_DIR="/tmp/ralph/results"
readonly WORKERS_DIR="/tmp/ralph/workers"
readonly PROMPTS_DIR="/tmp/ralph/prompts"
readonly CHECKPOINT_FILE="/tmp/ralph/checkpoint.json"

# --- Helpers ---

_cleanup_orphaned_branches() {
  local worktree_branches=""
  worktree_branches="$(git worktree list --porcelain | grep '^branch ' | sed 's|^branch refs/heads/||')"

  local branch
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    if ! echo "$worktree_branches" | grep -qxF "$branch"; then
      git branch -D "$branch" 2>/dev/null && wt_info "Deleted orphaned branch: $branch"
    fi
  done < <(git branch --list 'ralph/*' | sed 's/^[* ]*//')
}

# --- Subcommands ---

cmd_init() {
  local force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *) shift ;;
    esac
  done

  # 既存ワーカーの worktree/window をクリーンアップ
  if [[ -d "$WORKERS_DIR" ]]; then
    for worker_file in "$WORKERS_DIR"/*.json; do
      [[ -f "$worker_file" ]] || continue
      local tid
      tid="$(jq -r '.task_id' "$worker_file")"
      wt_delete "ralph/${tid}" 2>/dev/null || true
    done
  fi

  _cleanup_orphaned_branches

  if [[ "$force" == true ]]; then
    # --force: 全消しリセット
    rm -rf "$RESULTS_DIR" "$WORKERS_DIR" "$PROMPTS_DIR" "$CHECKPOINT_FILE"
  else
    # デフォルト: workers のみクリア、prompts 保持、results の .status のみ削除
    rm -rf "$WORKERS_DIR"
    rm -f "$RESULTS_DIR"/*.status 2>/dev/null || true
  fi

  mkdir -p "$RESULTS_DIR" "$WORKERS_DIR" "$PROMPTS_DIR"
  wt_info "Initialized (force=$force): $RESULTS_DIR, $WORKERS_DIR, $PROMPTS_DIR"
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

  local prompt_abs
  prompt_abs="$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")"

  # Split window: left=review, right=claude (worker)
  local review_pane
  review_pane=$(tmux display-message -t "$window_name" -p '#{pane_id}')
  local claude_pane
  claude_pane=$(tmux split-window -h -t "$window_name" -c "$worktree_path" -P -F '#{pane_id}')
  if command -v nvim &>/dev/null; then
    tmux send-keys -t "$review_pane" "nvim ." Enter
  fi

  # Launch claude TUI then send /ralph with file path reference
  # - No --dangerously-skip-permissions (avoids "Are you sure?" confirmation)
  # - Stop hook + backpressure hook provide autonomous loop + quality gate
  # - Pass file path instead of content to avoid tmux send-keys buffer limit
  tmux send-keys -t "$claude_pane" "claude --model ${model}" Enter

  # Wait for TUI to initialize by detecting prompt via capture-pane
  local wait_elapsed=0
  local wait_timeout=30
  while [[ "$wait_elapsed" -lt "$wait_timeout" ]]; do
    sleep 1
    wait_elapsed=$((wait_elapsed + 1))
    local pane_content
    pane_content="$(tmux capture-pane -t "$claude_pane" -p 2>/dev/null || true)"
    # Detect claude TUI ready: prompt indicator ">" or "tips" welcome screen
    if echo "$pane_content" | grep -qE '^\s*>|^╭|tips'; then
      break
    fi
  done
  if [[ "$wait_elapsed" -ge "$wait_timeout" ]]; then
    wt_error "Timeout waiting for claude TUI to initialize in $claude_pane"
    return 1
  fi

  # Send /ralph with prompt file path (ralph will Read the file)
  tmux send-keys -t "$claude_pane" "/ralph 'Read ${prompt_abs} for task instructions and implement accordingly.' --skip-plan" Enter

  # Record worker metadata
  local worker_json="${WORKERS_DIR}/${task_id}.json"
  cat > "$worker_json" <<WORKER_EOF
{
  "task_id": "${task_id}",
  "branch": "${branch}",
  "worktree": "${worktree_path}",
  "window": "${window_name}",
  "claude_pane": "${claude_pane}",
  "model": "${model}",
  "prompt_file": "${prompt_abs}",
  "started": $(date +%s)
}
WORKER_EOF

  wt_success "Launched worker: $task_id in $window_name (model: $model, pane: $claude_pane)"
}

cmd_status() {
  local json_mode=false
  local wait_seconds=0
  local task_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      --wait) wait_seconds="${2:-20}"; shift 2 ;;
      *) task_id="$1"; shift ;;
    esac
  done

  if [[ "$wait_seconds" -gt 0 ]]; then
    sleep "$wait_seconds"
  fi

  if [[ "$json_mode" == true ]]; then
    _status_json
  elif [[ -n "$task_id" ]]; then
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
  local worker_file="${WORKERS_DIR}/${task_id}.json"

  if [[ ! -f "$worker_file" ]]; then
    echo "unknown"
    return
  fi

  local pane_id
  pane_id="$(jq -r '.claude_pane // empty' "$worker_file")"

  if [[ -z "$pane_id" ]]; then
    echo "running"
    return
  fi

  # tmux capture-pane で完了判定 (3段階: done / dead / running)
  local result
  result="$(_pane_status "$pane_id" "$task_id")"
  echo "$result"
}

# Returns: "done" | "dead" | "running"
_pane_status() {
  local pane_id="$1"
  local task_id="$2"
  local result_file="${RESULTS_DIR}/${task_id}.md"

  # pane が存在しない場合: 結果ファイルの有無で done/dead を判定
  if ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane_id"; then
    if [[ -f "$result_file" ]]; then
      echo "done"
    else
      echo "dead"
    fi
    return
  fi

  # capture-pane で全履歴を取得し RALPH_COMPLETE を検出
  local captured
  captured="$(tmux capture-pane -t "$pane_id" -p -S - 2>/dev/null || true)"
  if echo "$captured" | grep -qF "RALPH_COMPLETE"; then
    echo "done"
    return
  fi

  echo "running"
}

_status_json() {
  local all_done=true
  local has_dead=false
  local workers_json="{"
  local first=true

  for worker_file in "$WORKERS_DIR"/*.json; do
    [[ -f "$worker_file" ]] || continue
    local tid
    tid="$(jq -r '.task_id' "$worker_file")"
    local st
    st="$(_worker_status "$tid")"

    if [[ "$first" == true ]]; then
      first=false
    else
      workers_json="${workers_json},"
    fi
    workers_json="${workers_json}\"${tid}\":\"${st}\""

    if [[ "$st" == "dead" ]]; then
      has_dead=true
    elif [[ "$st" != "done" ]]; then
      all_done=false
    fi
  done
  workers_json="${workers_json}}"

  printf '{"all_done":%s,"has_dead":%s,"workers":%s}\n' "$all_done" "$has_dead" "$workers_json"
}

# --- Checkpoint ---

cmd_checkpoint() {
  local phase="${1:-}"
  local json_data="${2:-}"
  [[ -z "$phase" ]] && { wt_error "Usage: checkpoint <phase> [json-data]"; return 1; }

  if [[ -n "$json_data" ]]; then
    echo "$json_data" | jq --arg phase "$phase" '. + {phase: $phase}' > "$CHECKPOINT_FILE"
  else
    jq -n --arg phase "$phase" '{phase: $phase}' > "$CHECKPOINT_FILE"
  fi
  wt_info "Checkpoint: $phase"
}

cmd_checkpoint_read() {
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    cat "$CHECKPOINT_FILE"
  else
    echo '{"phase":"none"}'
  fi
}

cmd_checkpoint_clear() {
  rm -f "$CHECKPOINT_FILE"
  wt_info "Checkpoint cleared"
}

_get_worktree() {
  local task_id="$1"
  local worker_file="${WORKERS_DIR}/${task_id}.json"
  [[ -f "$worker_file" ]] || { wt_error "No worker metadata for $task_id"; return 1; }
  jq -r '.worktree' "$worker_file"
}

cmd_save() {
  local task_id="${1:-}"
  [[ -z "$task_id" ]] && { wt_error "Usage: ralph-orchestrate.sh save <task-id>"; return 1; }

  local worktree
  worktree="$(_get_worktree "$task_id")" || return 1

  # Stage all changes (including untracked files)
  git -C "$worktree" add -A

  # Save patch of all staged changes
  local patch_file="${RESULTS_DIR}/${task_id}.patch"
  git -C "$worktree" diff --cached > "$patch_file"

  if [[ ! -s "$patch_file" ]]; then
    wt_info "No changes to save for $task_id"
    rm -f "$patch_file"
    return 0
  fi

  # Commit to branch (allows recovery even after worktree removal)
  git -C "$worktree" commit -m "ralph/${task_id}: worker changes" --no-verify

  wt_success "Saved: $patch_file ($(wc -l < "$patch_file") lines)"
}

cmd_merge() {
  local task_id="${1:-}"
  [[ -z "$task_id" ]] && { wt_error "Usage: ralph-orchestrate.sh merge <task-id>"; return 1; }

  local patch_file="${RESULTS_DIR}/${task_id}.patch"
  [[ -f "$patch_file" ]] || { wt_error "No patch file for $task_id: $patch_file"; return 1; }
  [[ -s "$patch_file" ]] || { wt_info "Empty patch for $task_id, skipping"; return 0; }

  wt_check_git || return 1

  if git apply --check "$patch_file" 2>/dev/null; then
    git apply "$patch_file"
    wt_success "Merged $task_id into current branch"
  else
    wt_error "Patch conflict for $task_id. Patch saved at: $patch_file"
    return 1
  fi
}

cmd_gen_prompt() {
  local task_id="${1:-}" task_name="${2:-}" completion_cond="${3:-}" files="${4:-}" ctx_file="${5:-}"
  [[ -z "$task_id" ]] && { wt_error "Usage: gen-prompt <id> <name> <cond> <files> [ctx-file]"; return 1; }

  local context=""
  if [[ -n "$ctx_file" ]] && [[ -f "$ctx_file" ]]; then
    context="$(cat "$ctx_file")"
  fi

  local prompt_file="${PROMPTS_DIR}/${task_id}.md"
  cat > "$prompt_file" <<PROMPT_EOF
You are a worker agent executing a specific task in an isolated git worktree.

## Task
ID: ${task_id}
Name: ${task_name}
Completion condition: ${completion_cond}
Target files: ${files}

## Context
${context}

## Instructions
1. Implement the task described above
2. Follow test-driven development when possible
3. Run type checks and linting to verify changes
4. Write result report to /tmp/ralph/results/${task_id}.md:

   Status: DONE / PARTIAL / BLOCKED
   Files changed:
     - <path> (created/modified/deleted)
   Tests:
     - <test_file>: PASS / FAIL
   Completion condition: <status>
   Notes: <any notes>

## Constraints
- Only modify files within this task's scope
- Do not modify files outside the listed target files
- Do not git push
- Do not git commit (the orchestrator will handle commits via save-all)
PROMPT_EOF
  echo "$prompt_file"
}

cmd_gen_prompt_batch() {
  local spec_file="${1:-}"
  [[ -z "$spec_file" ]] && { wt_error "Usage: gen-prompt-batch <task-spec.json>"; return 1; }
  [[ -f "$spec_file" ]] || { wt_error "Spec file not found: $spec_file"; return 1; }

  local count
  count="$(jq 'length' "$spec_file")"
  local i=0
  while [[ "$i" -lt "$count" ]]; do
    local task_id task_name completion_cond files ctx_file
    task_id="$(jq -r ".[$i].id" "$spec_file")"
    task_name="$(jq -r ".[$i].name" "$spec_file")"
    completion_cond="$(jq -r ".[$i].completion_condition" "$spec_file")"
    files="$(jq -r ".[$i].files" "$spec_file")"
    ctx_file="$(jq -r ".[$i].context_file // empty" "$spec_file")"
    cmd_gen_prompt "$task_id" "$task_name" "$completion_cond" "$files" "$ctx_file"
    i=$((i + 1))
  done
  wt_success "Generated $count prompts"
}

cmd_save_all() {
  local errors=0
  for worker_file in "$WORKERS_DIR"/*.json; do
    [[ -f "$worker_file" ]] || continue
    local tid
    tid="$(jq -r '.task_id' "$worker_file")"
    cmd_save "$tid" || errors=$((errors + 1))
  done
  if [[ "$errors" -gt 0 ]]; then
    wt_error "save-all: $errors failures"
    return 1
  fi
  wt_success "save-all: all workers saved"
}

cmd_send() {
  local task_id="${1:-}"
  local message="${2:-}"
  [[ -z "$task_id" ]] && { wt_error "Usage: ralph-orchestrate.sh send <task-id> <message>"; return 1; }
  [[ -z "$message" ]] && { wt_error "message is required"; return 1; }

  local worker_file="${WORKERS_DIR}/${task_id}.json"
  [[ -f "$worker_file" ]] || { wt_error "No worker metadata for $task_id"; return 1; }

  local pane_id
  pane_id="$(jq -r '.claude_pane // empty' "$worker_file")"
  [[ -z "$pane_id" ]] && { wt_error "No claude_pane recorded for $task_id"; return 1; }

  if ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane_id"; then
    wt_error "Pane $pane_id no longer exists for $task_id"
    return 1
  fi

  tmux send-keys -t "$pane_id" "$message" Enter
  wt_success "Sent message to $task_id ($pane_id)"
}

cmd_results() {
  for worker_file in "$WORKERS_DIR"/*.json; do
    [[ -f "$worker_file" ]] || continue
    local tid
    tid="$(jq -r '.task_id' "$worker_file")"
    local result_file="${RESULTS_DIR}/${tid}.md"
    echo "=== ${tid} ==="
    if [[ -f "$result_file" ]]; then
      cat "$result_file"
    else
      echo "(no result file)"
    fi
    echo ""
  done
}

cmd_cleanup() {
  local task_id="${1:-}"
  [[ -z "$task_id" ]] && { wt_error "Usage: ralph-orchestrate.sh cleanup <task-id>"; return 1; }

  wt_check_git || return 1
  wt_delete "ralph/${task_id}" || true
  rm -f "${WORKERS_DIR}/${task_id}.json"
  _cleanup_orphaned_branches
  wt_info "Cleaned up worker: $task_id"
}

cmd_cleanup_all() {
  local keep_results=false
  local task_ids=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-results) keep_results=true; shift ;;
      *) task_ids+=("$1"); shift ;;
    esac
  done

  wt_check_git || return 1

  if [[ ${#task_ids[@]} -gt 0 ]]; then
    # 指定タスクのみ cleanup
    for tid in "${task_ids[@]}"; do
      wt_delete "ralph/${tid}" 2>/dev/null || true
      rm -f "${WORKERS_DIR}/${tid}.json"
    done
  else
    # 全 worker cleanup
    for worker_file in "$WORKERS_DIR"/*.json; do
      [[ -f "$worker_file" ]] || continue
      local tid
      tid="$(jq -r '.task_id' "$worker_file")"
      wt_delete "ralph/${tid}" 2>/dev/null || true
    done
    rm -rf "$WORKERS_DIR"
  fi

  _cleanup_orphaned_branches

  if [[ "$keep_results" == false ]]; then
    rm -rf "$RESULTS_DIR" "$PROMPTS_DIR"
    wt_info "Cleaned up all (including results and prompts)"
  else
    wt_info "Cleaned up workers (results preserved in: $RESULTS_DIR)"
  fi

  rm -f "$CHECKPOINT_FILE"
}

# --- Main ---

case "${1:-}" in
  init)              shift; cmd_init "$@" ;;
  launch)            shift; cmd_launch "$@" ;;
  status)            shift; cmd_status "$@" ;;
  send)              shift; cmd_send "$@" ;;
  save)              cmd_save "${2:-}" ;;
  save-all)          cmd_save_all ;;
  merge)             cmd_merge "${2:-}" ;;
  gen-prompt)        shift; cmd_gen_prompt "$@" ;;
  gen-prompt-batch)  cmd_gen_prompt_batch "${2:-}" ;;
  results)           cmd_results ;;
  checkpoint)        shift; cmd_checkpoint "$@" ;;
  checkpoint-read)   cmd_checkpoint_read ;;
  checkpoint-clear)  cmd_checkpoint_clear ;;
  cleanup)           cmd_cleanup "${2:-}" ;;
  cleanup-all)       shift; cmd_cleanup_all "$@" ;;
  help|*)
    cat <<EOF
ralph-orchestrate.sh - Ralph worker lifecycle management

Usage:
  ralph-orchestrate.sh init [--force]                    Initialize work directories
  ralph-orchestrate.sh launch <task-id> <prompt-file> [--model MODEL]
                                                         Launch worker in tmux window
  ralph-orchestrate.sh status [--json] [--wait N] [task-id]
                                                         Check worker status
  ralph-orchestrate.sh send <task-id> <message>          Send message to worker pane
  ralph-orchestrate.sh save <task-id>                    Save worker changes as patch + commit
  ralph-orchestrate.sh save-all                          Save all workers
  ralph-orchestrate.sh merge <task-id>                   Apply saved patch to current branch
  ralph-orchestrate.sh gen-prompt <id> <name> <cond> <files> [ctx-file]
                                                         Generate prompt from template
  ralph-orchestrate.sh gen-prompt-batch <spec.json>      Generate all prompts from JSON
  ralph-orchestrate.sh results                           Print all result files
  ralph-orchestrate.sh checkpoint <phase> [json-data]    Set checkpoint
  ralph-orchestrate.sh checkpoint-read                   Read checkpoint (or {"phase":"none"})
  ralph-orchestrate.sh checkpoint-clear                  Clear checkpoint
  ralph-orchestrate.sh cleanup <task-id>                 Remove worker worktree
  ralph-orchestrate.sh cleanup-all [--keep-results] [task-id...]
                                                         Remove all (or specified) worker worktrees
EOF
    ;;
esac
