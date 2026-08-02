#!/bin/bash

# Linux (Debian/Ubuntu/Alpine) Setup Script
# No -e: individual steps may fail without aborting the rest; failures are
# collected via run_step and reported through finish_steps (non-zero exit).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$DOTFILES_DIR/config"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/utils.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/install-common.sh"

# NO_SUDO mode is decided by install.sh (--no-sudo flag). Default false when run standalone.
: "${NO_SUDO:=false}"
export NO_SUDO

# Temp directory base (honors TMPDIR; falls back to ~/.cache to avoid hardcoded paths)
_td="${TMPDIR:-$HOME/.cache}"

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

# Avoid downloading the apt index repeatedly in one installer run. Repository
# setup functions may force a refresh after adding a new source.
APT_INDEX_UPDATED=false
apt_update_once() {
  local force="${1:-false}"
  if [[ "$force" == "true" || "$APT_INDEX_UPDATED" != "true" ]]; then
    $SUDO apt update
    APT_INDEX_UPDATED=true
  fi
}

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
  # SKIP_1P propagated from install.sh --skip-1p (container/ephemeral env)
  if [[ "${SKIP_1P:-false}" == "true" ]]; then
    log_warn "1Password CLI check skipped (--skip-1p). Secret-dependent steps will no-op."
    return 0
  fi

  # op 未導入 / 未 signin でも abort しない (install.sh の check_1password_cli と同じ方針)。
  # ここは run_step から直接呼ばれるので exit すると linux.sh 全体が落ち、後続の
  # set_default_shell まで飛ばされる。secret 依存ステップは op read が no-op fallback
  # するので継続して問題なく、signin 後に再実行すれば secret が反映される。
  # 未 signin の最終案内は install.sh の summary が出す。
  if ! command_exists op; then
    log_warn "1Password CLI not installed. Secret-dependent steps will no-op."
    log_warn "Install: https://developer.1password.com/docs/cli/get-started/"
    return 0
  fi

  if op whoami &>/dev/null; then
    log_success "1Password CLI: signed in"
  else
    log_warn "1Password CLI: not signed in. Secret-dependent steps will no-op this run."
    log_warn "Sign in with 'eval \$(op signin)' and re-run to populate secrets."
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
    apt_update_once
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

# Upgrade system git to a recent stable release on Ubuntu via the git-core PPA.
# Ubuntu ships an old git (22.04 = 2.34) that lacks in-place partial-clone
# conversion (`git fetch --refetch`, added in 2.36) and other modern fetch
# fixes. The git project itself recommends ppa:git-core/ppa for current git.
# Version-guarded and idempotent: no-op once git is new enough.
install_git_latest() {
  local target_major=2 target_minor=36

  # Debian/Ubuntu sudo path only. The PPA is Ubuntu-specific.
  command_exists apt || return 0
  if [[ "$NO_SUDO" == "true" ]]; then
    log_info "No-sudo mode: git is upgraded via pixi (config/pixi-packages.txt), not the PPA"
    return 0
  fi
  if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    log_info "Non-Ubuntu apt host: skipping git-core PPA (use distro backports for newer git)"
    return 0
  fi

  if command_exists git; then
    local ver major rest minor
    ver=$(git --version | awk '{print $3}')
    major=${ver%%.*}
    rest=${ver#*.}
    minor=${rest%%.*}
    if (( major > target_major || (major == target_major && minor >= target_minor) )); then
      log_success "git $ver already >= ${target_major}.${target_minor}"
      return 0
    fi
    log_info "git $ver older than ${target_major}.${target_minor}, upgrading via git-core PPA..."
  fi

  if ! command_exists add-apt-repository; then
    apt_update_once
    $SUDO apt install -y software-properties-common
  fi
  $SUDO add-apt-repository -y ppa:git-core/ppa
  apt_update_once true
  $SUDO apt install -y git
  log_success "git upgraded to $(git --version | awk '{print $3}')"
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
  mkdir -p "$_td/udev-gothic-nf"
  unzip -o "$zip_file" -d "$_td/udev-gothic-nf"
  cp "$_td"/udev-gothic-nf/UDEVGothic_NF_*/UDEVGothicNF-*.ttf "$font_dir/"
  rm -rf "$zip_file" "$_td/udev-gothic-nf"
  fc-cache -fv >/dev/null 2>&1
  log_success "UDEV Gothic Nerd Font installed"
}

# --- Tool Installation Helpers ---

# Get a tool's config field value via indirect expansion
# (:- keeps unset optional fields safe under `set -u`)
_tool_field() {
  local var="TOOL_${1}_${2}"
  echo "${!var:-}"
}

# --- APT repo install functions (Debian/Ubuntu only) ---

install_gh_apt() {
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  apt_update_once true
  $SUDO apt install -y gh
}

install_eza_apt() {
  $SUDO mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | $SUDO gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | $SUDO tee /etc/apt/sources.list.d/gierens.list
  $SUDO chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  apt_update_once true
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

# atuin の setup script は `grep -q "atuin init zsh" "${ZDOTDIR:-$HOME}/.zshrc"` が
# 空振りすると ~/.zshrc へ init 行を追記する。~/.zshrc は stow symlink なので
# dotfiles repo 本体 (common/zsh/.zshrc) が汚れ、次回 install の link_dotfiles が
# stow --adopt 前チェックで停止する。init は linux/zsh/.zshrc.local が担当済みなので、
# 「追記済み」に見えるダミー .zshrc を持つ ZDOTDIR を渡して guard を成立させ、
# 追記そのものを起こさせない。PATH 側の追記は ATUIN_NO_MODIFY_PATH=1 が抑止する。
_atuin_rc_guard_dir() {
  local d="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/atuin-rc-guard"
  mkdir -p "$d"
  printf 'eval "$(atuin init zsh)"\n' > "$d/.zshrc"
  printf '%s' "$d"
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
    # Linux-only tool set (github releases migrated off the eval/scrape engine).
    # conf.d is auto-loaded by mise and NOT stowed, so macOS never sees it.
    mkdir -p "$HOME/.config/mise/conf.d"
    cp "$CONFIG_DIR/mise-linux.toml" "$HOME/.config/mise/conf.d/dotfiles-linux.toml"
    log_info "Installing mise-managed tools..."
    "$HOME/.local/bin/mise" install -y 2>/dev/null || true
    # `mise activate bash` は interactive shell 用 (PROMPT_COMMAND hook) で、
    # installer のような非対話 script では PATH が一切書き換わらない。後続 step
    # (install_npm_packages / install_compiled_tools の go) から mise 管理ツールを
    # 見せるため、install 後に shims を直接 PATH へ載せる。
    eval "$("$HOME/.local/bin/mise" activate bash --shims 2>/dev/null || true)"
  fi

  # Summary
  echo
  log_info "── Tool Summary ──"
  [[ ${#_new[@]} -gt 0 ]] && log_success "  New: ${_new[*]}"
  [[ ${#_existing[@]} -gt 0 ]] && log_info "  Existing: ${_existing[*]}"
}

install_bun() {
  if command_exists bun; then
    log_success "bun already installed"
    return
  fi

  log_info "Installing bun (tmux-palette runtime)..."
  # Installs into ~/.bun; PATH is exported in zshrc.common (~/.bun/bin).
  # bun の installer は `basename "$SHELL"` で分岐して rc に PATH を追記するが、
  # ~/.zshrc は stow symlink なので dotfiles repo 本体が書き換わり、次回 install の
  # link_dotfiles が "Uncommitted changes ... stow --adopt" で停止する (再実行の
  # たびに重複追記もされる)。PATH は zshrc.common が担当済みなので、追記分岐に
  # 入らない SHELL 名 (sh → case の `*` fallback) を渡して抑制する。
  curl -fsSL https://bun.sh/install | SHELL=/bin/sh bash
  log_success "bun installed"
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

  apt_update_once true
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
        echo '# zsh is installed under ~/.pixi/bin in no-sudo mode; ensure it is on PATH'
        echo '# before the lookup so login bash hands off to zsh instead of staying put.'
        echo '[ -d "$HOME/.pixi/bin" ] && PATH="$HOME/.pixi/bin:$PATH"'
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
  local build_dir="$_td/fancy-cat-build"
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

# Build tmux 3.6a from source when the available tmux is older.
# Rationale (no-sudo): sudoless hosts lose apt's tmux 3.2+, and pixi's
# conda-forge tmux 3.6 crashes on attach in this environment (xterm-ghostty +
# real PTY combination). The system tmux 3.2a is too old to forward bracketed
# paste properly to TUIs (allow-passthrough is missing).
# Rationale (sudo あり): distro が 3.4〜3.5a を配る間 (Debian trixie = 3.5a)、
# tmux はコマンド出力を vis エスケープし `-F` の 0x1f 区切りが `\037` に化ける。
# agent index 側は agent_unvis で復号しているが、根本解消は 3.6 以降を使うこと。
# どちらの経路でも upstream 3.6a を system libevent/ncurses に対してビルドする。
install_tmux_source() {
  local target_version="3.6a"
  local current_bin="$HOME/.local/bin/tmux"

  # PATH 上の tmux が target 以上なら何もしない (idempotent)
  local have
  have=$(tmux -V 2>/dev/null | awk '{print $2}')
  if [[ -n "$have" && "$(printf '%s\n%s\n' "$target_version" "$have" | sort -V | head -1)" == "$target_version" ]]; then
    log_success "tmux $have already satisfies >= $target_version"
    return 0
  fi

  # Check build dependencies
  local missing=()
  for cmd in gcc make wget tar; do
    command_exists "$cmd" || missing+=("$cmd")
  done
  # Header check: libevent and ncurses headers required
  local lib_missing=()
  [[ -f /usr/include/event2/event.h ]] || [[ -f /usr/include/event.h ]] || lib_missing+=("libevent-dev")
  [[ -f /usr/include/ncurses.h ]] || [[ -f /usr/include/ncurses/ncurses.h ]] || lib_missing+=("libncurses-dev")

  if [[ ${#missing[@]} -gt 0 || ${#lib_missing[@]} -gt 0 ]]; then
    log_warn "tmux source build skipped — missing: ${missing[*]:-} ${lib_missing[*]:-}"
    log_warn "  Ask host admin to install: ${missing[*]} ${lib_missing[*]}"
    return 0
  fi

  log_info "Building tmux $target_version from source..."
  local src_dir="$_td/tmux-$target_version"
  local url="https://github.com/tmux/tmux/releases/download/$target_version/tmux-$target_version.tar.gz"
  rm -rf "$src_dir" "$_td/tmux-$target_version.tar.gz"
  (
    set -e
    cd "$_td"
    wget -q "$url" -O "tmux-$target_version.tar.gz"
    tar xf "tmux-$target_version.tar.gz"
    cd "tmux-$target_version"
    ./configure --prefix="$HOME/.local" >/dev/null 2>&1
    make -j4 >/dev/null 2>&1
    make install >/dev/null 2>&1
  )
  rm -rf "$src_dir" "$_td/tmux-$target_version.tar.gz"

  if [[ -x "$current_bin" ]]; then
    log_success "tmux $("$current_bin" -V) installed to ~/.local/bin/tmux"
  else
    log_error "tmux source build failed"
    return 1
  fi
}

# --- Main Execution ---

run_step check_requirements
run_step install_system_packages
run_step install_git_latest
run_step install_tmux_source
run_step install_modern_tools
run_step install_bun
run_step install_npm_packages
run_step install_claude_mem
run_step install_serena
run_step install_context_mode
run_step install_code_review_graph
run_step install_auto_mode
run_step configure_claude_remote_control_autostart
run_step link_ai_scripts
run_step install_gh_extensions
run_step install_compiled_tools
run_step install_ghostty_terminfo
run_step install_fancy_cat
run_step install_1password_cli
run_step check_1password
run_step set_default_shell

finish_steps "Linux setup complete!"
