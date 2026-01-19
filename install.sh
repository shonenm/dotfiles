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
install_1password_cli() {
  local os=$(detect_os)

  if [[ "$os" == "mac" ]]; then
    if command_exists brew; then
      log_info "Installing 1Password CLI via Homebrew..."
      brew install 1password-cli
    else
      log_error "Homebrew not found. Please install Homebrew first."
      exit 1
    fi
  elif [[ "$os" == "linux" ]]; then
    if command_exists apt; then
      log_info "Installing 1Password CLI via apt..."
      # Setup SUDO
      local SUDO=""
      [[ $EUID -ne 0 ]] && SUDO="sudo"

      # Add 1Password apt repository
      curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        $SUDO gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg 2>/dev/null || true

      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
        $SUDO tee /etc/apt/sources.list.d/1password.list >/dev/null

      $SUDO apt update
      $SUDO apt install -y 1password-cli
    else
      log_error "apt not found. Please install 1Password CLI manually:"
      echo "  https://developer.1password.com/docs/cli/get-started/"
      exit 1
    fi
  else
    log_error "Unsupported OS. Please install 1Password CLI manually."
    exit 1
  fi
}

check_1password_cli() {
  # Check if op is installed, install if not
  if ! command_exists op; then
    log_warn "1Password CLI is not installed."
    install_1password_cli
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

# Stow a package with conflict detection and backup
stow_package() {
  local pkg_dir="$1"
  local pkg_name="$2"

  # dry-runでコンフリクトを検出
  local conflicts
  conflicts=$(stow -n -d "$pkg_dir" -t "$HOME" "$pkg_name" 2>&1 | \
    grep "existing target" | sed 's/.*existing target is neither a link nor a directory: //' || true)

  # コンフリクトファイルをバックアップ
  if [[ -n "$conflicts" ]]; then
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      local target="$HOME/$file"
      if [[ -e "$target" && ! -L "$target" ]]; then
        if mv "$target" "$target.dotfiles-bak" 2>/dev/null; then
          log_info "    Backed up: $file → $file.dotfiles-bak"
        else
          log_warn "    Cannot move $file (bind mount?), skipping $pkg_name"
          return 0
        fi
      fi
    done <<< "$conflicts"
  fi

  # stow実行（--adoptで残りの差分を吸収）
  if ! stow -d "$pkg_dir" -t "$HOME" --adopt "$pkg_name" 2>/dev/null; then
    log_warn "  Failed to link $pkg_name"
  fi
  return 0
}

# Verify critical symlinks were created
verify_stow() {
  local failed=()
  local checks=(
    ".config/tmux"
    ".config/mise"
    ".config/nvim"
    ".config/starship.toml"
  )

  for path in "${checks[@]}"; do
    # Check if path exists as symlink or directory (stow creates symlinks to dirs)
    if [[ ! -L "$HOME/$path" && ! -e "$HOME/$path" ]]; then
      failed+=("$path")
    fi
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo
    log_warn "Some dotfiles may not be linked correctly:"
    for f in "${failed[@]}"; do
      log_warn "  - ~/$f"
    done
    log_info "Try running manually: stow -v -t ~ -d common <package>"
    log_info "Or check for conflicts with: stow -n -v -t ~ -d common <package>"
  fi
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

  # Restore dotfiles after adopt (adopted files may have overwritten our dotfiles)
  log_info "Restoring dotfiles from git..."
  git -C "$DOTFILES_DIR" checkout -- common/ 2>/dev/null || true
  [[ -d "$DOTFILES_DIR/$os" ]] && git -C "$DOTFILES_DIR" checkout -- "$os/" 2>/dev/null || true

  # Create empty .gitconfig.local if not exists (for machine-specific git user settings)
  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    touch "$HOME/.gitconfig.local"
    log_info "Created ~/.gitconfig.local for machine-specific git settings"
    log_info "Run 'setup_git_from_op' to configure git user from 1Password"
  fi

  # Verify critical symlinks were created
  verify_stow

  log_success "Dotfiles linked successfully"
}

# --- 4. Generate AI CLI configs from templates ---
# These configs need absolute paths for hooks to work in non-interactive shells
generate_ai_cli_configs() {
  log_info "Generating AI CLI configs..."

  # Clear webhook cache to ensure fresh URLs from 1Password
  local cache_dir="${XDG_DATA_HOME:-$HOME/.local/share}/ai-notify"
  if [[ -d "$cache_dir" ]]; then
    rm -rf "$cache_dir"
    log_info "  Cleared webhook cache"
  fi

  local templates_dir="$DOTFILES_DIR/templates"

  # Claude CLI
  if [[ -f "$templates_dir/claude-settings.json" ]]; then
    mkdir -p "$HOME/.claude"
    rm -f "$HOME/.claude/settings.json" 2>/dev/null || true
    sed "s|__HOME__|$HOME|g" "$templates_dir/claude-settings.json" > "$HOME/.claude/settings.json"
    log_success "  Generated ~/.claude/settings.json"
  fi

  # Claude Code skills
  if [[ -d "$templates_dir/claude-skills" ]]; then
    mkdir -p "$HOME/.claude/skills"
    for skill_dir in "$templates_dir/claude-skills"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      mkdir -p "$HOME/.claude/skills/$skill_name"
      for file in "$skill_dir"*; do
        [[ -f "$file" ]] || continue
        sed "s|__HOME__|$HOME|g" "$file" > "$HOME/.claude/skills/$skill_name/$(basename "$file")"
      done
      log_success "  Generated skill: $skill_name"
    done
  fi

  # Codex CLI
  if [[ -f "$templates_dir/codex-config.toml" ]]; then
    mkdir -p "$HOME/.codex"
    sed "s|__HOME__|$HOME|g" "$templates_dir/codex-config.toml" > "$HOME/.codex/config.toml"
    log_success "  Generated ~/.codex/config.toml"
  fi

  # Gemini CLI
  if [[ -f "$templates_dir/gemini-settings.json" ]]; then
    mkdir -p "$HOME/.gemini"
    sed "s|__HOME__|$HOME|g" "$templates_dir/gemini-settings.json" > "$HOME/.gemini/settings.json"
    log_success "  Generated ~/.gemini/settings.json"
  fi

  # Cache webhooks and send setup notifications
  log_info "  Caching webhooks..."
  for tool in claude codex gemini; do
    if "$DOTFILES_DIR/scripts/ai-notify.sh" --setup "$tool" 2>/dev/null; then
      log_success "    ✓ $tool webhook cached and notified"
    else
      log_warn "    ✗ $tool webhook not available"
    fi
  done
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

  # 3.5. Install sheldon plugins
  if command_exists sheldon; then
    log_info "Installing sheldon plugins..."
    sheldon lock --update
    log_success "Sheldon plugins installed"
  fi

  # 3.6. Regenerate tmux theme on Linux (fixes powerline char encoding)
  if [[ "$(detect_os)" == "linux" ]]; then
    log_info "Regenerating tmux theme for Linux..."
    "$DOTFILES_DIR/scripts/regenerate-tmux-theme.sh" "$HOME/.config/tmux/tokyonight.tmux"
  fi

  # 4. Generate AI CLI configs (with absolute paths)
  generate_ai_cli_configs

  echo
  log_success "=== Installation Complete! ==="
  log_info "Please restart your shell or run: source ~/.zshrc"

  # Show mise-managed tools info
  echo
  echo "────────────────────────────────────────────────────────"
  echo "  mise-managed tools"
  echo "────────────────────────────────────────────────────────"
  echo "  node   (lts)    - Node.js / npm"
  echo "  python (latest) - Python"
  echo ""
  echo "  Commands:"
  echo "    mise install        # Install all tools"
  echo "    mise list           # Show installed versions"
  echo "    mise use node@20    # Switch version (project)"
  echo "    mise use -g node@22 # Switch version (global)"
  echo "────────────────────────────────────────────────────────"
}

main "$@"
