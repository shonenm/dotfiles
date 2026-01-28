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
  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

  # Nerd Font (for terminal icons)
  install_nerd_font

  # Starship
  if ! command_exists starship; then
    log_info "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi

  # Mise (Package Manager)
  if ! command_exists mise; then
    log_info "Installing mise..."
    curl https://mise.run | sh
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
  fi

  # Zoxide (smarter cd)
  if ! command_exists zoxide; then
    log_info "Installing Zoxide..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  fi

  # Atuin (shell history)
  if ! command_exists atuin; then
    log_info "Installing Atuin..."
    # --yes: skip confirmation, shell config is managed by dotfiles
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --yes
  fi

  # dotenvx (encrypted .env management)
  if ! command_exists dotenvx; then
    log_info "Installing dotenvx..."
    curl -sfS https://dotenvx.sh | sh
  fi

  # uv (Python package installer)
  if ! command_exists uv; then
    log_info "Installing uv..."
    # UV_NO_MODIFY_PATH: shell config is managed by dotfiles
    curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
  fi

  # Rust (via rustup)
  if ! command_exists cargo; then
    log_info "Installing Rust via rustup..."
    # --no-modify-path: shell config is managed by dotfiles
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
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
  fi

  # Lazydocker
  if ! command_exists lazydocker; then
    log_info "Installing Lazydocker..."
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
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
  fi

  # Tokei (code statistics)
  if ! command_exists tokei; then
    log_info "Installing Tokei..."
    cargo install tokei
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
    fi

    # Bat (aptではbatcat)
    if ! command_exists bat && ! command_exists batcat; then
      log_info "Installing Bat..."
      $SUDO apt install -y bat
    fi
    if command_exists batcat && ! command_exists bat; then
      $SUDO ln -sf "$(which batcat)" /usr/local/bin/bat
    fi
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
