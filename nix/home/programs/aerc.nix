{ ... }:

{
  # aerc binary installed via nix/modules/packages/core.nix (Phase 1a).
  # Config files are too complex for full attrset translation (187-line binds.conf
  # with section-specific keymaps), so they live as adjacent text files captured
  # via builtins.readFile — content is materialized into the Nix store at build time.

  xdg.configFile."aerc/aerc.conf".text = builtins.readFile ./aerc/aerc.conf;
  xdg.configFile."aerc/binds.conf".text = builtins.readFile ./aerc/binds.conf;
  xdg.configFile."aerc/accounts.conf".text = builtins.readFile ./aerc/accounts.conf;
}
