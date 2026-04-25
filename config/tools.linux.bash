#!/bin/bash
# Linux tool definitions - sourced by scripts/linux.sh
#
# Each tool: TOOL_<name>_<field> variables
# Fields:
#   check_cmd     - command to verify installation
#   method        - curl_pipe | github_release | github_release_binary | cargo | apt_repo
#   curl_cmd      - (curl_pipe) install command
#   cargo_crate   - (cargo) crate name
#   github_repo   - (github_release) owner/repo
#   archive_pattern - (github_release) tarball name template (vars: VERSION, VERSION_NOTAG, ARCH)
#   binary_path   - (github_release) path to binary inside tarball
#   binary_map    - (github_release_binary) "uname_arch:filename" pairs
#   arch_map      - architecture mapping "uname_arch:tool_arch" pairs
#   install_cmd   - (github_release) custom install command
#   install_fn    - (apt_repo) function name to call
#   install_dir   - (github_release_binary) target directory
#   depends_on    - tool name that must be installed first
#   post_install  - command to run after installation
#   apt_only      - "true" to skip on Alpine
#   alt_check_cmd - alternative check command (e.g., batcat for bat)

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

# AI agent token compression CLI (60-90% reduction). GitHub release tarball.
TOOL_rtk_check_cmd="rtk"
TOOL_rtk_method="github_release"
TOOL_rtk_github_repo="rtk-ai/rtk"
TOOL_rtk_archive_pattern='rtk-${ARCH}.tar.gz'
TOOL_rtk_binary_path='rtk'
TOOL_rtk_arch_map='x86_64:x86_64-unknown-linux-musl aarch64:aarch64-unknown-linux-gnu'

TOOL_direnv_check_cmd="direnv"
TOOL_direnv_method="github_release_binary"
TOOL_direnv_github_repo="direnv/direnv"
TOOL_direnv_binary_map='x86_64:direnv.linux-amd64 aarch64:direnv.linux-arm64'
TOOL_direnv_install_dir="$HOME/.local/bin"

# ════════════════════════════════════════
# GitHub release installs (tarball)
# ════════════════════════════════════════

TOOL_fzf_check_cmd="fzf"
TOOL_fzf_method="github_release"
TOOL_fzf_github_repo="junegunn/fzf"
TOOL_fzf_archive_pattern='fzf-${VERSION_NOTAG}-linux_${ARCH}.tar.gz'
TOOL_fzf_binary_path='fzf'
TOOL_fzf_arch_map='x86_64:amd64 aarch64:arm64'

# fzf-tmux は fzf の release tarball に含まれておらず、master ブランチの単体スクリプト。
# 独立 tool として登録しておくと、fzf が既に入っている環境でも post-add でこれだけ
# 補完インストールできる (sesh の popup prefix+C-f が依存)。
TOOL_fzftmux_check_cmd="fzf-tmux"
TOOL_fzftmux_method="curl_pipe"
TOOL_fzftmux_depends_on="fzf"
TOOL_fzftmux_curl_cmd='if [[ "$NO_SUDO" == "true" ]]; then mkdir -p "$HOME/.local/bin"; curl -fsSL https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-tmux -o "$HOME/.local/bin/fzf-tmux" && chmod +x "$HOME/.local/bin/fzf-tmux"; else curl -fsSL https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-tmux -o /tmp/fzf-tmux && $SUDO install -m 0755 /tmp/fzf-tmux /usr/local/bin/fzf-tmux && rm -f /tmp/fzf-tmux; fi'

TOOL_fastfetch_check_cmd="fastfetch"
TOOL_fastfetch_method="github_release"
TOOL_fastfetch_github_repo="fastfetch-cli/fastfetch"
TOOL_fastfetch_archive_pattern='fastfetch-linux-${ARCH}.tar.gz'
TOOL_fastfetch_binary_path='fastfetch-linux-${ARCH}/usr/bin/fastfetch'
TOOL_fastfetch_arch_map='x86_64:amd64 aarch64:aarch64'

TOOL_delta_check_cmd="delta"
TOOL_delta_method="github_release"
TOOL_delta_github_repo="dandavison/delta"
TOOL_delta_archive_pattern='delta-${VERSION}-${ARCH}-unknown-linux-gnu.tar.gz'
TOOL_delta_binary_path='delta-${VERSION}-${ARCH}-unknown-linux-gnu/delta'
TOOL_delta_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_lazygit_check_cmd="lazygit"
TOOL_lazygit_method="github_release"
TOOL_lazygit_github_repo="jesseduffield/lazygit"
TOOL_lazygit_archive_pattern='lazygit_${VERSION_NOTAG}_Linux_${ARCH}.tar.gz'
TOOL_lazygit_binary_path='lazygit'
TOOL_lazygit_arch_map='x86_64:x86_64 aarch64:arm64'

TOOL_ghq_check_cmd="ghq"
TOOL_ghq_method="github_release"
TOOL_ghq_github_repo="x-motemen/ghq"
TOOL_ghq_archive_pattern='ghq_linux_${ARCH}.zip'
TOOL_ghq_binary_path='ghq_linux_${ARCH}/ghq'
TOOL_ghq_arch_map='x86_64:amd64 aarch64:arm64'

TOOL_neovim_check_cmd="nvim"
TOOL_neovim_method="github_release"
TOOL_neovim_github_repo="neovim/neovim"
TOOL_neovim_archive_pattern='nvim-linux-${ARCH}.tar.gz'
TOOL_neovim_arch_map='x86_64:x86_64 aarch64:arm64'
TOOL_neovim_install_cmd='_install_neovim_tarball "$archive" "$ARCH"'
TOOL_neovim_apt_only="true"

# ════════════════════════════════════════
# GitHub release installs (single binary)
# ════════════════════════════════════════

TOOL_dops_check_cmd="dops"
TOOL_dops_method="github_release_binary"
TOOL_dops_github_repo="Mikescher/better-docker-ps"
TOOL_dops_binary_map='x86_64:dops_linux-amd64-static aarch64:dops_linux-arm64'
TOOL_dops_install_dir="$HOME/.local/bin"

# ════════════════════════════════════════
# Cargo installs (all depend on rust)
# ════════════════════════════════════════

TOOL_tokei_check_cmd="tokei"
TOOL_tokei_method="cargo"
TOOL_tokei_cargo_crate="tokei"
TOOL_tokei_depends_on="rust"

# tealdeer: single binary, renamed to `tldr` at $install_dir via check_cmd
TOOL_tealdeer_check_cmd="tldr"
TOOL_tealdeer_method="github_release_binary"
TOOL_tealdeer_github_repo="tealdeer-rs/tealdeer"
TOOL_tealdeer_binary_map='x86_64:tealdeer-linux-x86_64-musl aarch64:tealdeer-linux-aarch64-musl'
TOOL_tealdeer_install_dir="$HOME/.local/bin"

TOOL_procs_check_cmd="procs"
TOOL_procs_method="cargo"
TOOL_procs_cargo_crate="procs"
TOOL_procs_depends_on="rust"

# sd: tarball, binary under sd-VERSION-ARCH-unknown-linux-musl/sd
TOOL_sd_check_cmd="sd"
TOOL_sd_method="github_release"
TOOL_sd_github_repo="chmln/sd"
TOOL_sd_archive_pattern='sd-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_sd_binary_path='sd-${VERSION}-${ARCH}-unknown-linux-musl/sd'
TOOL_sd_arch_map='x86_64:x86_64 aarch64:aarch64'

# dust: tarball, binary under dust-VERSION-ARCH-unknown-linux-musl/dust
TOOL_dust_check_cmd="dust"
TOOL_dust_method="github_release"
TOOL_dust_github_repo="bootandy/dust"
TOOL_dust_archive_pattern='dust-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_dust_binary_path='dust-${VERSION}-${ARCH}-unknown-linux-musl/dust'
TOOL_dust_arch_map='x86_64:x86_64 aarch64:aarch64'

# bottom (btm): tarball is flat, binary name is `btm`
TOOL_bottom_check_cmd="btm"
TOOL_bottom_method="github_release"
TOOL_bottom_github_repo="ClementTsang/bottom"
TOOL_bottom_archive_pattern='bottom_${ARCH}-unknown-linux-musl.tar.gz'
TOOL_bottom_binary_path='btm'
TOOL_bottom_arch_map='x86_64:x86_64 aarch64:aarch64'

# rip2 (rip): tarball is flat, binary name is `rip`
TOOL_rip2_check_cmd="rip"
TOOL_rip2_method="github_release"
TOOL_rip2_github_repo="MilesCranmer/rip2"
TOOL_rip2_archive_pattern='rip-Linux-${ARCH}-musl.tar.gz'
TOOL_rip2_binary_path='rip'
TOOL_rip2_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_quay_check_cmd="quay"
TOOL_quay_method="cargo"
TOOL_quay_cargo_crate="quay-tui"
TOOL_quay_depends_on="rust"

# lsd: tarball, binary under lsd-VERSION-ARCH-unknown-linux-musl/lsd
TOOL_lsd_check_cmd="lsd"
TOOL_lsd_method="github_release"
TOOL_lsd_github_repo="lsd-rs/lsd"
TOOL_lsd_archive_pattern='lsd-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_lsd_binary_path='lsd-${VERSION}-${ARCH}-unknown-linux-musl/lsd'
TOOL_lsd_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_gitabsorb_check_cmd="git-absorb"
TOOL_gitabsorb_method="cargo"
TOOL_gitabsorb_cargo_crate="git-absorb"
TOOL_gitabsorb_depends_on="rust"

TOOL_cargoupdate_check_cmd="cargo-install-update"
TOOL_cargoupdate_method="cargo"
TOOL_cargoupdate_cargo_crate="cargo-update"
TOOL_cargoupdate_depends_on="rust"

TOOL_keifu_check_cmd="keifu"
TOOL_keifu_method="cargo"
TOOL_keifu_cargo_crate="keifu"
TOOL_keifu_depends_on="rust"

TOOL_yazi_check_cmd="yazi"
TOOL_yazi_method="github_release"
TOOL_yazi_github_repo="sxyazi/yazi"
TOOL_yazi_archive_pattern='yazi-${ARCH}-unknown-linux-gnu.zip'
TOOL_yazi_binary_path='yazi-${ARCH}-unknown-linux-gnu/yazi'
TOOL_yazi_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_just_check_cmd="just"
TOOL_just_method="github_release"
TOOL_just_github_repo="casey/just"
TOOL_just_archive_pattern='just-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_just_binary_path='just'
TOOL_just_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_watchexec_check_cmd="watchexec"
TOOL_watchexec_method="github_release"
TOOL_watchexec_github_repo="watchexec/watchexec"
TOOL_watchexec_archive_pattern='watchexec-${VERSION_NOTAG}-${ARCH}-unknown-linux-musl.tar.xz'
TOOL_watchexec_binary_path='watchexec-${VERSION_NOTAG}-${ARCH}-unknown-linux-musl/watchexec'
TOOL_watchexec_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_hyperfine_check_cmd="hyperfine"
TOOL_hyperfine_method="github_release"
TOOL_hyperfine_github_repo="sharkdp/hyperfine"
TOOL_hyperfine_archive_pattern='hyperfine-${VERSION}-${ARCH}-unknown-linux-gnu.tar.gz'
TOOL_hyperfine_binary_path='hyperfine-${VERSION}-${ARCH}-unknown-linux-gnu/hyperfine'
TOOL_hyperfine_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_gitleaks_check_cmd="gitleaks"
TOOL_gitleaks_method="github_release"
TOOL_gitleaks_github_repo="gitleaks/gitleaks"
TOOL_gitleaks_archive_pattern='gitleaks_${VERSION_NOTAG}_linux_${ARCH}.tar.gz'
TOOL_gitleaks_binary_path='gitleaks'
TOOL_gitleaks_arch_map='x86_64:x64 aarch64:arm64'

TOOL_xh_check_cmd="xh"
TOOL_xh_method="github_release"
TOOL_xh_github_repo="ducaale/xh"
TOOL_xh_archive_pattern='xh-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_xh_binary_path='xh-${VERSION}-${ARCH}-unknown-linux-musl/xh'
TOOL_xh_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_ouch_check_cmd="ouch"
TOOL_ouch_method="github_release"
TOOL_ouch_github_repo="ouch-org/ouch"
TOOL_ouch_archive_pattern='ouch-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_ouch_binary_path='ouch-${ARCH}-unknown-linux-musl/ouch'
TOOL_ouch_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_glow_check_cmd="glow"
TOOL_glow_method="github_release"
TOOL_glow_github_repo="charmbracelet/glow"
TOOL_glow_archive_pattern='glow_${VERSION_NOTAG}_Linux_${ARCH}.tar.gz'
TOOL_glow_binary_path='glow_${VERSION_NOTAG}_Linux_${ARCH}/glow'
TOOL_glow_arch_map='x86_64:x86_64 aarch64:arm64'

TOOL_viddy_check_cmd="viddy"
TOOL_viddy_method="github_release"
TOOL_viddy_github_repo="sachaos/viddy"
TOOL_viddy_archive_pattern='viddy-${VERSION}-linux-${ARCH}.tar.gz'
TOOL_viddy_binary_path='viddy'
TOOL_viddy_arch_map='x86_64:x86_64 aarch64:arm64'

TOOL_doggo_check_cmd="doggo"
TOOL_doggo_method="github_release"
TOOL_doggo_github_repo="mr-karan/doggo"
TOOL_doggo_archive_pattern='doggo_${VERSION_NOTAG}_Linux_${ARCH}.tar.gz'
TOOL_doggo_binary_path='doggo_${VERSION_NOTAG}_Linux_${ARCH}/doggo'
TOOL_doggo_arch_map='x86_64:x86_64 aarch64:arm64'

TOOL_sesh_check_cmd="sesh"
TOOL_sesh_method="github_release"
TOOL_sesh_github_repo="joshmedeski/sesh"
TOOL_sesh_archive_pattern='sesh_Linux_${ARCH}.tar.gz'
TOOL_sesh_binary_path='sesh'
TOOL_sesh_arch_map='x86_64:x86_64 aarch64:arm64'

TOOL_topgrade_check_cmd="topgrade"
TOOL_topgrade_method="github_release"
TOOL_topgrade_github_repo="topgrade-rs/topgrade"
TOOL_topgrade_archive_pattern='topgrade-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_topgrade_binary_path='topgrade'
TOOL_topgrade_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_grex_check_cmd="grex"
TOOL_grex_method="github_release"
TOOL_grex_github_repo="pemistahl/grex"
TOOL_grex_archive_pattern='grex-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_grex_binary_path='grex'
TOOL_grex_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_typst_check_cmd="typst"
TOOL_typst_method="github_release"
TOOL_typst_github_repo="typst/typst"
TOOL_typst_archive_pattern='typst-${ARCH}-unknown-linux-musl.tar.xz'
TOOL_typst_binary_path='typst-${ARCH}-unknown-linux-musl/typst'
TOOL_typst_arch_map='x86_64:x86_64 aarch64:aarch64'

TOOL_rainfrog_check_cmd="rainfrog"
TOOL_rainfrog_method="github_release"
TOOL_rainfrog_github_repo="achristmascarl/rainfrog"
TOOL_rainfrog_archive_pattern='rainfrog-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz'
TOOL_rainfrog_binary_path='rainfrog'
TOOL_rainfrog_arch_map='x86_64:x86_64 aarch64:aarch64'

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

# ════════════════════════════════════════
# Install order (dependencies must come before dependents)
# ════════════════════════════════════════

LINUX_TOOL_ORDER=(
  # Infrastructure (no deps)
  bun starship mise sheldon zoxide atuin dotenvx uv rust lazydocker direnv
  # GitHub releases (no deps)
  fzf fzftmux fastfetch delta lazygit ghq dops yazi rainfrog typst
  just watchexec hyperfine gitleaks xh ouch glow viddy doggo topgrade grex sesh rtk
  # APT-only (skipped on Alpine)
  gh neovim eza bat postgresql
  # Cargo tools (depend on rust)
  tokei tealdeer procs sd dust bottom rip2 lsd quay gitabsorb cargoupdate keifu
  # Python tools (depend on uv)
  pgcli
)
