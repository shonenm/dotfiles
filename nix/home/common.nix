{ config, pkgs, ... }:

{
  # Cross-platform home-manager programs shared by mac.nix and linux.nix.
  # Platform-specific entries (aerospace, ghostty, sketchybar — mac UI;
  # any future linux-only modules) stay in the platform entry file.

  imports = [
    # Phase 2a — simple configs
    ./programs/bat.nix
    ./programs/fd.nix
    ./programs/gh.nix
    ./programs/gh-dash.nix
    ./programs/git.nix
    ./programs/lazygit.nix
    ./programs/mise.nix
    ./programs/sesh.nix
    ./programs/aerc.nix
    # Phase 2b — shell stack
    ./programs/zsh.nix
    ./programs/zsh-abbr.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    # Phase 2c — editor (mac-only UI modules live in mac.nix)
    ./programs/nvim.nix
    ./programs/vim.nix
    # Phase 2d — stateful + scripts
    ./programs/atuin.nix
    ./programs/claude.nix
    ./programs/codex.nix
    ./programs/opensessions.nix
    ./programs/pi.nix
    ./programs/traefik-dev.nix
    ./programs/bin.nix
    ./programs/scripts.nix
  ];

  home.stateVersion = "25.05";
  programs.home-manager.enable = true;
}
