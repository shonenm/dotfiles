#!/bin/bash
# tmux テーマファイルを再生成（powerline文字を正しいバイトで埋め込む）
# Linux環境でgit clone後に角丸が表示されない場合に使用

set -euo pipefail

TARGET="${1:-$HOME/.config/tmux/tokyonight.tmux}"

# Powerline / Nerd Font characters
LEFT=$(printf '\xee\x82\xb6')
RIGHT=$(printf '\xee\x82\xb4')
GIT_ICON=$(printf '\xee\x82\xa0')
CLOCK_ICON=$(printf '\xef\x80\x97')
USER_ICON=$(printf '\xef\x80\x87')

cat > "$TARGET" << EOF
set -g mode-style "fg=#1a1b26,bg=#f7768e,bold"
set -g copy-mode-match-style "fg=#1a1b26,bg=#9ece6a"
set -g copy-mode-current-match-style "fg=#1a1b26,bg=#f7768e,bold"
set -g copy-mode-mark-style "fg=#1a1b26,bg=#bb9af7"
set -g message-style "fg=#7aa2f7,bg=default"
set -g message-command-style "fg=#7aa2f7,bg=default"
set -g pane-border-style "fg=#3b4261"
set -g pane-active-border-style "#{?pane_in_mode,fg=#f7768e,fg=#7aa2f7}"
set -g status "on"
set -g status-interval 2
set -g status-justify "left"
set -g status-style "fg=#7aa2f7,bg=default"
set -g status-left-length "100"
set -g status-right-length "250"
set -g status-left-style NONE
set -g status-right-style NONE
set -g status-left "#[fg=#1a1b26,bg=#f7768e,bold]  #S #[fg=#f7768e,bg=default]${RIGHT} "
set -g status-right "#{?pane_in_mode,#[fg=#f7768e]${LEFT}#[fg=#1a1b26 bg=#f7768e bold] COPY #[fg=#f7768e bg=default]${RIGHT},#{?client_prefix,#[fg=#e0af68]${LEFT}#[fg=#1a1b26 bg=#e0af68 bold] PREFIX #[fg=#e0af68 bg=default]${RIGHT},#[fg=#7aa2f7]${LEFT}#[fg=#1a1b26 bg=#7aa2f7] NORMAL #[fg=#7aa2f7 bg=default]${RIGHT}}}#[fg=#9ece6a,bg=default]${LEFT}#[fg=#1a1b26,bg=#9ece6a] ${GIT_ICON} #(cd #{pane_current_path}; git branch --show-current 2>/dev/null || echo '-') #[fg=#9ece6a,bg=default]${RIGHT}#[fg=#7aa2f7,bg=default]${LEFT}#[fg=#1a1b26,bg=#7aa2f7] ${CLOCK_ICON} %m/%d %H:%M #[fg=#7aa2f7,bg=default]${RIGHT}#[fg=#7dcfff,bg=default]${LEFT}#[fg=#1a1b26,bg=#7dcfff,bold] ${USER_ICON} #h #[fg=#7dcfff,bg=default]"
setw -g window-status-activity-style "underscore,fg=#a9b1d6,bg=default"
setw -g window-status-separator ""
setw -g window-status-style "NONE,fg=#a9b1d6,bg=default"
setw -g window-status-format "#[fg=#3b4261,bg=default]${LEFT}#[fg=#a9b1d6,bg=#3b4261] #I #W #[fg=#3b4261,bg=default]${RIGHT}"
setw -g window-status-current-format "#[fg=#7aa2f7,bg=default]${LEFT}#[fg=#1a1b26,bg=#7aa2f7,bold] #I #W #[fg=#7aa2f7,bg=default]${RIGHT}"
EOF

echo "Generated: $TARGET"
echo "Run: tmux source ~/.config/tmux/tmux.conf"
