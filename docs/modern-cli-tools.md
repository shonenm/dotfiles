# Modern CLI Tools

従来のUnixコマンドを置き換えるモダンCLIツール一覧。

すべてのエイリアスは `common/zsh/.zshrc.common` で定義。
ツールがインストールされている場合のみ有効化される（`command -v` チェック）。

## エイリアス一覧

| 従来コマンド | 新コマンド | パッケージ名 | エイリアス | 説明 |
|-------------|-----------|-------------|-----------|------|
| `ls` | `lsd` | lsd | `ls`, `ll`, `la` | ファイル一覧（アイコン・カラー表示） |
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
- **apt/apk**: eza, bat, ripgrep, fd, postgresql-client 等
- **GitHub release**: direnv, just, watchexec, hyperfine, gitleaks, xh, ouch, glow, viddy, doggo, topgrade, grex, dblab 等
- **cargo**: tealdeer, procs, sd, du-dust, bottom, rm-improved, git-absorb, cargo-update 等
- **uv tool**: pgcli

## エイリアス定義

`common/zsh/.zshrc.common` より:

```bash
# ls -> lsd (fallback: eza)
if command -v lsd &>/dev/null; then
  alias ls="lsd"
  alias ll="lsd -l"
  alias la="lsd -la"
elif command -v eza &>/dev/null; then
  alias ls="eza --icons --git"
  alias ll="eza --icons --git -l"
  alias la="eza --icons --git -la"
fi

# Auto ls on cd
chpwd() {
  ls
}

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

## グローバルエイリアス（パイプ修飾子）

コマンドの末尾に付けてパイプ処理を簡潔に書ける `alias -g`:

| エイリアス | 展開先 | 使用例 |
|-----------|--------|--------|
| `L` | `\| bat` | `git log L` |
| `G` | `\| rg` | `ps aux G node` |
| `C` | `\| pbcopy` | `pwd C` |
| `H` | `\| head` | `ls H` |
| `T` | `\| tail` | `ls T` |

## Suffixエイリアス（拡張子ごとのオープナー）

ファイル名を直接入力するだけで適切なアプリで開く `alias -s`:

| 拡張子 | 起動コマンド |
|--------|-------------|
| `.md`, `.txt`, `.yaml`, `.yml`, `.toml`, `.json` | `nvim` |
| `.py` | `python` |
| `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp` | `open` |

## Zshオプション

`common/zsh/.zshrc.common` で設定:

| オプション | 効果 |
|-----------|------|
| `CORRECT` | コマンドのスペルミスを検出して修正候補を提示 |
| `AUTO_CD` | ディレクトリ名だけ入力すれば `cd` なしで移動 |
| `NO_FLOW_CONTROL` | `Ctrl+S`/`Ctrl+Q` のフロー制御を無効化 |

## 注意事項

- `lsd` がインストールされていない環境（Linux等）では `eza` にフォールバック
- `cd` 実行時に `chpwd` フックで自動的に `ls` が実行される（zoxide の `cd` でも発火）
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
| `keifu` | keifu | Git コミットグラフ TUI（ブランチ構造の可視化に特化） |
| `cargo-install-update` | cargo-update | cargo install パッケージの一括アップデート (`cargo install-update -a`) |
| `pgcli` | pgcli | PostgreSQL インタラクティブクライアント（オートコンプリート・シンタックスハイライト） |
| `dblab` | dblab | TUI データベースクライアント（スキーマブラウジング・クエリ実行） |
| `psql` | postgresql@17 | PostgreSQL クライアントツール群（pg_dump, pg_restore 等） |

## fd 設定

`common/fd/.config/fd/ignore` でグローバル ignore パターン:

```
node_modules
.cache
__pycache__
.venv
target
.next
.turbo
```

- fd は `~/.config/fd/ignore` をグローバル ignore として自動で読む
- snacks.nvim の picker で `--no-ignore-vcs` を使用し、`.gitignore` はバイパスしつつこの ignore は尊重
- ターミナルでの素の `fd` コマンドにも効く

## bat 設定

`common/bat/.config/bat/config` でグローバル設定:

- **テーマ**: Visual Studio Dark+
- **スタイル**: 行番号、Git変更マーカー、ヘッダー表示
- **構文マッピング**: `.env` → DotENV、`.envrc` → Bash

## atuin 設定

シェル履歴をローカル SQLite に保存し、高速検索を提供する。

### キーバインド

| キー | 動作 | 関数 |
|------|------|------|
| `Ctrl+R` | 全文検索画面 | `atuin-search` |
| `Up` | 入力中文字でフィルタ | `atuin-up-search` |
| `Ctrl+P` | 入力中文字でフィルタ | `atuin-up-search` |

- `Ctrl+R` と `Up` は `atuin init zsh` でデフォルト設定
- `Ctrl+P` は `mac/zsh/.zshrc.local` で追加設定
