{ pkgs, ... }:

{
  # Phase 1a: nixpkgs-native packages from config/Brewfile.
  # Custom packages (keifu, rtk, lemonade, FelixKratz/*) → Phase 1b (overlays).
  # Casks (ghostty, raycast, karabiner-elements, aerospace) → Phase 1c.
  environment.systemPackages = with pkgs; [
    # Shell & Terminal
    tmux
    starship
    sheldon
    atuin
    zoxide
    sesh
    stow
    aerc

    # Image Processing
    imagemagick
    qrencode

    # Development
    neovim
    typst
    # lazygit → home-manager (programs.lazygit, Phase 2a)
    lazydocker
    delta # git-delta
    # gh → home-manager (programs.gh, Phase 2a)
    ghq
    # mise → home-manager (programs.mise, Phase 2a)
    uv
    rustup
    bun

    # Development Workflow
    direnv
    just
    watchexec
    hyperfine
    autossh
    pueue

    # Database
    pgcli
    postgresql_17

    # Security
    gitleaks

    # Modern CLI tools
    eza
    lsd
    # bat → home-manager (programs.bat, Phase 2a)
    ripgrep
    # fd → home-manager (programs.fd, Phase 2a)
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
  ];
}
