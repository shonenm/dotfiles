# TokyoNight Night colors for Tmux (Transparent + Powerline)

# Mode style
set -g mode-style "fg=#7aa2f7,bg=#3b4261"

# Message style
set -g message-style "fg=#7aa2f7,bg=default"
set -g message-command-style "fg=#7aa2f7,bg=default"

# Pane border
set -g pane-border-style "fg=#3b4261"
set -g pane-active-border-style "fg=#0055bb"

# Status bar (transparent)
set -g status "on"
set -g status-interval 2
set -g status-justify "left"
set -g status-style "fg=#7aa2f7,bg=default"

set -g status-left-length "100"
set -g status-right-length "250"

set -g status-left-style NONE
set -g status-right-style NONE

# Left: Session name (Rounded style)
set -g status-left "#[fg=#7aa2f7,bg=default]#[fg=#1a1b26,bg=#7aa2f7,bold]  #S #[fg=#7aa2f7,bg=default] "

# Right: CPU, Memory, Git branch, Date, Time, Hostname (Rounded style)
set -g status-right "#{prefix_highlight}\
#[fg=#3b4261,bg=default]#[fg=#a9b1d6,bg=#3b4261]  #(top -l 1 | grep -E '^CPU' | awk '{print $3}' | cut -d'%' -f1)%% #[fg=#3b4261,bg=default]\
#[fg=#414868,bg=default]#[fg=#a9b1d6,bg=#414868]  #(memory_pressure | grep 'System-wide' | awk '{print 100-$5}')%% #[fg=#414868,bg=default]\
#[fg=#9ece6a,bg=default]#[fg=#1a1b26,bg=#9ece6a]  #(cd #{pane_current_path}; git branch --show-current 2>/dev/null || echo '-') #[fg=#9ece6a,bg=default]\
#[fg=#7aa2f7,bg=default]#[fg=#1a1b26,bg=#7aa2f7]  %m/%d %H:%M #[fg=#7aa2f7,bg=default]\
#[fg=#7dcfff,bg=default]#[fg=#1a1b26,bg=#7dcfff,bold]  #h #[fg=#7dcfff,bg=default]"

# Window status (Powerline style)
setw -g window-status-activity-style "underscore,fg=#a9b1d6,bg=default"
setw -g window-status-separator ""
setw -g window-status-style "NONE,fg=#a9b1d6,bg=default"

# Inactive window (Rounded style)
setw -g window-status-format "#[fg=#3b4261,bg=default]#[fg=#a9b1d6,bg=#3b4261] #I #W #[fg=#3b4261,bg=default]"

# Active window (Rounded style with highlight)
setw -g window-status-current-format "#[fg=#7aa2f7,bg=default]#[fg=#1a1b26,bg=#7aa2f7,bold] #I #W #[fg=#7aa2f7,bg=default]"

# Prefix highlight plugin settings
set -g @prefix_highlight_output_prefix "#[fg=#e0af68]#[bg=default]#[fg=#1a1b26]#[bg=#e0af68]"
set -g @prefix_highlight_output_suffix "#[fg=#e0af68,bg=default]"
