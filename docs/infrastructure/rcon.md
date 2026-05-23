# rcon - リモート接続ツール

SSH + ホスト側 tmux + Docker をワンコマンドで接続するツール。

## 現在の実装

`common/zsh/.zshrc.common` 内のシェル関数として実装。

```bash
rcon                      # fzf でターゲット選択
rcon ailab:syntopic-dev   # host:container 形式で直接指定
rcon pi-500               # host のみ（コンテナなし）
rcon pi-500 dev           # tmux セッション名を明示指定
```

### 設定ファイル

`~/.config/rcon/targets` に1行1ターゲットで記載:

```
ailab:syntopic-dev
ailab:another-container
pi-500
```

### アーキテクチャ

2026-04 に設計変更: tmux をリモートホスト側で **1サーバーに集約** し、各 session が docker container に対応する形に移行した。

```
Ghostty
  └─ ssh host
      └─ tmux (ホスト側、1 server)
          ├─ session "syntopic-dev"      → docker exec -it syntopic-dev
          ├─ session "another-container" → docker exec -it another-container
          └─ session "main"              → ホスト shell (container なし target)
```

以前は `SSH → docker exec → container内でtmux` という構成で、コンテナ毎に別 tmux サーバーが立っていた。新構成の利点:

- **opensessions が1サーバーで全 container を監視**: サイドバーに container 単位でセッションが並ぶ
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

## 将来の拡張計画

### 別リポジトリ化の検討（2025-02調査済み）

シェル関数から Go 製 CLI への移行を検討。

#### 動機

- ET/Mosh/SSH のトランスポート切り替え
- TOML 設定ファイルによる高度な設定
- 接続履歴・統計機能

#### 想定される構成

```
rcon/
├── cmd/rcon/main.go
├── config/           # TOML設定読み込み
├── transport/        # ssh, mosh, et の抽象化
├── history/          # 接続履歴（SQLite or JSON）
└── README.md
```

#### 設定ファイルイメージ（TOML）

```toml
[defaults]
transport = "ssh"  # ssh | mosh | et
tmux_session = "main"

[[targets]]
name = "ailab-dev"
host = "ailab"
container = "syntopic-dev"
transport = "et"  # オーバーライド可能

[[targets]]
name = "pi-500"
host = "pi-500"
# container なし = ホスト直接
```

#### 類似ツール調査結果

| ツール | 特徴 | rcon との違い |
|--------|------|--------------|
| [intmux](https://github.com/dsummersl/intmux) | Python製、SSH+Docker+tmux | マルチホスト同時接続向け |
| [sshmx](https://github.com/mrbooshehri/sshmx) | Bash製、SSH管理特化 | Docker 非対応 |
| [DevPod](https://github.com/loft-sh/devpod) | devcontainer.json ベース | IDE統合前提で重い |
| [Eternal Terminal](https://eternalterminal.dev/) | 永続接続 | Docker exec 統合なし |
| [Mosh](https://mosh.org/) | UDP永続接続 | Docker exec 統合なし |

完全に代替できるツールがないため、自前実装の価値あり。

#### 実装言語の選定理由（Go）

- シングルバイナリでクロスプラットフォーム対応
- [Go SSH SDK](https://pkg.go.dev/golang.org/x/crypto/ssh) が充実
- TOML パース、SQLite 操作が標準的
- dotfiles のポータビリティ方針に合致

#### 移行ステップ

1. 別リポジトリ `rcon` を作成
2. 最小限の Go 実装（現在のシェル関数と同等機能）
3. 段階的に設定ファイル・履歴機能を追加
4. dotfiles からはバイナリを PATH に置くか `go install` で導入
