#!/bin/bash

# macOS Setup Script (Homebrew packages)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

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
  lazydocker
  gh
  mise
  uv
  rust

  # Modern CLI tools
  eza
  bat
  ripgrep
  fd
  fzf
  jq
  yazi
  tokei
)

BREW_CASKS=(
  # Terminal
  ghostty

  # Productivity
  raycast
  karabiner-elements
  aerospace

  # Fonts
  font-sketchybar-app-font
)

NPM_PACKAGES=(
  # AI CLI tools
  "@anthropic-ai/claude-code"
  "@openai/codex"
  "@google/gemini-cli"
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

install_npm_packages() {
  if ! command_exists npm; then
    log_warn "npm not found, skipping npm packages"
    return
  fi

  log_info "Installing npm packages..."

  for pkg in "${NPM_PACKAGES[@]}"; do
    if ! npm list -g "$pkg" &>/dev/null; then
      log_info "Installing $pkg..."
      npm install -g "$pkg"
    else
      log_success "$pkg already installed"
    fi
  done
}

install_dotenvx() {
  if command_exists dotenvx; then
    log_success "dotenvx already installed"
    return
  fi

  log_info "Installing dotenvx..."
  brew install dotenvx/brew/dotenvx
}

install_mise_tools() {
  if ! command_exists mise; then
    log_warn "mise not found, skipping mise tools"
    return
  fi

  log_info "Installing tools via mise..."
  eval "$(mise activate bash)"
  mise install node python pnpm -y 2>/dev/null || true
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

# Run if sourced
install_brew_packages
install_brew_casks
install_mise_tools
install_npm_packages
install_dotenvx
link_ai_scripts
set_default_shell

log_success "macOS packages installed!"
