ulimit -S -n 2048

# PATH settings (also needed for non-interactive shells like Claude CLI hooks
# and tmux popups launched via `zsh -lc`, which do not source .zshrc)
# .pixi/bin holds pixi-installed CLIs (gh など)。.local/bin より後ろに置く
# ことで source-built tmux 等が pixi 版より優先される (.zshrc.common と同順序)。
[[ -d "$HOME/.pixi/bin" ]] && export PATH="$HOME/.pixi/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/dotfiles/scripts" ]] && export PATH="$HOME/dotfiles/scripts:$PATH"

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# zsh-abbr
export ABBR_USER_ABBREVIATIONS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-abbr/user-abbreviations"
