{ config, ... }:

{
  # pi-coding-agent harness. Runtime state (sessions/, cache/, packages/,
  # logs/, history/, telemetry/, credentials.json) is excluded — written
  # by pi at runtime in ~/.pi/.
  # services/ (docker-compose for SearXNG etc.) intentionally stays in
  # the repo at common/pi/services/; it's not stowed/home-managed anywhere.

  # === Static config (store-managed, atomic switch) ===
  home.file.".pi/.gitignore".source =
    ../../../common/pi/.pi/.gitignore;
  home.file.".pi/agent/AGENTS.md".source =
    ../../../common/pi/.pi/agent/AGENTS.md;
  home.file.".pi/agent/APPEND_SYSTEM.md".source =
    ../../../common/pi/.pi/agent/APPEND_SYSTEM.md;
  home.file.".pi/agent/keybindings.json".source =
    ../../../common/pi/.pi/agent/keybindings.json;
  home.file.".pi/agent/settings.json".source =
    ../../../common/pi/.pi/agent/settings.json;

  # === Hot-loop dirs (mkOutOfStoreSymlink → dotfiles repo) ===
  # These are edited frequently and consumed via pi's /reload (which
  # re-reads from the symlink target). Store-copying them would force
  # darwin-rebuild switch per edit. mkOutOfStoreSymlink points the
  # symlink at the dotfiles checkout instead so /reload picks up changes
  # immediately. Trade-off: no atomic rollback for these dirs (git
  # handles versioning), no remote --target-host deploy of these
  # specific files. Same pattern as nvim (Phase 2c) and gh/hosts.yml
  # (Phase 2a). HM #2085: must use absolute path.
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/pi/.pi/agent/extensions";
  home.file.".pi/agent/prompts".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/pi/.pi/agent/prompts";
  home.file.".pi/agent/skills".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/pi/.pi/agent/skills";
}
