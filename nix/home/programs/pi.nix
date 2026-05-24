{ ... }:

{
  # pi-coding-agent harness static config. Runtime state (sessions/, cache/,
  # packages/, logs/, history/, telemetry/, credentials.json) is excluded —
  # written by pi at runtime in ~/.pi/.
  # services/ (docker-compose for SearXNG etc.) intentionally stays in the
  # repo at common/pi/services/; it's not stowed/home-managed anywhere.

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

  home.file.".pi/agent/extensions" = {
    source = ../../../common/pi/.pi/agent/extensions;
    recursive = true;
  };
  home.file.".pi/agent/prompts" = {
    source = ../../../common/pi/.pi/agent/prompts;
    recursive = true;
  };
  home.file.".pi/agent/skills" = {
    source = ../../../common/pi/.pi/agent/skills;
    recursive = true;
  };
}
