{ pkgs, lib, ... }:

{
  # Linux user-level packages (home-manager).
  #
  # Counterpart to nix/modules/packages/core.nix (mac, nix-darwin
  # environment.systemPackages). On Linux we don't have nix-darwin so
  # everything goes through home.packages.
  #
  # Excluded vs mac core.nix:
  #   sketchybar / borders / macmon  — macOS UI
  #   postgresql_17                  — large; use apt's postgresql-client
  #                                    on hosts that need it
  # Excluded vs both (already installed by programs.* home-manager modules):
  #   bat, fd, gh, git, lazygit, mise — programs.<name>.enable = true
  #   starship, tmux, zsh             — programs.<name>.enable = true
  #
  # System-level (not installable via home.packages on a regular user
  # account) stays on apt:
  #   build-essential, pkg-config, libssl-dev, openssh-server, fonts,
  #   postgresql server, system X libs.
  # See docs/install/linux-apt-residue.md.

  home.packages = with pkgs; [
    # --- Shell & Terminal ---
    atuin
    sesh
    aerc
    stow

    # --- Image Processing ---
    imagemagick
    qrencode

    # --- Development ---
    neovim
    typst
    lazydocker
    delta # git-delta
    ghq
    uv
    rustup
    bun

    # --- Development Workflow ---
    direnv
    just
    watchexec
    hyperfine
    autossh
    pueue

    # --- Database ---
    pgcli
    # postgresql_17 omitted — heavy; use apt postgresql-client where needed

    # --- Security ---
    gitleaks

    # --- Modern CLI tools ---
    eza
    lsd
    ripgrep
    fzf
    jq
    yazi
    tokei
    tealdeer
    procs
    sd
    dust
    bottom
    fastfetch
    xh
    git-absorb
    ouch
    glow
    viddy
    doggo
    topgrade
    grex

    # --- Misc ---
    zsh-completions
  ];

  nixpkgs.config.allowUnfree = true;
}
