ulimit -S -n 2048

# PATH settings (also needed for non-interactive shells like Claude CLI hooks)
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/dotfiles/scripts" ]] && export PATH="$HOME/dotfiles/scripts:$PATH"

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# zsh-abbr
export ABBR_USER_ABBREVIATIONS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-abbr/user-abbreviations"
