{ ... }:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = false; # zsh.nix sources starship manually

    # The original starship.toml relies on Powerline / Nerd Font codepoints
    # (U+E0B0 …) that are easy to lose when retyping into a Nix string.
    # Parse the TOML file directly so the bytes flow through unchanged.
    settings = builtins.fromTOML (
      builtins.readFile ../../../common/starship/.config/starship.toml
    );
  };
}
