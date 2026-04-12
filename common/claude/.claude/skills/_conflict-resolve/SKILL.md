---
name: _conflict-resolve
description: Git merge/rebase のコンフリクトを解決し、3way diff レビュー用の状態を保存します。
user-invocable: true
arguments: "[<target>] [--rebase]"
---

# Conflict Resolve - コンフリクト解決

Git merge/rebase で発生したコンフリクトを解決し、ユーザーが `conflict-review` コマンドで 3way diff レビューできる状態にする。

## 引数

| 引数 | 説明 |
|------|------|
| (なし) | 既存のコンフリクト状態を検出して解決 |
| `<target>` | 指定ブランチをマージしてコンフリクトを解決 |
| `--rebase` | `<target>` と組み合わせて rebase モードで解決 |

### 使用例

```bash
/conflict-resolve                           # 既にコンフリクト中の場合
/conflict-resolve origin/main               # origin/main をマージ
/conflict-resolve feature/auth              # feature/auth をマージ
/conflict-resolve origin/main --rebase      # origin/main に rebase
```

## 手順

### 1. 状況判定

現在の Git 状態を確認して処理を分岐:

```bash
# コンフリクト中かどうかを確認
CONFLICT_FILES=$(git diff --name-only --diff-filter=U)

# rebase 中かどうかを確認
git rev-parse --verify REBASE_HEAD &>/dev/null
```

#### merge モード (--rebase なし)

| 状況 | 判定 | 処理 |
|------|------|------|
| 引数あり + コンフリクトなし | 新規マージ | Step 2 (事前分析) から |
| 引数なし + コンフリクトあり | 既存コンフリクト | Step 4 (状態保存) から |
| 引数あり + コンフリクトあり | エラー | 既存コンフリクトを先に解決するよう案内 |
| 引数なし + コンフリクトなし | エラー | 引数が必要である旨を案内 |

#### rebase モード (--rebase あり)

| 状況 | 判定 | 処理 |
|------|------|------|
| --rebase + target あり + コンフリクトなし | 新規 rebase | Step 2r (事前分析 - rebase) から |
| --rebase + target なし | エラー | --rebase には target が必要 |
| --rebase + コンフリクトあり | エラー | 既存コンフリクトを先に解決するよう案内 |

### 2. 事前分析 (新規マージの場合のみ)

```bash
BASE=$(git merge-base HEAD <target>)
git log --oneline $BASE..HEAD              # ours の変更
git log --oneline $BASE..<target>          # theirs の変更
git diff --stat $BASE...<target>           # ファイル単位の差分
```

分析結果をサマリーとして出力する。

### 2r. 事前分析 (新規 rebase の場合のみ)

```bash
BASE=$(git merge-base HEAD <target>)
git log --oneline $BASE..HEAD              # rebase 対象のコミット群
git log --oneline $BASE..<target>          # target の変更
git diff --stat $BASE...<target>           # ファイル単位の差分
```

分析結果をサマリーとして出力する。

### 3. マージ実行 (新規マージの場合のみ)

```bash
git merge --no-commit <target>
```

コンフリクトがなければ完了報告して終了 (Step 8 へ)。

### 3r. rebase 実行 (新規 rebase の場合のみ)

```bash
# 1. .git/info/attributes に一時書き込み (rebase 全体が完了するまで維持する)
mkdir -p .git/info
echo '* merge=conflict-driver' >> .git/info/attributes

# 2. rebase 実行
git rebase <target>
```

重要な注意点:
- conflict-driver が自動で各コミットのコンフリクトを解消する
- conflict-driver が失敗 (exit 1) した場合、git rebase が停止する
- 停止時は手動コンフリクト解決フローに入る (Step 4 → 5 → 6 → 6r)
- `.git/info/attributes` は rebase 全体が完了するまで削除しない (Step 8r でクリーンアップ)

### 4. コンフリクト状態の保存

```bash
conflict-save
```

コンフリクトファイルの base/ours/theirs をセッションディレクトリに保存する。
セッションディレクトリは worktree 単位でスコープされる (`/tmp/conflict_session/<git-dir-hash>/`)。
既にユーザーが merge/rebase を実行してコンフリクト状態にある場合も、このステップは必須。

### 5. Trivial コンフリクト処理

complex な解決に入る前に、機械的に処理できるコンフリクトを先に片付ける。

| 分類 | 判定条件 | 解決方法 |
|------|----------|----------|
| lock file | `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock` 等 | 下記の 3 ステップで解決 |
| import 整理 | コンフリクト範囲が import/require/use 文のみ | 両方の import をマージ |
| whitespace | 空行・インデントのみの差分 | theirs を採用 |

lock file の解決手順:
1. ours 側の内容で確定して stage する (`git checkout --ours <file> && git add <file>`)
2. 再生成コマンドをユーザーに提示し、実行の確認を取る (副作用があるため自動実行しない)
3. 確認後に再生成を実行し、改めて `git add <file>`

再生成コマンド例:
- `npm install` / `yarn install` / `pnpm install` → `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml`
- `cargo generate-lockfile` → `Cargo.lock`

### 6. コンテキスト収集 + コンフリクト解決

#### 6a. BASE の計算

```bash
# 新規マージ / 新規 rebase の場合 (Step 2 / 2r で計算済み)
BASE=$(git merge-base HEAD <target>)

# 既存コンフリクトの場合 (状況に応じてフォールバック)
if git rev-parse --verify MERGE_HEAD &>/dev/null; then
  BASE=$(git merge-base HEAD MERGE_HEAD)
elif git rev-parse --verify REBASE_HEAD &>/dev/null; then
  BASE=$(git merge-base HEAD REBASE_HEAD)
elif git rev-parse --verify ORIG_HEAD &>/dev/null; then
  BASE=$(git merge-base HEAD ORIG_HEAD)
else
  # --onto 等で上記が全て失敗する場合
  BASE=""  # コンテキスト収集をスキップ。Step 8 の報告に「変更履歴なしで解決」と記載する
fi
```

#### 6b. ファイルごとのコンテキスト収集 (解決前に実行)

```bash
# BASE が取得できた場合のみ
git log --oneline $BASE..HEAD -- <file>          # ours の変更理由

# theirs の変更理由: 操作種別に応じた ref を使用
# - merge:       git log --oneline $BASE..MERGE_HEAD -- <file>
# - rebase:      git log --oneline $BASE..REBASE_HEAD -- <file>
#                (REBASE_HEAD が存在しなければ ORIG_HEAD)
# - cherry-pick: git log --oneline $BASE..CHERRY_PICK_HEAD -- <file>
# - 新規マージ:  git log --oneline $BASE..<target> -- <file>
```

- 関連テストファイルの特定 (`*.test.*`, `*.spec.*`, `__tests__/`, `*_test.*`)

#### 6c. 解決の実行

解決原則:

- デフォルトは needs-review。high confidence は機械的に判定できるケースのみ:
  - import の整理・追加のみ
  - whitespace / フォーマットのみ
  - 独立した機能追加 (両方が異なる箇所を変更)
  - コメントの追加のみ
- 機能の保全を最優先する
  - 片方が削除/スタブ化し、もう片方が実装を持つ場合、実装を保持する
  - `throw new Error('not implemented')` や空実装への置き換えは、必ず needs-review
- 削除 vs 変更 は常に needs-review
  - 「リファクタリングで移動した」可能性を考慮し、移動先を確認してから判断する
- 設定ファイル・ドキュメントは加算的にマージする
- アーキテクチャ変更 vs 機能追加
  - 新機能のロジックを新アーキテクチャのパターンに適応させて保持する
  - 適応が自明でない場合は needs-review にし、旧実装をコメントとして残す
- エラーハンドリング・ビジネスロジックの削除は needs-review

- `:1:(base)` / `:2:(ours)` / `:3:(theirs)` + 変更履歴から意図を理解して解決
- confidence level を判定:
  - `high`: import整理、whitespace、独立した追加、コメントのみの場合に限定
  - `needs-review`: 上記以外すべて。特に:
    - 片方の変更が削除/スタブ化されている
    - アーキテクチャパターンの変更を跨ぐ解決
    - ビジネスロジックに影響
    - 関数・クラス・エクスポートの削除を含む
- `needs-review` 箇所に `REVIEW:` インラインコメントを挿入 (言語の構文に合わせる)
- 解決後 `git add <file>`
- merge/cherry-pick モード: `git commit` は実行しない (ユーザーがレビュー後に実行)
- rebase モード: Step 6r へ進む

REVIEW コメント構文:

| 拡張子 | 構文 |
|--------|------|
| `.ts`, `.js`, `.go`, `.rs`, `.java` 等 | `// REVIEW:` |
| `.py`, `.rb`, `.sh`, `.yaml` 等 | `# REVIEW:` |
| `.lua` | `-- REVIEW:` |
| `.html`, `.xml`, `.vue` 等 | `<!-- REVIEW: -->` |

### 6r. rebase 継続ループ (rebase モードのみ)

全コンフリクトを `git add` した後、rebase を継続する。

```bash
GIT_EDITOR=true git rebase --continue
```

- 次のコミットでもコンフリクトが発生したら Step 4 に戻る
- 全コミットが完了するまでこのループを繰り返す
- rebase 完了後は Step 7 → Step 8r へ進む

lock file の rebase 中の扱い:
- `pnpm-lock.yaml` 等が繰り返しコンフリクトする場合、`.git/info/attributes` に `pnpm-lock.yaml merge=ours` を追加して自動解決する
- rebase 完了後に再生成する

### 7. 解決結果の検証

rebase モードでは rebase 全体が完了した後にのみ実行する (中間コミットでは実行しない)。

プロジェクトタイプを検出し、静的検証を実行する (副作用のないコマンドのみ)。

| 検出ファイル | 検証コマンド |
|-------------|-------------|
| `tsconfig.json` | `npx tsc --noEmit` |
| `Cargo.toml` | `cargo check` |
| `go.mod` | `go vet ./...` |
| `pyproject.toml` | `ruff check` / `mypy` |
| (該当なし) | `git diff --check` |

自動修正の境界:
- 自動修正する: import 文の整理、未使用 import の削除、未使用変数の削除 (明らかにコンフリクト解決の副産物に限る)
- 自動修正しない: 型エラー、ロジックエラー、その他一切。エラー内容を Step 8 の報告に含め、human review に委ねる

### 8. 完了報告 + rerere 記録

rebase 中かどうかを検出し、適切な次のステップを案内:

```bash
git rev-parse --verify REBASE_HEAD &>/dev/null  # true なら rebase 中

# デフォルトブランチを動的に検出 (レビューコマンドで使用)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
```

rerere による解消パターンの記録:

```bash
git rerere            # 解消パターンの記録確認
git rerere status     # rerere が追跡中のファイル一覧
git rerere forget <file>  # 誤った解消パターンを削除
```

以下の形式で報告する:

```
## マージ完了 (レビュー待ち)

### Trivial 解決
- path/to/package-lock.json (lock file: ours で確定済み、再生成が必要)
- path/to/imports.ts (import 整理: 両方をマージ)

### コンフリクト解決 (high confidence)
#### path/to/file.ts
- ours: (変更内容の説明)
- theirs: (変更内容の説明)
- 解決方針: (どう解決したかの説明)

### コンフリクト解決 (needs-review)
#### path/to/complex.ts
- ours: (変更内容の説明)
- theirs: (変更内容の説明)
- 解決方針: (どう解決したかの説明)
- REVIEW: コメントを挿入済み

### 自動マージされたファイル
- path/to/auto.ts

### 検証結果
- `npx tsc --noEmit`: pass
- 未解決のエラー: (あれば詳細)

### 次のステップ
`conflict-review` を実行してレビューしてください。
`REVIEW:` コメントが挿入されたファイルは重点的に確認してください。

rebase 完了後のレビュー:
- `rebase-review <target>` を実行して、conflict-driver が解消したコミットをレビュー
  (例: `rebase-review origin/develop`。引数省略時は reflog から自動検出)

レビュー用コマンド (デフォルトブランチは動的に検出して置換する):
- merge の場合: `git diff HEAD MERGE_HEAD`
- rebase の場合: `git range-diff origin/<default-branch> ORIG_HEAD HEAD`
- 共通: `git diff origin/<default-branch>..HEAD`

rerere 管理:
- 解消パターン確認: `git rerere status`
- 誤った記録の削除: `git rerere forget <file>`

### rerere
- rerere キャッシュに記録済み (同一パターン再発時は自動適用)
```

### 8r. rebase 完了処理 (rebase モードのみ)

rebase が全コミット完了した後に実行する。

```bash
# 1. .git/info/attributes をクリーンアップ
sed -i '/merge=conflict-driver/d' .git/info/attributes
sed -i '/merge=ours/d' .git/info/attributes

# 2. stale REBASE_HEAD のクリーンアップ
# git の rebase 完了処理で REBASE_HEAD pseudo-ref の削除が漏れることがある
# (custom merge driver + 手動解決の組み合わせで発生する edge case)
GIT_DIR="$(git rev-parse --git-dir)"
if [[ -f "${GIT_DIR}/REBASE_HEAD" ]] && \
   [[ ! -d "${GIT_DIR}/rebase-merge" ]] && \
   [[ ! -d "${GIT_DIR}/rebase-apply" ]]; then
  rm -f "${GIT_DIR}/REBASE_HEAD"
fi

# 3. 検証 (Step 7)
# 4. rerere 記録
# 5. 完了報告 (Step 8 の形式)
```

`git range-diff` の活用:

rebase はコミットごとにコンフリクトを解決するため、最終 diff だけでは各コミットでの解決の根拠が失われる。`git range-diff` を使うことで「rebase 前後で各コミットに何が起きたか」を差分として確認できる。

出力の読み方:
- `1: abc1234 = 1: def5678` — コンフリクトなし。スキップ可
- `1: abc1234 ! 1: def5678` — 解決が入った。重点レビュー対象
- `1: abc1234 < -:` — 削除されたコミット
- `-: < 1: def5678` — 新規追加されたコミット

`!` マークのコミットのみ重点的にレビューすることで、merge の一括レビューと同等の効率を保ちながら、コミット意図と解決の対応関係を確認できる。

## 禁止事項

- merge/cherry-pick モードで `git commit` を実行すること (ユーザーがレビュー後に実行)
- `conflict-save` をスキップすること
- コンフリクトを強引に片方で上書きすること (必ず根拠を示すこと)

注意: rebase モードでは `GIT_EDITOR=true git rebase --continue` の実行は必須 (Step 6r)。
