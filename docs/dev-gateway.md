# dev-gateway

リモートホスト上に Traefik を 1 つ立て、複数 docker container への HTTP/HTTPS 入口を 1 port に集約する個人インフラ。

## 解決する問題

- 並列に立てる開発環境 (git worktree, ブランチ別 stack 等) を増やすたびに、ローカルから専用 port forward を追加しないといけない
- 管理 UI ごとに forward を増やしている
- VPN 切断時の復旧コストが forward 本数に比例

## 仕組み

```
[ローカル]                       [リモート]
  ssh -L 48080 ─────────────────► Traefik :48080 (TCP SNI passthrough, HTTPS)
  ssh -L 48081 ─────────────────► Traefik :48081 (HTTP, 管理 UI 用)
  ssh -L 48090 ─────────────────► Traefik :48090 (dashboard / API)
                                     │
                                     ├── (HTTPS) upstream nginx A (SNI: *-foo.localhost)
                                     ├── (HTTPS) upstream nginx B (SNI: *-bar.localhost)
                                     ├── (HTTP)  ui-x.dev.localhost  → container x:port
                                     ├── (HTTP)  ui-y.dev.localhost  → container y:port
                                     └── ...
```

- Traefik は docker socket を read-only で watch し、`traefik.enable=true` label が付いた container を自動でルート化
- HTTPS は upstream 側で TLS 終端 → Traefik は ClientHello の SNI で振り分け (mkcert 等で発行した `*.localhost` 証明書をそのまま使える)
- HTTP は Traefik で HTTP router 集約。`name.dev.localhost:48081` のような subdomain でアクセス
- TCP 独自プロトコル (postgres, redis 系, debugger 等) は Traefik を経由せず個別 forward (Traefik の TCP routing は SNI が必要なため)

## 配置

dotfiles 内:
- `common/traefik-dev/.config/traefik-dev/compose.yml` — Traefik コンテナ定義
- `common/traefik-dev/.config/traefik-dev/traefik.yml` — static config
- `scripts/dev-gateway` — ローカルから操作する CLI
- `scripts/dev-gateway-lib.sh` — 共通ロジック

リモート側に dotfiles を stow すると、`~/.config/traefik-dev/` が出現する。

## 初回セットアップ

リモートに対して 1 度だけ実行 (sudo 不要、ユーザーが `docker` group 所属である必要):

```sh
# ローカルから:
dev-gateway up <host-alias>     # 自動で `docker network create dev-edge` も実行
```

`~/.config/traefik-dev/compose.yml` が立ち上がる。

## アプリ側でやること (Traefik にぶら下げる)

### HTTPS upstream を SNI passthrough で受ける場合

upstream nginx (アプリ側プロキシ) を `dev-edge` ネットワークに参加させ、label を付与:

```yaml
services:
  nginx:
    networks:
      - default
      - dev-edge
    labels:
      traefik.enable: "true"
      traefik.docker.network: "dev-edge"
      traefik.tcp.routers.<name>.rule: "HostSNI(`*-<name>.localhost`)"
      traefik.tcp.routers.<name>.tls.passthrough: "true"
      traefik.tcp.routers.<name>.entrypoints: "websecure"
      traefik.tcp.services.<name>.loadbalancer.server.port: "443"
networks:
  dev-edge:
    external: true
```

### HTTP コンテナを subdomain で公開する場合

```yaml
services:
  some-ui:
    labels:
      traefik.enable: "true"
      traefik.docker.network: "dev-edge"
      traefik.http.routers.some-ui.rule: "Host(`some-ui.dev.localhost`)"
      traefik.http.routers.some-ui.entrypoints: "web"
      traefik.http.services.some-ui.loadbalancer.server.port: "3000"
    networks:
      - default
      - dev-edge
networks:
  dev-edge:
    external: true
```

## ローカル側 DNS

- Chrome / Firefox: `*.localhost` は自動で 127.0.0.1 に解決される (RFC 6761)
- Safari: 解決しないので dnsmasq 推奨
  - `brew install dnsmasq`
  - `address=/.localhost/127.0.0.1` を追加

## 使い方

```sh
dev-gateway up      <host>            # 起動
dev-gateway status  <host>            # コンテナ状態
dev-gateway routes  <host>            # 現在登録されているルート一覧
dev-gateway logs    <host> [service]  # Traefik ログ追従
dev-gateway reload  <host>            # Traefik 再起動
dev-gateway down    <host>            # 停止

# 環境変数でデフォルト host を渡す:
export DEV_GATEWAY_DEFAULT_HOST=<host-alias>
dev-gateway up
dev-gateway routes
```

## トラブルシュート

- routes が空: `traefik.enable=true` label が付いた container が起動していないか、Traefik と同じ docker network に参加していない
- 対象 URL にアクセスできない: `dev-tunnel status` で ssh 健全性確認 → `dev-gateway status` で Traefik 健全性確認 → `dev-gateway routes` で対象ルートの存在確認
- HTTPS 証明書エラー: upstream 側の `*.localhost` 証明書が SAN にアクセスホスト名を含んでいるか確認

## 関連

- `dev-tunnel`: ローカルから本 gateway への 1 本 forward を autossh で堅牢化
