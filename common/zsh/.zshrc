# Load common settings
[[ -f "$HOME/.zshrc.common" ]] && source "$HOME/.zshrc.common"

# Load OS-specific settings
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

command -v fzf &>/dev/null && source <(fzf --zsh)
