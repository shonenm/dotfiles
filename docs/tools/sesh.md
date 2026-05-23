# sesh

ファジーファインダー型の tmux セッションマネージャー。zoxide / ghq / 既存 tmux セッションを横断して fuzzy 検索し、新規セッション作成または既存セッション切替を1アクションで行う「tmux のコマンドパレット」。

- Plugin: [joshmedeski/sesh](https://github.com/joshmedeski/sesh)
- Config: `common/sesh/.config/sesh/sesh.toml`
- Install (Mac): `brew "joshmedeski/sesh/sesh"` (`config/Brewfile`)
- Install (Linux): `TOOL_sesh_*` in `config/tools.linux.bash` — GitHub release tarball を `~/.local/bin` (NO_SUDO モード) or `/usr/local/bin` に展開

## 役割分担

| 手段 | 対象 | 用途 |
|------|------|------|
| `prefix s` (choose-tree -O name) | ローカル tmux session (名前順) | 既存セッションの一覧閲覧と切替 |
| `prefix Tab` (switch-client -l) | 直前のローカル session | sesh 非依存の素の tmux トグル |
| `prefix L` (sesh last) | 直前の session (sesh 履歴) | picker 経由の履歴も拾う sesh 版 last |
| `prefix ( / )` (switch-client -p/-n) | ローカル session (名前順) | 隣接セッションへの巡回 |
| `prefix f` (tmux-session-color.sh) | ローカル session のみ | 色付き fzf picker + プレビュー |
| **`prefix C-f` (sesh)** | **config + tmux + zoxide + fd 横断** | **多段フィルタ popup (公式 README 流)** |
| **`Alt-s` (zsh widget)** | 同上、シェルから起動 | tmux 外からでも sesh へ |
| opensessions サイドバー | ローカル session + AI agent 状態 | 永続的に見える横型一覧 + AI 状態可視化 |

sesh の強みは「セッションが存在しない場合は zoxide/wildcard から新規作成する」機能。既存セッション切替のみなら `prefix s` / `prefix f` / opensessions サイドバーで十分。

## tmux 側の土台

`common/tmux/.config/tmux/tmux.conf` に入れてある sesh 運用の前提:

```tmux
set -g detach-on-destroy off   # セッション閉鎖時に tmux から放り出されない (sesh last 必須条件)

bind L run-shell "sesh last || tmux display-message -d 1000 'Only one session'"
bind C-f display-popup -E -w 80% -h 70% '...多段フィルタ popup...'
```

`detach-on-destroy off` が無いとセッションを閉じた際に tmux クライアント自体が終了してしまい、`sesh last` で戻る体験が成立しない。

## 多段フィルタ popup のキー

`prefix C-f` で popup を開いた後、popup 内で以下のキーでソースを切替:

| キー | プロンプト | フィルタ |
|------|-----------|----------|
| `Ctrl-a` | ⚡ | すべて (default) |
| `Ctrl-t` | 🪟 | tmux sessions のみ |
| `Ctrl-g` | ⚙️ | sesh.toml の config entries のみ |
| `Ctrl-x` | 📁 | zoxide ディレクトリのみ |
| `Ctrl-f` | 🔎 | `fd` で `$HOME` 以下のディレクトリ検索 |
| `Ctrl-d` |   | 現在ハイライト中の session を `tmux kill-session` |
| `Tab` / `Shift+Tab` |   | 次/前の候補へ |
| `Enter` |   | 選択して attach/connect |

## 設定

### ソース順序と基本

```toml
#:schema https://github.com/joshmedeski/sesh/raw/main/sesh.schema.json

sort_order = ["config", "tmux", "zoxide"]
dir_length = 2
cache = true                 # v2 の 5 秒 TTL キャッシュ (popup 連打時に効く)
blacklist = ["scratch"]      # popup/scratch セッションをリストから除外

[default_session]
preview_command = "eza --all --git --icons --color=always {}"
```

- `#:schema` ディレクティブで taplo LSP の補完と検証が効く
- `dir_length = 2` で同名プロジェクト区別 (`projects/sesh` vs `tools/sesh`)
- `blacklist` には dotfiles 環境で使う一時セッション名 (`scratch` は `prefix j` の scratchpad) を入れる

### 固定エントリ (最小限)

命名規約 (`pers-*` など) を守りたい頻用 path だけ `[[session]]` で定義。

```toml
[[session]]
name = "pers-dotfiles"
path = "~/dotfiles"

[[session]]
name = "pers-config"
path = "~/.config"
```

### ワイルドカード (プロジェクト群を丸ごと)

ghq 配下のリポジトリと `~/workspace` の作業ディレクトリを丸ごと拾う。新しく `ghq get` で増えたプロジェクトも自動で picker に現れる。

```toml
[[wildcard]]
pattern = "~/ghq/github.com/*/*"

[[wildcard]]
pattern = "~/workspace/*"
```

### startup_script によるプロジェクトブートストラップ

`startup_command` は session が新規作成されたときに実行される1行コマンド、または実行可能スクリプトへのパス。`common/sesh/.config/sesh/scripts/` に典型的なレイアウト用スクリプトを用意している (新規シェル script は `chmod +x` 必須)。

| スクリプト | 用途 |
|-----------|------|
| `generic-project.sh` | Git 状態を表示してから nvim を起動（単一ペイン、軽量） |
| `node-project.sh`    | 上下 2 ペイン: 上 nvim / 下 30% で `npm run dev` 待機 |

設定例:

```toml
# 全ての dotfiles セッションでは generic-project.sh を走らせる
[[session]]
name = "pers-dotfiles"
path = "~/dotfiles"
startup_command = "~/.config/sesh/scripts/generic-project.sh"

# 特定の Node プロジェクトだけ node-project.sh を適用
[[wildcard]]
pattern = "~/ghq/github.com/shonenm/my-node-app"
startup_command = "~/.config/sesh/scripts/node-project.sh"
```

ポイント:

- **再 attach では走らない**: `startup_command` は "create" 時のみ。既存セッションに戻っても副作用なし
- **`--command/-c` 経由では走らない**: `sesh connect -c "..."` のように `--command` を渡すとスキップされるため、picker から普通に接続するのが前提
- **より重いセットアップは別スクリプト化**: `scripts/` 配下に複数テンプレートを置いて使い分ける。プロジェクト固有のセットアップが必要になったら `[[session]]` で `startup_command` を指定

### zoxide を育てる

sesh の `zoxide` ソースは `zoxide` の頻度スコア順で並ぶため、zoxide のデータベースを意図的に育てると picker の有用性が上がる:

- プロジェクトディレクトリには必ず一度 `cd` で入る (`cd` は zoxide に alias 済み: `zoxide init zsh --cmd cd`)
- 浅いがよく飛ぶ場所 (`~/Downloads`, `~/.config/*`) も意識的に cd しておく

## シェル側バインド (Alt-s)

`common/zsh/.zshrc.common` に zle widget を登録している。

```zsh
bindkey '\es' sesh-sessions  # Alt-s
```

- tmux 内: `prefix+C-f` と同じ体験を prefix なしで (1 チョード)
- tmux 外: ターミナルを新規で開いた直後、`tmux attach` 前に `Alt-s` で直接 sesh picker → 既存 session に attach

## git worktree + Claude Code 並列実行

dotfiles には [`scripts/wt`](../scripts/wt) (git worktree + tmux window 統合 CLI) が同梱されている。`wt new feat/login` で `<main>--wt--<slug>` 形式のサイドカーディレクトリを作り、現在 session の **新規 window** を開いてそこに cd する仕組み。

sesh 側には下記のワイルドカードを入れており、既存の `wt` で作られた worktree ディレクトリはそのまま sesh picker に現れる:

```toml
[[wildcard]]
pattern = "~/*--wt--*"

[[wildcard]]
pattern = "~/ghq/github.com/*/*--wt--*"
```

### 運用パターン

| 目的 | 手順 |
|------|------|
| 同一 session で並列作業 (window per worktree) | `wt new <branch>` — 既存の `wt` フロー、高速。opensessions サイドバーでは 1 session として集約 |
| 独立 session で並列 Claude Code | `wt new <branch>` で worktree を作った後、`prefix C-f` → ワイルドカード経由で **別 session** として attach。各 worktree が独立した opensessions 行になる |
| worktree から親プロジェクトへ戻る | `prefix 9` → `sesh connect --root`。現在の `pane_current_path` を sesh に渡し、親相当の session にジャンプ |

### Claude Code 自動起動 (opt-in)

特定の worktree で Claude を毎回自動起動したい場合、sesh.toml に `startup_command = "claude"` を付けたワイルドカードを追加する:

```toml
[[wildcard]]
pattern = "~/*--wt--*"
startup_command = "claude"
```

ただし全 worktree で強制されると非 Claude ワークでも claude プロセスが立つため、デフォルトでは未適用 (コメント例のみ)。`ralph-parallel` 等で強制したい場合だけ opt-in。

## rcon との関係

sesh はローカル tmux サーバーでのみ動作する。rcon で接続する remote tmux のセッションは local sesh の対象外。remote 側でも sesh を使いたい場合は、接続先ホストに個別に sesh をインストールする (別 Phase)。

## Troubleshooting

### `prefix L` が効かない (セッション間で戻れない)

- `tmux show-options -g detach-on-destroy` が `off` になっているか確認
- セッションが 1 個しかないと `Only one session` メッセージが 1 秒表示される (正常)

### `[[session]]` に定義したエントリが picker に出ない

- `sesh list -c` で config エントリのみ表示して TOML が読み込めているか確認
- シンリンクが張れているか: `ls -la ~/.config/sesh/sesh.toml`
- `sort_order` に `config` が含まれているか

### wildcard に定義した path が picker に出ない

- そのディレクトリに一度 `cd` したか (内部的に globbing + zoxide に似た解決)
- `sesh list` で出ない場合は `sesh list -c` と `sesh list -z` を個別に確認

### zoxide 候補が少ない

- `zoxide query -l` でスコア順のディレクトリ一覧を確認
- 一度も cd していないディレクトリは出ない

### popup 内で誤って session を kill した

- `Ctrl-d` でアクティブ session を kill している。復元するには sesh 経由で再作成
- 惜しいなら `tmux-resurrect` で直近の save 時点から復元可能

## 関連

- [tmux.md](./tmux.md) — tmux 全般 + Phase 1 の session 命名規約とキーバインド
- [opensessions.md](./opensessions.md) — 常駐型サイドバー + AI agent 状態監視
