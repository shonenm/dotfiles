#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "$DOTFILES_DIR/scripts/utils.sh"

# Install Homebrew (Mac only)
install_homebrew() {
  if [[ "$(detect_os)" != "mac" ]]; then
    return
  fi

  if ! command_exists brew; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to PATH for this session
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    log_success "Homebrew already installed"
  fi
}

# Install GNU Stow
install_stow() {
  if command_exists stow; then
    log_success "GNU Stow already installed"
    return
  fi

  log_info "Installing GNU Stow..."
  case "$(detect_os)" in
    mac)   brew install stow ;;
    linux) sudo apt install -y stow ;;
  esac
}

# Install OS-specific packages
install_packages() {
  local os=$(detect_os)

  case "$os" in
    mac)
      log_info "Installing Mac packages..."
      source "$DOTFILES_DIR/scripts/mac.sh"
      ;;
    linux)
      log_info "Installing Linux packages..."
      source "$DOTFILES_DIR/scripts/linux.sh"
      ;;
  esac
}

# Stow dotfiles
stow_dotfiles() {
  local os=$(detect_os)

  # Stow common packages
  log_info "Stowing common dotfiles..."
  cd "$DOTFILES_DIR/common"
  for pkg in */; do
    pkg_name="${pkg%/}"
    log_info "  Stowing $pkg_name..."
    stow -t "$HOME" -R "$pkg_name" 2>/dev/null || log_warn "  Failed to stow $pkg_name"
  done

  # Stow OS-specific packages
  if [[ "$os" == "mac" && -d "$DOTFILES_DIR/mac" ]]; then
    log_info "Stowing macOS-specific dotfiles..."
    cd "$DOTFILES_DIR/mac"
    for pkg in */; do
      pkg_name="${pkg%/}"
      log_info "  Stowing $pkg_name..."
      stow -t "$HOME" -R "$pkg_name" 2>/dev/null || log_warn "  Failed to stow $pkg_name"
    done
  fi

  if [[ "$os" == "linux" && -d "$DOTFILES_DIR/linux" ]]; then
    log_info "Stowing Linux-specific dotfiles..."
    cd "$DOTFILES_DIR/linux"
    for pkg in */; do
      pkg_name="${pkg%/}"
      log_info "  Stowing $pkg_name..."
      stow -t "$HOME" -R "$pkg_name" 2>/dev/null || log_warn "  Failed to stow $pkg_name"
    done
  fi
}

# Main
main() {
  log_info "=== Dotfiles Setup ==="
  log_info "OS: $(detect_os)"
  log_info "Dotfiles: $DOTFILES_DIR"
  echo

  # Create .config if not exists
  mkdir -p "$HOME/.config"

  # Install dependencies
  install_homebrew
  install_stow

  # Ask if user wants to install packages
  read -p "Install packages? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    install_packages
  fi

  # Stow dotfiles
  stow_dotfiles

  echo
  log_success "=== Dotfiles setup complete! ==="
  log_info "Restart your shell or run: source ~/.zshrc"
}

main "$@"
