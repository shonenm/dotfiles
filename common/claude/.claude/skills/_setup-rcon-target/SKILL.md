---
name: _setup-rcon-target
description: 新しい rcon ターゲット (host もしくは host:container) をセットアップする。targets ファイル追加、SSH/dotfiles/tmux 接続検証、Docker volume mount スニペット生成を半自動化。
user-invocable: true
arguments: "<host> | <host>:<container>"
argument-hint: "<host>[:<container>]"
when_to_use: "Use when the user wants to register a new rcon target (remote host or remote-host:container pair) and verify everything is wired up for host-tmux + docker-exec operation. Automates the process described in docs/rcon-setup.md."
---

# Setup rcon Target

新しい rcon ターゲットをセットアップし、すぐ使える状態にする。詳細原理は `docs/rcon-setup.md` を参照。

## 引数

| 引数 | 説明 |
|------|------|
| `<host>` | SSH 接続可能な host 名 (~/.ssh/config で解決可能) |
| `<host>:<container>` | 上記 + docker container 指定 |

### 使用例

```
/_setup-rcon-target chronos
/_setup-rcon-target chronos:syntopic-dev
/_setup-rcon-target ailab:another-container
```

## 手順

### 1. 引数の解析

- `:` を含むか: `host` と `container` に分離
- 含まない: host のみ (container なし target)

### 2. Mac 側: `~/.config/rcon/targets` に追加

```bash
mkdir -p ~/.config/rcon
# 既存に同じ行があれば skip (idempotent)
touch ~/.config/rcon/targets
if ! grep -qxF "<target>" ~/.config/rcon/targets; then
  echo "<target>" >> ~/.config/rcon/targets
fi
```

追加前に現在の内容を表示してユーザーに確認を求めず、そのまま追加する。

### 3. SSH 疎通確認

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 <host> true 2>&1
```

- 成功: 次へ
- 失敗:
  - 「`ssh-copy-id <host>` を実行して公開鍵を配置してください」と案内
  - `~/.ssh/config` に `Host <host>` が無さそうなら追加も案内
  - スキルはここで停止

### 4. リモート dotfiles 存在確認

```bash
ssh <host> 'ls -la ~/dotfiles/scripts/tmux-docker-enter 2>/dev/null && command -v tmux'
```

- 両方揃っていれば OK
- 揃ってなければ案内:
  ```
  リモートに dotfiles がセットアップされていません。リモートで以下を実行してください:
    git clone git@github.com:shonenm/dotfiles.git ~/dotfiles
    cd ~/dotfiles
    ./install.sh --no-sudo   # sudoless なら
    ./install.sh              # sudo 利用可なら
  完了後に再度このコマンドを実行してください。
  ```
  スキルはここで停止

### 5. container 指定時: docker 存在確認 + volume mount スニペット生成

```bash
ssh <host> "docker inspect <container> --format '{{json .Mounts}}' 2>&1"
```

- container が存在しない (stopped / 未作成): 新規作成用の `docker run` / `docker compose` スニペットを生成 (下記パターン参照)
- 存在するが volume mount が不足: 追加すべき mount を差分表示
- 全て揃っている: 「準備OK」と表示

#### mount 必須項目

以下が container 内で見えている必要がある:

| mount | 用途 |
|-------|------|
| `~/.claude` → container 内 home の `.claude` | opensessions の Claude watcher |
| `~/.codex` → 同 `.codex` | Codex watcher |
| `~/.local/share/amp` → 同 `.local/share/amp` | Amp watcher |
| プロジェクトディレクトリをホストと同じパスで | cwd 引き継ぎ (pane分割時) |

container 内 user が root なら `/root/...`、それ以外なら `/home/<user>/...`。判定は `docker exec <container> id -un` で可能。

#### docker run スニペット例

```bash
docker run -d \
  --name <container> \
  -v $HOME/.claude:<homedir>/.claude \
  -v $HOME/.codex:<homedir>/.codex \
  -v $HOME/.local/share/amp:<homedir>/.local/share/amp \
  -v $HOME/proj/<project>:<homedir>/proj/<project> \
  --workdir <homedir>/proj/<project> \
  <image>
```

#### docker-compose.yml の追加スニペット例

```yaml
services:
  <container>:
    volumes:
      - ~/.claude:<homedir>/.claude
      - ~/.codex:<homedir>/.codex
      - ~/.local/share/amp:<homedir>/.local/share/amp
      - ~/proj/<project>:<homedir>/proj/<project>
    working_dir: <homedir>/proj/<project>
```

生成したスニペットはそのまま出力する (ユーザーが該当ファイルに反映)。

### 6. 完了報告

以下をまとめて出力:

```
Target added: <target>
  Targets file: ~/.config/rcon/targets
  SSH: OK
  Dotfiles on remote: OK
  Docker container: <status>

Next steps:
  [container なしの場合]
    rcon <host>
  [container ありで mount 揃っている場合]
    rcon <host>:<container>
  [container が未作成 / mount 不足の場合]
    上記スニペットを <docker-compose.yml or 起動スクリプト> に反映し、container を recreate:
      docker compose down && docker compose up -d
    その後: rcon <host>:<container>
```

## エラー時の挙動

- どのステップで失敗したかを明確に表示
- 必要な手動作業を案内
- targets への追記は行った状態で停止 (再実行時に idempotent)

## 注意事項

- container 作成 / recreate はスキルでは行わない (ユーザー責任で compose 設定 or 起動スクリプトを調整)
- 既存 container の volume mount を変更するには recreate が必要 (差分更新不可) — ユーザーに明示
- target が既に存在する場合はスキップしつつ、残りの検証は実施
- `/_setup-rcon-target` は冪等: 何度実行しても安全
