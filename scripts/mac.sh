#!/bin/bash

# macOS Setup Script (Homebrew packages)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$DOTFILES_DIR/config"
source "$SCRIPT_DIR/utils.sh"

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

install_npm_packages() {
  if ! command_exists npm; then
    log_warn "npm not found, skipping npm packages"
    return
  fi

  local npm_file="$CONFIG_DIR/packages.npm.txt"
  if [[ ! -f "$npm_file" ]]; then
    log_warn "NPM package list not found: $npm_file"
    return
  fi

  log_info "Installing npm packages..."
  while IFS= read -r pkg; do
    if ! npm list -g "$pkg" &>/dev/null; then
      log_info "Installing $pkg..."
      npm install -g "$pkg"
    else
      log_success "$pkg already installed"
    fi
  done < <(read_package_list "$npm_file")
}

install_dops() {
  if command_exists dops; then
    log_success "dops already installed"
    return
  fi

  log_info "Installing dops (better docker ps)..."
  mkdir -p "$HOME/.local/bin"

  local arch=$(uname -m)
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

install_gh_extensions() {
  if ! command_exists gh; then
    log_warn "gh CLI not found, skipping gh extensions"
    return
  fi

  if gh extension list | grep -q "dlvhdr/gh-dash"; then
    log_success "gh-dash already installed"
  else
    log_info "Installing gh-dash extension..."
    gh extension install dlvhdr/gh-dash
    log_success "gh-dash installed"
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

# --- Main Execution ---
install_brew_bundle
install_mise_tools
install_npm_packages
install_dops
install_quay
install_gh_extensions
link_ai_scripts
set_default_shell

log_success "macOS packages installed!"
