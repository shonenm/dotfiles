{ config, ... }:

{
  # Claude Code harness. Runtime state (projects/, sessions/, cache/,
  # file-history/, plugins/, etc.) is excluded — those are written by
  # Claude Code at runtime and coexist in ~/.claude/.

  # === Static config (store-managed, atomic switch) ===
  home.file.".claude/.gitignore".source =
    ../../../common/claude/.claude/.gitignore;
  home.file.".claude/news-profile.example.yaml".source =
    ../../../common/claude/.claude/news-profile.example.yaml;
  home.file.".claude/statusline-command.sh" = {
    source = ../../../common/claude/.claude/statusline-command.sh;
    executable = true;
  };
  # agents/ houses long-lived subagents (ralph-worker / ralph-reviewer)
  # that don't change often — keep them in /nix/store for atomic switch.
  home.file.".claude/agents" = {
    source = ../../../common/claude/.claude/agents;
    recursive = true;
  };

  # === Hot-loop dirs (mkOutOfStoreSymlink → dotfiles repo) ===
  # hooks / rules / skills are actively iterated (shell hook tweaks, rule
  # adjustments, d-* skill development). Store-copying them would force
  # darwin-rebuild switch per edit. Same pattern as nvim (Phase 2c) and
  # gh/hosts.yml (Phase 2a). HM #2085: must use absolute path.
  home.file.".claude/hooks".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/claude/.claude/hooks";
  home.file.".claude/rules".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/claude/.claude/rules";
  home.file.".claude/skills".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/dotfiles/common/claude/.claude/skills";
}
