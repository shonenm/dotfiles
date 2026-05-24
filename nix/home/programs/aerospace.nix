{ ... }:

{
  # home-manager has no programs.aerospace module (verified against
  # master as of 2026-05-24). aerospace.toml is a single declarative
  # file — ship it via xdg.configFile so changes go through switch.

  xdg.configFile."aerospace/aerospace.toml".source =
    ./aerospace/aerospace.toml;
}
