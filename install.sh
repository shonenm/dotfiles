#!/bin/bash
set -euo pipefail

# Dotfiles root directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "$DOTFILES_DIR/scripts/utils.sh"

# --- Argument Parsing ---
SKIP_PROMPT=false
for arg in "$@"; do
  [[ "$arg" == "-y" ]] && SKIP_PROMPT=true
done

# --- 0. 1Password CLI Check (Required) ---
check_1password_cli() {
  # Check if op is installed
  if ! command_exists op; then
    log_error "1Password CLI is not installed."
    echo
    echo "  Install instructions:"
    echo "    Mac:   brew install 1password-cli"
    echo "    Linux: https://developer.1password.com/docs/cli/get-started/"
    echo
    exit 1
  fi

  # Check if signed in
  if ! op whoami &>/dev/null; then
    log_error "1Password CLI is not signed in."
    echo
    echo "  Run the following command to sign in:"
    echo "    eval \$(op signin)"
    echo
    echo "  Then re-run this script."
    exit 1
  fi

  log_success "1Password CLI: ready"
}

# --- 1. Install Homebrew (Mac only) ---
install_homebrew() {
  if [[ "$(detect_os)" != "mac" ]]; then
    return
  fi

  if command_exists brew; then
    log_success "Homebrew already installed"
    return
  fi

  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add to PATH for this session
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

# --- 2. Setup Environment (Delegate to scripts/) ---
setup_environment() {
  local os=$(detect_os)
  log_info "Detected OS: $os"

  case "$os" in
    mac)
      if [[ -f "$DOTFILES_DIR/scripts/mac.sh" ]]; then
        log_info "Running macOS setup script..."
        bash "$DOTFILES_DIR/scripts/mac.sh"
      else
        log_warn "scripts/mac.sh not found. Skipping package installation."
      fi
      ;;
    linux)
      if [[ -f "$DOTFILES_DIR/scripts/linux.sh" ]]; then
        log_info "Running Linux setup script..."
        bash "$DOTFILES_DIR/scripts/linux.sh"
      else
        log_warn "scripts/linux.sh not found. Skipping package installation."
      fi
      ;;
    *)
      log_warn "Unsupported OS. Skipping package installation."
      ;;
  esac
}

# --- 3. Link Dotfiles (Stow) ---
BACKUP_DIR=""

# Initialize backup directory (called once per install)
init_backup_dir() {
  BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"
}

# Backup a file preserving directory structure
backup_file() {
  local file="$1"
  if [[ -z "$BACKUP_DIR" ]]; then
    init_backup_dir
  fi
  local relative_path="${file#$HOME/}"
  local backup_path="$BACKUP_DIR/$relative_path"
  mkdir -p "$(dirname "$backup_path")"

  # Try mv first, if fails (device busy), use cp + rm
  if ! mv "$file" "$backup_path" 2>/dev/null; then
    cp -a "$file" "$backup_path" && rm -f "$file"
  fi
  log_warn "  Backed up: ~/$relative_path"
}

# Stow a package with conflict handling
stow_package() {
  local pkg_dir="$1"
  local pkg_name="$2"

  cd "$pkg_dir"

  # Dry-run to detect conflicts
  local output
  output=$(stow -n -t "$HOME" "$pkg_name" 2>&1) || true

  # Check for conflicts (existing files not owned by stow or regular files)
  if echo "$output" | grep -q "existing target"; then
    # Extract conflicting files from error messages like:
    # "existing target is not owned by stow: .gitconfig"
    # "existing target is neither a link nor a directory: .gitconfig"
    local files
    files=$(echo "$output" | grep "existing target" | \
            grep -oE ': [^ ]+$' | sed 's/: //')

    # Backup each conflicting file
    for file in $files; do
      if [[ -n "$file" && -e "$HOME/$file" ]]; then
        backup_file "$HOME/$file"
      fi
    done
  fi

  # Now stow (should succeed after backing up conflicts)
  stow -t "$HOME" -R "$pkg_name" 2>&1 | grep -v "^LINK:" || true
}

link_dotfiles() {
  log_info "Linking dotfiles..."

  # Check if stow is installed
  if ! command_exists stow; then
    log_error "Stow is not installed. Skipping linking."
    log_warn "Please check if setup scripts ran correctly."
    return 1
  fi

  # Create .config if not exists
  mkdir -p "$HOME/.config"

  # Stow common packages
  if [[ -d "$DOTFILES_DIR/common" ]]; then
    log_info "Linking common dotfiles..."
    for pkg in "$DOTFILES_DIR/common"/*/; do
      pkg_name="$(basename "$pkg")"
      log_info "  Linking $pkg_name..."
      stow_package "$DOTFILES_DIR/common" "$pkg_name"
    done
  fi

  # Stow OS-specific packages
  local os=$(detect_os)
  if [[ -d "$DOTFILES_DIR/$os" ]]; then
    log_info "Linking $os-specific dotfiles..."
    for pkg in "$DOTFILES_DIR/$os"/*/; do
      pkg_name="$(basename "$pkg")"
      log_info "  Linking $pkg_name..."
      stow_package "$DOTFILES_DIR/$os" "$pkg_name"
    done
  fi

  # Show backup location if any files were backed up
  if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
    echo
    log_warn "Some existing files were backed up to:"
    log_warn "  $BACKUP_DIR"
    log_info "You can restore them manually if needed."
  fi

  log_success "Dotfiles linked successfully"
}

# --- Main ---
main() {
  log_info "=== Dotfiles Installation Start ==="
  log_info "OS: $(detect_os)"
  log_info "Dotfiles: $DOTFILES_DIR"
  echo

  # 0. Check 1Password CLI first
  check_1password_cli

  # 1. Install Homebrew (Mac only, required before other packages)
  install_homebrew

  # 2. Run environment setup (install packages)
  if [[ "$SKIP_PROMPT" == "true" ]]; then
    setup_environment
  else
    read -p "Install packages? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      setup_environment
    fi
  fi

  # 3. Link dotfiles (stow)
  link_dotfiles

  echo
  log_success "=== Installation Complete! ==="
  log_info "Please restart your shell or run: source ~/.zshrc"
}

main "$@"
