#!/bin/sh
# prefix+Space file finder (tmux display-popup 内で実行)。
#
# スコープと表示:
#   デフォルト = cwd を含む git repo 全体 (repo 外なら $HOME)。ROOT からの相対パス表示。
#   クエリを "/" から打ち始めると "/" 全体検索へ切替 (絶対パス表示、/home... で絞込)。
#   "/" を消すとスコープ検索へ戻る。
# 選択で同じ popup 内に read-only nvim を開いてプレビュー、終了で popup が閉じる。
#
# ponytail: ROOT へ cd して fd を相対出力に。preview/nvim も cwd=ROOT で解決。
#           モード境界でだけ reload。全体 fd は "/" を打った瞬間に1回だけ走る。

ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
cd "$ROOT" || exit 1
FLAG="$(mktemp -u)"   # 存在 = 全体検索モード (境界検出用の状態フラグ)
export FLAG
trap 'rm -f "$FLAG"' EXIT

# スコープ検索: cwd(=ROOT) を相対出力。repo は .gitignore が効く。$HOME 用に主要ノイズ除外。
scoped='fd --type f --hidden --exclude .git --exclude node_modules --exclude Library --exclude .cache .'

file=$(
  eval "$scoped" |
    fzf --reverse --border-label ' find file ' --prompt '🔎  ' \
        --preview 'bat --style=numbers --color=always --line-range :500 {} 2>/dev/null || cat {}' \
        --preview-window 'right:60%' \
        --bind 'change:transform:
          if [ "${FZF_QUERY#/}" != "$FZF_QUERY" ]; then
            [ -f "$FLAG" ] || { : > "$FLAG"; printf "reload(fd --type f --hidden . / 2>/dev/null)"; }
          else
            [ -f "$FLAG" ] && { rm -f "$FLAG"; printf "reload(fd --type f --hidden --exclude .git --exclude node_modules --exclude Library --exclude .cache .)"; }
          fi'
) || exit 0

[ -n "$file" ] && exec nvim -R "$file"
