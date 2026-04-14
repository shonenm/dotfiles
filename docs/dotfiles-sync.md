# Dotfiles 同期戦略

Mac (source of truth) → ailab (Linux source of truth) → 各 docker container (bind mount で参照) の 3 層構成で、編集箇所を 1 つに保ちつつ全環境へ反映する仕組み。

## 全体像

```
Mac (編集)
  │
  └─ dotsync ──> github
                   │
                   └─ ssh ailab git pull ──> ailab:~/dotfiles
                                                   │
                                                   ├─ post-merge hook → tmux 全 server reload (ailab 側)
                                                   │
                                                   └─ bind mount (ro) ──> 各 docker container
```

`git pull` が走るのは **Mac (任意)** と **ailab (`dotsync` 経由で自動)** の 2 箇所のみ。container は git clone を持たず、ailab の clone を bind mount で参照するので pull 不要。

## 構成要素

### 1. Mac で `dotsync`

`common/zsh/.zshrc.common` で定義:

```zsh
dotsync           # git push + ailab で git pull --ff-only
dotsync --no-pull # push のみ (ailab 接続不可時)
```

push が失敗すれば ailab pull もスキップされる。ailab 側で `--ff-only` を強制しているので、ailab 側で先に変更があれば fail し、明示的な merge を促す。

### 2. ailab `post-merge` git hook

`scripts/git-hooks/post-merge` を `.git/hooks/post-merge` に symlink (`install.sh` の `setup_git_hooks` step が実行)。

`git pull` 完了後に `/tmp/tmux-*/` 配下の全 socket に対して `tmux source-file ~/.config/tmux/tmux.conf` を broadcast。`prefix+r` を手で叩く必要がなくなる。

> 注: `default-terminal` 等 server-startup-only な option は live reload では適用されない。99% の編集は live で OK だが、稀にズレた時だけ手動で `tmux kill-server` 検討。

### 3. Container は ailab dotfiles を bind mount

各 container の `compose.yml` に追記:

```yaml
volumes:
  - /home/matsushima/dotfiles:/home/devuser/dotfiles:ro
```

container 内では:

- git clone は **行わない** (bind mount で参照するだけ)
- 初回 build 時 (Dockerfile / setup script) に `~/dotfiles/install.sh --no-sudo` を 1 回実行
  - stow で `~/.config/...` 等の symlink 作成
  - `pixi-packages.txt` 等で user-scope tool 導入
- 以降、ailab 側で dotfiles が更新されれば mount 経由で即時反映 (symlink の指す先が更新されるだけ)
- 設定反映: tmux は host 側 server なので ailab post-merge hook で reload 済み。zsh は `exec zsh` or 新規 shell で。

#### compose.yml 設定例

`syntopic-dev`, `fluid-sbi-dev`, `geniac-patent-pipeline` 等の compose.yml `services.<name>.volumes` に追加:

```yaml
volumes:
  - ${HOME}/dotfiles:/home/${USERNAME:-devuser}/dotfiles:ro
```

`ro` (read-only) は意図的: container 内から dotfiles を編集すると ailab 側と矛盾するので、編集は host (Mac → ailab) 経由に限定する。

#### Dockerfile 修正例

```dockerfile
# 旧: container 内で git clone + install
# RUN git clone https://github.com/shonenm/dotfiles ~/dotfiles \
#  && ~/dotfiles/install.sh --no-sudo

# 新: bind mount された dotfiles を使って install のみ実行
# (volume mount は build 時には存在しないので、ENTRYPOINT で初回判定 or
#  compose の post-create hook 等で 1 回だけ実行する)
```

簡易には container 起動後に手動で `docker exec -it <name> ~/dotfiles/install.sh --no-sudo --skip-prompt` を初回だけ叩く運用で良い。

## install.sh / install ワークフロー

各環境で 1 度だけ実行:

| 環境 | コマンド | 何をする |
|------|---------|---------|
| Mac | `./install.sh` | brew + stow + tmux plugins + git hooks |
| ailab | `./install.sh --no-sudo` | pixi + source-built tmux + stow + git hooks |
| container | `./install.sh --no-sudo --skip-prompt` | 同上 (mount された dotfiles に対して実行) |

dotfiles の中身 (config) を変えただけなら **再 install 不要**。新規 package を `tools.linux.bash` / `pixi-packages.txt` に追加した時だけ再実行。

## 何が共有でき、何ができないか

| 種類 | 共有手段 | 自動性 |
|------|---------|--------|
| ソースファイル (`tmux.conf`, `.zshrc.common` 等) | git + bind mount | 編集 → `dotsync` で全環境反映 |
| symlink (`~/.config/tmux/tmux.conf` 等) | 各環境で `stow` | 初回 install.sh で 1 回作る |
| system パッケージ (zsh, tmux, gh 等) | apt / pixi / source build | 環境ごと 1 回 install.sh |
| tmux 設定の live reload | post-merge hook | ailab で自動、Mac は手動 `prefix+r` |
| zsh 設定の live reload | (手動 `exec zsh`) | 自動化しない (副作用大) |

## トラブルシュート

### `dotsync` で ailab pull が fail

```
dotsync: ailab pull failed (push succeeded)
```

ailab 側で先に local 変更があるか、conflict あり。手動で:

```bash
ssh ailab 'cd ~/dotfiles && git status'
```

### post-merge hook が反応しない

- `~/dotfiles/.git/hooks/post-merge` が symlink になっているか確認
- なければ `~/dotfiles/install.sh` を再実行 (`setup_git_hooks` が走る)
- hook が実行されても tmux server がなければ何も起きない (no-op exit)

### container で dotfiles 編集したい

bind mount を `:ro` から外せば書ける。ただし source of truth が分裂するので非推奨。基本は Mac で編集 → `dotsync` で全環境同期。

## 関連ドキュメント

- [install.md](./install.md) — Mac 通常 install
- [install-no-sudo.md](./install-no-sudo.md) — Linux no-sudo install
- [rcon-setup.md](./rcon-setup.md) — リモート接続コマンド
