# --- macOS-specific settings ---
if [[ "$OSTYPE" == darwin* ]]; then
  # Setting PATH for Python 3.11
  PATH="/Library/Frameworks/Python.framework/Versions/3.11/bin:${PATH}"
  export PATH

  # Homebrew
  [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

  # OrbStack: command-line tools and integration
  source ~/.orbstack/shell/init.zsh 2>/dev/null || :
fi
