{ ... }:

{
  # Ghostty is the active terminal — its config controls font, theme,
  # background image, keybindings, and shell integration features. The
  # backgrounds/ directory holds a JPEG referenced by background-image.
  # themes/ holds custom theme definitions referenced by `theme = ...`.

  xdg.configFile."ghostty/config".source =
    ./ghostty/config;

  xdg.configFile."ghostty/backgrounds" = {
    source = ./ghostty/backgrounds;
    recursive = true;
  };

  xdg.configFile."ghostty/themes" = {
    source = ./ghostty/themes;
    recursive = true;
  };
}
