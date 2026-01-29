# Modern CLI Tools

従来のUnixコマンドを置き換えるモダンCLIツール一覧。

すべてのエイリアスは `common/zsh/.zshrc.common` で定義。
ツールがインストールされている場合のみ有効化される（`command -v` チェック）。

## エイリアス一覧

| 従来コマンド | 新コマンド | パッケージ名 | エイリアス | 説明 |
|-------------|-----------|-------------|-----------|------|
| `ls` | `eza` | eza | `ls`, `ll`, `la` | ファイル一覧（アイコン・Git対応） |
| `cat` | `bat` | bat | `cat` | シンタックスハイライト付きファイル表示 |
| `grep` | `rg` | ripgrep | `grep` | 高速な正規表現検索 |
| `find` | `fd` | fd | `find` | 高速なファイル検索 |
| `man` | `tldr` | tealdeer | `man` | 簡潔なコマンドヘルプ |
| `ps` | `procs` | procs | `ps` | プロセス一覧（カラー・ツリー表示） |
| `sed` | `sd` | sd | `sed` | 直感的な検索・置換 |
| `du` | `dust` | dust | `du` | ディスク使用量の可視化 |
| `top` | `btm` | bottom | `top` | システムモニター（グラフ表示） |
| `rm` | `rip` | rip2 | `rm` | 安全なファイル削除（ゴミ箱方式） |

## インストール

### macOS

```bash
brew install eza bat ripgrep fd tealdeer procs sd dust bottom rip2
```

### Linux (Debian/Ubuntu)

基本ツール（eza, bat, ripgrep, fd）は apt で、残りは cargo でインストール:

```bash
cargo install tealdeer procs sd du-dust bottom rm-improved
```

### Linux (Alpine)

```bash
apk add eza bat ripgrep fd tealdeer dust bottom
cargo install procs sd rm-improved
```

## エイリアス定義

`common/zsh/.zshrc.common` より:

```bash
# ls -> eza
if command -v eza &>/dev/null; then
  alias ls="eza --icons --git"
  alias ll="eza --icons --git -l"
  alias la="eza --icons --git -la"
fi

# Modern replacements
command -v bat &>/dev/null && alias cat="bat"
command -v rg &>/dev/null && alias grep="rg"
command -v fd &>/dev/null && alias find="fd"
command -v tldr &>/dev/null && alias man="tldr"
command -v procs &>/dev/null && alias ps="procs"
command -v sd &>/dev/null && alias sed="sd"
command -v dust &>/dev/null && alias du="dust"
command -v btm &>/dev/null && alias top="btm"
command -v rip &>/dev/null && alias rm="rip"
```

## 注意事項

- エイリアスは `command -v` で存在確認してから設定されるため、ツールが未インストールでも安全
- 元のコマンドを使いたい場合は `\command` でエイリアスをバイパス（例: `\rm file.txt`）
- `rip` はファイルをゴミ箱（`~/.local/share/graveyard`）に移動するため、完全削除には `\rm` を使用
- `tldr` は初回実行時にキャッシュのダウンロードが必要（`tldr --update`）
