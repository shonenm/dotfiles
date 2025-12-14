#!/bin/bash

# --- Helper Functions ---
log_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[1;32m[OK]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

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
    sudo apt update

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
    sudo apt install -y "${APT_PACKAGES[@]}"

    # Ubuntu固有のコマンド名リンク修正
    if command_exists fdfind && ! command_exists fd; then
      sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi
    if command_exists batcat && ! command_exists bat; then
      sudo ln -sf "$(which batcat)" /usr/local/bin/bat
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

  # Ubuntuの場合のみ、aptで入らないツールを補完 (Alpineはapkで全部入るため不要)
  if command_exists apt; then
    # Neovim (Binary)
    if ! command_exists nvim; then
      log_info "Installing Neovim..."
      curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
      sudo rm -rf /opt/nvim
      sudo tar -C /opt -xzf nvim-linux64.tar.gz
      sudo ln -sf /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim
      rm nvim-linux64.tar.gz
    fi
    # ezaなどは必要ならここでバイナリDL、もしくは mise で管理推奨
  fi
}

# --- Main Execution ---

check_requirements
install_system_packages
install_modern_tools

log_success "Linux setup complete!"
