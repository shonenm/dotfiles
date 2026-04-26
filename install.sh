#!/bin/bash
set -euo pipefail

# Dotfiles root directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "$DOTFILES_DIR/scripts/utils.sh"

# --- Argument Parsing ---
# NO_SUDO defaults to false (use sudo/system path).
# Pass --no-sudo to opt into pixi-based user-scope install on sudoless hosts.
SKIP_PROMPT=false
NO_SUDO=false
SKIP_1P=false
for arg in "$@"; do
  case "$arg" in
    -y|--skip-prompt) SKIP_PROMPT=true ;;
    --no-sudo)        NO_SUDO=true ;;
    --skip-1p)        SKIP_1P=true ;;
  esac
done
export NO_SUDO SKIP_1P

# --- 0. 1Password CLI Check (Required) ---
install_1password_cli() {
  local os
  os=$(detect_os)

  if [[ "$os" == "mac" ]]; then
    if command_exists brew; then
      log_info "Installing 1Password CLI via Homebrew..."
      brew install 1password-cli
    else
      log_error "Homebrew not found. Please install Homebrew first."
      exit 1
    fi
  elif [[ "$os" == "linux" ]]; then
    if [[ "$NO_SUDO" == "true" ]]; then
      _install_1password_cli_user_scope
    elif command_exists apt; then
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

# Install 1Password CLI to ~/.local/bin without sudo (tarball from cache.agilebits.com)
_install_1password_cli_user_scope() {
  local arch
  case "$(uname -m)" in
    x86_64)         arch="amd64" ;;
    aarch64|arm64)  arch="arm64" ;;
    *)              log_error "Unsupported arch for 1Password CLI: $(uname -m)"; return 1 ;;
  esac

  # Resolve latest version from AgileBits update API (fall back to known-good if API/json fails)
  local version="${OP_CLI_VERSION:-}"
  if [[ -z "$version" ]]; then
    version=$(curl -fsSL 'https://app-updates.agilebits.com/check/1/0/CLI2/en/0/N' 2>/dev/null \
      | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version",""))' 2>/dev/null \
      || true)
  fi
  version="${version:-2.33.1}"

  local zip="/tmp/op.zip"
  local url="https://cache.agilebits.com/dist/1P/op2/pkg/v${version}/op_linux_${arch}_v${version}.zip"

  log_info "Installing 1Password CLI v${version} (user-scope, no sudo)..."
  mkdir -p "$HOME/.local/bin"
  if ! curl -fsSL "$url" -o "$zip"; then
    log_error "Failed to download 1Password CLI from $url"
    log_error "Override version with OP_CLI_VERSION env var (see https://app-updates.agilebits.com/product_history/CLI2)"
    return 1
  fi
  if ! command_exists unzip; then
    log_error "unzip not found. Install via pixi first: pixi global install unzip"
    rm -f "$zip"
    return 1
  fi
  unzip -o "$zip" op -d "$HOME/.local/bin" >/dev/null
  chmod +x "$HOME/.local/bin/op"
  rm -f "$zip"
  export PATH="$HOME/.local/bin:$PATH"
  log_success "1Password CLI installed to ~/.local/bin/op"
}

check_1password_cli() {
  # --skip-1p: container / ephemeral env で secret lookup が不要な時。
  # Notion MCP 等を使うステップは対応する op read が no-op fallback するので
  # 警告だけ出して続行する。
  if [[ "$SKIP_1P" == "true" ]]; then
    log_warn "1Password CLI check skipped (--skip-1p). Secret-dependent steps will no-op."
    return 0
  fi

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
    echo "  Or skip 1Password secrets entirely:"
    echo "    $0 --skip-1p (combine with --skip-prompt --no-sudo as needed)"
    echo
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
  local os
  os=$(detect_os)
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
  conflicts=$(stow -n --no-folding -d "$pkg_dir" -t "$HOME" "$pkg_name" 2>&1 | \
    grep "existing target" | sed 's/.*over existing target //' | sed 's/ since.*//' || true)

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

  # stow実行（--adoptで残りの差分を吸収、--no-foldingでディレクトリ全体のシンリンクを防止）
  if ! stow --no-folding -d "$pkg_dir" -t "$HOME" --adopt "$pkg_name" 2>/dev/null; then
    log_warn "  Failed to link $pkg_name"
  fi
  return 0
}

# Clean up orphaned (non-symlink) files left behind in stow-managed directories.
# stow --adopt only handles files present in the stow package. Files that exist
# only in the target directory are ignored, causing stale configs to persist.
# Usage: cleanup_stow_orphans <pkg_dir> <relative_subdir>
cleanup_stow_orphans() {
  local pkg_dir="$1"     # e.g. /path/to/dotfiles/common
  local subdir="$2"      # e.g. nvim/.config/nvim/lua/plugins
  local pkg_name="${subdir%%/*}"  # e.g. nvim
  local target_dir="$HOME/${subdir#*/}"  # e.g. ~/.config/nvim/lua/plugins
  local source_dir="$pkg_dir/$subdir"

  [[ -d "$target_dir" ]] || return 0
  [[ -d "$source_dir" ]] || return 0

  local orphans_found=false
  for file in "$target_dir"/*.lua; do
    [[ -e "$file" ]] || continue
    # Skip symlinks (managed by stow) and backup files
    [[ -L "$file" ]] && continue
    [[ "$file" == *.dotfiles-bak ]] && continue

    local basename
    basename="$(basename "$file")"

    # Only remove if there's no corresponding file in the stow source
    if [[ ! -e "$source_dir/$basename" ]]; then
      if ! $orphans_found; then
        log_info "  Cleaning up orphaned files in ~/${subdir#*/}/"
        orphans_found=true
      fi
      mv "$file" "$file.dotfiles-bak"
      log_info "    Backed up orphan: $basename → $basename.dotfiles-bak"
    fi
  done
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

# Fixup bind-mounted config files that stow couldn't replace
fixup_bind_mounts() {
  # .gitconfig: inject [include] to pull in dotfiles gitconfig
  local dotfiles_gitconfig="$DOTFILES_DIR/common/git/.gitconfig"
  if [[ -f "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" && -f "$dotfiles_gitconfig" ]]; then
    if ! grep -qF "path = $dotfiles_gitconfig" "$HOME/.gitconfig" 2>/dev/null; then
      if [[ -w "$HOME/.gitconfig" ]]; then
        printf '\n[include]\n    path = %s\n' "$dotfiles_gitconfig" >> "$HOME/.gitconfig"
        log_info "  Injected [include] into bind-mounted .gitconfig"
      else
        # Fallback: Git reads both ~/.gitconfig and $XDG_CONFIG_HOME/git/config
        local xdg_git_config="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
        mkdir -p "$(dirname "$xdg_git_config")"
        if ! grep -qF "path = $dotfiles_gitconfig" "$xdg_git_config" 2>/dev/null; then
          printf '[include]\n    path = %s\n' "$dotfiles_gitconfig" >> "$xdg_git_config"
        fi
        log_info "  .gitconfig is read-only, wrote [include] to $xdg_git_config"
      fi
    else
      log_success "  .gitconfig already includes dotfiles config"
    fi
  fi

  # .ssh/config: prepend Include to pull in dotfiles ssh config
  local os
  os=$(detect_os)
  local dotfiles_ssh="$DOTFILES_DIR/$os/ssh/.ssh/config"
  if [[ -f "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" && -f "$dotfiles_ssh" ]]; then
    if ! grep -qF "Include $dotfiles_ssh" "$HOME/.ssh/config" 2>/dev/null; then
      if [[ -w "$HOME/.ssh/config" ]]; then
        local tmp
        tmp=$(mktemp)
        printf 'Include %s\n\n' "$dotfiles_ssh" > "$tmp"
        cat "$HOME/.ssh/config" >> "$tmp"
        cp "$tmp" "$HOME/.ssh/config"
        rm "$tmp"
        log_info "  Injected Include into bind-mounted .ssh/config"
      else
        log_warn "  .ssh/config is read-only, skipping injection"
      fi
    else
      log_success "  .ssh/config already includes dotfiles config"
    fi
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
  local os
  os=$(detect_os)
  if [[ -d "$DOTFILES_DIR/$os" ]]; then
    log_info "Linking $os-specific dotfiles..."
    for pkg in "$DOTFILES_DIR/$os"/*/; do
      pkg_name="$(basename "$pkg")"
      log_info "  Linking $pkg_name..."
      stow_package "$DOTFILES_DIR/$os" "$pkg_name"
    done
  fi

  # Fixup bind-mounted config files (Docker/devcontainer)
  fixup_bind_mounts

  # Restore dotfiles after adopt (adopted files may have overwritten our dotfiles)
  log_info "Restoring dotfiles from git..."
  git -C "$DOTFILES_DIR" checkout -- common/ 2>/dev/null || true
  [[ -d "$DOTFILES_DIR/$os" ]] && git -C "$DOTFILES_DIR" checkout -- "$os/" 2>/dev/null || true

  # Clean up orphaned files in stow-managed directories
  # stow --adopt only handles files that exist in both source and target.
  # Files that exist only in the target (e.g. pre-stow nvim plugin configs) are left behind
  # and can interfere with the dotfiles config (LazyVim loads all lua/plugins/*.lua files).
  cleanup_stow_orphans "$DOTFILES_DIR/common" "nvim/.config/nvim/lua/plugins"
  cleanup_stow_orphans "$DOTFILES_DIR/common" "nvim/.config/nvim/lua/config"

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

# --- 3.7. Setup tmux plugins (TPM + tmux-which-key) ---
setup_tmux_plugins() {
  local tpm_path="$HOME/.tmux/plugins/tpm"

  # Install TPM if not present
  if [[ ! -d "$tpm_path" ]]; then
    log_info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$tpm_path"
  fi

  # Install TPM plugins (non-interactive)
  if [[ -x "$tpm_path/bin/install_plugins" ]]; then
    log_info "Installing tmux plugins via TPM..."
    "$tpm_path/bin/install_plugins" >/dev/null 2>&1 || true
  fi

  # Setup tmux-which-key config symlink
  local whichkey_plugin="$HOME/.tmux/plugins/tmux-which-key"
  local whichkey_config="$HOME/.config/tmux/plugins/tmux-which-key/config.yaml"
  if [[ -d "$whichkey_plugin" && -f "$whichkey_config" ]]; then
    ln -sf "$whichkey_config" "$whichkey_plugin/config.yaml"
    log_info "Linked tmux-which-key config"

    # Rebuild tmux-which-key menu (requires Python)
    if command_exists python3 && [[ -x "$whichkey_plugin/plugin.sh.tmux" ]]; then
      log_info "Building tmux-which-key menu..."
      "$whichkey_plugin/plugin.sh.tmux" >/dev/null 2>&1 || true
    fi
  fi

  # tmux-thumbs: build Rust binary if cargo is available
  local thumbs_plugin="$HOME/.tmux/plugins/tmux-thumbs"
  if [[ -d "$thumbs_plugin" ]] && command_exists cargo; then
    if [[ ! -x "$thumbs_plugin/target/release/thumbs" ]]; then
      log_info "Building tmux-thumbs..."
      (cd "$thumbs_plugin" && cargo build --release) >/dev/null 2>&1 || true
    fi
  fi

  log_success "tmux plugins installed"
}

# --- 3.8. Link dotfiles repo's git hooks ---
# scripts/git-hooks/* are committed in the repo. Link them into .git/hooks/
# so they run on git operations against the dotfiles repo itself. Currently:
#   - post-merge: broadcasts `tmux source-file` to all running tmux servers
#                 after `git pull`, so config edits propagate live.
setup_git_hooks() {
  local hooks_src="$DOTFILES_DIR/scripts/git-hooks"
  local hooks_dst="$DOTFILES_DIR/.git/hooks"

  [[ -d "$hooks_src" ]] || return 0
  [[ -d "$hooks_dst" ]] || return 0

  for hook in "$hooks_src"/*; do
    [[ -f "$hook" ]] || continue
    local name; name="$(basename "$hook")"
    ln -sf "$hook" "$hooks_dst/$name"
    log_info "Linked git hook: $name"
  done
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

  # Claude MCP servers (from mcp.json, secrets resolved via 1Password)
  local mcp_config="$DOTFILES_DIR/common/claude/.config/claude/mcp.json"
  if [[ -f "$mcp_config" ]] && command -v claude &>/dev/null; then
    local notion_token=""
    if command -v op &>/dev/null; then
      notion_token=$(op read "op://Personal/Notion MCP/credential" 2>/dev/null || true)
    fi
    # Read each server from mcp.json and register via claude mcp add-json
    python3 -c "
import json, sys
with open('$mcp_config') as f:
    servers = json.load(f)['mcpServers']
for name, config in servers.items():
    print(json.dumps({'name': name, 'config': config}))
" | while IFS= read -r entry; do
      local name config
      name=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
      config=$(echo "$entry" | python3 -c "import json,sys; d=json.load(sys.stdin)['config']; print(json.dumps(d))")
      # Resolve ${NOTION_TOKEN} placeholder
      if [[ -n "$notion_token" ]]; then
        config="${config//\$\{NOTION_TOKEN\}/$notion_token}"
      fi
      # Resolve ${HOME} placeholder (e.g. for cache dirs)
      config="${config//\$\{HOME\}/$HOME}"
      if claude mcp add-json --scope user "$name" "$config" >/dev/null 2>&1; then
        log_success "  Registered MCP server: $name"
      else
        log_warn "  Failed to register MCP server: $name"
      fi
    done
  fi

  # Claude Code skills (from common/claude, skip if Stow symlinks exist)
  local skills_src="$DOTFILES_DIR/common/claude/.claude/skills"
  if [[ -d "$skills_src" ]]; then
    mkdir -p "$HOME/.claude/skills"
    for skill_dir in "$skills_src"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      local target_dir="$HOME/.claude/skills/$skill_name"
      # Stow がディレクトリ自体をシンボリックリンクにしている場合はスキップ
      if [[ -L "$target_dir" ]]; then
        log_success "  Skill already linked: $skill_name"
        continue
      fi
      mkdir -p "$target_dir"
      local all_linked=true
      for file in "$skill_dir"*; do
        [[ -f "$file" ]] || continue
        local target_file
        target_file="$target_dir/$(basename "$file")"
        # Stow がファイル単位でシンボリックリンクにしている場合はスキップ
        if [[ -L "$target_file" ]]; then
          continue
        fi
        all_linked=false
        cp "$file" "$target_file"
      done
      if [[ "$all_linked" == "true" ]]; then
        log_success "  Skill already linked: $skill_name"
      else
        log_success "  Generated skill: $skill_name"
      fi
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

  # Claude fallback setup (cache OpenRouter API key)
  if "$DOTFILES_DIR/scripts/claude-fallback.sh" setup 2>/dev/null; then
    log_success "  Claude fallback ready (run 'claude-fallback.sh on' during outages)"
  else
    log_warn "  Claude fallback setup skipped (API keys not available)"
  fi
}

# --- Main ---
main() {
  log_info "=== Dotfiles Installation Start ==="
  log_info "OS: $(detect_os)"
  log_info "Dotfiles: $DOTFILES_DIR"
  if [[ "$(detect_os)" == "linux" && "$NO_SUDO" == "true" ]]; then
    log_info "Mode: no-sudo (pixi-based user-scope install)"
  fi
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

  # 2.5. Pick up tools installed by setup_environment (subshell PATH doesn't
  # propagate back). Prepend user-scope bin dirs so subsequent steps
  # (link_dotfiles → stow, sheldon, etc) can find them.
  for d in "$HOME/.pixi/bin" "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin"; do
    [[ -d "$d" ]] && export PATH="$d:$PATH"
  done

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

  # 3.7. Install TPM plugins and setup tmux-which-key
  setup_tmux_plugins

  # 3.8. Link git hooks into .git/hooks (post-merge → tmux reload broadcast)
  setup_git_hooks

  # 4. Generate AI CLI configs (with absolute paths)
  generate_ai_cli_configs

  # 4.5. Configure rtk Claude Code hook (token compression)
  configure_rtk_claude_hook

  echo
  log_success "=== Installation Complete! ==="
  log_info "Please restart your shell or run: source ~/.zshrc"

  # Unified summary (all config-driven)
  print_install_summary
}

# --- 4.5. Configure rtk Claude Code hook ---
# rtk init -g registers a Bash hook in ~/.claude/settings.json that transparently
# rewrites commands like `git status` -> `rtk git status` for 60-90% token reduction.
# Idempotent: skips if hook already configured.
configure_rtk_claude_hook() {
  if ! command_exists rtk; then
    log_warn "rtk not installed, skipping rtk Claude hook setup"
    return 0
  fi

  local settings_file="$HOME/.claude/settings.json"
  if [[ -f "$settings_file" ]] && grep -q '"rtk"' "$settings_file" 2>/dev/null; then
    log_info "rtk Claude hook already configured"
    return 0
  fi

  log_info "Configuring rtk Claude Code hook (token compression)..."
  if rtk init -g; then
    log_success "rtk Claude hook configured"
  else
    log_warn "rtk init -g failed (non-fatal)"
  fi
}

# --- Installation Summary (reads from config files) ---
print_install_summary() {
  local os
  os=$(detect_os)
  local CONFIG_DIR="$DOTFILES_DIR/config"

  echo
  echo "────────────────────────────────────────────────────────"
  echo "  Installation Summary"
  echo "────────────────────────────────────────────────────────"

  # 1. System packages / Homebrew
  if [[ "$os" == "mac" ]]; then
    local brewfile="$CONFIG_DIR/Brewfile"
    if [[ -f "$brewfile" ]]; then
      local brew_count cask_count
      brew_count=$(grep -c '^brew ' "$brewfile" 2>/dev/null || echo 0)
      cask_count=$(grep -c '^cask ' "$brewfile" 2>/dev/null || echo 0)
      printf "  %-14s %d formulae, %d casks\n" "Homebrew" "$brew_count" "$cask_count"
    fi
  elif [[ "$os" == "linux" ]]; then
    # System packages
    if command_exists apt; then
      local pkg_file="$CONFIG_DIR/packages.linux.apt.txt"
    else
      local pkg_file="$CONFIG_DIR/packages.linux.alpine.txt"
    fi
    if [[ -f "$pkg_file" ]]; then
      local pkg_count
      pkg_count=$(grep -cv '^\s*#\|^\s*$' "$pkg_file" 2>/dev/null || echo 0)
      printf "  %-14s %d packages\n" "System" "$pkg_count"
    fi

    # Linux tools
    local tools_file="$CONFIG_DIR/tools.linux.bash"
    if [[ -f "$tools_file" ]]; then
      source "$tools_file"
      local tools_ok=0 tools_total=0 tools_missing=()
      for tool in "${LINUX_TOOL_ORDER[@]}"; do
        local var="TOOL_${tool}_check_cmd"
        local check_cmd="${!var}"
        local var2="TOOL_${tool}_alt_check_cmd"
        local alt="${!var2:-}"
        ((++tools_total))
        if command_exists "$check_cmd" || { [[ -n "$alt" ]] && command_exists "$alt"; }; then
          ((++tools_ok))
        else
          tools_missing+=("$tool")
        fi
      done
      printf "  %-14s %d / %d installed" "Tools" "$tools_ok" "$tools_total"
      if [[ ${#tools_missing[@]} -gt 0 ]]; then
        printf " (missing: %s)" "${tools_missing[*]}"
      fi
      echo
    fi
  fi

  # 2. NPM packages
  local npm_file="$CONFIG_DIR/packages.npm.txt"
  if [[ -f "$npm_file" ]]; then
    local npm_ok=0 npm_total=0 npm_missing=()
    while IFS= read -r pkg; do
      ((++npm_total))
      if command_exists npm && npm list -g "$pkg" &>/dev/null; then
        ((++npm_ok))
      else
        npm_missing+=("$pkg")
      fi
    done < <(grep -v '^\s*#' "$npm_file" | grep -v '^\s*$')
    printf "  %-14s %d / %d installed" "NPM" "$npm_ok" "$npm_total"
    if [[ ${#npm_missing[@]} -gt 0 ]]; then
      printf " (missing: %s)" "${npm_missing[*]}"
    fi
    echo
  fi

  # 3. mise runtimes
  local mise_config="$DOTFILES_DIR/common/mise/.config/mise/config.toml"
  if [[ -f "$mise_config" ]]; then
    local mise_items=()
    while IFS='=' read -r tool version; do
      tool="${tool// /}"
      version="${version## }"
      version="${version%% }"
      version="${version//\"/}"
      [[ -z "$tool" ]] && continue
      mise_items+=("$tool:$version")
    done < <(awk '/^\[tools\]/{f=1;next} /^\[/{f=0} f && /=/' "$mise_config")
    printf "  %-14s " "mise"
    local first=true
    for item in "${mise_items[@]}"; do
      local t="${item%%:*}" v="${item##*:}"
      $first || printf ", "
      printf "%s (%s)" "$t" "$v"
      first=false
    done
    echo
  fi

  # 4. Other tools (not managed by package lists)
  local other_items=()
  command_exists dops && other_items+=("dops")
  command_exists op && other_items+=("op")
  if [[ "$os" == "linux" ]] && command_exists fc-list; then
    fc-list 2>/dev/null | grep -qi "UDEVGothic" && other_items+=("Nerd Font")
  fi
  if [[ ${#other_items[@]} -gt 0 ]]; then
    local other_str
    other_str=$(IFS=', '; echo "${other_items[*]}")
    printf "  %-14s %s\n" "Other" "$other_str"
  fi

  echo "────────────────────────────────────────────────────────"
}

main "$@"
