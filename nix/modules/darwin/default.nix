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

  # Shells managed by nix-darwin; /etc/zshrc bootstrap remains untouched in Phase 1a
  # programs.zsh.enable = true;  # Phase 2 (dotfiles migration)
}
