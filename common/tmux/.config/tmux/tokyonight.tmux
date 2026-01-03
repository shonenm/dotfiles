# TokyoNight Night colors for Tmux (Transparent + Powerline)

# Mode style (copy mode selection - red to match border)
set -g mode-style "fg=#1a1b26,bg=#f7768e,bold"

# Copy mode match highlighting
set -g copy-mode-match-style "fg=#1a1b26,bg=#9ece6a"
set -g copy-mode-current-match-style "fg=#1a1b26,bg=#f7768e,bold"
set -g copy-mode-mark-style "fg=#1a1b26,bg=#bb9af7"

# Message style
set -g message-style "fg=#7aa2f7,bg=default"
set -g message-command-style "fg=#7aa2f7,bg=default"

# Pane border (dynamic color based on mode)
set -g pane-border-style "fg=#3b4261"
# copy mode: 赤, 通常: 青
set -g pane-active-border-style "#{?pane_in_mode,fg=#f7768e,fg=#7aa2f7}"

# Status bar (transparent)
set -g status "on"
set -g status-interval 2
set -g status-justify "left"
set -g status-style "fg=#7aa2f7,bg=default"

set -g status-left-length "100"
set -g status-right-length "250"

set -g status-left-style NONE
set -g status-right-style NONE

# Left: Session name (桃色 #f7768e、左端は角丸なし)
set -g status-left "#[fg=#1a1b26,bg=#f7768e,bold]  #S #[fg=#f7768e,bg=default] "

# Right: Custom mode indicator + Git branch, Date, Time, Hostname
# Mode indicator: copy=red, prefix=yellow, normal=gray
set -g status-right "#{?pane_in_mode,#[fg=#f7768e]#[fg=#1a1b26 bg=#f7768e bold] COPY #[fg=#f7768e bg=default],#{?client_prefix,#[fg=#e0af68]#[fg=#1a1b26 bg=#e0af68 bold] PREFIX #[fg=#e0af68 bg=default],#[fg=#3b4261]#[fg=#a9b1d6 bg=#3b4261] NORMAL #[fg=#3b4261 bg=default]}}\
#[fg=#9ece6a,bg=default]#[fg=#1a1b26,bg=#9ece6a]  #(cd #{pane_current_path}; git branch --show-current 2>/dev/null || echo '-') #[fg=#9ece6a,bg=default]\
#[fg=#7aa2f7,bg=default]#[fg=#1a1b26,bg=#7aa2f7]  %m/%d %H:%M #[fg=#7aa2f7,bg=default]\
#[fg=#7dcfff,bg=default]#[fg=#1a1b26,bg=#7dcfff,bold]  #h #[fg=#7dcfff,bg=default]"

# Window status (Powerline style)
setw -g window-status-activity-style "underscore,fg=#a9b1d6,bg=default"
setw -g window-status-separator ""
setw -g window-status-style "NONE,fg=#a9b1d6,bg=default"

# Inactive window (Rounded style) + Claude badge
setw -g window-status-format "#[fg=#3b4261,bg=default]#[fg=#a9b1d6,bg=#3b4261] #I #W #[fg=#3b4261,bg=default]#(~/dotfiles/scripts/tmux-claude-badge.sh window #{window_index})"

# Active window (Rounded style with highlight) + Claude badge (dimmed)
setw -g window-status-current-format "#[fg=#7aa2f7,bg=default]#[fg=#1a1b26,bg=#7aa2f7,bold] #I #W #[fg=#7aa2f7,bg=default]#(~/dotfiles/scripts/tmux-claude-badge.sh window #{window_index} focused)"

# Prefix highlight plugin settings (not used, kept for compatibility)
set -g @prefix_highlight_output_prefix ""
set -g @prefix_highlight_output_suffix ""
