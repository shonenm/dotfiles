{ ... }:

{
  # atuin shell history sync. Binary installed via core.nix (Phase 1a).
  # History database lives at ~/.local/share/atuin (mutable, untouched).

  xdg.configFile."atuin/config.toml".source =
    ./atuin/config.toml;
}
