#!/bin/bash

# --- 1. Helper Functions (必須: これがないと動きません) ---
log_info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

log_success() {
  echo -e "\033[1;32m[OK]\033[0m $1"
}

log_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# --- 2. Dependency Check (ご要望の機能) ---
check_dependencies() {
  local fatal_error=0

  # このスクリプトは apt と sudo を前提としています
  if ! command_exists apt; then
    log_error "This script requires 'apt' (Debian/Ubuntu)."
    fatal_error=1
  fi

  if ! command_exists sudo; then
    log_error "'sudo' command is missing. Please install sudo first."
    fatal_error=1
  fi

  if [ $fatal_error -eq 1 ]; then
    log_error "Missing required dependencies. Exiting."
    exit 1
  fi
}

# --- 3. Configuration ---

APT_PACKAGES=(
  # Essentials
  build-essential
  curl
  wget
  git
  unzip
  gpg

  # Shell tools
  fish
  zsh
  tmux
  fzf
  ripgrep
  fd-find
  bat
  jq
)

install_apt_packages() {
  log_info "Updating apt..."
  sudo apt update

  log_info "Installing APT packages..."
  for pkg in "${APT_PACKAGES[@]}"; do
    if ! dpkg -l "$pkg" &>/dev/null; then
      log_info "Installing $pkg..."
      sudo apt install -y "$pkg"
    else
      log_success "$pkg already installed"
    fi
  done

  # Debian/Ubuntu specific command name fixes
  # fd-find -> fd
  if command_exists fdfind && ! command_exists fd; then
    log_info "Linking fdfind to fd..."
    sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
  fi

  # batcat -> bat
  if command_exists batcat && ! command_exists bat; then
    log_info "Linking batcat to bat..."
    sudo ln -sf "$(which batcat)" /usr/local/bin/bat
  fi
}

install_modern_tools() {
  # Create ~/.local/bin if not exists
  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

  # Starship
  if ! command_exists starship; then
    log_info "Installing Starship..."
    # 依存関係として curl が必要 (aptでインストール済みのはず)
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  else
    log_success "Starship already installed"
  fi

  # Neovim (latest)
  if ! command_exists nvim; then
    log_info "Installing Neovim..."
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
    sudo rm -rf /opt/nvim
    sudo tar -C /opt -xzf nvim-linux64.tar.gz
    sudo ln -sf /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim
    rm nvim-linux64.tar.gz
  else
    log_success "Neovim already installed"
  fi

  # eza (modern ls)
  if ! command_exists eza; then
    log_info "Installing eza..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
    sudo apt update
    sudo apt install -y eza
  else
    log_success "eza already installed"
  fi

  # mise (version manager)
  if ! command_exists mise; then
    log_info "Installing mise..."
    curl https://mise.run | sh
  else
    log_success "mise already installed"
  fi

  # sheldon (plugin manager)
  if ! command_exists sheldon; then
    log_info "Installing sheldon..."
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
  else
    log_success "sheldon already installed"
  fi

  # zoxide
  if ! command_exists zoxide; then
    log_info "Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  else
    log_success "zoxide already installed"
  fi

  # atuin
  if ! command_exists atuin; then
    log_info "Installing atuin..."
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
  else
    log_success "atuin already installed"
  fi

  # lazygit
  if ! command_exists lazygit; then
    log_info "Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit /usr/local/bin
    rm lazygit lazygit.tar.gz
  else
    log_success "lazygit already installed"
  fi
}

# --- Main Execution ---

# 1. 依存関係チェック (ここに追加しました)
check_dependencies

# 2. パッケージインストール
install_apt_packages
install_modern_tools

log_success "Linux packages installed!"
