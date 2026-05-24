{ ... }:

{
  # Conflict-resolution helpers shipped via stow at ~/.local/bin/. These
  # are referenced from .gitconfig's `[merge "conflict-driver"]` driver.

  home.file.".local/bin/conflict-driver" = {
    source = ../../../common/bin/.local/bin/conflict-driver;
    executable = true;
  };
  home.file.".local/bin/conflict-resolve-file" = {
    source = ../../../common/bin/.local/bin/conflict-resolve-file;
    executable = true;
  };
  home.file.".local/bin/conflict-review" = {
    source = ../../../common/bin/.local/bin/conflict-review;
    executable = true;
  };
  home.file.".local/bin/conflict-save" = {
    source = ../../../common/bin/.local/bin/conflict-save;
    executable = true;
  };
  home.file.".local/bin/rebase-review" = {
    source = ../../../common/bin/.local/bin/rebase-review;
    executable = true;
  };
  home.file.".local/bin/validate-resolved" = {
    source = ../../../common/bin/.local/bin/validate-resolved;
    executable = true;
  };
}
