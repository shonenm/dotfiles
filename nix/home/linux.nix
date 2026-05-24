{ config, pkgs, lib, ... }:

{
  # Linux home-manager entry. Common cross-platform programs + Linux
  # user-level packages. Same configuration works for:
  #   - sudo Linux hosts (ailab, full dev workstations): Nix installed
  #     system-wide via Determinate; `home-manager switch --flake .#matsushimakouta@linux`
  #     runs at user level identically to mac.
  #   - sudoless Linux hosts (rcon containers, pi-500, locked-down):
  #     Nix bootstrapped via nix-user-chroot (user namespaces) or
  #     nix-portable (proot fallback) — same home-manager config applies.
  #     See docs/install/nix-sudoless-bootstrap.md.

  imports = [
    ./common.nix
    ../modules/packages/linux.nix
  ];

  # home.username + home.homeDirectory provided by mkLinuxHome in flake.nix
  # so per-host accounts (matsushimakouta on ailab, shonenm on pi-500, …)
  # all reuse this module.
}
