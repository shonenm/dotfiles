# 新環境セットアップ

どの環境 (Mac / Linux sudo / Linux no-sudo / Docker container) でも最短でこの dotfiles を立ち上げるためのレシピ集。AI アシスタントが読んで順に実行することを想定。

## 環境別レシピ

### Mac (新マシン)

```bash
xcode-select --install      # git / cc など前提ツール
git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
eval $(op signin)           # 初回のみ 1P 対話ログイン (必要)
```

install.sh は Homebrew / Brewfile / stow / AI CLI 設定生成 / tmux plugins を一気に処理します。

### Linux (sudo あり)

```bash
git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
eval $(op signin)
```

apt で system パッケージと apt_repo 系 (gh/eza/bat/psql) が入ります。

### Linux (no-sudo / 共有ホスト)

```bash
git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --no-sudo
eval $(op signin)           # 対話ログイン、初回のみ
```

pixi (user-scope) でパッケージを取得。tmux は source build (gcc/make/libevent-dev/libncurses-dev が host に必要)。

### Docker container

前提: ホスト (Mac か ailab 等の Linux) にすでに dotfiles が入っている。

#### Step 1 (AI 経由で自動化)

```
/d-setup-rcon-target <host>:<container> --apply
```

これで以下が自動実行される:
1. `~/.config/rcon/targets` に target 追記
2. SSH 疎通確認
3. compose.yml に dotfiles bind mount を追記
4. `docker compose up -d --force-recreate <service>`
5. container 内で `~/dotfiles/scripts/install-in-container.sh` 実行

#### Step 1 (手動)

```bash
# ① compose.yml の対象 service の volumes に追記
#    - $HOME/dotfiles:/home/${USERNAME:-devuser}/dotfiles:ro

# ② recreate
cd <project-dir> && docker compose up -d --force-recreate <service>

# ③ container 内で install を 1 発
docker exec <container> ~/dotfiles/scripts/install-in-container.sh

# ④ shell 再起動で反映
docker exec -it <container> zsh
# container 内で: exec zsh
```

## 日々の同期

1 箇所だけ編集して全環境に撒きたい:

```bash
dotsync   # Mac で: git push + ssh ailab git pull
```

- Mac → ailab: dotsync で自動
- ailab → container: bind mount なので **何もしなくて良い** (ファイルはその場で新しくなる)
- tmux config 変更: ailab 側の post-merge hook が pull 後に `tmux source-file` 自動 broadcast

`install.sh` を再実行する必要があるのは **新しい system パッケージを追加した時だけ** (config 編集のみなら不要)。

## 新ツール追加時の checklist

dotfiles に新ツールを足す時、書く場所は install 経路で変わる:

| ツールの性質 | 追加先 | 例 |
|------------|-------|----|
| Mac 専用 (brew) | `config/Brewfile` | macmon, aerospace, ghostty |
| apt で入る標準パッケージ | `config/packages.linux.apt.txt` + `config/pixi-packages.txt` (**両方必須**) | jq, stow, zsh, ripgrep |
| apt_repo 経由 (gh, eza, bat, psql) | `config/tools.linux.bash` の TOOL_* 宣言 + `config/pixi-packages.txt` | gh, eza, bat |
| curl-pipe インストーラ | `config/tools.linux.bash` (curl_pipe 方式) | starship, bun, mise, atuin |
| GitHub Releases のプリビルトバイナリ | `config/tools.linux.bash` (github_release / github_release_binary 方式) | fzf, delta, lazygit, sd, dust |
| mise 管理 (言語ランタイム等) | `common/mise/.config/mise/config.toml` | node, go, uv, python |
| npm | `config/packages.npm.txt` | — |

**apt/pixi 二重管理を忘れないための CI チェック**: `scripts/check-package-duplication.sh` が `packages.linux.apt.txt` と `pixi-packages.txt` のミラー状態を検証。同期が崩れると CI が失敗する。追加時に片方忘れた場合は CI に教えてもらえる。

## 各環境の把握している制約

### Mac
- 完成度が最も高い。特殊事情なし。

### Linux sudo
- `build-essential` 等は apt で入る。cargo-install 系 tool もビルド可能。
- apt_repo 系 (gh/eza/bat/psql) のキー登録で多少の手数あり (install.sh で自動化済)。

### Linux no-sudo
- **1P signin が対話必須** (初回のみ)。自動化したいなら `~/.op-session-token` や launchd での signin 維持を検討。
- **tmux source build は host に build-essential + libevent-dev + libncurses-dev が要る**。管理者に依頼できないなら system tmux 3.2a を使う (allow-passthrough 等未対応のため体験低下)。
- CONDA_PREFIX リーク: pixi の一部 tool で Python env を conda 認識して挙動変化する可能性。

### Docker container
- **sudo (NOPASSWD) 前提**。install-in-container.sh は apt で build-essential を入れる。
- **1P は container 内に signin しない**方針 (`--skip-1p`)。secret が必要な操作は host 側で行う。
- **force-recreate で container layer の install 状態が消える**。install-in-container.sh を 1 発叩き直せば数分で復旧。
- **bind mount を compose に書くまで host 側 dotfiles と接続されない**。`/d-setup-rcon-target --apply` で自動化。

## 将来検討

### 統一 registry (未実装)

現状、新ツール追加時は用途別に 3 箇所書く必要がある (apt + pixi + Brewfile)。`config/tools.toml` のような単一宣言ファイルに統合し、install.sh が環境 → 取得経路を自動選択する設計が検討候補。ただし:
- 全面書き換えに数百行必要
- 現時点の重複は 4 tool (gh/eza/bat/psql) のみで、validator で早期検出できるため緊急性は低い
- 実装時は既存の `check_cmd` gate を維持し、既存インストールに影響しないこと

### cargo 依存の完全撤廃

cargo 方式 (gcc 必須) の残り tool: `procs` / `tokei` / `quay-tui` / `gitabsorb` / `cargoupdate` / `keifu`。主要な 6 つ (tealdeer/sd/dust/bottom/rip2/lsd) は prebuilt 移行済 (PR #XX)。残りもほとんどプリビルト入手可能なので段階移行予定。

## 関連 docs

- [install.md](./install.md) — Mac install 詳細
- [install-no-sudo.md](./install-no-sudo.md) — no-sudo mode 詳細
- [rcon-setup.md](./rcon-setup.md) — rcon / リモート接続
- [dotfiles-sync.md](./dotfiles-sync.md) — 3 層同期 architecture
