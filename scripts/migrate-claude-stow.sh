#!/bin/bash
# Migrate ~/.claude from directory symlink to individual file symlinks
# This fixes the issue where Claude runtime files were written into the dotfiles repo

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/utils.sh
source "$DOTFILES_DIR/scripts/utils.sh"

main() {
  log_info "Checking ~/.claude structure..."

  # Check if ~/.claude is a directory symlink
  if [ -L ~/.claude ]; then
    log_warn "$HOME/.claude is a directory symlink (stow folding detected)"
    log_info "This will be migrated to individual file symlinks"
    echo

    # Get the symlink target
    local target
    target="$(readlink ~/.claude)"
    log_info "Current target: $target"

    # Backup runtime files
    local backup_dir
    backup_dir="/tmp/claude-migration-$(date +%s)"
    mkdir -p "$backup_dir"

    log_info "Backing up runtime files to $backup_dir..."

    # List of runtime files/dirs to preserve
    local runtime_items=(
      ".credentials.json"
      "backups"
      "cache"
      "file-history"
      "history.jsonl"
      "mcp-needs-auth-cache.json"
      "paste-cache"
      "plans"
      "plugins"
      "projects"
      "session-env"
      "sessions"
      "shell-snapshots"
      "telemetry"
      "debug"
      "ide"
      "news-profile.yaml"
    )

    for item in "${runtime_items[@]}"; do
      if [ -e ~/.claude/"$item" ]; then
        cp -a ~/.claude/"$item" "$backup_dir/" 2>/dev/null || true
        log_info "  Backed up: $item"
      fi
    done

    # Remove the directory symlink
    log_info "Removing directory symlink..."
    rm ~/.claude

    # Recreate as real directory
    mkdir -p ~/.claude

    # Restore runtime files
    log_info "Restoring runtime files..."
    for item in "${runtime_items[@]}"; do
      if [ -e "$backup_dir/$item" ]; then
        cp -a "$backup_dir/$item" ~/.claude/ 2>/dev/null || true
        log_success "  Restored: $item"
      fi
    done

    # Re-stow to create individual symlinks
    log_info "Re-running stow with --no-folding..."
    cd "$DOTFILES_DIR"
    stow --no-folding -d common -t ~ --restow claude

    log_success "Migration completed!"
    log_info "Backup kept at: $backup_dir"
    echo
    log_info "Verifying structure..."

  elif [ -d ~/.claude ]; then
    log_success "$HOME/.claude is already a directory (not a symlink)"
    log_info "Checking individual files..."

    # Check if individual files are symlinks
    local has_symlinks=false
    for item in agents hooks rules skills; do
      if [ -L ~/.claude/"$item" ]; then
        log_success "  $item -> $(readlink ~/.claude/$item)"
        has_symlinks=true
      elif [ -d ~/.claude/"$item" ]; then
        log_warn "  $item is a regular directory (should be symlink)"
      fi
    done

    if [ "$has_symlinks" = false ]; then
      log_warn "No expected symlinks found. Re-running stow..."
      cd "$DOTFILES_DIR"
      stow --no-folding -d common -t ~ --restow claude
      log_success "Stow completed"
    fi

  else
    log_warn "$HOME/.claude does not exist"
    log_info "Running stow to create it..."
    cd "$DOTFILES_DIR"
    stow --no-folding -d common -t ~ claude
    log_success "Stow completed"
  fi

  echo
  log_success "=== Structure Verification ==="
  echo "$HOME/.claude type: $([ -L ~/.claude ] && echo "symlink" || echo "directory")"
  for item in agents hooks rules skills .gitignore; do
    if [ -e ~/.claude/"$item" ]; then
      if [ -L ~/.claude/"$item" ]; then
        echo "  $item: symlink -> $(readlink ~/.claude/$item)"
      else
        echo "  $item: $([ -d ~/.claude/$item ] && echo "directory" || echo "file")"
      fi
    fi
  done

  echo
  log_info "Runtime files (should NOT be symlinks):"
  for item in history.jsonl cache file-history; do
    if [ -e ~/.claude/"$item" ]; then
      if [ -L ~/.claude/"$item" ]; then
        log_warn "  $item: symlink (UNEXPECTED!)"
      else
        log_success "  $item: $([ -d ~/.claude/$item ] && echo "directory" || echo "file") (OK)"
      fi
    fi
  done
}

main "$@"
