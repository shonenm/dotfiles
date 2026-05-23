{ ... }:

{
  # zsh-abbr is loaded as a zsh plugin (see nix/home/programs/zsh.nix).
  # This module just publishes the user-abbreviations file at
  # ABBR_USER_ABBREVIATIONS_FILE = ~/.config/zsh-abbr/user-abbreviations.

  xdg.configFile."zsh-abbr/user-abbreviations".text =
    builtins.readFile ../../../common/zsh-abbr/.config/zsh-abbr/user-abbreviations;
}
