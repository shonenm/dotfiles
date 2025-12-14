# --- Path & Mise ---
eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(mise activate zsh)"

export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/dotfiles/scripts:$PATH"

# --- Completion Init (最重要: これをプラグインより先に書く) ---
autoload -Uz compinit
compinit

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# deno
export DENO_INSTALL="/Users/USERNAME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"
export PATH=$PATH:$HOME/bin

# mycommand
alias psh='push.sh'
alias ws='ws.sh'
alias mkws='mkws.sh'
alias setde='setDE.sh'
alias addws='addws.sh'
alias tc='code.sh'
alias filepath="create_unsolved_path_files.sh"
alias sortjson="sort_json.sh"
alias collectFiles="collect_files.sh"

# usage
alias zshrc="code ~/.zshrc"
alias cl="clear"
alias mkd="mkdir"
alias c="code"
alias szshrc="source ~/.zshrc"

# vim
alias v="nvim"
alias vimconf="code ~/.config/nvim/init.vim"

# tmux
alias tm="tmux"
alias tmconf="code ~/.config/tmux/.tmux.conf"

# zellij
alias zj="zellij"

# ls (eza)
alias ls="eza --icons --git"
alias ll="eza --icons --git -l"
alias la="eza --icons --git -la"
alias l='ls -CF'

# cd
alias cd='z'
alias ..2='cd ../..'
alias ..3='cd ../../..'
alias ..4='cd ../../../..'
alias ..5='cd ../../../../..'

# よく利用するディレクトリの頭文字の連結
alias R='ws.sh --Research'
alias n='ws.sh --netse'
alias K='cd ~/works/KetchApp; code .'
alias h='cd ~'

# 'd'と言っても人それぞれ
# alias d='cd ~/.dotfiles'
# alias d='cd ~/Desktop'
# alias d='cd ~/Documents/Dropbox'
# alias d='cd ~/Dropbox'

# git
eval "$(gh completion -s zsh)"
alias g='git'
alias ga='git add'
alias gd='git diff'
alias gs='git status'
alias gp='git push'
alias gb='git branch'
alias gsh='git stash'
alias gsp='git stash pop'
alias gco='git checkout'
alias gf='git fetch'
alias gc='git commit'
alias gpl='git pull'
alias grh='git reset --hard HEAD'
alias grs='git reset --soft HEAD^'
alias gpf='git push --force'

# open
alias o='open'

# apt
alias agi='sudo apt install'
alias agr='sudo apt remove'
alias agu='sudo apt update'

# apt-get
alias ag='sudo apt-get'
alias agi='sudo apt-get install'
alias agr='sudo apt-get remove'
alias agu='sudo apt-get update'

[ -f "/Users/USERNAME/.ghcup/env" ] && . "/Users/USERNAME/.ghcup/env" # ghcup-env

# --- Modern Tools ---
eval "$(sheldon source)"
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
eval "$(atuin init zsh)"
. "$HOME/.local/bin/env"

# lazygit
alias lzg='lazygit'

# lazydocker
alias lzd='lazydocker'

# tmux
if command -v tmux >/dev/null 2>&1 && [ -n "$TMUX" ]; then
  tmux source ~/.config/tmux/.tmux.conf
fi

# vpnutil ( for Mac )
alias vpn='vpnutil'
alias vpns='check_vpn_status'
alias vpnc='vpn_connect_with_fzf'
alias vpnd='vpn_disconnect_if_connected'

# vpnutil ( for Mac )
check_vpn_status() {
  # Extract the output of vpnutil list as json.
  vpn_data=$(vpnutil list)

  # Extract connected vpn.
  connected_vpns=$(echo "$vpn_data" | jq -r '.VPNs[] | select(.status == "Connected") | "\(.name) (\(.status))"')

  if [[ -z "$connected_vpns" ]]; then
    echo "No Connected"
  else
    echo "Connected VPN:"
    echo "$connected_vpns"
  fi
}

vpn_connect_with_fzf() {
  # Extract the output of vpnutil list as json.
  vpn_data=$(vpnutil list)

  # Get the name and status of the VPN and select it with fzf.
  selected_vpn=$(echo "$vpn_data" | jq -r '.VPNs[] | "\(.name) (\(.status))"' | fzf --prompt="choose a vpn: ")

  # If there is no selected VPN, exit
  if [[ -z "$selected_vpn" ]]; then
    echo "VPN selection canceled."
    return
  fi

  # Extract the vpn name
  vpn_name=$(echo "$selected_vpn" | sed 's/ (.*)//')

  # Connection place
  echo "connection: $vpn_name"
  vpnutil start "$vpn_name"
}

vpn_disconnect_if_connected() {
  # Extract the output of vpnutil list as json.
  vpn_data=$(vpnutil list)

  # Extract connected VPN
  connected_vpns=$(echo "$vpn_data" | jq -r '.VPNs[] | select(.status == "Connected") | .name')

  if [[ -z "$connected_vpns" ]]; then
    echo "No vpn connected."
  else
    echo "Disconnect the following VPN connections:"
    echo "$connected_vpns"

    # Turn off each connected VPN.
    for vpn in $connected_vpns; do
      echo "cutting: $vpn"
      vpnutil stop "$vpn"
    done
    echo "Disconnected all vpn connections."
  fi
}

export PATH="/opt/homebrew/Cellar/node/23.2.0/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# --- Modern Aliases ---
alias cat="bat"
alias grep="rg"

# --- 1Password CLI ---
if command -v op &>/dev/null; then
  # シークレット取得関数
  op_secret() {
    op read "$1" 2>/dev/null
  }

  # 遅延読み込み（初回使用時にTouch ID）
  export_op_secret() {
    local var_name="$1"
    local op_ref="$2"
    export "$var_name"="$(op read "$op_ref" 2>/dev/null)"
  }

  # API Keys (必要時にコメント解除)
  # export_op_secret "OPENAI_API_KEY" "op://Personal/OpenAI API/credential"
  # export_op_secret "GITHUB_TOKEN" "op://Personal/GitHub Token/credential"
fi

# --- History ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY

# --- Yazi (file manager) ---
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}
