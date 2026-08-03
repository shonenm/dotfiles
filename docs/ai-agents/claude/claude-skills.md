# Claude Code Skills

> **由来:** **Upstream** Claude Code Skills仕様 / **Plugin** 外部plugin由来skill / **Configuration** 配置・共有設定 / **Custom** d-* skills（[区分](../../provenance.md#区分)）

Claude Code で使用可能なカスタムスキルのリファレンス。

## スキル一覧

| スキル | 説明 |
|--------|------|
| `/d-beacon` | AeroSpace ワークスペースに環境を紐付け |
| `/d-commit` | セッション内の変更を分析してコミット作成 |
| `/d-diff-explain` | hunk 単位の解説つき差分ビュー HTML を生成 |
| `/d-news` | プロファイルベースのパーソナライズドニュース収集 |
| `/d-setup-rcon-target` | rcon ターゲットの登録 + 接続検証 + docker mount スニペット生成 |
| `/d-update-md` | セッション内の変更に関連するドキュメント更新 |

Ralph系スキルは[Ralph概要](../ralph/overview.md)を参照。

## /d-beacon

現在の環境を AeroSpace ワークスペースに紐付けます。通知バッジを正しいワークスペースに表示するために使用します。

### 使い方

```
/d-beacon <workspace_number>
```

### 例

```
/d-beacon 3
```

現在の git リポジトリ（または pwd）をワークスペース 3 に登録します。

### 保存先

`~/.local/share/claude/workspace_map.json`:

```json
{
  "~/dotfiles": {
    "workspace": "3",
    "registered_at": "1768789301"
  }
}
```

### いつ使うか

- 新しいリポジトリで Claude を初めて起動した時
- 通知を正しいワークスペースに表示したい時

詳細は [`claude-beacon.md`](claude-beacon.md) を参照。

## /d-commit

現在のセッションで行った変更を分析し、適切なコミットメッセージで git commit を作成します。

### 使い方

```bash
/d-commit                      # セッション内の変更のみ
/d-commit all                  # 全ての未コミット変更
/d-commit src/                 # セッション内の src/ の変更のみ
/d-commit all src/             # src/ の全変更
/d-commit file.ts utils.ts     # 特定ファイル（セッション内）
/d-commit all common/nvim/     # ディレクトリの全変更
```

### コミットメッセージフォーマット

`prefix(scope): description`

| Prefix | 用途 |
|--------|------|
| `feat` | 新機能 |
| `imprv` | 既存機能の改善 |
| `fix` | バグ修正 |
| `rfac` | リファクタリング |
| `docs` | ドキュメント |
| `chore` | ビルド・CI・その他 |

### 動作

1. `git status` と `git diff` で変更を確認
2. `git log` で最近のコミットメッセージのスタイルを学習
3. 変更内容を分析してコミットメッセージを生成
4. 適切なファイルを `git add` してコミット作成

### 注意

- `.env`, `credentials.json` 等のシークレットファイルは自動で除外
- `git push` は実行しない（手動で push が必要）

## /d-diff-explain

git diff の hunk ごとに Claude が解説を書き、解説つきの差分ビュー HTML を生成してブラウザで開きます。実装理解、レビュー準備、引き継ぎ資料に使います。

### 使い方

```bash
/d-diff-explain                          # main...HEAD
/d-diff-explain HEAD~3                   # 直近 3 コミット
/d-diff-explain main...feature -- src/   # 範囲とパスを指定
```

### 動作

1. `diff-explain hunks <引数>` で hunk ID (`<path>#<連番>`) 付きの diff を取得
2. 必要に応じて周辺コードを読み、hunk ごとの解説 JSON を `$TMPDIR` に書く
3. `diff-explain render -e <json> --open <引数>` で HTML を生成してブラウザで開く

### diff-explain コマンド

スキルを介さず単体でも使えます（解説なしの差分ビューとして）。

```bash
diff-explain hunks [--split N] [<git diff の引数>...]
diff-explain render -e explain.json [-o out.html] [--open] [--split N] [<git diff の引数>...]
```

`--split`（既定 40 行）は長い hunk をトップレベル定義の直前で擬似 hunk に分割し、新規ファイルでも解説を細かく付けられるようにします。`hunks` と `render` は同じ値で分割する必要があります（hunk ID がずれるため）。`0` で無効。

`explain.json` の形式:

```json
{
  "title": "見出し",
  "overview": "全体の解説",
  "files": {"path/to/file.ts": "ファイル単位の解説"},
  "hunks": {"path/to/file.ts#1": "hunk の解説"}
}
```

### remote での利用

remote（rcon 接続先のホストやコンテナ）でも dotfiles を stow していればそのまま動きますが、ブラウザが無いため `--open` は無効化され、代わりにローカルでの取得方法が案内されます。ローカル側から取りに行きます。

```bash
diff-explain-open <host>[:<container>]              # 最新の HTML を取得して開く
diff-explain-open ailab:myproject-dev ~/.cache/diff-explain/x.html   # パス明示
```

`ssh`（コンテナ指定時は `docker exec` 経由）で HTML を吸い出し、ローカルの一時ディレクトリに置いて `open` / `xdg-open` します。ターゲット指定は rcon の `~/.config/rcon/targets` と同じ `host` / `host:container` 形式。単一 HTML なので転送はこれだけで完結します（`diff-explain render -o -` で stdout に出せるため、別の転送手段に差し替えることもできます）。

差分は左右 2 カラム（左が変更前、右が変更後）で表示します。連続する削除行と追加行を順に突き合わせるだけの対応付けなので、片側しかない行は反対側が空欄になります。

出力先の既定は `$XDG_CACHE_HOME/diff-explain/<repo>-<timestamp>.html`。シンタックスハイライトは highlight.js を CDN から読むため、オフラインでは色が付かないだけで表示自体は保たれます（行単位で解析するため、複数行文字列やブロックコメントの色は正確ではありません）。

## /d-news

`~/.claude/news-profile.yaml` に基づいてパーソナライズドニュースを収集します。

### 使い方

```
/d-news           # 過去1週間（デフォルト）
/d-news day       # 過去24時間
/d-news month     # 過去1ヶ月
```

### プロファイル設定

`~/.claude/news-profile.yaml`:

```yaml
personal:
  name: "Your Name"
  company: "Your Company"
  role: "Backend Engineer"
  location: "Tokyo, Japan"

interests:
  technical:
    - "Rust language"
    - "Neovim ecosystem"
  industry:
    - "developer tools"
  companies:
    - "Anthropic"
```

### 処理フロー

1. プロファイルを読み込み、興味分野ごとに 5-8 個の検索クエリを生成
2. WebSearch で情報源を収集し、関連性でフィルタ
3. 上位 5-8 記事を WebFetch で要約
4. カテゴリ別（Technical / Industry / Companies / Serendipity）にまとめて出力

### 制約

- WebSearch: 5-10 回
- WebFetch: 5-8 回
- プロファイル未設定時はテンプレートを表示して終了

### プロファイルテンプレート

`common/claude/.claude/news-profile.example.yaml` を `~/.claude/news-profile.yaml` にコピーして編集。

## /d-setup-rcon-target

新しい rcon ターゲット (リモートホスト or ホスト + docker container) を登録し、接続前提条件を検証する。

### 使い方

```
/d-setup-rcon-target chronos
/d-setup-rcon-target chronos:myproject-dev
/d-setup-rcon-target ailab:another-container
```

### 動作

1. `~/.config/rcon/targets` に target を追記 (冪等)
2. SSH 疎通確認 (`ssh -o BatchMode=yes <host> true`)
3. リモート側の dotfiles / tmux / `scripts/tmux-docker-enter` の存在確認
4. container 指定時: docker 上の存在確認 + 必須 volume mount (`~/.claude`, `~/.codex`, `~/.local/share/amp`, プロジェクトパス) の diff
5. 不足している mount は docker-compose / docker run の追記スニペットとして出力

### 前提

- Mac: zsh + `rcon` コマンドが有効 (`common/zsh/.zshrc.common`)
- リモート: dotfiles install済 (`~/dotfiles` に clone + `./install.sh [--no-sudo]`)
- container: docker daemon と docker CLI 利用可能

詳細は[rconセットアップ](../../infrastructure/rcon-setup.md)。

## /d-update-md

現在のセッションで行った変更に関連する markdown ドキュメントを更新または作成します。

### 使い方

```
/d-update-md
```

引数なし。セッション内の変更を自動で分析します。

### 対象ドキュメント

- `docs/tools/` - Neovim、tmux、Zsh、Starshipなど
- `docs/configuration/` - Git、1Password、CLI、AeroSpace / SketchyBar
- `docs/infrastructure/` - database、rcon、同期、gateway
- `docs/ai-agents/claude/` - Claude Code
- `docs/install/` - install手順
- `docs/tools/neovim/patches/` - Neovim patch
- `docs/troubleshooting/` - 問題解決手順

### 更新基準

**更新する**:
- 新しい機能・プラグインの追加
- 既存機能の大幅な変更
- 新しいキーバインドの追加
- 新しいコマンド・ワークフローの追加
- 依存関係の追加・削除
- パッチ・ワークアラウンドの追加

**更新しない**:
- バグ修正のみ（ドキュメントに影響しない）
- 内部リファクタリング（外部動作に変更なし）
- コメントの追加・修正のみ
- 既にドキュメント化済みの機能の微調整

### 動作

1. セッション内の変更（Edit/Write ツールの履歴）を振り返る
2. 関連するドキュメントを特定
3. 更新が必要か判断
4. 必要なら既存のフォーマットに従って更新
5. 不要なら理由を説明して終了

### 注意

- セッション内の変更のみが対象（`git diff` は使わない）
- コミットは行わない（ユーザーが別途コミット）
- 既存のトーンとスタイルを維持

## 関連ドキュメント

- [Ralph Pattern](../ralph/overview.md) - 自律開発ループ (`/d-ralph`, `/d-ralph-plan`, `/d-ralph-cancel`, `/d-ralph-resume`, `/d-ralph-parallel`)
- [Claude Development](claude-development.md) - 開発環境・ツール全般
- [Claude Beacon](claude-beacon.md) - 通知システム
