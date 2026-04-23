#!/bin/bash
# tmux テーマファイルを再生成（powerline文字を正しいバイトで埋め込む）
# Linux環境でgit clone後に角丸が表示されない場合に使用
#
# Usage: regenerate-tmux-theme.sh <tokyonight|syntopic> [target_file]
#
# 重要: *.tmux を直接編集せず、このスクリプトを編集して再生成すること
# powerline文字がgit操作で破損する可能性があるため

set -euo pipefail

THEME="${1:-}"
if [ -z "$THEME" ]; then
  echo "Usage: $0 <tokyonight|syntopic> [target_file]" >&2
  exit 1
fi

# --- Color Palette ---
case "$THEME" in
  tokyonight)
    TARGET="${2:-$HOME/.config/tmux/tokyonight.tmux}"
    THEME_LABEL="TokyoNight Night"
    BG_DARK="#1a1b26"
    FG_SUBTLE="#545c7e"
    FG_TEXT="#a9b1d6"
    BG_HIGHLIGHT="#292e42"
    BORDER_INACTIVE="#3b4261"
    ACCENT_PRIMARY="#7aa2f7"
    ACCENT_SESSION="#f7768e"
    SESSION_FG="#1a1b26"
    COLOR_SUCCESS="#73daca"
    COLOR_ERROR="#f7768e"
    COLOR_WARNING="#ffea00"
    COLOR_RELOAD="#ff9e64"
    COLOR_THUMBS="#41a6b5"
    COLOR_ZOOM="#bb9af7"
    COLOR_GIT="#9ece6a"
    COLOR_DATE_BG="#7aa2f7"
    COLOR_DATE_FG="#1a1b26"
    COLOR_HOST_BG="#7dcfff"
    COLOR_MSG="#7aa2f7"
    WINDOW_INACTIVE_BG="#3b4261"
    WINDOW_INACTIVE_FG="#a9b1d6"
    ;;
  syntopic)
    TARGET="${2:-$HOME/.config/tmux/syntopic.tmux}"
    THEME_LABEL="SynTopic"
    # Palette derived from @syntopic/design-system token.js (dark mode CSS variables).
    # HSL origin shown alongside hex for traceability; tmux needs hex literals.
    BG_DARK="#0F1A15"          # topic-base    hsl(153 27% 8%)
    FG_SUBTLE="#64748B"        # text-subtle   hsl(215 16% 47%)
    FG_TEXT="#94A3B8"          # text-subtle lightened for window labels
    BG_HIGHLIGHT="#1E2E28"     # topic-border  hsl(158 21% 15%)
    BORDER_INACTIVE="#1E2E28"  # topic-border
    ACCENT_PRIMARY="#047857"   # brand-green   hsl(163 94% 24%)
    ACCENT_SESSION="#047857"   # brand-green
    SESSION_FG="#F8FAFC"       # text-default (dark)  hsl(210 40% 98%)
    COLOR_SUCCESS="#22C55E"    # status-success
    COLOR_ERROR="#EF4444"      # status-error
    COLOR_WARNING="#FACC15"    # status-warning
    COLOR_RELOAD="#F59E0B"     # status-active
    COLOR_THUMBS="#3B82F6"     # status-info
    COLOR_ZOOM="#A855F7"       # status-inactive
    COLOR_GIT="#22C55E"        # status-success
    COLOR_DATE_BG="#8B5A2B"    # brand-brown   hsl(29 53% 36%)
    COLOR_DATE_FG="#F8FAFC"    # text-default
    COLOR_HOST_BG="#3B82F6"    # status-info
    COLOR_MSG="#047857"        # brand-green
    WINDOW_INACTIVE_BG="#1E2E28"  # topic-border
    WINDOW_INACTIVE_FG="#94A3B8"  # text-subtle lightened
    ;;
  catppuccin)
    TARGET="${2:-$HOME/.config/tmux/catppuccin.tmux}"
    THEME_LABEL="Catppuccin Mocha"
    BG_DARK="#1e1e2e"
    FG_SUBTLE="#6c7086"
    FG_TEXT="#cdd6f4"
    BG_HIGHLIGHT="#313244"
    BORDER_INACTIVE="#45475a"
    ACCENT_PRIMARY="#89b4fa"
    ACCENT_SESSION="#f38ba8"
    SESSION_FG="#1e1e2e"
    COLOR_SUCCESS="#a6e3a1"
    COLOR_ERROR="#f38ba8"
    COLOR_WARNING="#f9e2af"
    COLOR_RELOAD="#fab387"
    COLOR_THUMBS="#94e2d5"
    COLOR_ZOOM="#cba6f7"
    COLOR_GIT="#a6e3a1"
    COLOR_DATE_BG="#89b4fa"
    COLOR_DATE_FG="#1e1e2e"
    COLOR_HOST_BG="#89dceb"
    COLOR_MSG="#89b4fa"
    WINDOW_INACTIVE_BG="#45475a"
    WINDOW_INACTIVE_FG="#cdd6f4"
    ;;
  gruvbox)
    TARGET="${2:-$HOME/.config/tmux/gruvbox.tmux}"
    THEME_LABEL="Gruvbox Dark"
    BG_DARK="#282828"
    FG_SUBTLE="#928374"
    FG_TEXT="#ebdbb2"
    BG_HIGHLIGHT="#3c3836"
    BORDER_INACTIVE="#504945"
    ACCENT_PRIMARY="#83a598"
    ACCENT_SESSION="#fb4934"
    SESSION_FG="#282828"
    COLOR_SUCCESS="#b8bb26"
    COLOR_ERROR="#fb4934"
    COLOR_WARNING="#fabd2f"
    COLOR_RELOAD="#fe8019"
    COLOR_THUMBS="#8ec07c"
    COLOR_ZOOM="#d3869b"
    COLOR_GIT="#b8bb26"
    COLOR_DATE_BG="#83a598"
    COLOR_DATE_FG="#282828"
    COLOR_HOST_BG="#8ec07c"
    COLOR_MSG="#83a598"
    WINDOW_INACTIVE_BG="#504945"
    WINDOW_INACTIVE_FG="#d5c4a1"
    ;;
  rosepine)
    TARGET="${2:-$HOME/.config/tmux/rosepine.tmux}"
    THEME_LABEL="Rose Pine"
    BG_DARK="#191724"
    FG_SUBTLE="#6e6a86"
    FG_TEXT="#e0def4"
    BG_HIGHLIGHT="#26233a"
    BORDER_INACTIVE="#403d52"
    ACCENT_PRIMARY="#9ccfd8"
    ACCENT_SESSION="#eb6f92"
    SESSION_FG="#191724"
    COLOR_SUCCESS="#31748f"
    COLOR_ERROR="#eb6f92"
    COLOR_WARNING="#f6c177"
    COLOR_RELOAD="#ebbcba"
    COLOR_THUMBS="#9ccfd8"
    COLOR_ZOOM="#c4a7e7"
    COLOR_GIT="#31748f"
    COLOR_DATE_BG="#c4a7e7"
    COLOR_DATE_FG="#191724"
    COLOR_HOST_BG="#9ccfd8"
    COLOR_MSG="#9ccfd8"
    WINDOW_INACTIVE_BG="#403d52"
    WINDOW_INACTIVE_FG="#e0def4"
    ;;
  *)
    echo "Unknown theme: $THEME (available: tokyonight, syntopic, catppuccin, gruvbox, rosepine)" >&2
    exit 1
    ;;
esac

# --- Powerline / Nerd Font characters (UTF-8 bytes) ---
LEFT=$(printf '\xee\x82\xb6')    # U+E0B6 - left rounded
RIGHT=$(printf '\xee\x82\xb4')   # U+E0B4 - right rounded
GIT_ICON=$(printf '\xee\x82\xa0')   # U+E0A0 - git branch
CLOCK_ICON=$(printf '\xef\x80\x97') # U+F017 - clock
USER_ICON=$(printf '\xef\x80\x87')  # U+F007 - user
KEY_ICON=$(printf '\xef\x84\x9c')   # U+F11C - keyboard

# Escaped comma for use inside #{?...} conditional (tmux requires #, to escape commas)
EC='#,'

# --- Status Right Components ---

# ヘルプ表示（prefix押下時）- カンマなしなのでエスケープ不要
HELP="#[fg=${COLOR_WARNING} bg=default]${LEFT}#[fg=${BG_DARK} bg=${COLOR_WARNING} bold] ${KEY_ICON} #[fg=${COLOR_WARNING} bg=default]${RIGHT} -| split  g git  G gh  k keifu  j scratch  f sess  F proj  v copy  r reload  ? keys  Space menu"

# 通常表示の各パーツ
# スタイル指定 #[...] 内のカンマを #, でエスケープ（ネストされた #{?...} のカンマはそのまま）
SR_SYSSTAT="#[fg=${BG_HIGHLIGHT}${EC}bg=default]${LEFT}#[fg=#ff6600${EC}bg=${BG_HIGHLIGHT}]#(~/dotfiles/scripts/tmux-claude-usage.sh)#[fg=${FG_SUBTLE}${EC}bg=${BG_HIGHLIGHT}]|#(~/dotfiles/scripts/tmux-cpu.sh)#[fg=${FG_SUBTLE}${EC}bg=${BG_HIGHLIGHT}]|#(~/dotfiles/scripts/tmux-ram.sh)#(~/dotfiles/scripts/tmux-gpu.sh)#(~/dotfiles/scripts/tmux-storage.sh)#[fg=${BG_HIGHLIGHT}${EC}bg=default]${RIGHT} "
SR_MODE="#{?#{==:#{client_key_table},off},#[fg=${FG_SUBTLE}]${LEFT}#[fg=${BG_DARK} bg=${FG_SUBTLE} bold]  OFF #[fg=${FG_SUBTLE} bg=default]${RIGHT},#{?#{==:#{@reload_mode},1},#[fg=${COLOR_RELOAD}]${LEFT}#[fg=${BG_DARK} bg=${COLOR_RELOAD} bold]  RELOAD #[fg=${COLOR_RELOAD} bg=default]${RIGHT},#{?#{==:#{window_name},[thumbs]},#[fg=${COLOR_THUMBS}]${LEFT}#[fg=${BG_DARK} bg=${COLOR_THUMBS} bold] 󰆤 THUMBS #[fg=${COLOR_THUMBS} bg=default]${RIGHT},#{?pane_in_mode,#[fg=${COLOR_ERROR}]${LEFT}#[fg=${BG_DARK} bg=${COLOR_ERROR} bold] COPY #[fg=${COLOR_ERROR} bg=default]${RIGHT},#{?pane_synchronized,#[fg=${COLOR_SUCCESS}]${LEFT}#[fg=${BG_DARK} bg=${COLOR_SUCCESS} bold] SYNC #[fg=${COLOR_SUCCESS} bg=default]${RIGHT},#{?window_zoomed_flag,#[fg=${COLOR_ZOOM}]${LEFT}#[fg=${BG_DARK} bg=${COLOR_ZOOM} bold]  ZOOM #P/#{window_panes} #[fg=${COLOR_ZOOM} bg=default]${RIGHT},#[fg=${ACCENT_PRIMARY}]${LEFT}#[fg=${BG_DARK} bg=${ACCENT_PRIMARY}] NORMAL #[fg=${ACCENT_PRIMARY} bg=default]${RIGHT}}}}}}}"
SR_GIT="#[fg=${COLOR_GIT}${EC}bg=default]${LEFT}#[fg=${BG_DARK}${EC}bg=${COLOR_GIT}] ${GIT_ICON} #(cd #{pane_current_path}; git branch --show-current 2>/dev/null || echo '-') #[fg=${COLOR_GIT}${EC}bg=default]${RIGHT}"
SR_DATE="#[fg=${COLOR_DATE_BG}${EC}bg=default]${LEFT}#[fg=${COLOR_DATE_FG}${EC}bg=${COLOR_DATE_BG}] ${CLOCK_ICON} %m/%d %H:%M #[fg=${COLOR_DATE_BG}${EC}bg=default]${RIGHT}"
SR_HOST="#[fg=${COLOR_HOST_BG}${EC}bg=default]${LEFT}#[fg=${BG_DARK}${EC}bg=${COLOR_HOST_BG}${EC}bold] ${USER_ICON} #h #[fg=${COLOR_HOST_BG}${EC}bg=default]"

# 通常表示を結合
SR_NORMAL="${SR_SYSSTAT}${SR_MODE}${SR_GIT}${SR_DATE}${SR_HOST}"

# 最終的なstatus-right（prefix時はヘルプ、それ以外は通常）
STATUS_RIGHT="#{?client_prefix,${HELP},${SR_NORMAL}}"

# --- Generate Theme File ---
cat > "$TARGET" << EOF
# ${THEME_LABEL} colors for Tmux (Transparent + Powerline)
# Generated by: scripts/regenerate-tmux-theme.sh ${THEME}
# Do NOT edit this file directly - edit the script and regenerate

# Theme variables (consumed by tmux.conf and scripts at runtime)
set -g @theme-name "${THEME}"
set -g @theme-bg-dark "${BG_DARK}"
set -g @theme-fg-subtle "${FG_SUBTLE}"
set -g @theme-border-inactive "${BORDER_INACTIVE}"
set -g @theme-border-success "${COLOR_SUCCESS}"

# Mode style (copy mode selection)
set -g mode-style "fg=${BG_DARK},bg=${COLOR_ERROR},bold"

# Copy mode match highlighting
set -g copy-mode-match-style "fg=${BG_DARK},bg=${COLOR_GIT}"
set -g copy-mode-current-match-style "fg=${BG_DARK},bg=${COLOR_ERROR},bold"
set -g copy-mode-mark-style "fg=${BG_DARK},bg=${COLOR_ZOOM}"

# Message style
set -g message-style "fg=${COLOR_MSG},bg=default"
set -g message-command-style "fg=${BG_DARK},bg=${COLOR_ZOOM},bold"

# --- Pane Border ---
set -g pane-border-lines double
set -g pane-border-style "fg=${BORDER_INACTIVE},bg=default"
# off: subtle, reload: active, thumbs: info, copy: error, sync: success, prefix: warning, zoom: inactive, default: primary
set -g pane-active-border-style '#{?#{==:#{client_key_table},off},fg=${FG_SUBTLE} bg=${BG_DARK},#{?#{==:#{@reload_mode},1},fg=${COLOR_RELOAD} bg=${BG_DARK},#{?#{==:#{window_name},[thumbs]},fg=${COLOR_THUMBS} bg=${BG_DARK},#{?pane_in_mode,fg=${COLOR_ERROR} bg=${BG_DARK},#{?pane_synchronized,fg=${COLOR_SUCCESS} bg=${BG_DARK},#{?client_prefix,fg=${COLOR_WARNING} bg=${BG_DARK},#{?window_zoomed_flag,fg=${COLOR_ZOOM} bg=${BG_DARK},fg=${ACCENT_PRIMARY} bg=${BG_DARK}}}}}}}}'
set -g pane-border-status top
set -g pane-border-format " #P: #{?pane_title,#{pane_title},#{pane_current_command}} "
set -g pane-border-indicators both

# --- Window Style ---
set -g window-style 'fg=colour248,bg=default'
set -g window-active-style 'fg=colour255,bg=default'

# --- Status Bar (transparent) ---
set -g status "on"
set -g status-interval 10
set -g status-justify "left"
set -g status-style "fg=${ACCENT_PRIMARY},bg=default"

set -g status-left-length "100"
set -g status-right-length "250"

set -g status-left-style NONE
set -g status-right-style NONE

# Left: Session name
set -g status-left "#[fg=${SESSION_FG},bg=${ACCENT_SESSION},bold]  #S #[fg=${ACCENT_SESSION},bg=default]${RIGHT} "

# Right: Prefix押下時はヘルプ、それ以外は通常表示
# 通常表示: [SYSSTAT] [MODE] [GIT] [DATE] [HOST]
# Mode priority: OFF > RELOAD > THUMBS > COPY > SYNC > ZOOM > NORMAL
# Note: カンマは #, でエスケープ（tmux conditional format内で必要）
set -g status-right "${STATUS_RIGHT}"

# --- Window Status (Powerline style) ---
setw -g window-status-activity-style "underscore,fg=${FG_TEXT},bg=default"
setw -g window-status-separator ""
setw -g window-status-style "NONE,fg=${FG_TEXT},bg=default"

# Inactive window (Rounded style) + Claude badge
setw -g window-status-format "#[fg=${WINDOW_INACTIVE_BG},bg=default]${LEFT}#[fg=${WINDOW_INACTIVE_FG},bg=${WINDOW_INACTIVE_BG}] #I #W #[fg=${WINDOW_INACTIVE_BG},bg=default]${RIGHT}#(~/dotfiles/scripts/tmux-claude-badge.sh window #{window_index} '' #S)"

# Active window (Rounded style with highlight) + Claude badge (dimmed)
setw -g window-status-current-format "#[fg=${ACCENT_PRIMARY},bg=default]${LEFT}#[fg=${SESSION_FG},bg=${ACCENT_PRIMARY},bold] #I #W #[fg=${ACCENT_PRIMARY},bg=default]${RIGHT}#(~/dotfiles/scripts/tmux-claude-badge.sh window #{window_index} focused #S)"

# Prefix highlight plugin settings (not used, kept for compatibility)
set -g @prefix_highlight_output_prefix ""
set -g @prefix_highlight_output_suffix ""
EOF

echo "Generated: $TARGET"
echo "Run: tmux source ~/.config/tmux/tmux.conf"
