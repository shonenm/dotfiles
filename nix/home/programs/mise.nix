{ ... }:

{
  programs.mise = {
    enable = true;
    globalConfig = {
      tools = {
        node = "lts";
        python = "latest";
        pnpm = "latest";
        deno = "latest";
        "npm:cspell" = "latest";
        go = "latest";
        cloudflared = "latest";
      };

      tasks = {
        update = {
          description = "Update all package managers and tools";
          run = ''
            # Nix-side update
            if command -v darwin-rebuild >/dev/null 2>&1; then
              nix flake update --flake ~/dotfiles
              sudo darwin-rebuild switch --flake ~/dotfiles
            elif command -v home-manager >/dev/null 2>&1; then
              nix flake update --flake ~/dotfiles
              home-manager switch --flake ~/dotfiles
            fi
            # Homebrew casks (mac UI apps not in nix-darwin)
            command -v brew >/dev/null 2>&1 && brew update && brew upgrade
            command -v tldr >/dev/null 2>&1 && tldr --update
          '';
        };

        doctor = {
          description = "Check dotfiles health";
          run = ''
            echo "==> Checking required tools..."
            for cmd in zsh tmux nvim starship atuin zoxide fzf fd rg bat eza ghq mise; do
              if command -v "$cmd" >/dev/null 2>&1; then
                printf "  ✓ %s (%s)\n" "$cmd" "$(command -v "$cmd")"
              else
                printf "  ✗ %s NOT FOUND\n" "$cmd"
              fi
            done
            echo ""
            echo "==> Active home-manager generation..."
            if command -v home-manager >/dev/null 2>&1; then
              home-manager generations 2>/dev/null | head -1
            else
              echo "  (managed by nix-darwin module — no standalone home-manager CLI)"
            fi
          '';
        };

        lint = {
          description = "Lint shell scripts with shellcheck";
          run = "shellcheck ~/dotfiles/scripts/*.sh";
        };
      };
    };
  };
}
