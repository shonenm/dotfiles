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
| `watch` | `viddy` | viddy | `watch` | 差分ハイライト付き定期実行 |
| `dig` | `doggo` | doggo | `dig` | カラー+JSON対応DNSクライアント |
| `curl`/`httpie` | `xh` | xh | `http` | モダンHTTPクライアント（Rust製） |

## インストール

### macOS

```bash
brew bundle --file=~/dotfiles/config/Brewfile
```

### Linux (Debian/Ubuntu / Alpine)

`install.sh` で自動インストール。ツール定義は `config/tools.linux.bash` に一元管理:

```bash
./install.sh   # apt/apk パッケージ + GitHub release + cargo を自動判別
```

各ツールのインストール方法:
- **apt/apk**: eza, bat, ripgrep, fd 等
- **GitHub release**: direnv, just, watchexec, hyperfine, gitleaks, xh, ouch, glow, viddy, doggo, topgrade, grex 等
- **cargo**: tealdeer, procs, sd, du-dust, bottom, rm-improved, git-absorb, cargo-update 等

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
command -v viddy &>/dev/null && alias watch="viddy"
command -v doggo &>/dev/null && alias dig="doggo"
command -v xh &>/dev/null && alias http="xh"
```

## 注意事項

- エイリアスは `command -v` で存在確認してから設定されるため、ツールが未インストールでも安全
- 元のコマンドを使いたい場合は `\command` でエイリアスをバイパス（例: `\rm file.txt`）
- `rip` はファイルをゴミ箱（`~/.local/share/graveyard`）に移動するため、完全削除には `\rm` を使用
- `tldr` は初回実行時にキャッシュのダウンロードが必要（`tldr --update`）

## エイリアスなしツール

エイリアスは設定されないが、Brewfile に含まれる追加ツール:

| ツール | パッケージ名 | 説明 |
|--------|-------------|------|
| `direnv` | direnv | ディレクトリ毎の環境変数自動ロード (`.envrc`) |
| `just` | just | モダンタスクランナー (Makefile代替) |
| `watchexec` | watchexec | ファイル監視・コマンド自動再実行 |
| `hyperfine` | hyperfine | コマンドベンチマーク（統計的精度） |
| `gitleaks` | gitleaks | Git秘密情報スキャン (`git secrets`) |
| `git-absorb` | git-absorb | 自動fixupコミット生成 (`git absorb`) |
| `ouch` | ouch | ユニバーサル圧縮/解凍（フォーマット自動検出） |
| `glow` | glow | ターミナルMarkdownレンダラー |
| `topgrade` | topgrade | 一括パッケージマネージャ更新 |
| `grex` | grex | 例文から正規表現を生成 |
| `quay` | quay-tui | TUIポートマネージャー（ローカルプロセス・SSHフォワード・Dockerコンテナ） |
| `cargo-install-update` | cargo-update | cargo install パッケージの一括アップデート (`cargo install-update -a`) |

## bat 設定

`common/bat/.config/bat/config` でグローバル設定:

- **テーマ**: Visual Studio Dark+
- **スタイル**: 行番号、Git変更マーカー、ヘッダー表示
- **構文マッピング**: `.env` → DotENV、`.envrc` → Bash
