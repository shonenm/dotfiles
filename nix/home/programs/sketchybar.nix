{ ... }:

{
  # sketchybar status bar config (sketchybarrc + plugins/*.sh).
  # Recursive xdg.configFile preserves the directory tree; executable
  # permission is inferred from source file perms (the plugin scripts
  # are chmod +x in the repo).

  xdg.configFile."sketchybar" = {
    source = ./sketchybar;
    recursive = true;
  };
}
