# --- macOS-specific settings ---
if [[ "$OSTYPE" == darwin* ]]; then
  # Homebrew
  [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

  # OrbStack: command-line tools and integration
  source ~/.orbstack/shell/init.zsh 2>/dev/null || :
fi
