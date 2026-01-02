# Claude Code tmux 通知統合
# Ghostty + tmux環境でClaude Codeの通知をtmuxステータスバーに表示

# ウィンドウ切り替え時にフォーカス処理を実行（3秒/6秒タイマー）
set-hook -g session-window-changed 'run-shell -b "~/dotfiles/scripts/tmux-claude-focus.sh"'

# セッション切り替え時も同様
set-hook -g client-session-changed 'run-shell -b "~/dotfiles/scripts/tmux-claude-focus.sh"'
