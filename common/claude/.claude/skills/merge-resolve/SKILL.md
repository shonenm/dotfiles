---
name: merge-resolve
description: Git merge/rebase のコンフリクトを解決し、3way diff レビュー用の状態を保存します。
user-invocable: true
arguments: "[<target>]"
---

# Merge Resolve - コンフリクト解決

Git merge/rebase で発生したコンフリクトを解決し、ユーザーが `merge-review` コマンドで 3way diff レビューできる状態にする。

## 引数

| 引数 | 説明 |
|------|------|
| (なし) | 既存のコンフリクト状態を検出して解決 |
| `<target>` | 指定ブランチをマージしてコンフリクトを解決 |

### 使用例

```bash
/merge-resolve                      # 既にコンフリクト中の場合
/merge-resolve origin/main          # origin/main をマージ
/merge-resolve feature/auth         # feature/auth をマージ
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

| 状況 | 判定 | 処理 |
|------|------|------|
| 引数あり + コンフリクトなし | 新規マージ | Step 2 (事前分析) から |
| 引数なし + コンフリクトあり | 既存コンフリクト | Step 4 (状態保存) から |
| 引数あり + コンフリクトあり | エラー | 既存コンフリクトを先に解決するよう案内 |
| 引数なし + コンフリクトなし | エラー | 引数が必要である旨を案内 |

### 2. 事前分析 (新規マージの場合のみ)

```bash
BASE=$(git merge-base HEAD <target>)
git log --oneline $BASE..HEAD              # ours の変更
git log --oneline $BASE..<target>          # theirs の変更
git diff --stat $BASE...<target>           # ファイル単位の差分
```

分析結果をサマリーとして出力する。

### 3. マージ実行 (新規マージの場合のみ)

```bash
git merge --no-commit <target>
```

コンフリクトがなければ完了報告して終了 (Step 8 へ)。

### 4. コンフリクト状態の保存

```bash
merge-save-states
```

コンフリクトファイルの base/ours/theirs を `/tmp/merge_review_*` に保存する。
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
# 新規マージの場合 (Step 2 で計算済み)
BASE=$(git merge-base HEAD <target>)

# 既存コンフリクトの場合 (状況に応じてフォールバック)
if git rev-parse --verify MERGE_HEAD &>/dev/null; then
  BASE=$(git merge-base HEAD MERGE_HEAD)
elif git rev-parse --verify REBASE_HEAD &>/dev/null; then
  BASE=$(git merge-base HEAD REBASE_HEAD)
elif git rev-parse --verify ORIG_HEAD &>/dev/null; then
  BASE=$(git merge-base HEAD ORIG_HEAD)
else
  # --onto 等で上記が全て失敗する場合は git log --merge で対象を特定
  BASE=""  # コンテキスト収集をスキップし、ファイル内容のみで解決
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

- `:1:(base)` / `:2:(ours)` / `:3:(theirs)` + 変更履歴から意図を理解して解決
- confidence level を判定:
  - `high`: 意図が明確で機械的に解決可能
  - `needs-review`: ロジック競合・判断が必要
- `needs-review` 箇所に `REVIEW:` インラインコメントを挿入 (言語の構文に合わせる)
- 解決後 `git add <file>`
- `git commit` / `git rebase --continue` は絶対に実行しない

REVIEW コメント構文:

| 拡張子 | 構文 |
|--------|------|
| `.ts`, `.js`, `.go`, `.rs`, `.java` 等 | `// REVIEW:` |
| `.py`, `.rb`, `.sh`, `.yaml` 等 | `# REVIEW:` |
| `.lua` | `-- REVIEW:` |
| `.html`, `.xml`, `.vue` 等 | `<!-- REVIEW: -->` |

### 7. 解決結果の検証

プロジェクトタイプを検出し、静的検証を実行する (副作用のないコマンドのみ)。

| 検出ファイル | 検証コマンド |
|-------------|-------------|
| `tsconfig.json` | `npx tsc --noEmit` |
| `Cargo.toml` | `cargo check` |
| `go.mod` | `go vet ./...` |
| `pyproject.toml` | `ruff check` / `mypy` |
| (該当なし) | `git diff --check` |

自動修正の境界:
- 自動修正する: import 文の整理、未使用 import の削除のみ
- 自動修正しない: 型エラー、ロジックエラー、その他一切。エラー内容を Step 8 の報告に含め、human review に委ねる

### 8. 完了報告 + rerere 記録

rebase 中かどうかを検出し、適切な次のステップを案内:

```bash
git rev-parse --verify REBASE_HEAD &>/dev/null  # true なら rebase 中
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
`merge-review` を実行してレビューしてください。
`REVIEW:` コメントが挿入されたファイルは重点的に確認してください。

レビュー用コマンド:
- merge の場合: `git diff HEAD MERGE_HEAD`
- rebase の場合: `git range-diff origin/main ORIG_HEAD HEAD`
- 共通: `git diff origin/main..HEAD`

rerere 管理:
- 解消パターン確認: `git rerere status`
- 誤った記録の削除: `git rerere forget <file>`
```

`git range-diff` 出力の読み方:
- `1: abc1234 = 1: def5678` — 変更なし (同一パッチ)
- `1: abc1234 ! 1: def5678` — パッチが変更された (diff が表示される)
- `1: abc1234 < -:` — 削除されたコミット
- `-: < 1: def5678` — 新規追加されたコミット

## 禁止事項

- `git commit` / `git rebase --continue` を実行すること
- `merge-save-states` をスキップすること
- コンフリクトを強引に片方で上書きすること (必ず根拠を示すこと)
