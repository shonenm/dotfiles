{ config, pkgs, ... }:

{
  # macOS home-manager entry. Common cross-platform programs + macOS-only
  # UI modules (aerospace window manager, Ghostty terminal config,
  # SketchyBar status bar).

  imports = [
    ./common.nix
    ./programs/aerospace.nix
    ./programs/ghostty.nix
    ./programs/sketchybar.nix
  ];

  home.username = "matsushimakouta";
  home.homeDirectory = "/Users/matsushimakouta";
}
