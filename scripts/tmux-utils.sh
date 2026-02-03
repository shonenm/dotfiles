#!/bin/bash
# tmux共通ユーティリティ
# Usage: source ~/dotfiles/scripts/tmux-utils.sh

_OS=$(uname -s)

# ファイルの更新時刻を取得（エポック秒）
get_mtime() {
  case "$_OS" in
    Linux)  stat -c %Y "$1" 2>/dev/null || echo 0 ;;
    Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
    *) echo 0 ;;
  esac
}
