#!/bin/bash

# macOS Setup Script (Homebrew packages)
# No -e: individual steps may fail without aborting the rest; failures are
# collected via run_step and reported through finish_steps (non-zero exit).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$DOTFILES_DIR/config"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/utils.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/install-common.sh"

install_brew_bundle() {
  local brewfile="$CONFIG_DIR/Brewfile"
  if [[ ! -f "$brewfile" ]]; then
    log_error "Brewfile not found: $brewfile"
    return 1
  fi
  log_info "Installing Homebrew packages from Brewfile..."
  brew bundle --file="$brewfile"
  log_success "Brewfile packages installed"
}

install_dops() {
  if command_exists dops; then
    log_success "dops already installed"
    return
  fi

  log_info "Installing dops (better docker ps)..."
  mkdir -p "$HOME/.local/bin"

  local arch
  arch=$(uname -m)
  local binary="dops_macos-amd64"
  [[ "$arch" == "arm64" ]] && binary="dops_macos-arm64"

  curl -fsSL "https://github.com/Mikescher/better-docker-ps/releases/latest/download/${binary}" \
    -o "$HOME/.local/bin/dops"
  chmod +x "$HOME/.local/bin/dops"
  log_success "dops installed to ~/.local/bin"
}

install_quay() {
  if command_exists quay; then
    log_success "quay already installed"
    return
  fi

  if ! command_exists cargo; then
    log_warn "cargo not found, skipping quay"
    return
  fi

  log_info "Installing quay (TUI port manager)..."
  cargo install quay-tui
  log_success "quay installed"
}

install_tmux_expose() {
  if command_exists tmux-expose; then
    log_success "tmux-expose already installed"
    return
  fi

  if ! command_exists cargo; then
    log_warn "cargo not found, skipping tmux-expose"
    return
  fi

  log_info "Installing tmux-expose (Mission Control session switcher)..."
  cargo install tmux-expose
  log_success "tmux-expose installed"
}

install_cargo_update() {
  if command_exists cargo-install-update; then
    log_success "cargo-update already installed"
    return
  fi

  if ! command_exists cargo; then
    log_warn "cargo not found, skipping cargo-update"
    return
  fi

  log_info "Installing cargo-update..."
  cargo install cargo-update
  log_success "cargo-update installed"
}

install_lemonade() {
  if command_exists lemonade; then
    log_success "lemonade already installed"
    return
  fi

  log_info "Installing lemonade (clipboard relay server)..."
  mkdir -p "$HOME/.local/bin"

  local arch tarball
  arch=$(uname -m)
  if [[ "$arch" == "arm64" ]]; then
    log_warn "lemonade upstream has no darwin_arm64 binary; skipping (build from source via go install if needed)"
    return
  fi
  tarball="lemonade_darwin_amd64.tar.gz"

  local tmpdir
  tmpdir=$(mktemp -d)
  curl -fsSL "https://github.com/lemonade-command/lemonade/releases/latest/download/${tarball}" \
    -o "$tmpdir/lemonade.tar.gz"
  tar -xzf "$tmpdir/lemonade.tar.gz" -C "$tmpdir"
  mv "$tmpdir/lemonade" "$HOME/.local/bin/lemonade"
  chmod +x "$HOME/.local/bin/lemonade"
  rm -rf "$tmpdir"
  log_success "lemonade installed to ~/.local/bin"

  # launchd: lemonade-server を常駐 (port 2489 で listen)
  local plist_src="$DOTFILES_DIR/templates/com.user.lemonade.plist"
  local plist_dst="$HOME/Library/LaunchAgents/com.user.lemonade.plist"
  if [[ -f "$plist_src" ]]; then
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/state"
    sed "s|__HOME__|$HOME|g" "$plist_src" > "$plist_dst"
    launchctl bootout "gui/$(id -u)/com.user.lemonade" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist_dst"
    log_success "lemonade-server launched via launchd (com.user.lemonade)"
  fi
}

install_mise_tools() {
  if ! command_exists mise; then
    log_warn "mise not found, skipping mise tools"
    return
  fi

  log_info "Installing tools via mise..."
  eval "$(mise activate bash)"
  mise install -y 2>/dev/null || true
}

set_default_shell() {
  if [[ "$SHELL" == *"zsh"* ]]; then
    log_success "Zsh is already the default shell"
    return
  fi

  log_info "Setting zsh as default shell..."
  chsh -s /bin/zsh
  log_success "Default shell changed to zsh (restart terminal to apply)"
}

link_ai_scripts() {
  mkdir -p "$HOME/.local/bin"

  # ai-notify.sh - required for Claude/Codex/Gemini CLI notifications
  if [[ -f "$SCRIPT_DIR/ai-notify.sh" ]]; then
    ln -sf "$SCRIPT_DIR/ai-notify.sh" "$HOME/.local/bin/ai-notify.sh"
    log_success "Linked ai-notify.sh to ~/.local/bin"
  fi
}

install_cursor_cli() {
  if command_exists cursor-agent; then
    log_success "cursor-agent already installed"
    return
  fi

  log_info "Installing Cursor CLI (cursor-agent)..."
  curl https://cursor.com/install -fsS | bash
  log_success "Cursor CLI installed"
}

# --- Main Execution ---
run_step install_brew_bundle
run_step install_mise_tools
run_step install_npm_packages
run_step install_claude_mem
run_step install_serena
run_step install_context_mode
run_step install_code_review_graph
run_step install_auto_mode
run_step install_cursor_cli
run_step configure_claude_remote_control_autostart
run_step install_dops
run_step install_quay
run_step install_tmux_expose
run_step install_cargo_update
run_step install_lemonade
run_step install_gh_extensions
run_step install_rust_tools
run_step link_ai_scripts
run_step set_default_shell

finish_steps "macOS packages installed!"
