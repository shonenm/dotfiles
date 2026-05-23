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
  ];

  home.username = "matsushimakouta";
  home.homeDirectory = "/Users/matsushimakouta";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
