{ config, lib, pkgs, ... }:

let
  # .p10k.zsh is large (1738 lines); ship as-is via readFile so the p10k
  # configure wizard's output is preserved verbatim.
  p10kConfig = builtins.readFile ../../../common/zsh/.p10k.zsh;
in
{
  programs.zsh = {
    enable = true;

    # HM disables its built-in compinit when oh-my-zsh/prezto isn't enabled;
    # we call compinit explicitly in initContent for the 24h-cached pattern.
    enableCompletion = false;
    autosuggestion.enable = false;     # provided manually via zsh-defer
    syntaxHighlighting.enable = false; # provided manually with mkOrder 5000 (HM #7592)

    history = {
      size = 50000;
      save = 50000;
      share = true;
      path = "${config.home.homeDirectory}/.zsh_history";
    };

    sessionVariables = {
      XDG_CONFIG_HOME = "${config.home.homeDirectory}/.config";

      FZF_DEFAULT_COMMAND = "fd --type f --hidden --exclude .git";
      FZF_CTRL_T_COMMAND = "fd --type f --hidden --exclude .git";
      FZF_ALT_C_COMMAND = "fd --type d --hidden --exclude .git";

      # forgit: rename conflicting alias (gsp is zsh-abbr 'git stash pop')
      forgit_stash_push = "gspu";

      # zsh-abbr
      ABBR_USER_ABBREVIATIONS_FILE = "${config.home.homeDirectory}/.config/zsh-abbr/user-abbreviations";

      DENO_INSTALL = "${config.home.homeDirectory}/.deno";
    };

    # envExtra goes into ~/.zshenv — runs for ALL shells (login + non-login).
    # Re-prepend nix-managed paths so Nix-installed binaries win over
    # /opt/homebrew/bin regardless of how the shell is launched.
    envExtra = ''
      for p in \
        "$HOME/.nix-profile/bin" \
        "/etc/profiles/per-user/$USER/bin" \
        "/run/current-system/sw/bin" \
        "/nix/var/nix/profiles/default/bin"
      do
        [[ -d "$p" ]] && export PATH="$p:$PATH"
      done

      # Env vars whose value embeds double quotes — declaring via
      # sessionVariables would produce `export VAR="..."` with broken inner
      # quoting. Use single-quoted heredocs here instead.
      export FZF_DEFAULT_OPTS='
        --height=80%
        --layout=reverse
        --border=rounded
        --info=inline
        --color=fg:#c0caf5,bg:-1,hl:#bb9af7
        --color=fg+:#c0caf5,bg+:#283457,hl+:#7dcfff
        --color=info:#7aa2f7,prompt:#7dcfff,pointer:#7dcfff
        --color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a
        --bind="ctrl-d:half-page-down,ctrl-u:half-page-up"
      '

      export FORGIT_STASH_FZF_OPTS='
        --bind="alt-p:reload(git stash pop $(cut -d: -f1 <<<{}) 1>/dev/null && git stash list)"
        --bind="alt-a:reload(git stash apply $(cut -d: -f1 <<<{}) 1>/dev/null && git stash list)"
        --bind="alt-d:reload(git stash drop $(cut -d: -f1 <<<{}) 1>/dev/null && git stash list)"
        --header="enter:show | alt-p:pop | alt-a:apply | alt-d:drop | ctrl-y:copy ref"
      '
    '';

    # PATH fix moved from profileExtra (login-shells only) to envExtra below
    # so non-login interactive shells (Ghostty default) also get it.

    # zsh-completions is consumed via fpath (its completion files land in
    # share/zsh/site-functions of the user profile, which is already in
    # FPATH). Install it as a regular home package instead of a plugin.

    plugins = [
      # zsh-defer first so subsequent plugins can be deferred from initContent
      {
        name = "zsh-defer";
        src = pkgs.zsh-defer;
        file = "share/zsh-defer/zsh-defer.plugin.zsh";
      }
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh";
      }
      {
        name = "zsh-abbr";
        src = pkgs.zsh-abbr;
        file = "share/zsh/zsh-abbr/zsh-abbr.plugin.zsh";
      }
      {
        name = "forgit";
        src = pkgs.zsh-forgit;
        file = "share/zsh/zsh-forgit/forgit.plugin.zsh";
      }
    ];

    shellAliases = {
      l = "ls -CF";
    };

    initContent = lib.mkMerge [
      # === Pre-init: p10k instant prompt MUST be at very top ===
      (lib.mkOrder 550 ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')

      # === p10k config (sourced after plugins, but functions are immediate) ===
      (lib.mkOrder 1000 ''
        # Powerlevel10k config (1738-line file inlined via readFile)
        ${p10kConfig}
      '')

      # === Default-priority content (1000): main .zshrc.common body ===
      ''
        # --- Shell ---
        [[ "$SHELL" != */zsh ]] && export SHELL=$(which zsh)

        # --- Terminal Detection (SSH) ---
        if [[ -n "$SSH_CONNECTION" && -z "$TERM_PROGRAM" && "$TERM" == *ghostty* ]]; then
          export TERM_PROGRAM=ghostty
        fi

        # --- Path (user-managed, non-Nix) ---
        [[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
        [[ -d "$HOME/.pixi/bin" ]] && export PATH="$HOME/.pixi/bin:$PATH"
        [[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"
        [[ -d "$HOME/.atuin/bin" ]] && export PATH="$HOME/.atuin/bin:$PATH"
        [[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
        # dotfiles/scripts/ PATH line removed in Phase 2d: all scripts are
        # now symlinked into ~/.local/bin via programs/scripts.nix and
        # ~/.local/bin is already prepended above.
        [[ -d "$DENO_INSTALL/bin" ]] && export PATH="$DENO_INSTALL/bin:$PATH"
        [[ -x "$HOME/syntopic/tools/packages/syntopic/bin/syntopic" ]] && \
          export PATH="$HOME/syntopic/tools/packages/syntopic/bin:$PATH"
        [[ -d "$HOME/bin" ]] && export PATH="$PATH:$HOME/bin"

        # --- 1Password Secrets (non-interactive, graceful) ---
        if command -v op &>/dev/null && op whoami &>/dev/null 2>&1; then
          export JINA_API_KEY="$(op read "op://Personal/Jina AI/credential" 2>/dev/null)"
        fi

        # --- Interactive-only ---
        [[ -o interactive ]] || return

        # --- Tool integrations ---
        command -v mise &>/dev/null && eval "$(mise activate zsh)"
        command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

        # --- Completion ---
        autoload -Uz compinit
        if [[ -n ''${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
          compinit
        else
          compinit -C
        fi

        # --- Conditional command aliases ---
        if command -v lsd &>/dev/null; then
          alias ls="lsd"
          alias ll="lsd -l"
          alias la="lsd -la"
        elif command -v eza &>/dev/null; then
          alias ls="eza --icons --git"
          alias ll="eza --icons --git -l"
          alias la="eza --icons --git -la"
        fi

        command -v rg &>/dev/null && alias grep="rg"
        command -v fd &>/dev/null && alias find="fd"
        command -v tldr &>/dev/null && alias man="tldr"
        command -v sd &>/dev/null && alias sed="sd"
        command -v dust &>/dev/null && alias du="dust"
        command -v btm &>/dev/null && alias top="btm"
        command -v rip &>/dev/null && alias rm="rip"
        command -v viddy &>/dev/null && alias watch="viddy"
        command -v doggo &>/dev/null && alias dig="doggo"
        command -v xh &>/dev/null && alias http="xh"

        # --- Global aliases (pipe modifiers) ---
        alias -g L='| bat'
        alias -g G='| rg'
        alias -g C='| pbcopy'
        alias -g H='| head'
        alias -g T='| tail'

        # --- Suffix aliases (open by extension) ---
        alias -s {md,txt,yaml,yml,toml,json}=nvim
        alias -s py=python
        alias -s {png,jpg,jpeg,gif,webp}=open

        # --- Modern tools (custom completions, starship, zoxide) ---
        [[ -d "$HOME/.zsh/completions" ]] && fpath=("$HOME/.zsh/completions" $fpath)
        command -v starship &>/dev/null && eval "$(starship init zsh)"
        command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"

        # --- Auto ls on cd ---
        chpwd() {
          ls
        }

        # --- 1Password CLI helpers ---
        if command -v op &>/dev/null; then
          op_secret() {
            op read "$1" 2>/dev/null
          }

          export_op_secret() {
            local var_name="$1"
            local op_ref="$2"
            export "$var_name"="$(op read "$op_ref" 2>/dev/null)"
          }

          setup_git_from_op() {
            local name email
            name=$(op read "op://Personal/Git Config/name") || { echo "Failed to read name"; return 1; }
            email=$(op read "op://Personal/Git Config/email") || { echo "Failed to read email"; return 1; }
            cat > ~/.gitconfig.local << GITCFG
        [user]
            name = $name
            email = $email
        GITCFG
            echo "Git config updated: $name <$email>"
          }
        fi

        # --- Zsh options ---
        setopt CORRECT
        setopt AUTO_CD
        setopt NO_FLOW_CONTROL

        # --- Yazi (file manager) ---
        y() {
          local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
          yazi "$@" --cwd-file="$tmp"
          if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
            builtin cd -- "$cwd"
          fi
          rm -f -- "$tmp"
        }

        # --- ghq + fzf repo picker ---
        if command -v ghq &>/dev/null && command -v fzf &>/dev/null; then
          repo() {
            local selected
            selected=$(ghq list | fzf --query="''${1:-}" \
              --preview "bat --style=plain --color=always $(ghq root)/{}/README.md 2>/dev/null || eza --icons -la $(ghq root)/{} 2>/dev/null || ls -la $(ghq root)/{}" \
              --preview-window=right:50%:wrap \
              --prompt="repo> " \
              --height=80%)
            if [[ -n "$selected" ]]; then
              cd "$(ghq root)/$selected"
            fi
          }
        fi

        # --- sesh widget (Alt-s) ---
        if command -v sesh &>/dev/null && command -v fzf &>/dev/null; then
          sesh-sessions() {
            local session
            session=$(sesh list -i | fzf --height 40% --reverse \
              --border-label ' sesh ' --border --prompt '⚡  ' --ansi < /dev/tty)
            if [[ -n "$session" ]]; then
              BUFFER="sesh connect \"$session\""
              zle accept-line
            else
              zle reset-prompt 2>/dev/null
            fi
          }
          zle -N sesh-sessions
          bindkey '\es' sesh-sessions
        fi

        # --- Claude wrapper ---
        _claude_should_auto_name() {
          case "''${1:-}" in
            agents|auth|auto-mode|doctor|install|mcp|plugin|plugins|setup-token|update|upgrade)
              return 1
              ;;
          esac
          local arg
          for arg in "$@"; do
            case "$arg" in
              -n|--name|--name=*|-r|--resume|--resume=*|--continue) return 1 ;;
            esac
          done
          return 0
        }

        claude() {
          printf '\033[?2004l'
          local rc
          local -a name_args=()
          if _claude_should_auto_name "$@"; then
            local auto_name
            auto_name="$(git -C "$PWD" branch --show-current 2>/dev/null)"
            [[ -z "$auto_name" ]] && auto_name="$(basename "$PWD")"
            [[ -n "$auto_name" ]] && name_args=(--name "$auto_name")
          fi
          if [[ -f "$HOME/.local/share/claude-fallback/active" ]]; then
            local fallback_env="$HOME/.local/share/claude-fallback/env"
            source "$fallback_env"
            ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
            ANTHROPIC_API_KEY="$OPENROUTER_API_KEY" \
            command claude "''${name_args[@]}" "$@"
          else
            command claude "''${name_args[@]}" "$@"
          fi
          rc=$?
          printf '\033[?2004h'
          return $rc
        }

        # --- Local bin env (cargo etc.) ---
        [[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

        # --- Claude context helpers (dexec/rssh/rcon/dotsync) ---
        _claude_context() {
          local project="''${CLAUDE_PROJECT:-$(basename "$PWD")}"
          local device="$(hostname -s)"
          local workspace="" tmux_session="" tmux_window=""
          if [[ -n "$TMUX" ]]; then
            tmux_session=$(tmux display-message -p '#S' 2>/dev/null)
            tmux_window=$(tmux display-message -p '#I' 2>/dev/null)
          fi
          local map_file="''${HOME}/.local/share/claude/workspace_map.json"
          if [[ -f "$map_file" ]]; then
            local env_key
            env_key=$(git rev-parse --show-toplevel 2>/dev/null)
            [[ -z "$env_key" ]] && env_key="$PWD"
            workspace=$(jq -r --arg key "$env_key" '.[$key].workspace // ""' "$map_file" 2>/dev/null)
          fi
          echo "{\"project\":\"$project\",\"device\":\"$device\",\"workspace\":\"$workspace\",\"tmux_session\":\"$tmux_session\",\"tmux_window\":\"$tmux_window\"}"
        }

        dexec() {
          local container="$1"
          [[ -z "$container" ]] && { echo "Usage: dexec <container> [command...]" >&2; return 1; }
          shift
          local context="''${CLAUDE_CONTEXT:-$(_claude_context)}"
          docker exec -it -e TERM="$TERM" -e COLORTERM="$COLORTERM" -e CLAUDE_CONTEXT="$context" "$container" "''${@:-bash}"
        }

        rssh() {
          local context="$(_claude_context)"
          local args=()
          local host=""
          local cmd_start=-1
          local i=1
          for arg in "$@"; do
            if [[ -z "$host" ]]; then
              if [[ "$arg" == -* ]]; then
                args+=("$arg")
                if [[ "$arg" =~ ^-[pioJLRDWFl]$ ]]; then
                  :
                fi
              elif [[ "''${args[-1]:-}" =~ ^-[pioJLRDWFl]$ ]]; then
                args+=("$arg")
              else
                host="$arg"
                args+=("$arg")
                cmd_start=$((i + 1))
              fi
            fi
            ((i++))
          done
          if [[ -z "$host" ]]; then
            echo "Usage: rssh [ssh-options] <host> [command]" >&2
            return 1
          fi
          local cmd=""
          if [[ $cmd_start -le $# ]]; then
            cmd="''${@:$cmd_start}"
          fi
          if [[ -n "$cmd" ]]; then
            ssh "''${args[@]}" "export CLAUDE_CONTEXT='$context' && $cmd"
          else
            ssh -t "''${args[@]}" "export CLAUDE_CONTEXT='$context' && exec \$SHELL -l"
          fi
        }

        rcon() {
          local target="$1" session="$2"
          if [[ -z "$target" ]]; then
            local config_file="''${XDG_CONFIG_HOME:-$HOME/.config}/rcon/targets"
            [[ ! -f "$config_file" ]] && { echo "rcon: config not found: $config_file" >&2; return 1; }
            target=$(command grep -v '^\s*#' "$config_file" | command grep -v '^\s*$' | fzf --prompt="rcon> ")
            [[ -z "$target" ]] && return 1
          fi
          local host container
          if [[ "$target" == *:* ]]; then
            host="''${target%%:*}"
            container="''${target#*:}"
          else
            host="$target"
          fi
          local context="''${CLAUDE_CONTEXT:-$(_claude_context)}"
          if [[ -n "$container" ]]; then
            local sess="''${session:-$container}"
            sess="''${sess//:/-}"
            sess="''${sess//./-}"
            ssh -t "$host" "
              set -e
              export PATH=\"\$HOME/.local/bin:\$PATH\"
              export TERMINFO_DIRS=\"\$HOME/.terminfo:/usr/share/terminfo:/lib/terminfo\"
              export CLAUDE_CONTEXT='$context'
              export RCON_HOST_MACHINE='$host'
              export RCON_CONTAINER='$container'
              export RCON_HOST_HOME=\"\$HOME\"
              cmd=\"\$HOME/dotfiles/scripts/tmux-docker-enter '$container'\"
              container_wd=\$(docker inspect '$container' --format '{{.Config.WorkingDir}}' 2>/dev/null)
              [ -z \"\$container_wd\" ] && container_wd=\"/\"
              existing_path=\$(tmux list-sessions -F '#{session_path}' -f \"#{==:#{session_name},$sess}\" 2>/dev/null | head -1 || true)
              if [ -n \"\$existing_path\" ] && [ \"\$existing_path\" != \"\$container_wd\" ]; then
                echo \"rcon: recreating session '$sess' (session_path was '\$existing_path', should be '\$container_wd')\" >&2
                tmux kill-session -t '$sess' 2>/dev/null || true
              fi
              tmux new-session -A -d -s '$sess' -c \"\$container_wd\" \"\$cmd\" 2>/dev/null || true
              tmux set-option -t '$sess' default-command \"\$cmd\"
              tmux set-option -t '$sess' '@rcon-host' '$host'
              tmux set-option -t '$sess' '@rcon-container' '$container'
              tmux set-option -t '$sess' '@rcon-container-home' \"\$container_wd\"
              exec tmux attach-session -t '$sess'
            "
          else
            local sess="''${session:-main}"
            ssh -t "$host" "
              export PATH=\"\$HOME/.local/bin:\$HOME/.pixi/bin:\$PATH\"
              export TERMINFO_DIRS=\"\$HOME/.terminfo:/usr/share/terminfo:/lib/terminfo\"
              export CLAUDE_CONTEXT='$context'
              export RCON_HOST_MACHINE='$host'
              zsh_bin=\$(command -v zsh 2>/dev/null) && export SHELL=\"\$zsh_bin\"
              cwd=\"\$HOME\"
              [ -d \"\$HOME/$sess\" ] && cwd=\"\$HOME/$sess\"
              tmux new-session -A -d -s '$sess' -c \"\$cwd\" 2>/dev/null || true
              tmux set-option -t '$sess' '@rcon-host' '$host'
              exec tmux attach-session -t '$sess'
            "
          fi
        }

        dotsync() {
          local skip_pull=false
          [[ "$1" == "--no-pull" ]] && skip_pull=true
          local repo_dir="''${DOTFILES_DIR:-$HOME/dotfiles}"
          ( cd "$repo_dir" && git push ) || { echo "dotsync: push failed" >&2; return 1; }
          if [[ "$skip_pull" == "false" ]]; then
            ssh -o ConnectTimeout=5 ailab 'cd ~/dotfiles && git pull --ff-only' \
              || { echo "dotsync: ailab pull failed (push succeeded)" >&2; return 1; }
          fi
        }

        # --- Container pane cwd tracking ---
        if [[ -f /.dockerenv ]] && [[ -n "''${TMUX_PANE:-}" ]] && [[ -d /tmp/tmux-pane-state ]]; then
          _tmux_track_container_cwd() {
            local num="''${TMUX_PANE#%}"
            print -r -- "$PWD" > "/tmp/tmux-pane-state/cwd-''${num}" 2>/dev/null
          }
          typeset -ga chpwd_functions
          chpwd_functions+=(_tmux_track_container_cwd)
          _tmux_track_container_cwd
        fi

        # --- fzf zsh integration ---
        command -v fzf &>/dev/null && source <(fzf --zsh)

        # --- zsh-syntax-highlighting: initialize highlighters list ---
        # .zshrc.local appends 'regexp' (for zsh-abbr coloring) without
        # initializing the array, which would otherwise leave only regexp
        # active and disable the default 'main' highlighter.
        typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS
        ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

        # Explicit style for aliases so the highlighter doesn't fall through
        # to unknown-token (red) when the alias's TARGET binary is checked
        # but the highlighter can't classify the alias itself.
        typeset -gA ZSH_HIGHLIGHT_STYLES
        ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan,bold'

        # zsh-autosuggestions: default fg=8 (dark gray) is nearly invisible
        # on the Dark mode terminal. Bump to fg=240 for visible contrast
        # while still clearly secondary to typed input.
        export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=240'

        # --- OS-specific zshrc.local (mac/linux divergence stays in stow tree) ---
        [[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

        # --- zsh-abbr reload after .zshrc.local (which calls 'abbr import') ---
        # Handled by .zshrc.local itself for now.
      ''

      # === Late: zsh-syntax-highlighting MUST load after everything else ===
      # HM #7592 workaround: don't use programs.zsh.syntaxHighlighting.enable
      # (no order guarantee). Source manually with mkOrder 5000.
      (lib.mkOrder 5000 ''
        source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

        # === Rebuild abbr regexp highlighter ============================
        # .zshrc.local builds a regex from $ABBR_REGULAR_USER_ABBREVIATIONS
        # to render abbreviations (gp, gpl, gs, …) green before space-
        # expansion, but its `ZSH_HIGHLIGHT_REGEXP+=(...)` runs while the
        # array isn't yet declared as an associative-friendly array (and
        # uses a stray top-level `local`), so the entry never actually
        # lands. Rebuild it here, after zsh-syntax-highlighting is loaded
        # (and after .zshrc.local has populated the abbr array), so the
        # pattern is in place at first prompt.
        if (( ''${+ABBR_REGULAR_USER_ABBREVIATIONS} )); then
          # .zshrc.local's broken `+=` left ZSH_HIGHLIGHT_REGEXP as a
          # scalar with a half-built string; the regexp highlighter
          # then tries to use ''${#ZSH_HIGHLIGHT_REGEXP[@]} as a loop
          # bound and falls into `bad math expression`. Hard-reset to
          # an empty array, then assign cleanly.
          unset ZSH_HIGHLIGHT_REGEXP
          typeset -ga ZSH_HIGHLIGHT_REGEXP=()
          local -a _abbr_keys=()
          local k
          for k in ''${(k)ABBR_REGULAR_USER_ABBREVIATIONS}; do
            _abbr_keys+="''${k//\"/}"
          done
          ZSH_HIGHLIGHT_REGEXP=('^[[:blank:][:space:]]*('"''${(j:|:)_abbr_keys}"')$' fg=green)
          unset k _abbr_keys
        fi

        # Force nix-managed paths to win. envExtra prepends them in .zshenv,
        # but somewhere in the launchd → Ghostty → /etc/zprofile chain
        # path_helper or similar reshuffles PATH and pushes them to the end.
        # Re-prepend here at the very end of .zshrc so Nix binaries shadow
        # /opt/homebrew/bin regardless of what happened earlier.
        for p in \
          "$HOME/.nix-profile/bin" \
          "/etc/profiles/per-user/$USER/bin" \
          "/run/current-system/sw/bin" \
          "/nix/var/nix/profiles/default/bin"
        do
          [[ -d "$p" ]] && export PATH="$p:''${PATH/$p:/}"
        done
      '')
    ];
  };

  # zsh-completions installs completion functions under
  # share/zsh/site-functions which is already in FPATH for the user profile.
  home.packages = [ pkgs.zsh-completions ];

  programs.zoxide = {
    enable = true;
    enableZshIntegration = false; # we source zoxide manually for `--cmd cd`
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = false; # we source fzf manually
  };
}
