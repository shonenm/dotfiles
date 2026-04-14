# rcon Setup Guide

ホスト集約 tmux + docker exec 構成でリモート開発環境をセットアップする手順。

`rcon` の動作原理は [rcon.md](./rcon.md)、opensessions の運用方針は [opensessions.md](./opensessions.md) を参照。本ドキュメントは「新しいターゲットを追加するときに何を設定すればよいか」のレシピ集。

## アーキテクチャ前提

```
Mac (Ghostty)
  └─ ssh chronos
      └─ host tmux server (chronos 上)
          ├─ session "syntopic-dev"      → docker exec syntopic-dev
          ├─ session "another-container" → docker exec another-container
          └─ session "main"              → host shell (container なし target)
```

- tmux はリモートホスト側で **1サーバーに集約**
- 各 session が docker container と1対1対応
- pane分割 / 新window で `default-command` 経由で自動 docker exec
- opensessions が複数 container を1つのサイドバーに集約表示

## セットアップ層別の責務

| レイヤ | 何を設定するか |
|-------|---------------|
| Mac 側 | `~/.config/rcon/targets` に target を1行追加 |
| リモートホスト (chronos等) | dotfiles install 済 + tmux 起動可 + docker CLI 利用可 |
| Docker container | **volume mount** で `~/.claude` 等をホストと共有 |

## 1. Mac 側: target 追加

```bash
mkdir -p ~/.config/rcon
cat >> ~/.config/rcon/targets <<'EOF'
chronos
chronos:syntopic-dev
chronos:another-container
EOF
```

形式: `<host>` または `<host>:<container>`。`<host>` は `~/.ssh/config` で解決可能な名前。コメントは `#` で開始。

`rcon` (引数なし) で fzf 選択、`rcon chronos:syntopic-dev` で直接指定。

## 2. リモートホスト (chronos 等): 一度だけのセットアップ

新しいリモートホストを使う初回:

```bash
# Mac 側で SSH 公開鍵を配置 (パスワードなし接続)
ssh-copy-id chronos

# リモート側で dotfiles を clone & install
ssh chronos
git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --no-sudo   # sudoless ホストの場合
# あるいは sudo 利用可ホストでは
./install.sh
```

これで以下が揃う:
- `tmux` (pixi 経由で `~/.pixi/bin/tmux`)
- `~/.config/tmux/tmux.conf` (stow symlink)
- `~/dotfiles/scripts/tmux-docker-enter` (wrapper)
- TPM + opensessions plugin
- zsh / stow / その他 CLI ツール

確認:
```bash
ssh chronos
which tmux                                    # ~/.pixi/bin/tmux
ls -la ~/dotfiles/scripts/tmux-docker-enter   # 実行可能
ls ~/.tmux/plugins/opensessions               # plugin 展開済
which docker                                   # docker CLI 存在
```

詳細は [install-no-sudo.md](./install-no-sudo.md)。

## 3. Docker container: volume mount を追加

opensessions の AI agent watcher (Claude Code / Codex / Amp) はホスト側のファイルシステムを読む。コンテナ内で agent を動かすなら `~/.claude` 等を mount しておく必要がある。

### docker-compose.yml の場合

```yaml
services:
  syntopic-dev:
    volumes:
      # AI agent state (opensessions 連携用)
      - ~/.claude:/home/devuser/.claude
      - ~/.codex:/home/devuser/.codex
      - ~/.local/share/amp:/home/devuser/.local/share/amp

      # pane-cwd state (host tmux popup wrapper が container 内 cwd を解決するため)
      # ホスト側ディレクトリは container ごとに分ける:
      #   ~/.cache/tmux-pane-state-<container>:/tmp/tmux-pane-state
      - ~/.cache/tmux-pane-state-syntopic-dev:/tmp/tmux-pane-state

      # プロジェクトファイル (cwd 引き継ぎを動かすため、ホストとパス揃える)
      - ~/proj/syntopic:/home/devuser/proj/syntopic

    working_dir: /home/devuser/proj/syntopic
```

container 内 user が `root` なら `/root/.claude` 等。

`~/.cache/tmux-pane-state-<container>` ホストディレクトリは mount 時に自動作成される (無ければ docker が作る)。ファイル内容は container-side zshrc の chpwd hook が書き出し、ホスト側 `tmux-popup-in-container` wrapper と `tmux-pane-context` helper が読む。worktree ごとに window を切って `cd` する運用で、各 window の正確な container cwd が popup (`prefix+g` lazygit 等) に伝わるようになる。

mount を省略した場合は機能が degrade するだけ (lazygit 等は container の `Config.WorkingDir` で開く、ユーザー cd 反映なし)。

反映:
```bash
docker compose down syntopic-dev
docker compose up -d syntopic-dev
```

### docker run の場合

```bash
docker stop syntopic-dev && docker rm syntopic-dev
docker run -d \
  --name syntopic-dev \
  -v ~/.claude:/root/.claude \
  -v ~/.codex:/root/.codex \
  -v ~/.cache/tmux-pane-state-syntopic-dev:/tmp/tmux-pane-state \
  -v ~/proj/syntopic:/root/proj/syntopic \
  --workdir /root/proj/syntopic \
  <image>
```

> ⚠️ container を recreate するとファイルシステム差分は失われる。永続化したいデータは別 volume に切り出しておく。

## 4. 接続テスト

```bash
# Mac 側で
rcon chronos                    # host のみ (sanity check)
# → host tmux session "main" に attach

rcon chronos:syntopic-dev       # container 接続
# → host tmux session "syntopic-dev" 作成、最初の pane が container 内 zsh

# 動作確認
hostname    # container のホスト名 (= short container ID 等)
pwd         # mount したプロジェクトパス

# pane 分割で自動 docker exec + cwd 引き継ぎ
prefix+|    # 右に分割
hostname    # 同じ container
pwd         # 同じディレクトリ

# detach
prefix+d
exit        # ssh 抜ける
```

## 5. opensessions サイドバー確認

attach 中の host tmux で:

```
prefix+o → s    # サイドバー focus
prefix+o → t    # トグル
prefix+o → 1-9  # 番号で session切替
```

期待:
- container 名で session が並ぶ
- container 内で Claude/Codex を起動 → status が反映 (volume mount 効いてれば)

詳細は [opensessions.md](./opensessions.md)。

## 日常運用フロー

```
朝:
  Mac: rcon chronos:syntopic-dev
  作業 (nvim, server起動, claude起動 等)
  prefix+d で detach (tmux session は host 側で生き続ける)

別 container に切替:
  Mac: rcon chronos:another-container
  または既存接続中なら prefix+o → s → 別 session 選択

夜:
  prefix+d で detach
  ssh 切断
  → host tmux server は生き続け、翌朝 rcon で即復帰
```

## トラブルシューティング

### `rcon: command not found` (Mac)

zsh が再起動されてない。新 terminal を開く or `source ~/.zshrc`。

### `tmux: command not found` (リモート)

pixi の PATH (`~/.pixi/bin`) が反映されてない。
- 新 ssh セッションを開く (`~/.profile` → `exec zsh -l` で `~/.bashrc` 経由 PATH 設定)
- もしくは `source ~/.bashrc` で現セッションに反映

### `tmux-docker-enter: No such file`

リモートに dotfiles が clone されてない、または `~/dotfiles` 以外に展開されている。`ls -la ~/dotfiles/scripts/tmux-docker-enter` で確認。

### pane 分割しても host shell に戻る

container が稼働してない。
```bash
docker ps -a | grep <container>   # 状態確認
docker start <container>            # 起動
```
container 起動後、pane を `exit` で閉じて新規分割するか `tmux respawn-pane`。

### pane 分割で cwd が引き継がれない

ホストとコンテナで対応するパスが存在しない。docker run の `-v` で同じパスでマウントする (例: `-v ~/proj/syntopic:~/proj/syntopic` ではなく `-v ~/proj/syntopic:/root/proj/syntopic` のときは host の `/home/user/proj/syntopic` と container の `/root/proj/syntopic` が異なるパスになる)。

cwd 完全一致が難しい場合は wrapper の fallback で container の WORKDIR で開くが、毎回 `cd` が必要になる。

### opensessions に AI status が出ない

container 内で動いてる Claude が ホスト `~/.claude/projects/` に書き込めていない (volume mount 不足)。

```bash
# host 側
ls -la ~/.claude/projects/          # JSONL が増えているか
# container 側
ls -la /root/.claude/projects/      # 同じ内容が見えるか (mount 効いてればホストと同じ)
```

mount 設定を見直して container を recreate。

### session 名に `:` `.` がある

tmux 制限のため `rcon` 内で自動的に `-` に sanitize される (`syntopic.dev` → `syntopic-dev`)。混乱を避けるなら container 名にこれらを使わない方が良い。

## 自動化

`/_setup-rcon-target` skill を使うと target 追加 + 接続検証 + docker mount スニペット生成を半自動化できる。

```
/_setup-rcon-target chronos:new-container
```

詳細はスキル定義 (`common/claude/.claude/skills/_setup-rcon-target/SKILL.md`) 参照。

## 関連ドキュメント

- [rcon.md](./rcon.md) — rcon コマンド本体の動作原理
- [opensessions.md](./opensessions.md) — opensessions 運用方針
- [install-no-sudo.md](./install-no-sudo.md) — sudoless 環境向け install
