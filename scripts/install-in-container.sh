#!/usr/bin/env bash
# install-in-container.sh — one-command dotfiles bootstrap for a docker container
#
# Assumes:
#   - This script lives at $DOTFILES_DIR/scripts/ and the dotfiles repo is
#     bind-mounted into the container at $HOME/dotfiles.
#   - The container has sudo NOPASSWD (per the project Dockerfile pattern).
#   - install.sh supports --no-sudo --skip-prompt --skip-1p.
#
# What it does:
#   1. Install build tools via apt (gcc / make / pkg-config / libssl-dev /
#      luarocks — required for tmux source build and some nvim plugins).
#   2. Run install.sh in no-sudo, non-interactive, no-1P mode.
#   3. Verify key symlinks + tools are in place.
#
# Usage:
#   From the host:
#     docker exec -it <container> ~/dotfiles/scripts/install-in-container.sh
#
#   From inside the container:
#     ~/dotfiles/scripts/install-in-container.sh

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
APT_PACKAGES=(
  build-essential
  pkg-config
  libssl-dev
  luarocks
)

if [[ ! -f "$DOTFILES_DIR/install.sh" ]]; then
  echo "error: dotfiles not found at $DOTFILES_DIR" >&2
  echo "       Expected bind-mount from host. Check compose.yml volumes." >&2
  exit 1
fi

if [[ ! -f /.dockerenv ]] && [[ -z "${container:-}" ]]; then
  echo "warn: /.dockerenv missing; this script expects to run inside a container." >&2
  echo "      Proceeding anyway, but behavior is not guaranteed." >&2
fi

log()   { printf '[install-in-container] %s\n' "$*"; }
warn()  { printf '[install-in-container] WARN: %s\n' "$*" >&2; }
fail()  { printf '[install-in-container] ERROR: %s\n' "$*" >&2; exit 1; }

# ── Step 1: apt build tools ────────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
  if ! sudo -n true 2>/dev/null; then
    warn "sudo requires a password; skipping apt build tool install."
    warn "  Expect cargo/luarocks-based tools and nvim native plugins to fail."
  else
    log "installing build tools via apt (${APT_PACKAGES[*]})..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${APT_PACKAGES[@]}"
    log "build tools ready."
  fi
else
  warn "apt-get not available; assuming build tools are present in the image."
fi

# ── Step 2: install.sh ────────────────────────────────────────────────────
log "running dotfiles install.sh (--no-sudo --skip-prompt --skip-1p)..."
"$DOTFILES_DIR/install.sh" --no-sudo --skip-prompt --skip-1p
log "install.sh completed."

# ── Step 3: verify ────────────────────────────────────────────────────────
log "verifying symlinks and key tools..."
fail_count=0

check_symlink() {
  local path="$1"
  if [[ -L "$path" ]] && [[ -e "$path" ]]; then
    log "  OK  symlink: $path"
  else
    warn "  MISS symlink: $path"
    fail_count=$((fail_count + 1))
  fi
}

check_tool() {
  local tool="$1"
  if "$DOTFILES_DIR/install.sh" --help 2>/dev/null; then :; fi  # ensure PATH
  # shellcheck disable=SC2016
  local path
  path=$(zsh -i -c "command -v $tool" 2>/dev/null | tail -1)
  if [[ -n "$path" ]]; then
    log "  OK  tool: $tool ($path)"
  else
    warn "  MISS tool: $tool"
    fail_count=$((fail_count + 1))
  fi
}

check_symlink "$HOME/.zshrc"
check_symlink "$HOME/.config/tmux/tmux.conf"
check_symlink "$HOME/.config/starship.toml"

for t in zsh starship mise sheldon eza bat fd rg fzf gh; do
  check_tool "$t"
done

if [[ $fail_count -gt 0 ]]; then
  warn "verify: $fail_count check(s) failed. Open a new zsh (exec zsh) and re-check."
  # Don't exit 1 — partial success is common on first install (some tools appear after exec zsh).
fi

log "done. Open a new shell or run: exec zsh"
