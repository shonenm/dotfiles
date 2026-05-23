# dev-tunnel

VPN 経由のリモート開発で発生する port forward の脆弱性を、autossh + ControlMaster で解消する個人ツール。

## 解決する問題

- VPN 切断や WiFi 切替で全 ssh forward が一斉に死ぬ
- 切れた際に手動で全 forward を貼り直す手間
- 起動忘れ

## 仕組み

- `autossh` が ssh セッション全体を監視し、ServerAliveInterval=30 で死活判定
- 死んだ場合は ssh プロセスごと再起動 → ControlMaster 経由でぶら下がる全 forward が一括復活
- forward の定義は ssh 側 (`~/.ssh/config` の `LocalForward`) に置き、dev-tunnel は autossh プロセス管理に専念
- PID は `~/.local/state/dev-tunnel/<host>.pid`、ログは `~/.local/state/dev-tunnel/logs/<host>.log`

## ssh config の推奨エントリ

`~/.ssh/config` 本体は dotfiles 管理だが、host 固有エントリは `~/.ssh/config.d/` に置く (環境固有のため)。
`Include ~/.ssh/config.d/*` が `~/.ssh/config` で読み込まれる前提。

テンプレ (`~/.ssh/config.d/<your-file>`):

```
Host <your-host-alias>
  HostName <remote-hostname-or-ip>
  User <your-user>
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ExitOnForwardFailure yes
  # dev-gateway 用 (Traefik) は 1 本に集約
  LocalForward 48080 127.0.0.1:48080
  LocalForward 48081 127.0.0.1:48081
  LocalForward 48090 127.0.0.1:48090
  # TCP プロトコル (Traefik 不向き) は個別に並べる。必要なものだけ。
  # LocalForward 5432 127.0.0.1:5432   # postgres
  # LocalForward 7687 127.0.0.1:7687   # bolt 等
```

ControlPath ディレクトリは事前に作成: `mkdir -p ~/.ssh/sockets`

## 使い方

```sh
# 引数で host 指定
dev-tunnel start <host-alias>
dev-tunnel status <host-alias>
dev-tunnel restart <host-alias>
dev-tunnel health <host-alias>
dev-tunnel stop <host-alias>

# 環境変数でデフォルト host を渡す方法も可
export DEV_TUNNEL_DEFAULT_HOST=<host-alias>
dev-tunnel start
dev-tunnel status
```

複数 host を扱う場合:

```sh
dev-tunnel start home-lab
dev-tunnel start work-vpn
dev-tunnel status home-lab
```

## トラブルシュート

- 起動するが forward されない: ssh config の `ExitOnForwardFailure=yes` で起動時にエラー → ログ (`~/.local/state/dev-tunnel/logs/<host>.log`) を確認
- ControlMaster が "not connected": autossh は生きているが ssh セッションが再接続中。ServerAliveInterval (30s) 後に復活するはず
- pid file が残っているのにプロセスがない: `dev-tunnel stop` で消える、または pid file を手で削除
- VPN 切断検知が遅い: ServerAliveInterval / ServerAliveCountMax を短くする (例: 10/2 で 20 秒で検知)

## 依存

- `autossh` (mac: `brew install autossh`、linux: `apt install autossh`)
  - dotfiles の `config/Brewfile` と `config/packages.linux.apt.txt` に追加済

## 関連

- `dev-gateway`: リモート側の Traefik 管理 (forward 1 本化の相方)
