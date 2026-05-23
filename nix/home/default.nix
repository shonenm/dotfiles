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
  ];

  home.username = "matsushimakouta";
  home.homeDirectory = "/Users/matsushimakouta";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
