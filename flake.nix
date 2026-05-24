{
  description = "dotfiles | macOS/Linux development environment (Nix-managed)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Helper to build a home-manager standalone configuration for Linux.
      # Used for both sudo and sudoless Linux paths — they share the same
      # home-manager modules; the difference is how Nix itself is bootstrapped
      # on the host (Determinate vs nix-user-chroot vs nix-portable).
      mkLinuxHome = system: home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        modules = [ ./nix/home/linux.nix ];
      };
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              jq
              nixpkgs-fmt
              statix
              nix-direnv
            ];
            shellHook = ''
              # dotfiles devShell
            '';
          };
        }
      );

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );

      # === macOS (nix-darwin + home-manager) ============================
      darwinConfigurations.shonenm = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./nix/hosts/mac.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "stow-backup";
            home-manager.users.matsushimakouta = import ./nix/home/mac.nix;
          }
        ];
        specialArgs = { inherit nixpkgs; };
      };

      # === Linux (home-manager standalone) ==============================
      # Works for both sudo and sudoless paths — same config; the
      # bootstrap differs (see docs/install/nix-sudoless-bootstrap.md).
      # Activation:
      #   nix run home-manager/master -- switch \
      #     --flake .#matsushimakouta@linux-$ARCH
      homeConfigurations = {
        "matsushimakouta@linux-x86_64" = mkLinuxHome "x86_64-linux";
        "matsushimakouta@linux-aarch64" = mkLinuxHome "aarch64-linux";
      };
    };
}
