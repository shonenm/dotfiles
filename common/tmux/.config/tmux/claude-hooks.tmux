# shellcheck shell=bash
# Claude Code tmux 通知統合
# Ghostty + tmux環境でClaude Codeの通知をtmuxステータスバーに表示

# フォーカス系 hook は tmux.conf の tmux-hook-dispatch.sh に集約する。
# ここでは常駐 watcher だけを起動する。

# ハング検知ウォッチャを起動(単一インスタンス保証。設定再読込でも多重起動しない)
run-shell -b "~/dotfiles/scripts/tmux-agent-hang-watch.sh >/dev/null 2>&1 || true"
