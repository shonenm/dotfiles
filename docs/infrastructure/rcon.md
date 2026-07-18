# rcon - リモート接続ツール

SSH + ホスト側 tmux + Docker をワンコマンドで接続するツール。

> tmux server が重くなった時の再起動・復元手順は
> [tmux-server-restart.md](./tmux-server-restart.md) を参照(再起動は必ず rcon 経由で)。

## 現在の実装

`common/zsh/.zshrc.common` 内のシェル関数として実装。

```bash
rcon                      # fzf でターゲット選択
rcon ailab:myproject-dev   # host:container 形式で直接指定
rcon pi-500               # host のみ（コンテナなし）
rcon pi-500 dev           # tmux セッション名を明示指定
```

### 設定ファイル

`~/.config/rcon/targets` に1行1ターゲットで記載:

```
ailab:myproject-dev
ailab:another-container
pi-500
```

### アーキテクチャ

2026-04 に設計変更: tmux をリモートホスト側で **1サーバーに集約** し、各 session が docker container に対応する形に移行した。

```
Ghostty
  └─ ssh host
      └─ tmux (ホスト側、1 server)
          ├─ session "myproject-dev"      → docker exec -it myproject-dev
          ├─ session "another-container" → docker exec -it another-container
          └─ session "main"              → ホスト shell (container なし target)
```

以前は `SSH → docker exec → container内でtmux` という構成で、コンテナ毎に別 tmux サーバーが立っていた。新構成の利点:

- **1 つのホスト tmux サーバーで全 container を集約**: session 一覧に container 単位で並ぶ
- **Claude Code/Codex/Amp の状態監視が一元化**: ホストの `~/.claude/projects/` 等が container 内 agent のJSONLを見る (要 volume mount: `-v ~/.claude:/root/.claude`)
- **Docker再起動耐性**: コンテナ recreate しても tmux session/レイアウトは残る
- **tmux をDockerイメージに仕込む必要がない**

### 自動化: default-command + tmux-docker-enter

pane 分割 (`prefix+|` / `prefix+-`) や新 window (`prefix+c`) で都度 `docker exec` を打つ手間を排除するため、各 session に `default-command` を設定して `scripts/tmux-docker-enter` wrapper を自動起動する:

```
tmux set-option -t <session> default-command "~/dotfiles/scripts/tmux-docker-enter <container>"
```

wrapper の挙動:

1. tmux pane の現在 cwd を取得
2. その cwd が container 内にも存在すれば `docker exec -w <cwd>` で同じディレクトリに入る
3. 存在しなければ container の WORKDIR で入る (エラーにしない)
4. container が停止している場合はホスト shell にフォールバック → pane が消えずに再接続可能

これにより、初回 `rcon` 後は pane 操作だけでスムーズに開発に入れる。

### cwd 引き継ぎの前提条件

pane 分割で元の cwd を引き継ぐには、**ホストとコンテナでプロジェクトパスが一致** している必要がある:

```bash
# docker run 時
docker run -v /home/user/proj:/home/user/proj ...
```

パスが異なる場合は wrapper の cwd チェックが失敗して container の WORKDIR フォールバックになる (動作はするが pane 毎に `cd` が必要)。

### Fallback 挙動

| 状況 | 挙動 |
|------|------|
| target = `host` (container なし) | ホストtmux に `main` セッション (or 指定 session) で直接入る |
| target = `host:container`, container 稼働中 | `tmux-docker-enter` で pane が container に入る |
| container が停止している | wrapper がホスト shell にフォールバック、`exit` 後に default-command 再実行 = コンテナ起動後に戻れる |
| session 名に `:` や `.` が含まれる | tmux 制限のため自動で `-` に sanitize される |

## 関連文書

- [rconセットアップ](rcon-setup.md)
- [tmux server再起動](tmux-server-restart.md)
- [No-Sudo Install Mode](../install/install-no-sudo.md)
