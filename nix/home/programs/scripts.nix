{ lib, ... }:

let
  scriptsDir = ../../../scripts;

  # Only top-level regular files (skip the git-hooks/ subdir — that
  # template directory is wired up via programs.git's runCommand).
  entries = builtins.readDir scriptsDir;
  scriptFiles = lib.filter
    (name: entries.${name} == "regular")
    (builtins.attrNames entries);
in
{
  # All scripts in dotfiles/scripts/ → ~/.local/bin/<name>.
  # This replaces the legacy `export PATH="$HOME/dotfiles/scripts:$PATH"`
  # line in .zshrc.common (removed from zsh.nix in the same PR).
  # ~/.local/bin is already prepended in .zshenv, so no PATH work needed.
  #
  # Lib scripts (*-lib.sh, etc.) are NOT executable but still co-located
  # with their consumers under ~/.local/bin so the conventional
  # `source "$(dirname "$0")/foo-lib.sh"` pattern keeps resolving.
  home.file = builtins.listToAttrs (map
    (name: {
      name = ".local/bin/${name}";
      value = {
        source = scriptsDir + "/${name}";
        executable = true;
      };
    })
    scriptFiles);
}
