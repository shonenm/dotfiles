{ pkgs, ... }:

{
  imports = [
    ../modules/darwin/default.nix
    ../modules/packages/core.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  # Apply to current user
  system.primaryUser = "matsushimakouta";
  users.users.matsushimakouta = {
    name = "matsushimakouta";
    home = "/Users/matsushimakouta";
  };
}
