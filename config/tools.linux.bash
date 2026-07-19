#!/bin/bash
# Linux tool definitions - sourced by scripts/linux.sh
#
# Each tool: TOOL_<name>_<field> variables
# Fields:
#   check_cmd     - command to verify installation
#   method        - curl_pipe | cargo | apt_repo
#   curl_cmd      - (curl_pipe) install command
#   cargo_crate   - (cargo) crate name
#   install_fn    - (apt_repo) function name to call
#   depends_on    - tool name that must be installed first
#   post_install  - command to run after installation
#   apt_only      - "true" to skip on Alpine
#   alt_check_cmd - alternative check command (e.g., batcat for bat)
#
# GitHub-release tools were migrated to mise (config/mise-linux.toml); the
# github_release / github_release_binary methods and their engine are removed.

# Nerd Font config (handled separately by install_nerd_font)
NERD_FONT_NAME="UDEVGothic"
NERD_FONT_VERSION="v2.0.0"
NERD_FONT_URL="https://github.com/yuru7/udev-gothic/releases/download/${NERD_FONT_VERSION}/UDEVGothic_NF_${NERD_FONT_VERSION}.zip"

# ════════════════════════════════════════
# curl-pipe installs
# ════════════════════════════════════════

TOOL_bun_check_cmd="bun"
TOOL_bun_method="curl_pipe"
TOOL_bun_curl_cmd='curl -fsSL https://bun.sh/install | bash'

TOOL_starship_check_cmd="starship"
TOOL_starship_method="curl_pipe"
TOOL_starship_curl_cmd='curl -sS https://starship.rs/install.sh | sh -s -- -y $([[ "$NO_SUDO" == "true" ]] && echo "-b $HOME/.local/bin")'

TOOL_mise_check_cmd="mise"
TOOL_mise_method="curl_pipe"
TOOL_mise_curl_cmd='curl https://mise.run | sh'

TOOL_sheldon_check_cmd="sheldon"
TOOL_sheldon_method="curl_pipe"
TOOL_sheldon_curl_cmd='curl --proto =https -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin'

TOOL_zoxide_check_cmd="zoxide"
TOOL_zoxide_method="curl_pipe"
TOOL_zoxide_curl_cmd='curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh'

TOOL_atuin_check_cmd="atuin"
TOOL_atuin_method="curl_pipe"
TOOL_atuin_curl_cmd='curl --proto =https --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --yes'

TOOL_dotenvx_check_cmd="dotenvx"
TOOL_dotenvx_method="curl_pipe"
TOOL_dotenvx_curl_cmd='curl -sfS "https://dotenvx.sh?directory=$HOME/.local/bin" | sh'

TOOL_uv_check_cmd="uv"
TOOL_uv_method="curl_pipe"
TOOL_uv_curl_cmd='curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh'

TOOL_rust_check_cmd="cargo"
TOOL_rust_method="curl_pipe"
TOOL_rust_curl_cmd='curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path'
TOOL_rust_post_install='[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"'

TOOL_lazydocker_check_cmd="lazydocker"
TOOL_lazydocker_method="curl_pipe"
TOOL_lazydocker_curl_cmd='curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash'

# fzf-tmux は fzf の release tarball に含まれておらず、master ブランチの単体スクリプト。
# fzf 本体は mise (config/mise-linux.toml) で入る。この script は install 時に fzf を
# 必要とせず (実行時のみ依存) 単体 download できるため depends_on は付けない。
TOOL_fzftmux_check_cmd="fzf-tmux"
TOOL_fzftmux_method="curl_pipe"
TOOL_fzftmux_curl_cmd='if [[ "$NO_SUDO" == "true" ]]; then mkdir -p "$HOME/.local/bin"; curl -fsSL https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-tmux -o "$HOME/.local/bin/fzf-tmux" && chmod +x "$HOME/.local/bin/fzf-tmux"; else _ft="$(mktemp -t fzf-tmux.XXXXXX)"; curl -fsSL https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-tmux -o "$_ft" && $SUDO install -m 0755 "$_ft" /usr/local/bin/fzf-tmux && rm -f "$_ft"; fi'

# ════════════════════════════════════════
# Cargo installs (all depend on rust)
# ════════════════════════════════════════

TOOL_tokei_check_cmd="tokei"
TOOL_tokei_method="cargo"
TOOL_tokei_cargo_crate="tokei"
TOOL_tokei_depends_on="rust"

TOOL_procs_check_cmd="procs"
TOOL_procs_method="cargo"
TOOL_procs_cargo_crate="procs"
TOOL_procs_depends_on="rust"

TOOL_quay_check_cmd="quay"
TOOL_quay_method="cargo"
TOOL_quay_cargo_crate="quay-tui"
TOOL_quay_depends_on="rust"

TOOL_gitabsorb_check_cmd="git-absorb"
TOOL_gitabsorb_method="cargo"
TOOL_gitabsorb_cargo_crate="git-absorb"
TOOL_gitabsorb_depends_on="rust"

TOOL_gittype_check_cmd="gittype"
TOOL_gittype_method="cargo"
TOOL_gittype_cargo_crate="gittype"
TOOL_gittype_depends_on="rust"

TOOL_cargoupdate_check_cmd="cargo-install-update"
TOOL_cargoupdate_method="cargo"
TOOL_cargoupdate_cargo_crate="cargo-update"
TOOL_cargoupdate_depends_on="rust"

TOOL_keifu_check_cmd="keifu"
TOOL_keifu_method="cargo"
TOOL_keifu_cargo_crate="keifu"
TOOL_keifu_depends_on="rust"

TOOL_tmuxexpose_check_cmd="tmux-expose"
TOOL_tmuxexpose_method="cargo"
TOOL_tmuxexpose_cargo_crate="tmux-expose"
TOOL_tmuxexpose_depends_on="rust"

# ════════════════════════════════════════
# APT repo installs (Debian/Ubuntu only)
# ════════════════════════════════════════

TOOL_gh_check_cmd="gh"
TOOL_gh_method="apt_repo"
TOOL_gh_apt_only="true"
TOOL_gh_install_fn="install_gh_apt"

TOOL_eza_check_cmd="eza"
TOOL_eza_method="apt_repo"
TOOL_eza_apt_only="true"
TOOL_eza_install_fn="install_eza_apt"

TOOL_bat_check_cmd="bat"
TOOL_bat_alt_check_cmd="batcat"
TOOL_bat_method="apt_repo"
TOOL_bat_apt_only="true"
TOOL_bat_install_fn="install_bat_apt"

TOOL_postgresql_check_cmd="psql"
TOOL_postgresql_method="apt_repo"
TOOL_postgresql_apt_only="true"
TOOL_postgresql_install_fn="install_postgresql_apt"

# pgcli via uv tool (depends on uv)
TOOL_pgcli_check_cmd="pgcli"
TOOL_pgcli_method="curl_pipe"
TOOL_pgcli_curl_cmd='uv tool install pgcli'
TOOL_pgcli_depends_on="uv"

# Cursor CLI (headless AI coding agent, Composer 2.5)
TOOL_cursor_check_cmd="cursor-agent"
TOOL_cursor_method="curl_pipe"
TOOL_cursor_curl_cmd='curl https://cursor.com/install -fsS | bash'

# ════════════════════════════════════════
# Install order (dependencies must come before dependents)
# ════════════════════════════════════════

LINUX_TOOL_ORDER=(
  # Infrastructure (no deps)
  bun starship mise sheldon zoxide atuin dotenvx uv rust lazydocker
  # fzf-tmux keybinding integration (curl-pipe)
  fzftmux
  # Cursor CLI (headless AI coding agent)
  cursor
  # APT-only (skipped on Alpine)
  gh eza bat postgresql
  # Cargo tools (depend on rust)
  tokei procs quay gitabsorb cargoupdate keifu gittype tmuxexpose
  # Python tools (depend on uv)
  pgcli
)
# GitHub-release tools (fzf, fastfetch, delta, lazygit, ghq, smug, dops, yazi,
# rainfrog, typst, just, watchexec, hyperfine, gitleaks, xh, ouch, glow, gum, viddy,
# doggo, topgrade, grex, sesh, lemonade, neovim, direnv, sd, dust,
# bottom, rip2, lsd, tealdeer) are installed via mise — see config/mise-linux.toml
# and the mise block in scripts/linux.sh. They no longer use the eval/scrape engine.
