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

コンフリクトがなければ完了報告して終了 (Step 6 へ)。

### 4. コンフリクト状態の保存

```bash
merge-save-states
```

コンフリクトファイルの base/ours/theirs を `/tmp/merge_review_*` に保存する。
既にユーザーが merge/rebase を実行してコンフリクト状態にある場合も、このステップは必須。

### 5. コンフリクト解決

- 各コンフリクトファイルについて `:1:(base) / :2:(ours) / :3:(theirs)` を参照
- 両方の変更意図を分析して解決方針を決定
- 解決後 `git add <file>`
- `git commit` / `git rebase --continue` は絶対に実行しない

### 6. 完了報告

rebase 中かどうかを検出し、適切な次のステップを案内:

```bash
git rev-parse --verify REBASE_HEAD &>/dev/null  # true なら rebase 中
```

以下の形式で報告する:

```
## マージ完了 (レビュー待ち)

### 自動マージされたファイル
- path/to/file.ts

### コンフリクト解決ファイル
#### path/to/conflict.ts
- ours: (変更内容の説明)
- theirs: (変更内容の説明)
- 解決方針: (どう解決したかの説明)

### 次のステップ
`merge-review` を実行してレビューしてください。
```

## 禁止事項

- `git commit` / `git rebase --continue` を実行すること
- `merge-save-states` をスキップすること
- コンフリクトを強引に片方で上書きすること (必ず根拠を示すこと)
