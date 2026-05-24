{ pkgs, lib, ... }:

{
  # Determinate Systems manages the Nix daemon itself.
  # Setting nix.enable = false prevents nix-darwin from overwriting Determinate's nix config.
  nix.enable = false;

  # Required by nix-darwin
  system.stateVersion = 5;

  # Use nix-command and flakes (already enabled by Determinate, but declared here for clarity)
  # nix.settings.experimental-features = [ "nix-command" "flakes" ];  # disabled due to nix.enable = false

  # Allow unfree packages (1password CLI, raycast, etc. may require this)
  nixpkgs.config.allowUnfree = true;

  # Delegate /etc/zshrc bootstrap to nix-darwin so it ships our zsh setup
  # (FPATH, completion site-functions, etc.) cleanly. User-level interactive
  # behaviour still comes from home-manager-managed ~/.zshrc.
  programs.zsh.enable = true;

  # === Phase 3a: macOS preferences (Tier 1) ===========================
  # Settings here are written to the relevant plist on `darwin-rebuild
  # switch`. Some require killall Dock / Finder / SystemUIServer or a
  # logout to fully reflect in the System Settings UI.

  system.defaults = {
    NSGlobalDomain = {
      # Fastest key repeat (System Settings → Keyboard slider can't reach this)
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      # Disable the accent picker so vim-style j/k hold works in any text field
      ApplePressAndHoldEnabled = false;
      # Always show file extensions in the Finder
      AppleShowAllExtensions = true;
    };

    dock = {
      autohide = true;
      show-recents = false;
      tilesize = 36;
      # Required for aerospace's workspace switching — when true, macOS
      # auto-reorders Spaces based on recency and aerospace's index-based
      # navigation breaks.
      mru-spaces = false;
    };

    finder = {
      ShowPathbar = true;
      ShowStatusBar = true;
      # List view by default
      FXPreferredViewStyle = "Nlsv";
      _FXSortFoldersFirst = true;
    };

    screencapture = {
      location = "~/Pictures/Screenshots";
      type = "png";
    };

    LaunchServices = {
      # Skip the "this app was downloaded from the internet" warning
      LSQuarantine = false;
    };
  };
}
