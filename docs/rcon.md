# rcon - リモート接続ツール

SSH + Docker + tmux をワンコマンドで接続するツール。

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
