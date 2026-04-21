#!/usr/bin/env bash
# node-project.sh — Node.js project bootstrap layout
#
# Usage: sesh.toml の [[wildcard]] / [[session]] の startup_command から参照:
#   startup_command = "~/.config/sesh/scripts/node-project.sh"
#
# Layout:
#   +----------------------------+
#   |                            |
#   |   nvim (current window)    |
#   |                            |
#   +----------------------------+
#   | $ npm run dev (30% height) |
#   +----------------------------+

set -e

# 下 30% に dev server 用 pane を分割
tmux split-window -v -p 30

# 上のペイン (エディタ) に戻って nvim 起動
tmux select-pane -U
tmux send-keys 'nvim' Enter

# 下のペインにフォーカスを移し、dev server コマンドを入力した状態で待機
# (Enter は送らない → ユーザーが確認してから起動)
tmux select-pane -D
if [ -f package.json ]; then
  if grep -q '"dev"' package.json 2>/dev/null; then
    tmux send-keys 'npm run dev'
  elif grep -q '"start"' package.json 2>/dev/null; then
    tmux send-keys 'npm start'
  fi
fi
