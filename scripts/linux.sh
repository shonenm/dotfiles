#!/bin/bash

# Linux (Debian/Ubuntu/Alpine) Setup Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Setup SUDO variable
if [[ $EUID -eq 0 ]]; then
  SUDO=""
elif command_exists sudo; then
  SUDO="sudo"
else
  log_warn "sudo not found, some installations may fail"
  SUDO=""
fi

NPM_PACKAGES=(
  # AI CLI tools
  "@anthropic-ai/claude-code"
  "@openai/codex"
  "@google/gemini-cli"
)

# --- 1. Pre-flight Check (ご要望の機能) ---
check_requirements() {
  local missing_requirements=()
  local has_package_manager=false

  log_info "Checking prerequisites..."

  # 1. パッケージマネージャーの確認
  if command_exists apk || command_exists apt; then
    has_package_manager=true
  fi

  if [ "$has_package_manager" = false ]; then
    log_error "No supported package manager found (apt or apk required)."
    log_error "This script supports Debian/Ubuntu or Alpine Linux."
    exit 1
  fi

  # 2. 必須コマンドの確認 (これらがないとスクリプトが動かない)
  # sudoはrootユーザーなら不要だが、一般ユーザーなら必須とする
  local required_cmds=("curl" "git")

  if [ "$(id -u)" -ne 0 ] && ! command_exists sudo; then
    missing_requirements+=("sudo")
  fi

  for cmd in "${required_cmds[@]}"; do
    if ! command_exists "$cmd"; then
      missing_requirements+=("$cmd")
    fi
  done

  # 3. 足りないものがあれば表示して終了
  if [ ${#missing_requirements[@]} -ne 0 ]; then
    log_error "Missing required commands to run this script:"
    echo "  ----------------------------------------"
    for tool in "${missing_requirements[@]}"; do
      echo "  - $tool"
    done
    echo "  ----------------------------------------"

    # OSに合わせてインストールコマンドを提案
    if command_exists apk; then
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
  # op コマンドがなければエラー
  if ! command_exists op; then
    log_error "1Password CLI not installed."
    log_error "Install: https://developer.1password.com/docs/cli/get-started/"
    exit 1
  fi

  # サインイン状態を確認
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
  # Alpine Linux (apk)
  if command_exists apk; then
    log_info "Alpine Linux detected. Using apk..."
    SUDO=""
    [ "$(id -u)" -ne 0 ] && SUDO="sudo"

    # Alpine向けパッケージ (ビルドツールや便利なツール)
    PACKAGES=(
      build-base
      zsh
      tmux
      jq
      stow
      neovim
      ripgrep
      fd
      bat
      fzf
      eza
      rsync
      github-cli
      luarocks
      tealdeer
      dust
      bottom
    )
    $SUDO apk add --no-cache "${PACKAGES[@]}"

  # Debian/Ubuntu (apt)
  elif command_exists apt; then
    log_info "Debian/Ubuntu detected. Using apt..."
    $SUDO apt update

    APT_PACKAGES=(
      build-essential
      zsh
      tmux
      jq
      stow
      unzip
      fzf
      ripgrep
      rsync
      luarocks
    )
    $SUDO apt install -y "${APT_PACKAGES[@]}"

    # Ubuntu固有のコマンド名リンク修正
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

  # Check if UDEV Gothic NF is already installed
  if fc-list 2>/dev/null | grep -qi "UDEVGothic"; then
    log_success "UDEV Gothic Nerd Font already installed"
    return
  fi

  log_info "Installing UDEV Gothic Nerd Font..."
  local version="v2.0.0"
  local zip_file="UDEVGothic_NF_${version}.zip"
  local url="https://github.com/yuru7/udev-gothic/releases/download/${version}/${zip_file}"

  curl -fLO "$url"
  unzip -o "$zip_file" -d /tmp/udev-gothic-nf
  cp /tmp/udev-gothic-nf/UDEVGothic_NF_*/UDEVGothicNF-*.ttf "$font_dir/"
  rm -rf "$zip_file" /tmp/udev-gothic-nf
  fc-cache -fv >/dev/null 2>&1
  log_success "UDEV Gothic Nerd Font installed"
}

install_modern_tools() {
  local _new=() _existing=()
  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

  # Nerd Font (for terminal icons)
  install_nerd_font

  # Starship
  if ! command_exists starship; then
    log_info "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    _new+=("starship")
  else
    log_success "Starship already installed"
    _existing+=("starship")
  fi

  # Mise (Package Manager)
  if ! command_exists mise; then
    log_info "Installing mise..."
    curl https://mise.run | sh
    _new+=("mise")
  else
    log_success "Mise already installed"
    _existing+=("mise")
  fi

  # Activate mise and install runtimes (Node.js, Python, pnpm)
  if [[ -f "$HOME/.local/bin/mise" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    eval "$($HOME/.local/bin/mise activate bash)"
    log_info "Installing Node.js, Python, and pnpm via mise..."
    $HOME/.local/bin/mise install node python pnpm -y 2>/dev/null || true
  fi

  # Sheldon (zsh plugin manager)
  if ! command_exists sheldon; then
    log_info "Installing Sheldon..."
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
      | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
    _new+=("sheldon")
  else
    log_success "Sheldon already installed"
    _existing+=("sheldon")
  fi

  # Zoxide (smarter cd)
  if ! command_exists zoxide; then
    log_info "Installing Zoxide..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    _new+=("zoxide")
  else
    log_success "Zoxide already installed"
    _existing+=("zoxide")
  fi

  # Atuin (shell history)
  if ! command_exists atuin; then
    log_info "Installing Atuin..."
    # --yes: skip confirmation, shell config is managed by dotfiles
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --yes
    _new+=("atuin")
  else
    log_success "Atuin already installed"
    _existing+=("atuin")
  fi

  # dotenvx (encrypted .env management)
  if ! command_exists dotenvx; then
    log_info "Installing dotenvx..."
    curl -sfS https://dotenvx.sh | sh
    _new+=("dotenvx")
  else
    log_success "dotenvx already installed"
    _existing+=("dotenvx")
  fi

  # uv (Python package installer)
  if ! command_exists uv; then
    log_info "Installing uv..."
    # UV_NO_MODIFY_PATH: shell config is managed by dotfiles
    curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
    _new+=("uv")
  else
    log_success "uv already installed"
    _existing+=("uv")
  fi

  # Rust (via rustup)
  if ! command_exists cargo; then
    log_info "Installing Rust via rustup..."
    # --no-modify-path: shell config is managed by dotfiles
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    _new+=("rust")
  else
    log_success "Rust already installed"
    _existing+=("rust")
  fi

  # Delta (git diff pager)
  if ! command_exists delta; then
    log_info "Installing Delta..."
    local delta_arch
    case "$(uname -m)" in
      x86_64)  delta_arch="x86_64" ;;
      aarch64) delta_arch="aarch64" ;;
      *)
        log_error "Unsupported architecture for Delta: $(uname -m)"
        return
        ;;
    esac
    DELTA_VERSION=$(curl -s "https://api.github.com/repos/dandavison/delta/releases/latest" | grep -Po '"tag_name": "\K[^"]*')
    curl -Lo delta.tar.gz "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${delta_arch}-unknown-linux-gnu.tar.gz"
    tar xf delta.tar.gz
    $SUDO install "delta-${DELTA_VERSION}-${delta_arch}-unknown-linux-gnu/delta" /usr/local/bin
    rm -rf delta.tar.gz "delta-${DELTA_VERSION}-${delta_arch}-unknown-linux-gnu"
    _new+=("delta")
  else
    log_success "Delta already installed"
    _existing+=("delta")
  fi

  # Lazygit
  if ! command_exists lazygit; then
    log_info "Installing Lazygit..."
    local lazygit_arch
    case "$(uname -m)" in
      x86_64)  lazygit_arch="x86_64" ;;
      aarch64) lazygit_arch="arm64" ;;
      *)
        log_error "Unsupported architecture for Lazygit: $(uname -m)"
        log_error "Supported: x86_64, aarch64"
        exit 1
        ;;
    esac
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_${lazygit_arch}.tar.gz"
    tar xf lazygit.tar.gz lazygit
    $SUDO install lazygit /usr/local/bin
    rm -f lazygit lazygit.tar.gz
    _new+=("lazygit")
  else
    log_success "Lazygit already installed"
    _existing+=("lazygit")
  fi

  # Lazydocker
  if ! command_exists lazydocker; then
    log_info "Installing Lazydocker..."
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
    _new+=("lazydocker")
  else
    log_success "Lazydocker already installed"
    _existing+=("lazydocker")
  fi

  # dops (better docker ps)
  if ! command_exists dops; then
    log_info "Installing dops..."
    local arch=$(uname -m)
    local binary="dops_linux-amd64-static"
    [[ "$arch" == "aarch64" ]] && binary="dops_linux-arm64"
    curl -fsSL "https://github.com/Mikescher/better-docker-ps/releases/latest/download/${binary}" \
      -o "$HOME/.local/bin/dops"
    chmod +x "$HOME/.local/bin/dops"
    _new+=("dops")
  else
    log_success "dops already installed"
    _existing+=("dops")
  fi

  # Tokei (code statistics)
  if ! command_exists tokei; then
    log_info "Installing Tokei..."
    cargo install tokei
    _new+=("tokei")
  else
    log_success "Tokei already installed"
    _existing+=("tokei")
  fi

  # Tealdeer (modern man pages)
  if ! command_exists tldr; then
    log_info "Installing Tealdeer..."
    cargo install tealdeer
    _new+=("tealdeer")
  else
    log_success "Tealdeer already installed"
    _existing+=("tealdeer")
  fi

  # Procs (modern ps)
  if ! command_exists procs; then
    log_info "Installing Procs..."
    cargo install procs
    _new+=("procs")
  else
    log_success "Procs already installed"
    _existing+=("procs")
  fi

  # Sd (modern sed)
  if ! command_exists sd; then
    log_info "Installing Sd..."
    cargo install sd
    _new+=("sd")
  else
    log_success "Sd already installed"
    _existing+=("sd")
  fi

  # Dust (modern du)
  if ! command_exists dust; then
    log_info "Installing Dust..."
    cargo install du-dust
    _new+=("dust")
  else
    log_success "Dust already installed"
    _existing+=("dust")
  fi

  # Bottom (modern top)
  if ! command_exists btm; then
    log_info "Installing Bottom..."
    cargo install bottom
    _new+=("bottom")
  else
    log_success "Bottom already installed"
    _existing+=("bottom")
  fi

  # Rip2 (safe rm replacement)
  if ! command_exists rip; then
    log_info "Installing Rip2..."
    cargo install rm-improved
    _new+=("rip2")
  else
    log_success "Rip2 already installed"
    _existing+=("rip2")
  fi

  # Ubuntuの場合のみ、aptで入らないツールを補完 (Alpineはapkで全部入るため不要)
  if command_exists apt; then
    # GitHub CLI (gh)
    if ! command_exists gh; then
      log_info "Installing GitHub CLI..."
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
      $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      $SUDO apt update
      $SUDO apt install -y gh
      _new+=("gh")
    else
      log_success "GitHub CLI already installed"
      _existing+=("gh")
    fi

    # Neovim (Binary)
    if ! command_exists nvim; then
      log_info "Installing Neovim..."
      local nvim_arch
      case "$(uname -m)" in
        x86_64)  nvim_arch="x86_64" ;;
        aarch64) nvim_arch="arm64" ;;
        *)
          log_error "Unsupported architecture for Neovim: $(uname -m)"
          log_error "Supported: x86_64, aarch64"
          exit 1
          ;;
      esac
      curl -fLO "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz"
      $SUDO rm -rf "/opt/nvim-linux-${nvim_arch}"
      $SUDO tar -C /opt -xzf "nvim-linux-${nvim_arch}.tar.gz"
      $SUDO ln -sf "/opt/nvim-linux-${nvim_arch}/bin/nvim" /usr/local/bin/nvim
      rm "nvim-linux-${nvim_arch}.tar.gz"
      _new+=("neovim")
    else
      log_success "Neovim already installed"
      _existing+=("neovim")
    fi

    # Eza (modern ls)
    if ! command_exists eza; then
      log_info "Installing Eza..."
      $SUDO mkdir -p /etc/apt/keyrings
      wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | $SUDO gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
      echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | $SUDO tee /etc/apt/sources.list.d/gierens.list
      $SUDO chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
      $SUDO apt update
      $SUDO apt install -y eza
      _new+=("eza")
    else
      log_success "Eza already installed"
      _existing+=("eza")
    fi

    # Bat (aptではbatcat)
    if ! command_exists bat && ! command_exists batcat; then
      log_info "Installing Bat..."
      $SUDO apt install -y bat
      _new+=("bat")
    else
      log_success "Bat already installed"
      _existing+=("bat")
    fi
    if command_exists batcat && ! command_exists bat; then
      $SUDO ln -sf "$(which batcat)" /usr/local/bin/bat
    fi
  fi

  # Summary
  echo
  log_info "── Tool Summary ──"
  if [[ ${#_new[@]} -gt 0 ]]; then
    log_success "  New: ${_new[*]}"
  fi
  if [[ ${#_existing[@]} -gt 0 ]]; then
    log_info "  Existing: ${_existing[*]}"
  fi
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

install_1password_cli() {
  if command_exists op; then
    log_success "1Password CLI already installed"
    return
  fi

  # Debian/Ubuntu only
  if ! command_exists apt; then
    log_warn "1Password CLI installation only supported on Debian/Ubuntu"
    return
  fi

  log_info "Installing 1Password CLI..."

  # Add 1Password apt repository
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

  # Add zsh to /etc/shells if not present
  if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
    echo "$zsh_path" | $SUDO tee -a /etc/shells >/dev/null
  fi

  log_info "Setting zsh as default shell..."
  if [[ $EUID -eq 0 ]]; then
    # Root user
    chsh -s "$zsh_path"
  else
    # Non-root user
    chsh -s "$zsh_path" || $SUDO usermod --shell "$zsh_path" "$USER"
  fi
  log_success "Default shell changed to zsh (restart terminal to apply)"
}

# --- 3. Link AI CLI notification scripts ---
link_ai_scripts() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  mkdir -p "$HOME/.local/bin"

  # ai-notify.sh - required for Claude/Codex/Gemini CLI notifications
  if [[ -f "$script_dir/ai-notify.sh" ]]; then
    ln -sf "$script_dir/ai-notify.sh" "$HOME/.local/bin/ai-notify.sh"
    log_success "Linked ai-notify.sh to ~/.local/bin"
  fi
}

# --- Main Execution ---

check_requirements
install_system_packages
install_modern_tools
install_npm_packages
link_ai_scripts
install_1password_cli
check_1password
set_default_shell

log_success "Linux setup complete!"
