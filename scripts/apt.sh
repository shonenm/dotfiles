#!/bin/bash

# APT packages for Linux (Debian/Ubuntu)

APT_PACKAGES=(
  # Essentials
  build-essential
  curl
  wget
  git
  unzip

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
}

install_modern_tools() {
  # Starship
  if ! command_exists starship; then
    log_info "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi

  # Neovim (latest)
  if ! command_exists nvim; then
    log_info "Installing Neovim..."
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
    sudo rm -rf /opt/nvim
    sudo tar -C /opt -xzf nvim-linux64.tar.gz
    sudo ln -sf /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim
    rm nvim-linux64.tar.gz
  fi

  # eza (modern ls)
  if ! command_exists eza; then
    log_info "Installing eza..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
    sudo apt update
    sudo apt install -y eza
  fi

  # mise (version manager)
  if ! command_exists mise; then
    log_info "Installing mise..."
    curl https://mise.run | sh
  fi

  # sheldon (plugin manager)
  if ! command_exists sheldon; then
    log_info "Installing sheldon..."
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
  fi

  # zoxide
  if ! command_exists zoxide; then
    log_info "Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  fi

  # atuin
  if ! command_exists atuin; then
    log_info "Installing atuin..."
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
  fi

  # lazygit
  if ! command_exists lazygit; then
    log_info "Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit /usr/local/bin
    rm lazygit lazygit.tar.gz
  fi
}

# Run if sourced
install_apt_packages
install_modern_tools
