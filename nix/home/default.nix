{ config, pkgs, ... }:

{
  imports = [
    ./programs/bat.nix
    ./programs/fd.nix
    ./programs/gh.nix
    ./programs/gh-dash.nix
    ./programs/git.nix
    ./programs/lazygit.nix
    ./programs/mise.nix
    ./programs/sesh.nix
    ./programs/aerc.nix
    # Phase 2b additions
    ./programs/zsh.nix
    ./programs/zsh-abbr.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    # Phase 2c additions
    ./programs/nvim.nix
    ./programs/vim.nix
    ./programs/aerospace.nix
    ./programs/ghostty.nix
    ./programs/sketchybar.nix
  ];

  home.username = "matsushimakouta";
  home.homeDirectory = "/Users/matsushimakouta";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
