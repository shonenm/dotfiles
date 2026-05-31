#!/bin/bash
# Phase 6: Nix-bootstrap installer.
# Replaces the previous ~800-line stow-based installer. Everything that
# used to be done by stow + scripts/{mac,linux}.sh is now declarative in
# nix-darwin / home-manager. This script does just enough to get Nix on
# the host and trigger the first `darwin-rebuild switch` or
# `home-manager switch`.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DOTFILES_DIR/scripts/utils.sh"

# --- Argument parsing -------------------------------------------------
NO_SUDO=false
SKIP_1P=false
BOOTSTRAP_MODE=""  # chroot | portable | "" (native sudo)
for arg in "$@"; do
  case "$arg" in
    -y|--skip-prompt) ;;  # accepted for compatibility; install.sh is non-interactive
    --no-sudo)        NO_SUDO=true ;;
    --skip-1p)        SKIP_1P=true ;;
    -h|--help)
      cat <<'EOF'
Usage: install.sh [-y|--skip-prompt] [--no-sudo] [--skip-1p]

Bootstraps a Nix-managed dotfiles environment. Three high-level steps:

  1. Verify 1Password CLI is present (needed by op-secret hooks in
     ~/.zshrc, by setup_git_from_op, etc.). Installs it via Homebrew
     (mac) or apt / pixi (linux).
  2. Install Nix via the Determinate Systems installer (multi-user on
     sudo hosts; falls back to user-namespace via nix-user-chroot on
     no-sudo hosts — see docs/install/nix-sudoless-bootstrap.md).
  3. Activate the configuration:
        mac:   sudo darwin-rebuild switch --flake .#shonenm
        linux: nix run home-manager/master -- switch \
                  --flake .#<user>@linux-<arch>

Flags:
  -y, --skip-prompt   Non-interactive (sudo prompts still appear when
                      Determinate's installer escalates).
  --no-sudo           Linux sudoless path (see docs).
  --skip-1p           Skip the 1Password CLI install step.
EOF
      exit 0
      ;;
  esac
done

OS=$(detect_os)
log_info "Detected OS: $OS"

# --- Step 1: 1Password CLI -------------------------------------------
if [[ "$SKIP_1P" != "true" ]]; then
  if command_exists op; then
    log_info "1Password CLI already installed: $(op --version)"
  else
    log_info "Installing 1Password CLI..."
    case "$OS" in
      mac)
        if ! command_exists brew; then
          log_error "Homebrew not found. Install via https://brew.sh first."
          exit 1
        fi
        brew install 1password-cli
        ;;
      linux)
        if [[ "$NO_SUDO" == "true" ]]; then
          log_warn "Skipping 1Password CLI on sudoless host. Install manually:"
          log_warn "  https://developer.1password.com/docs/cli/get-started/"
        else
          # Add 1Password repo + install
          curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
            sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
            sudo tee /etc/apt/sources.list.d/1password.list >/dev/null
          sudo apt update && sudo apt install -y 1password-cli
        fi
        ;;
      *)
        log_error "Unsupported OS: $OS"; exit 1 ;;
    esac
  fi
fi

# --- Step 2: Nix -----------------------------------------------------
if command_exists nix; then
  log_info "Nix already installed: $(nix --version)"
else
  log_info "Installing Nix via Determinate Systems installer..."
  if [[ "$OS" == "linux" && "$NO_SUDO" == "true" ]]; then
    log_info "Sudoless Linux host — running preflight to select bootstrap path..."
    _preflight_result=$(bash "$DOTFILES_DIR/scripts/nix-preflight.sh" 2>/dev/null \
      | grep -oE 'READY-CHROOT|READY-PORTABLE|READY-NATIVE|BLOCKED')
    case "$_preflight_result" in
      READY-NATIVE)
        log_info "Preflight: READY-NATIVE — proceeding with Determinate installer (sudo prompt expected)."
        NO_SUDO=false
        ;;
      READY-CHROOT)
        log_info "Preflight: READY-CHROOT → nix-user-chroot bootstrap"
        _nuc_bin="$HOME/.local/bin/nix-user-chroot"
        _nuc_store="$HOME/.nix-store/nix"
        _nuc_version="2.1.1"
        _nuc_arch="$(uname -m)"
        mkdir -p "$HOME/.local/bin" "$_nuc_store"
        if [[ ! -x "$_nuc_bin" ]]; then
          log_info "Downloading nix-user-chroot ${_nuc_version}..."
          curl -fsSL \
            "https://github.com/nix-community/nix-user-chroot/releases/download/${_nuc_version}/nix-user-chroot-bin-${_nuc_version}-${_nuc_arch}-unknown-linux-musl" \
            -o "$_nuc_bin"
          chmod +x "$_nuc_bin"
        fi
        log_info "Installing Nix inside user chroot (single-user)..."
        "$_nuc_bin" "$_nuc_store" bash -lc \
          'curl -L https://nixos.org/nix/install | sh -s -- --no-daemon'
        mkdir -p "$HOME/.config/nix"
        echo 'experimental-features = nix-command flakes' > "$HOME/.config/nix/nix.conf"
        BOOTSTRAP_MODE="chroot"
        ;;
      READY-PORTABLE)
        log_info "Preflight: READY-PORTABLE → nix-portable bootstrap"
        _np_bin="$HOME/.local/bin/nix-portable"
        _np_arch="$(uname -m)"
        mkdir -p "$HOME/.local/bin"
        if [[ ! -x "$_np_bin" ]]; then
          log_info "Downloading nix-portable..."
          curl -fsSL \
            "https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-${_np_arch}" \
            -o "$_np_bin"
          chmod +x "$_np_bin"
        fi
        BOOTSTRAP_MODE="portable"
        ;;
      *)
        log_warn "Preflight: BLOCKED — cannot bootstrap Nix without root on this host."
        log_warn "See docs/install/nix-sudoless-bootstrap.md (Section C) for pixi fallback."
        exit 0
        ;;
    esac
  fi

  determinate_flags="install --no-confirm"
  [[ "$OS" == "linux" ]] && determinate_flags="install linux --no-confirm"

  # shellcheck disable=SC2086
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
    sh -s -- $determinate_flags

  # Make nix available in current shell
  # shellcheck disable=SC1091
  [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]] && \
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# --- Step 3: Activate the flake --------------------------------------
log_info "Activating flake configuration..."

cd "$DOTFILES_DIR"

case "$OS" in
  mac)
    # Currently only one darwin host (shonenm). If/when more land, branch here.
    log_info "Running: sudo darwin-rebuild switch --flake .#shonenm"
    if ! command_exists darwin-rebuild; then
      log_info "First-time activation — invoking via 'nix run nix-darwin'..."
      sudo /nix/var/nix/profiles/default/bin/nix run nix-darwin -- \
        switch --flake .#shonenm
    else
      sudo darwin-rebuild switch --flake .#shonenm
    fi
    ;;
  linux)
    arch=$(uname -m)
    case "$arch" in
      x86_64)  hm_arch="x86_64" ;;
      aarch64) hm_arch="aarch64" ;;
      *) log_error "Unsupported Linux arch: $arch"; exit 1 ;;
    esac
    user="${USER:-$(id -un)}"
    target="${user}@linux-${hm_arch}"
    log_info "Running: nix run home-manager/master -- switch --flake .#$target -b stow-backup"
    case "${BOOTSTRAP_MODE}" in
      chroot)
        _nuc_bin="$HOME/.local/bin/nix-user-chroot"
        _nuc_store="$HOME/.nix-store/nix"
        "$_nuc_bin" "$_nuc_store" bash -lc \
          ". ~/.nix-profile/etc/profile.d/nix.sh && cd ~/dotfiles && nix run home-manager/master -- switch --flake \".#${target}\" -b stow-backup"
        ;;
      portable)
        _np_bin="$HOME/.local/bin/nix-portable"
        cd ~/dotfiles
        "$_np_bin" nix run home-manager/master -- switch --flake ".#${target}" -b stow-backup
        ;;
      *)
        nix run home-manager/master -- switch --flake ".#$target" -b stow-backup
        ;;
    esac
    ;;
esac

log_info "Done. Open a new shell session to pick up the updated environment."
log_info "Optional verification:"
log_info "  which fd starship tmux        # → /nix/store/... or ~/.nix-profile/bin"
log_info "  abbr list | wc -l             # → ~66 abbreviations"
