{ config, lib, pkgs, ... }:

let
  lazygitSettings = {
    git = {
      branchLogCmd = "git log --graph --color=always --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' {{branchName}} --";
      pagers = [
        {
          pager = "delta --dark --paging=never --side-by-side --line-numbers --syntax-theme=\"Visual Studio Dark+\"";
          colorArg = "always";
        }
        {
          pager = "delta --dark --paging=never --line-numbers --syntax-theme=\"Visual Studio Dark+\"";
          colorArg = "always";
        }
      ];
      allBranchesLogCmds = [
        "git log --graph --color=always --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --all"
      ];
    };
    gui = {
      sidePanelWidth = 0.15;
      theme = {
        selectedLineBgColor = [ "underline" ];
        selectedRangeBgColor = [ "underline" ];
        # Note: showIcons/nerdFontsVersion are nested under theme in the
        # original config (which is non-standard but tolerated by lazygit).
        showIcons = true;
        nerdFontsVersion = "3";
      };
    };
    refresher = {
      refreshInterval = 3;
    };
    os = {
      editCommand = "nvim";
      # tmux popup 内で起動されるため OSC52 では host clipboard に届かない。
      # OS 判定 wrapper 経由で pbcopy/lemonade/wl-copy/xclip を直接呼ぶ。
      copyToClipboardCmd = "~/dotfiles/scripts/clipboard-copy";
    };
  };

  yamlFormat = pkgs.formats.yaml { };
in
{
  # programs.lazygit on Darwin writes to ~/Library/Application Support/lazygit,
  # but lazygit itself respects XDG_CONFIG_HOME (set in zsh) and reads from
  # ~/.config/lazygit first. Use xdg.configFile directly to align both.
  home.packages = [ pkgs.lazygit ];

  xdg.configFile."lazygit/config.yml".source =
    yamlFormat.generate "lazygit-config.yml" lazygitSettings;
}
