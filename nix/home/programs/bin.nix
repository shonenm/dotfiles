{ ... }:

{
  # Conflict-resolution helpers shipped via stow at ~/.local/bin/. These
  # are referenced from .gitconfig's `[merge "conflict-driver"]` driver.

  home.file.".local/bin/conflict-driver" = {
    source = ./bin/conflict-driver;
    executable = true;
  };
  home.file.".local/bin/conflict-resolve-file" = {
    source = ./bin/conflict-resolve-file;
    executable = true;
  };
  home.file.".local/bin/conflict-review" = {
    source = ./bin/conflict-review;
    executable = true;
  };
  home.file.".local/bin/conflict-save" = {
    source = ./bin/conflict-save;
    executable = true;
  };
  home.file.".local/bin/rebase-review" = {
    source = ./bin/rebase-review;
    executable = true;
  };
  home.file.".local/bin/validate-resolved" = {
    source = ./bin/validate-resolved;
    executable = true;
  };
}
