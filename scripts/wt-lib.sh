#!/usr/bin/env bash
# wt-lib.sh - git worktree + tmux window management library
#
# Usage: source this file in your scripts, then call wt_* functions.
#   source "$(dirname "$0")/wt-lib.sh"
#   path=$(wt_create feat/login)
#
# All status messages go to stderr. Only data (paths, names) goes to stdout.
# This allows: path=$(wt_create branch) to capture only the path.

# --- Output helpers ---
# Override these in your script before calling wt_* functions to customize.

wt_success() { printf '\033[0;32mok\033[0m %s\n' "$*" >&2; }
wt_error()   { printf '\033[0;31merror\033[0m %s\n' "$*" >&2; }
wt_info()    { printf '\033[0;36minfo\033[0m %s\n' "$*" >&2; }

# --- Prerequisites ---

wt_check_git() {
  command -v git &>/dev/null || { wt_error "git is not installed"; return 1; }
  git rev-parse --git-dir &>/dev/null 2>&1 || { wt_error "Not in a git repository"; return 1; }
}

# --- Pure getters (stdout: single value) ---

wt_main_worktree() {
  git worktree list --porcelain | head -1 | sed 's/^worktree //'
}

wt_repo_name() {
  local main
  main="$(wt_main_worktree)"
  basename "$main"
}

wt_path() {
  local branch="$1"
  local main_path
  main_path="$(wt_main_worktree)"
  local slug="${branch//\//-}"
  echo "${main_path}--wt--${slug}"
}

wt_window_name() {
  local branch="$1"
  local repo
  repo="$(wt_repo_name)"
  echo "${repo}#${branch}"
}

# --- State checks ---

wt_exists() {
  local branch="$1"
  local path
  path="$(wt_path "$branch")"
  local escaped
  escaped="$(printf '%s' "$path" | sed 's/[][\\.^$*+?{}()|]/\\&/g')"
  git worktree list | grep -q "$escaped"
}

wt_window_exists() {
  local name="$1"
  tmux list-windows -F '#{window_name}' 2>/dev/null | grep -qxF "$name"
}

# --- Actions ---

wt_select_window() {
  local name="$1"
  tmux select-window -t "$name"
}

wt_copy_ignored() {
  local src="$1"
  local dst="$2"

  # TODO: Make configurable via .wt-config or similar per-project config
  # Currently hardcoded for SynTopic monorepo structure

  # Directories to symlink instead of copy (large, shared safely)
  local -a symlink_dirs=(
    "node_modules"
    ".pnpm-store"
    ".venv"
    "agents/worker/.venv"
    "agents/api/.venv"
    "bff/node_modules"
    "web/node_modules"
    "hocuspocus/node_modules"
    "test-e2e/node_modules"
    "packages/*/node_modules"
    "seeding/node_modules"
  )

  # Directories to skip entirely (regenerable caches)
  local -a skip_dirs=(
    ".mypy_cache"
    ".turbo"
    ".serena/cache"
    ".dumps"
    ".ruff_cache"
    ".pytest_cache"
    "anonymizer/output"
    "agents/.mypy_cache"
    "__pycache__"
  )

  local entries
  entries="$(git -C "$src" ls-files --others --ignored --exclude-standard --directory --no-empty-directory 2>/dev/null)" || return 0
  [[ -z "$entries" ]] && return 0

  wt_info "Syncing ignored files from main worktree..."
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local src_path="$src/$entry"
    local dst_path="$dst/$entry"
    [[ -e "$src_path" ]] || continue

    # Strip trailing slash for matching
    local entry_clean="${entry%/}"

    # Check if this entry should be skipped
    local should_skip=false
    for pattern in "${skip_dirs[@]}"; do
      if [[ "$entry_clean" == *"$pattern"* ]]; then
        should_skip=true
        break
      fi
    done
    [[ "$should_skip" == true ]] && continue

    # Check if this entry should be symlinked
    local should_symlink=false
    for pattern in "${symlink_dirs[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$entry_clean" == $pattern ]]; then
        should_symlink=true
        break
      fi
    done

    if [[ "$should_symlink" == true ]]; then
      local abs_src
      abs_src="$(cd "$src" && pwd)/$entry_clean"
      mkdir -p "$(dirname "$dst_path")"
      ln -snf "$abs_src" "${dst_path%/}"
      continue
    fi

    # Default: copy
    mkdir -p "$(dirname "$dst_path")"
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS APFS: clonefile (CoW, ディスク消費ほぼゼロ)
      cp -ac "$src_path" "$dst_path" 2>/dev/null || cp -a "$src_path" "$dst_path" 2>/dev/null || true
    else
      # Linux: -x でマウントポイントを越えない (Docker ボリューム等を除外)
      cp -ax --reflink=auto "$src_path" "$dst_path" 2>/dev/null || cp -ax "$src_path" "$dst_path" 2>/dev/null || true
    fi
  done <<< "$entries"
  wt_success "Synced ignored files"
}

# Create a worktree and its associated tmux window.
# stdout: worktree absolute path
# Returns 0 on success, 1 on failure.
wt_create() {
  local branch="${1:-}"
  local base="${2:-}"
  [[ -z "$branch" ]] && { wt_error "branch name required"; return 1; }

  local path win
  path="$(wt_path "$branch")"
  win="$(wt_window_name "$branch")"

  local wt_found=false
  if wt_exists "$branch"; then
    wt_found=true
  fi

  # Existing worktree + existing window: switch and return
  if [[ "$wt_found" == true ]] && wt_window_exists "$win"; then
    wt_info "Switching to existing window: $win"
    wt_select_window "$win"
    echo "$path"
    return 0
  fi

  # Kill orphaned window (worktree deleted but tmux window still exists)
  if [[ "$wt_found" == false ]] && wt_window_exists "$win"; then
    tmux kill-window -t "$win" 2>/dev/null || true
    wt_info "Killed orphaned window: $win"
  fi

  # Create worktree if it doesn't exist
  if [[ "$wt_found" == false ]]; then
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      git worktree add "$path" "$branch" >&2
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
      git worktree add "$path" "$branch" >&2
    else
      if [[ -n "$base" ]]; then
        git worktree add -b "$branch" "$path" "$base" >&2
      else
        git worktree add -b "$branch" "$path" >&2
      fi
    fi
    local main
    main="$(wt_main_worktree)"
    wt_copy_ignored "$main" "$path"
  fi

  # Create tmux window (skip if not in tmux)
  if [[ -n "${TMUX:-}" ]]; then
    tmux new-window -n "$win" -c "$path"
    wt_success "Created window: $win"
  else
    wt_info "Worktree ready: $path"
    wt_info "Not in tmux session, skipping window creation"
  fi

  echo "$path"
}

# Delete a worktree and its associated tmux window.
wt_delete() {
  local branch="${1:-}"
  [[ -z "$branch" ]] && { wt_error "branch name required"; return 1; }

  local path win
  path="$(wt_path "$branch")"
  win="$(wt_window_name "$branch")"

  if wt_window_exists "$win"; then
    tmux kill-window -t "$win"
    wt_info "Closed window: $win"
  fi

  if wt_exists "$branch"; then
    git worktree remove "$path" || { wt_error "Failed to remove worktree (uncommitted changes?)"; return 1; }
    wt_success "Removed worktree: $path"
  else
    wt_info "Worktree not found: $path"
  fi
}

# Remove all worktrees matching the --wt-- pattern.
wt_clean() {
  local repo
  repo="$(wt_repo_name)"

  local found=false
  while IFS= read -r line; do
    local wt_dir branch_info
    wt_dir="$(echo "$line" | awk '{print $1}')"
    branch_info="$(echo "$line" | sed 's/.*\[//' | sed 's/\]//')"

    [[ "$wt_dir" == *--wt--* ]] || continue
    found=true

    local win="${repo}#${branch_info}"
    if wt_window_exists "$win"; then
      tmux kill-window -t "$win"
      wt_info "Closed window: $win"
    fi

    if git worktree remove "$wt_dir" 2>/dev/null; then
      wt_success "Removed: $wt_dir"
    else
      wt_error "Failed to remove: $wt_dir (uncommitted changes?)"
    fi
  done < <(git worktree list)

  git worktree prune
  if [[ "$found" == false ]]; then
    wt_info "No worktrees to clean"
  else
    wt_success "Worktree prune complete"
  fi
}
