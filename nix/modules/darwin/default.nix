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

  # === macOS preferences =============================================
  # Tier 1 (Phase 3a, low-risk universal):
  #   key repeat, accent picker, file extensions, Dock auto-hide, Finder
  #   path/status bar + list view + sort folders first, screenshot
  #   location + format, LSQuarantine disabled.
  # Tier 2 (Phase 3b, opinionated dev defaults):
  #   Dark mode lock, all NSAutomatic*Enabled disabled, no iCloud default
  #   save, hot corners disabled (aerospace boundaries), trackpad
  #   tap-to-click.
  # Tier 3 (Phase 3b, security baseline):
  #   immediate lock on screensaver.
  #
  # Settings are written to plists on `darwin-rebuild switch`. Some
  # require killall Dock / Finder / SystemUIServer or a re-login to
  # fully reflect in the System Settings UI.

  system.defaults = {
    NSGlobalDomain = {
      # --- Tier 1 ---
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      ApplePressAndHoldEnabled = false;
      AppleShowAllExtensions = true;
      # --- Tier 2 ---
      # Lock OS UI to dark — repo theme stack (tmux, Ghostty, starship,
      # p10k) is dark; macOS UI matching avoids palette clashes.
      AppleInterfaceStyle = "Dark";
      # All NSAutomatic* off (incompatible with dev workflows: code,
      # CLI commands, single quotes in strings, etc.)
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      # Default Save dialog → local disk, not iCloud
      NSDocumentSaveNewDocumentsToCloud = false;
    };

    dock = {
      # --- Tier 1 ---
      autohide = true;
      show-recents = false;
      tilesize = 36;
      mru-spaces = false;
      # --- Tier 2 ---
      # Hot corners off: aerospace uses screen edges for workspace
      # navigation; macOS triggering Mission Control / sleep on those
      # edges interferes.
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
    };

    finder = {
      # --- Tier 1 ---
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "Nlsv";
      _FXSortFoldersFirst = true;
    };

    screencapture = {
      # --- Tier 1 ---
      location = "~/Pictures/Screenshots";
      type = "png";
    };

    LaunchServices = {
      # --- Tier 1 ---
      LSQuarantine = false;
    };

    # --- Tier 2: trackpad ---
    trackpad = {
      # Tap-to-click (no need to press down)
      Clicking = true;
    };

    # --- Tier 3: screensaver password ---
    screensaver = {
      askForPassword = true;
      # Lock immediately on sleep / screensaver (0 = no grace period)
      askForPasswordDelay = 0;
    };
  };

  # === services.aerospace ============================================
  # nix-darwin's launchd-managed startup for AeroSpace. Replaces
  # AeroSpace's own `start-at-login = true` (removed from aerospace.toml).
  # launchd label: org.nixos.aerospace (KeepAlive + RunAtLoad).
  #
  # Settings sourced from nix/home/programs/aerospace/aerospace.toml
  # via builtins.fromTOML so the existing config remains the source of
  # truth. Module assertions: !settings.start-at-login (removed).
  services.aerospace = {
    enable = true;
    settings = builtins.fromTOML
      (builtins.readFile ../../home/programs/aerospace/aerospace.toml);
  };

  # === Karabiner-Elements / SketchyBar deferred =======================
  # services.karabiner-elements: v15 architecture rewrite + recurring
  # post-rebuild breakage reports (nix-darwin#564, #639). Defer until a
  # focused migration window with TCC re-grant rehearsal.
  # services.sketchybar: inline cfg.config takes shell lines; user's
  # setup is sketchybarrc + 14 plugins/*.sh referencing $PLUGIN_DIR.
  # Inline conversion non-trivial and currently working via OS auto-start.
}
