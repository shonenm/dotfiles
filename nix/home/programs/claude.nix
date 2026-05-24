{ ... }:

{
  # Claude Code harness static config. Runtime state (projects/, sessions/,
  # cache/, file-history/, plugins/, etc.) is excluded — those are written
  # by Claude Code at runtime and coexist in ~/.claude/.

  home.file.".claude/.gitignore".source =
    ../../../common/claude/.claude/.gitignore;
  home.file.".claude/news-profile.example.yaml".source =
    ../../../common/claude/.claude/news-profile.example.yaml;
  home.file.".claude/statusline-command.sh" = {
    source = ../../../common/claude/.claude/statusline-command.sh;
    executable = true;
  };

  home.file.".claude/agents" = {
    source = ../../../common/claude/.claude/agents;
    recursive = true;
  };
  home.file.".claude/hooks" = {
    source = ../../../common/claude/.claude/hooks;
    recursive = true;
  };
  home.file.".claude/rules" = {
    source = ../../../common/claude/.claude/rules;
    recursive = true;
  };
  home.file.".claude/skills" = {
    source = ../../../common/claude/.claude/skills;
    recursive = true;
  };
}
