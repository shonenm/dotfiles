#!/usr/bin/env bash
# generic-project.sh — Minimal single-pane bootstrap with nvim
#
# Usage: sesh.toml の [[wildcard]] / [[session]] の startup_command から参照:
#   startup_command = "~/.config/sesh/scripts/generic-project.sh"
#
# Layout: 単一ペインで nvim を起動するだけ。追加の pane/window は作らない。
# lazygit などの popup は tmux 側の既存キーバインド (prefix+g) で即起動できるため、
# このスクリプトでは pre-launch しない (プロセスを無駄に立てない)。

set -e

# Git リポジトリ内であれば、nvim 起動前に status を確認しやすいように
# 2 行分のヒントを表示してから nvim へ
if git rev-parse --git-dir >/dev/null 2>&1; then
  tmux send-keys 'git status --short && echo && nvim' Enter
else
  tmux send-keys 'nvim' Enter
fi
