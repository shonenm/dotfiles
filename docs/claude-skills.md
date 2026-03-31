# Claude Code Skills

Claude Code で使用可能なカスタムスキルのリファレンス。

## スキル一覧

| スキル | 説明 |
|--------|------|
| `/beacon` | Aerospace ワークスペースに環境を紐付け |
| `/commit` | セッション内の変更を分析してコミット作成 |
| `/news` | プロファイルベースのパーソナライズドニュース収集 |
| `/update-md` | セッション内の変更に関連するドキュメント更新 |

Ralph 系スキルは [`ralph.md`](ralph.md) を参照。

## /beacon

現在の環境を Aerospace ワークスペースに紐付けます。通知バッジを正しいワークスペースに表示するために使用します。

### 使い方

```
/beacon <workspace_number>
```

### 例

```
/beacon 3
```

現在の git リポジトリ（または pwd）をワークスペース 3 に登録します。

### 保存先

`~/.local/share/claude/workspace_map.json`:

```json
{
  "/Users/matsushimakouta/dotfiles": {
    "workspace": "3",
    "registered_at": "1768789301"
  }
}
```

### いつ使うか

- 新しいリポジトリで Claude を初めて起動した時
- 通知を正しいワークスペースに表示したい時

詳細は [`claude-beacon.md`](claude-beacon.md) を参照。

## /commit

現在のセッションで行った変更を分析し、適切なコミットメッセージで git commit を作成します。

### 使い方

```bash
/commit                      # セッション内の変更のみ
/commit all                  # 全ての未コミット変更
/commit src/                 # セッション内の src/ の変更のみ
/commit all src/             # src/ の全変更
/commit file.ts utils.ts     # 特定ファイル（セッション内）
/commit all common/nvim/     # ディレクトリの全変更
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

## /news

`~/.claude/news-profile.yaml` に基づいてパーソナライズドニュースを収集します。

### 使い方

```
/news           # 過去1週間（デフォルト）
/news day       # 過去24時間
/news month     # 過去1ヶ月
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

## /update-md

現在のセッションで行った変更に関連する markdown ドキュメントを更新または作成します。

### 使い方

```
/update-md
```

引数なし。セッション内の変更を自動で分析します。

### 対象ドキュメント

- `docs/neovim.md` - Neovim 設定の変更
- `docs/tmux.md` - tmux 設定の変更
- `docs/git-config.md` - Git 設定の変更
- `docs/zsh-startup-optimization.md` - Zsh 設定の変更
- `docs/modern-cli-tools.md` - CLI ツールの追加・変更
- `docs/1password-integration.md` - 1Password 連携の変更
- `docs/starship.md` - Starship 設定の変更
- `docs/sketchybar-aerospace.md` - SketchyBar/Aerospace 設定の変更
- `docs/database.md` - データベース関連の変更
- `docs/claude-*.md` - Claude Code 関連の変更
- `docs/install.md` - インストール手順の変更
- `docs/patches/*.md` - パッチ・ワークアラウンドの説明
- `docs/troubleshooting/*.md` - トラブルシューティング情報

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

- [Ralph Pattern](ralph.md) - 自律開発ループ (`/ralph`, `/ralph-plan`, `/ralph-cancel`, `/ralph-resume`, `/ralph-parallel`)
- [Claude Development](claude-development.md) - 開発環境・ツール全般
- [Claude Beacon](claude-beacon.md) - 通知システム
