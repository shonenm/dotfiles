# Load common settings
[[ -f "$HOME/.zshrc.common" ]] && source "$HOME/.zshrc.common"

# Load OS-specific settings
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# --- Completion Init (cached: full rebuild once per 24h) ---
# 全 fpath 追加 (.zshrc.common の ~/.zsh/completions, sheldon の zsh-completions) の
# 後に 1 回だけ実行する。compinit 後の fpath 追加は補完登録されない。
# (#qN.mh+24) glob 修飾子は extended_glob 必須のため無名関数内で局所有効化する
# (無効だと条件が常に真になり、毎起動フル compinit + compaudit が走る)。
if [[ -o interactive ]]; then
  autoload -Uz compinit
  () {
    setopt local_options extended_glob
    local dump="${ZDOTDIR:-$HOME}/.zcompdump"
    local -a stale
    stale=( $dump(#qN.mh+24) )
    if [[ ! -f "$dump" || -n "$stale" ]]; then
      compinit
    else
      compinit -C
    fi
  }
fi

command -v fzf &>/dev/null && source <(fzf --zsh)
