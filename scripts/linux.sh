#!/bin/bash

# Linux (Debian/Ubuntu/Alpine) Setup Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$DOTFILES_DIR/config"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/utils.sh"

# NO_SUDO mode is decided by install.sh (--no-sudo flag). Default false when run standalone.
: "${NO_SUDO:=false}"
export NO_SUDO

# Setup SUDO variable (empty in NO_SUDO mode so $SUDO-prefixed commands run as user)
if [[ "$NO_SUDO" == "true" ]]; then
  SUDO=""
elif [[ $EUID -eq 0 ]]; then
  SUDO=""
elif command_exists sudo; then
  SUDO="sudo"
else
  log_error "sudo not found. Re-run with --no-sudo for user-scope installation."
  exit 1
fi

# Load pixi library for NO_SUDO mode
if [[ "$NO_SUDO" == "true" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/pixi-lib.sh"
fi

# Source tool definitions from config
# shellcheck source=/dev/null
source "$CONFIG_DIR/tools.linux.bash"

# --- 1. Pre-flight Check ---
check_requirements() {
  local missing_requirements=()

  log_info "Checking prerequisites..."

  # In NO_SUDO mode, only curl + git are hard requirements (pixi bootstraps the rest)
  # In sudo mode, apt or apk must be available as well
  if [[ "$NO_SUDO" != "true" ]]; then
    if ! command_exists apk && ! command_exists apt; then
      log_error "No supported package manager found (apt or apk required)."
      log_error "This script supports Debian/Ubuntu or Alpine Linux."
      log_error "For sudoless environments, re-run with --no-sudo."
      exit 1
    fi

    if [ "$(id -u)" -ne 0 ] && ! command_exists sudo; then
      missing_requirements+=("sudo")
    fi
  fi

  local required_cmds=("curl" "git")
  for cmd in "${required_cmds[@]}"; do
    if ! command_exists "$cmd"; then
      missing_requirements+=("$cmd")
    fi
  done

  if [ ${#missing_requirements[@]} -ne 0 ]; then
    log_error "Missing required commands to run this script:"
    echo "  ----------------------------------------"
    for tool in "${missing_requirements[@]}"; do
      echo "  - $tool"
    done
    echo "  ----------------------------------------"

    if [[ "$NO_SUDO" == "true" ]]; then
      echo "In no-sudo mode, please ask your admin to install: ${missing_requirements[*]}"
    elif command_exists apk; then
      echo "Please run: apk add ${missing_requirements[*]}"
    elif command_exists apt; then
      echo "Please run: apt update && apt install -y ${missing_requirements[*]}"
    fi

    exit 1
  fi

  log_success "Prerequisites met."
}

# --- 1.5. 1Password CLI Check ---
check_1password() {
  if ! command_exists op; then
    log_error "1Password CLI not installed."
    log_error "Install: https://developer.1password.com/docs/cli/get-started/"
    exit 1
  fi

  if op whoami &>/dev/null; then
    log_success "1Password CLI: signed in"
  else
    log_error "1Password CLI: not signed in"
    echo "  ----------------------------------------"
    echo "  Run the following command to sign in:"
    echo ""
    echo "    eval \$(op signin)"
    echo ""
    echo "  Then re-run this script."
    echo "  ----------------------------------------"
    exit 1
  fi
}

# --- 2. Install Functions ---

install_system_packages() {
  # NO_SUDO mode: bootstrap pixi and install system packages via conda-forge (user-scope)
  if [[ "$NO_SUDO" == "true" ]]; then
    log_info "No-sudo mode: installing system packages via pixi..."
    install_pixi || { log_error "pixi bootstrap failed"; return 1; }
    install_pixi_packages "$CONFIG_DIR/pixi-packages.txt" || true
    return
  fi

  if command_exists apk; then
    log_info "Alpine Linux detected. Using apk..."
    local _sudo=""
    [ "$(id -u)" -ne 0 ] && _sudo="sudo"
    readarray -t PACKAGES < <(read_package_list "$CONFIG_DIR/packages.linux.alpine.txt")
    $_sudo apk add --no-cache "${PACKAGES[@]}"

  elif command_exists apt; then
    log_info "Debian/Ubuntu detected. Using apt..."
    $SUDO apt update
    readarray -t APT_PACKAGES < <(read_package_list "$CONFIG_DIR/packages.linux.apt.txt")
    $SUDO apt install -y "${APT_PACKAGES[@]}"

    # Ubuntu symlink fixups
    if command_exists fdfind && ! command_exists fd; then
      $SUDO ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi
    if command_exists batcat && ! command_exists bat; then
      $SUDO ln -sf "$(which batcat)" /usr/local/bin/bat
    fi
  fi
}

install_nerd_font() {
  local font_dir="$HOME/.local/share/fonts"
  mkdir -p "$font_dir"

  if fc-list 2>/dev/null | grep -qi "${NERD_FONT_NAME:-UDEVGothic}"; then
    log_success "UDEV Gothic Nerd Font already installed"
    return
  fi

  log_info "Installing UDEV Gothic Nerd Font..."
  local version="${NERD_FONT_VERSION:-v2.0.0}"
  local zip_file="UDEVGothic_NF_${version}.zip"
  local url="${NERD_FONT_URL:-https://github.com/yuru7/udev-gothic/releases/download/${version}/${zip_file}}"

  curl -fLO "$url"
  unzip -o "$zip_file" -d /tmp/udev-gothic-nf
  cp /tmp/udev-gothic-nf/UDEVGothic_NF_*/UDEVGothicNF-*.ttf "$font_dir/"
  rm -rf "$zip_file" /tmp/udev-gothic-nf
  fc-cache -fv >/dev/null 2>&1
  log_success "UDEV Gothic Nerd Font installed"
}

# --- Tool Installation Helpers ---

# Get a tool's config field value via indirect expansion
_tool_field() {
  local var="TOOL_${1}_${2}"
  echo "${!var}"
}

# Resolve architecture from arch_map
_resolve_arch() {
  local arch_map="$1"
  local uname_arch
  uname_arch=$(uname -m)
  for mapping in $arch_map; do
    local key="${mapping%%:*}"
    local val="${mapping##*:}"
    if [[ "$uname_arch" == "$key" ]]; then
      echo "$val"
      return 0
    fi
  done
  return 1
}

# Install via GitHub release tarball
_install_github_release() {
  local tool="$1"
  local repo arch_map ARCH VERSION VERSION_NOTAG
  repo=$(_tool_field "$tool" "github_repo")
  arch_map=$(_tool_field "$tool" "arch_map")

  # shellcheck disable=SC2034  # used in eval'd archive_pattern/install_cmd
  ARCH=$(_resolve_arch "$arch_map") || {
    log_error "Unsupported architecture for $tool: $(uname -m)"
    return 1
  }

  VERSION=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep -Po '"tag_name": "\K[^"]*')
  # shellcheck disable=SC2034  # used in eval'd archive_pattern/install_cmd
  VERSION_NOTAG="${VERSION#v}"

  local custom_cmd
  custom_cmd=$(_tool_field "$tool" "install_cmd")
  if [[ -n "$custom_cmd" ]]; then
    local archive_pattern archive
    archive_pattern=$(eval echo "$(_tool_field "$tool" "archive_pattern")")
    archive="/tmp/$archive_pattern"
    curl -fLo "$archive" "https://github.com/$repo/releases/download/$VERSION/$archive_pattern"
    eval "$custom_cmd"
    rm -f "$archive"
  else
    local archive_pattern binary_path
    archive_pattern=$(eval echo "$(_tool_field "$tool" "archive_pattern")")
    binary_path=$(eval echo "$(_tool_field "$tool" "binary_path")")
    curl -fLo "/tmp/$archive_pattern" "https://github.com/$repo/releases/download/$VERSION/$archive_pattern"
    if [[ "$archive_pattern" == *.zip ]]; then
      unzip -o "/tmp/$archive_pattern" -d /tmp
    else
      tar xf "/tmp/$archive_pattern" -C /tmp
    fi
    # Target dir: ~/.local/bin in NO_SUDO mode, else /usr/local/bin
    if [[ "$NO_SUDO" == "true" ]]; then
      mkdir -p "$HOME/.local/bin"
      install "/tmp/$binary_path" "$HOME/.local/bin/"
    else
      $SUDO install "/tmp/$binary_path" /usr/local/bin/
    fi
    rm -rf "/tmp/$archive_pattern" "/tmp/${binary_path%/*}"
  fi
}

# Install neovim tarball (extracted to ~/.local/opt in NO_SUDO mode, /opt otherwise)
_install_neovim_tarball() {
  local archive="$1" arch="$2"
  if [[ "$NO_SUDO" == "true" ]]; then
    local opt="$HOME/.local/opt"
    mkdir -p "$opt" "$HOME/.local/bin"
    rm -rf "$opt/nvim-linux-${arch}"
    tar -C "$opt" -xzf "$archive"
    ln -sf "$opt/nvim-linux-${arch}/bin/nvim" "$HOME/.local/bin/nvim"
  else
    $SUDO rm -rf "/opt/nvim-linux-${arch}"
    $SUDO tar -C /opt -xzf "$archive"
    $SUDO ln -sf "/opt/nvim-linux-${arch}/bin/nvim" /usr/local/bin/nvim
  fi
}

# Install via GitHub release single binary
_install_github_release_binary() {
  local tool="$1"
  local repo binary_map install_dir
  repo=$(_tool_field "$tool" "github_repo")
  binary_map=$(_tool_field "$tool" "binary_map")
  install_dir=$(_tool_field "$tool" "install_dir")
  install_dir="${install_dir:-$HOME/.local/bin}"

  local uname_arch binary
  uname_arch=$(uname -m)
  for mapping in $binary_map; do
    local key="${mapping%%:*}" val="${mapping##*:}"
    [[ "$uname_arch" == "$key" ]] && binary="$val" && break
  done
  if [[ -z "$binary" ]]; then
    log_error "Unsupported architecture for $tool: $uname_arch"
    return 1
  fi

  local check_cmd
  check_cmd=$(_tool_field "$tool" "check_cmd")
  mkdir -p "$install_dir"
  curl -fsSL "https://github.com/$repo/releases/latest/download/$binary" \
    -o "$install_dir/$check_cmd"
  chmod +x "$install_dir/$check_cmd"
}

# --- APT repo install functions (Debian/Ubuntu only) ---

install_gh_apt() {
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  $SUDO apt update
  $SUDO apt install -y gh
}

install_eza_apt() {
  $SUDO mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | $SUDO gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | $SUDO tee /etc/apt/sources.list.d/gierens.list
  $SUDO chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  $SUDO apt update
  $SUDO apt install -y eza
}

install_bat_apt() {
  $SUDO apt install -y bat
  if command_exists batcat && ! command_exists bat; then
    $SUDO ln -sf "$(which batcat)" /usr/local/bin/bat
  fi
}

install_postgresql_apt() {
  $SUDO apt install -y postgresql-client
}

# --- Main Tool Dispatcher ---

install_modern_tools() {
  local _new=() _existing=()
  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

  # Nerd Font (handled separately)
  install_nerd_font

  for tool in "${LINUX_TOOL_ORDER[@]}"; do
    local check_cmd method apt_only alt_check_cmd
    check_cmd=$(_tool_field "$tool" "check_cmd")
    method=$(_tool_field "$tool" "method")
    apt_only=$(_tool_field "$tool" "apt_only")
    alt_check_cmd=$(_tool_field "$tool" "alt_check_cmd")

    # Skip apt-only tools on Alpine
    if [[ "$apt_only" == "true" ]] && ! command_exists apt; then
      continue
    fi

    # In NO_SUDO mode, skip apt_repo tools (they come from pixi-packages.txt instead)
    if [[ "$NO_SUDO" == "true" ]] && [[ "$method" == "apt_repo" ]]; then
      continue
    fi

    # Check if already installed (also verify binary runs on this arch)
    if command_exists "$check_cmd"; then
      if "$check_cmd" --version &>/dev/null || "$check_cmd" --help &>/dev/null || "$check_cmd" version &>/dev/null; then
        log_success "$tool already installed"
        _existing+=("$tool")
        continue
      else
        log_warn "$tool found but not executable (wrong arch?), reinstalling..."
      fi
    fi
    if [[ -n "$alt_check_cmd" ]] && command_exists "$alt_check_cmd"; then
      if "$alt_check_cmd" --version &>/dev/null || "$alt_check_cmd" --help &>/dev/null || "$alt_check_cmd" version &>/dev/null; then
        log_success "$tool already installed"
        _existing+=("$tool")
        continue
      else
        log_warn "$tool found but not executable (wrong arch?), reinstalling..."
      fi
    fi

    # Check dependency
    local dep dep_cmd
    dep=$(_tool_field "$tool" "depends_on")
    if [[ -n "$dep" ]]; then
      dep_cmd=$(_tool_field "$dep" "check_cmd")
      if ! command_exists "$dep_cmd"; then
        log_warn "Skipping $tool: dependency '$dep' not installed"
        continue
      fi
    fi

    log_info "Installing $tool..."

    case "$method" in
      curl_pipe)
        eval "$(_tool_field "$tool" "curl_cmd")"
        ;;
      github_release)
        _install_github_release "$tool"
        ;;
      github_release_binary)
        _install_github_release_binary "$tool"
        ;;
      cargo)
        cargo install "$(_tool_field "$tool" "cargo_crate")"
        ;;
      apt_repo)
        local fn
        fn=$(_tool_field "$tool" "install_fn")
        if declare -f "$fn" &>/dev/null; then
          "$fn"
        else
          log_error "No install function for $tool: $fn"
          continue
        fi
        ;;
      *)
        log_error "Unknown install method for $tool: $method"
        continue
        ;;
    esac

    # Post-install hook
    local post_install
    post_install=$(_tool_field "$tool" "post_install")
    [[ -n "$post_install" ]] && eval "$post_install"

    _new+=("$tool")
  done

  # Mise tools (special: depends on mise, activates it)
  if command_exists mise || [[ -f "$HOME/.local/bin/mise" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    eval "$("$HOME/.local/bin/mise" activate bash 2>/dev/null || true)"
    log_info "Installing mise-managed tools..."
    "$HOME/.local/bin/mise" install -y 2>/dev/null || true
  fi

  # Summary
  echo
  log_info "── Tool Summary ──"
  [[ ${#_new[@]} -gt 0 ]] && log_success "  New: ${_new[*]}"
  [[ ${#_existing[@]} -gt 0 ]] && log_info "  Existing: ${_existing[*]}"
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

install_claude_mem() {
  if ! command_exists npx; then
    log_warn "npx not found, skipping claude-mem"
    return
  fi

  if [[ -f "$HOME/.claude-mem/settings.json" ]]; then
    log_success "claude-mem already installed"
    return
  fi

  log_info "Installing claude-mem..."
  npx -y claude-mem install
}

install_1password_cli() {
  if command_exists op; then
    log_success "1Password CLI already installed"
    return
  fi

  # NO_SUDO path: install.sh's check_1password_cli() → _install_1password_cli_user_scope() handles it
  if [[ "$NO_SUDO" == "true" ]]; then
    log_info "No-sudo mode: 1Password CLI install is handled by install.sh"
    return
  fi

  # Debian/Ubuntu only (sudo path)
  if ! command_exists apt; then
    log_warn "1Password CLI installation only supported on Debian/Ubuntu"
    return
  fi

  log_info "Installing 1Password CLI..."

  curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    $SUDO gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
    $SUDO tee /etc/apt/sources.list.d/1password.list

  $SUDO apt update
  $SUDO apt install -y 1password-cli

  log_success "1Password CLI installed"
}

set_default_shell() {
  if [[ "$SHELL" == *"zsh"* ]]; then
    log_success "Zsh is already the default shell"
    return
  fi

  local zsh_path
  zsh_path=$(which zsh)

  if [[ -z "$zsh_path" ]]; then
    log_warn "Zsh not found, skipping default shell change"
    return
  fi

  # NO_SUDO path: inject `exec zsh -l` into ~/.profile so login shells hand off to zsh
  if [[ "$NO_SUDO" == "true" ]]; then
    local profile="$HOME/.profile"
    local marker='# dotfiles: exec zsh -l (no-sudo mode)'
    if [[ -f "$profile" ]] && grep -qF "$marker" "$profile"; then
      log_success "zsh exec marker already present in ~/.profile"
    else
      # shellcheck disable=SC2016 # intentionally written as literal sh into ~/.profile
      {
        echo ""
        echo "$marker"
        echo 'if [ -z "$ZSH_VERSION" ] && [ -t 0 ] && command -v zsh >/dev/null 2>&1; then'
        echo '  exec zsh -l'
        echo 'fi'
      } >> "$profile"
      log_success "Injected 'exec zsh -l' into ~/.profile (no-sudo mode)"
    fi
    log_info "  New login shells will switch to zsh automatically (sudo not available for chsh)"
    return
  fi

  # sudo path: /etc/shells + chsh
  if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
    echo "$zsh_path" | $SUDO tee -a /etc/shells >/dev/null
  fi

  log_info "Setting zsh as default shell..."
  if [[ $EUID -eq 0 ]]; then
    chsh -s "$zsh_path"
  else
    chsh -s "$zsh_path" || $SUDO usermod --shell "$zsh_path" "$USER"
  fi
  log_success "Default shell changed to zsh (restart terminal to apply)"
}

link_ai_scripts() {
  mkdir -p "$HOME/.local/bin"

  if [[ -f "$SCRIPT_DIR/ai-notify.sh" ]]; then
    ln -sf "$SCRIPT_DIR/ai-notify.sh" "$HOME/.local/bin/ai-notify.sh"
    log_success "Linked ai-notify.sh to ~/.local/bin"
  fi
}

install_gh_extensions() {
  if ! command_exists gh; then
    log_warn "gh CLI not found, skipping gh extensions"
    return
  fi

  if ! gh auth status &>/dev/null; then
    log_warn "gh CLI not authenticated, skipping gh extensions"
    return
  fi

  if gh extension list | grep -q "dlvhdr/gh-dash"; then
    log_success "gh-dash already installed"
  else
    log_info "Installing gh-dash extension..."
    if gh extension install dlvhdr/gh-dash; then
      log_success "gh-dash installed"
    else
      log_error "Failed to install gh-dash"
    fi
  fi
}

install_ghostty_terminfo() {
  if infocmp xterm-ghostty &>/dev/null; then
    log_success "xterm-ghostty terminfo already installed"
    return
  fi

  local terminfo_src="$CONFIG_DIR/xterm-ghostty.terminfo"
  if [[ ! -f "$terminfo_src" ]]; then
    log_warn "xterm-ghostty.terminfo not found in config/"
    return
  fi

  log_info "Installing xterm-ghostty terminfo..."
  mkdir -p "$HOME/.terminfo"
  tic -x -o "$HOME/.terminfo" "$terminfo_src" 2>/dev/null
  log_success "xterm-ghostty terminfo installed"
}

install_fancy_cat() {
  if command_exists fancy-cat; then
    log_success "fancy-cat already installed"
    return
  fi

  # fancy-cat は Zig プロジェクトのため、ビルドに Zig が必要
  local zig_cmd=""
  if command_exists zig; then
    zig_cmd="zig"
  else
    log_warn "fancy-cat: zig not found, skipping (install zig to enable: mise use -g zig)"
    return
  fi

  log_info "Building fancy-cat from source..."
  local build_dir="/tmp/fancy-cat-build"
  rm -rf "$build_dir"
  git clone --recursive https://github.com/freref/fancy-cat.git "$build_dir"
  (
    cd "$build_dir" || return 1
    $zig_cmd build --release=small
  )
  mkdir -p "$HOME/.local/bin"
  mv "$build_dir/zig-out/bin/fancy-cat" "$HOME/.local/bin/"
  rm -rf "$build_dir"
  log_success "fancy-cat installed to ~/.local/bin"
}

# --- Main Execution ---

check_requirements
install_system_packages
install_modern_tools
install_npm_packages
install_claude_mem
link_ai_scripts
install_gh_extensions
install_ghostty_terminfo
install_fancy_cat
install_1password_cli
check_1password
set_default_shell

log_success "Linux setup complete!"
