# opensessions

tmux セッション + AI エージェント状態を横断管理するサイドバープラグイン。

- Plugin: [Ataraxy-Labs/opensessions](https://github.com/Ataraxy-Labs/opensessions)
- Config: `common/opensessions/.config/opensessions/config.json`
- tmux 側: `common/tmux/.config/tmux/tmux.conf` の `set -g @plugin 'Ataraxy-Labs/opensessions'`
- 依存: `bun` (TPM が plugin 取得後、bun でランタイムを動かす)

## 役割

- **セッション一覧のサイドバー**: tmux session を縦に並べて `prefix+o → s` で focus、`prefix+o → 1-9` で直接切替
- **AI エージェント状態の可視化**: Claude Code / Codex / Amp / OpenCode の状態 (idle/running/done/error 等) を session 単位で集計
- **Thread (instance) 追跡**: 同一 session 内で複数 AI instance が走っていれば thread として区別
- **Git 情報**: session の cwd の branch / dirty / worktree 状態
- **Port 検知**: session 内で listening している localhost port をクリックで開ける

## データモデル (重要)

**セッションが最小単位**。window / pane は count として表示されるだけで、状態集計の軸にはならない。

watcher は以下の対応関係で動く:

```
ファイルシステムの transcript (例: ~/.claude/projects/<encoded-dir>/*.jsonl)
  → projectDir を抽出
  → resolveSession(projectDir) でtmux session に解決
  → そのsessionに status/thread 情報を紐付け
```

`resolveSession` は tmux session 作成時の `dir` (cwd) を照合するので:

- **同じ cwd で起動された session** のみ正しく紐付く
- 同一 session 内の別 window で別 project を開いていると、片方はsidebarに出ない

## 運用方針 (本 dotfiles 環境)

### 1 コンテナ = 1 セッション

`rcon ailab:syntopic-dev` で起動した tmux session は名前 `syntopic-dev`、cwd がcontainerのプロジェクトパスになる。opensessions サイドバーには container 毎に1行並ぶ。複数プロジェクトを扱う場合は **別コンテナ = 別 session** に分ける。

### 同プロジェクトの並列作業 = 同 session 内の別 window

1プロジェクトで Claude を並列起動する場合 (ralph-parallel 等) は、同じ session の別 window で走らせる。watcher が threadId で区別して detail panel に instance リストとして並ぶ。

### 避けるべきパターン

- 1つの session 内で `cd /other/proj` して別プロジェクトの Claude を起動 → `resolveSession` が最初の projectDir しかマッチしないため、2つ目以降は sidebar に出ない
- host tmux と container 内 tmux を二重起動して両方で opensessions を有効化 → watcher が二元化して状態が分散

## AI エージェント監視の要件

watcher が読むファイルパス:

| Agent | Path |
|-------|------|
| Claude Code | `~/.claude/projects/*.jsonl` |
| Codex | `~/.codex/sessions/` |
| Amp | `~/.local/share/amp/threads/` |
| OpenCode | `~/.local/share/opencode/opencode.db` |

opensessions はホスト側 tmux サーバー内で動くため、これらのファイルも **ホスト側** から見える必要がある。Docker コンテナ内で Claude を動かす場合は volume mount が必須:

```bash
docker run \
  -v ~/.claude:/root/.claude \
  -v ~/.codex:/root/.codex \
  ...
```

これによりコンテナ内で生成された JSONL / transcript がホスト側 opensessions から読み取れる。

## rcon との連携

`rcon host:container` コマンドで起動する tmux session は、opensessions に以下として現れる:

- **名前**: container 名 (`:` / `.` は `-` に sanitize)
- **cwd**: `tmux-docker-enter` で container に入った際の初期パス (プロジェクトディレクトリを bind mount していれば host と一致)
- **default-command**: 各 pane/window が `tmux-docker-enter` 経由で container に入る
- **エージェント状態**: container 内で起動された Claude/Codex の JSONL が ホスト `~/.claude` で見えていれば sidebar に反映

詳細は [rcon.md](./rcon.md)。

## Programmatic API (補足)

HTTP 経由で status / progress / log を push 可能 (`127.0.0.1:7391`):

```sh
curl -X POST http://127.0.0.1:7391/set-status \
  -H 'content-type: application/json' \
  -d '{"session":"syntopic-dev","text":"Deploying","tone":"warn"}'
```

ralph-crew 等の自動化から状態を可視化したい場合に使用する。

## Troubleshooting

### session がサイドバーに現れない

- `prefix+o → r` で手動 refresh
- tmux session の `dir` が watcher の projectDir 候補と一致するか確認:
  ```bash
  tmux list-sessions -F '#{session_name} #{session_path}'
  ```

### agent status が更新されない

- ホスト側の JSONL パスに実際にファイルがあるか確認
- コンテナ内で生成されたものなら volume mount を点検
- `~/.claude/projects/` の encoded directory 名は cwd を特殊エンコードしたもの (`-` 区切り)

### サイドバーが消える / 表示崩れ

- `prefix+o → t` でトグル
- ヒューリスティック復帰しないときは `opensessions` プロセスを再起動:
  ```bash
  pkill -f opensessions
  ```
  次回 tmux reload 時に自動再起動

## 関連

- [tmux.md](./tmux.md) — tmux 全般
- [rcon.md](./rcon.md) — host tmux + docker exec パターン
- [ralph.md](./ralph.md) — 自律ループとAI agent状態連携
