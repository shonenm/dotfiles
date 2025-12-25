ulimit -S -n 2048

# PATH settings (also needed for non-interactive shells like Claude CLI hooks)
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/dotfiles/scripts" ]] && export PATH="$HOME/dotfiles/scripts:$PATH"

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
