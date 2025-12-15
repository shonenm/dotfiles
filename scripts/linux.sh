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

install_modern_tools() {
  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

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
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
  fi

  # Ubuntuの場合のみ、aptで入らないツールを補完 (Alpineはapkで全部入るため不要)
  if command_exists apt; then
    # Neovim (Binary)
    if ! command_exists nvim; then
      log_info "Installing Neovim..."
      curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
      $SUDO rm -rf /opt/nvim
      $SUDO tar -C /opt -xzf nvim-linux64.tar.gz
      $SUDO ln -sf /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim
      rm nvim-linux64.tar.gz
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

# --- Main Execution ---

check_requirements
install_system_packages
install_modern_tools
install_npm_packages
install_1password_cli
check_1password

log_success "Linux setup complete!"
