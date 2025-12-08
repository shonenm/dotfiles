# TokyoNight Night colors for Tmux (Transparent)

# Mode style
set -g mode-style "fg=#7aa2f7,bg=#3b4261"

# Message style
set -g message-style "fg=#7aa2f7,bg=default"
set -g message-command-style "fg=#7aa2f7,bg=default"

# Pane border
set -g pane-border-style "fg=#3b4261"
set -g pane-active-border-style "fg=#7aa2f7"

# Status bar (transparent)
set -g status "on"
set -g status-interval 5
set -g status-justify "left"
set -g status-style "fg=#7aa2f7,bg=default"

set -g status-left-length "100"
set -g status-right-length "200"

set -g status-left-style NONE
set -g status-right-style NONE

# Left: Session name
set -g status-left "#[fg=#1a1b26,bg=#7aa2f7,bold]  #S #[fg=#7aa2f7,bg=default,nobold,nounderscore,noitalics] "

# Right: Current directory, Git branch, Date, Time, Hostname
set -g status-right "#{prefix_highlight}#[fg=#c0caf5,bg=default]  #{pane_current_path} #[fg=#9ece6a,bg=default]  #(cd #{pane_current_path}; git branch --show-current 2>/dev/null || echo '-') #[fg=#7aa2f7,bg=default]  %Y-%m-%d  %H:%M #[fg=#1a1b26,bg=#7aa2f7,bold]  #h "

# Window status (transparent)
setw -g window-status-activity-style "underscore,fg=#a9b1d6,bg=default"
setw -g window-status-separator ""
setw -g window-status-style "NONE,fg=#a9b1d6,bg=default"

# Inactive window
setw -g window-status-format "#[fg=#545c7e,bg=default] #I  #W "

# Active window
setw -g window-status-current-format "#[fg=#7aa2f7,bg=default,bold] #I  #W "

# Prefix highlight plugin settings
set -g @prefix_highlight_output_prefix "#[fg=#e0af68]#[bg=default]#[fg=#1a1b26]#[bg=#e0af68]"
set -g @prefix_highlight_output_suffix ""
