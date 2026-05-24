{ ... }:

{
  # Codex CLI config. Runtime state (auth.json, history.jsonl, sessions/,
  # cache/, memories/, etc.) is excluded — those are written by Codex at
  # runtime and live alongside config.toml in ~/.codex/.
  # The .gitignore is stowed so that if someone `git init`s in ~/.codex
  # those runtime files don't get tracked.

  home.file.".codex/config.toml".source =
    ./codex/config.toml;
  home.file.".codex/.gitignore".source =
    ./codex/.gitignore;
}
