{ config, lib, pkgs, ... }:

let
  # Local plugin (lives in this repo). mkTmuxPlugin copies the tree to
  # $out/share/tmux-plugins/tmux-popup-manager and tmux's run-shell sees
  # `popup-manager.tmux` as the rtp file.
  tmuxPopupManager = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-popup-manager";
    version = "local";
    src = ./tmux/plugins/tmux-popup-manager;
    rtpFilePath = "popup-manager.tmux";
  };

  # tmux-which-key needs its custom config.yaml inside its own install dir
  # (the plugin reads from "$(dirname "$0")/config.yaml" at load time).
  # Override the nixpkgs derivation to bundle the user's config.yaml.
  tmuxWhichKeyWithConfig = pkgs.tmuxPlugins.tmux-which-key.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      cp ${../../../common/tmux/.config/tmux/plugins/tmux-which-key/config.yaml} \
         $out/share/tmux-plugins/tmux-which-key/config.yaml
    '';
  });
in
{
  programs.tmux = {
    enable = true;

    # tmux's default behaviour for the package-managed conf is to point at
    # $XDG_CONFIG_HOME/tmux/tmux.conf — keep that. Pass our config via
    # extraConfig (also goes through the same path).
    extraConfig = builtins.readFile ./tmux/tmux.conf;

    plugins = [
      # Plugin extraConfig runs BEFORE the plugin source (HM design),
      # so @resurrect-* / @continuum-* vars are set at the right time.
      {
        plugin = pkgs.tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          # Resurrect long-lived supervisors across reboot. Leading "~" matches
          # the process via extended regex against the full command line.
          # ralph-crew daemon: on resurrect, its own startup hook re-runs
          # _run_init which rebuilds the crew-NN windows/panes against the new
          # pane_ids.
          set -g @resurrect-processes '"~ralph-crew daemon"'
        '';
      }
      {
        plugin = pkgs.tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
        '';
      }
      pkgs.tmuxPlugins.vim-tmux-navigator
      {
        plugin = pkgs.tmuxPlugins.tmux-thumbs;
        extraConfig = ''
          set -g @thumbs-key e
        '';
      }
      tmuxWhichKeyWithConfig
      tmuxPopupManager
      # ataraxy-labs/opensessions: NOT in nixpkgs and writes to its own
      # checkout at runtime — installed via TPM line in tmux.conf instead.
    ];
  };

  # Theme files (referenced by tmux.conf via `source-file ~/.config/tmux/${theme}.tmux`)
  # tmux config dir is also where the scripts live; ship them all here.
  xdg.configFile = {
    "tmux/tokyonight.tmux".source =
      ../../../common/tmux/.config/tmux/tokyonight.tmux;
    "tmux/catppuccin.tmux".source =
      ../../../common/tmux/.config/tmux/catppuccin.tmux;
    "tmux/gruvbox.tmux".source =
      ../../../common/tmux/.config/tmux/gruvbox.tmux;
    "tmux/rosepine.tmux".source =
      ../../../common/tmux/.config/tmux/rosepine.tmux;
    "tmux/syntopic.tmux".source =
      ../../../common/tmux/.config/tmux/syntopic.tmux;
    "tmux/claude-hooks.tmux".source =
      ../../../common/tmux/.config/tmux/claude-hooks.tmux;
  };

  # tmux-layout dev preset (used by tmux-layout script)
  xdg.dataFile."tmux-layout/dev.layout".source =
    ../../../common/tmux/.local/share/tmux-layout/dev.layout;
}
