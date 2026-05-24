{ ... }:

{
  # opensessions tmux plugin desktop config (separate from the TPM-installed
  # plugin itself, which lives under ~/.tmux/plugins/opensessions).

  xdg.configFile."opensessions/config.json".source =
    ../../../common/opensessions/.config/opensessions/config.json;
}
