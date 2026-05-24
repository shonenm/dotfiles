{ config, lib, pkgs, ... }:

{
  # LazyVim setup: lazy.nvim writes to lazy-lock.json at runtime when
  # plugins are added/updated/removed. If the tree lives in /nix/store
  # (read-only) lazy.nvim fails with E5113: Read-only file system.
  #
  # The community convergent pattern (NixOS Discourse #35109, LazyVim
  # discussion #1972) is to mkOutOfStoreSymlink the whole .config/nvim,
  # keeping lazy.nvim's existing workflow (`:Lazy update`, git-add the
  # lockfile yourself).
  #
  # IMPORTANT: must use an absolute path via config.home.homeDirectory.
  # Relative paths (`./nvim`) resolve inside the store copy of the flake
  # and silently link into /nix/store — folke filed this as HM#2085.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/nvim/.config/nvim";
}
