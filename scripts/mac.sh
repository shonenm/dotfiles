#!/bin/bash

# macOS Setup Script (Homebrew packages)

BREW_PACKAGES=(
  # Shell & Terminal
  fish
  starship
  sheldon
  atuin
  zoxide

  # Development
  neovim
  lazygit
  gh
  mise

  # Modern CLI tools
  eza
  bat
  ripgrep
  fd
  fzf
  jq
  yazi
)

BREW_CASKS=(
  # Terminal
  ghostty

  # Productivity
  raycast
  karabiner-elements
)

install_brew_packages() {
  log_info "Installing Homebrew packages..."

  for pkg in "${BREW_PACKAGES[@]}"; do
    if ! brew list "$pkg" &>/dev/null; then
      log_info "Installing $pkg..."
      brew install "$pkg"
    else
      log_success "$pkg already installed"
    fi
  done
}

install_brew_casks() {
  log_info "Installing Homebrew casks..."

  for cask in "${BREW_CASKS[@]}"; do
    if ! brew list --cask "$cask" &>/dev/null; then
      log_info "Installing $cask..."
      brew install --cask "$cask"
    else
      log_success "$cask already installed"
    fi
  done
}

# Run if sourced
install_brew_packages
install_brew_casks

log_success "macOS packages installed!"
