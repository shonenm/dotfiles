{ config, ... }:

{
  programs.gh = {
    enable = true;
    settings = {
      version = "1";
      git_protocol = "https";
      editor = "";
      prompt = "enabled";
      pager = "";
      aliases = {
        co = "pr checkout";
      };
      http_unix_socket = "";
      browser = "";
    };
  };

  # hosts.yml contains the gh auth token (machine-specific, gitignored).
  # Symlink it out of the Nix store so `gh auth login` writes back to the same
  # file across darwin-rebuild generations. Source path will move out of
  # common/gh/ in Phase 6 (deletion of legacy stow tree).
  home.file.".config/gh/hosts.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/gh/.config/gh/hosts.yml";
}
