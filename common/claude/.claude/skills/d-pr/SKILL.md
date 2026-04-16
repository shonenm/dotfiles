---
name: d-pr
description: 変更を分析して PR を作成します。AI がリッチな PR 本文を生成します。
user-invocable: true
arguments: "<options>"
argument-hint: "[--draft] [--base <branch>]"
when_to_use: "Use when the user asks to create a pull request, open a PR, or submit changes for review."
hooks:
  PreToolUse:
    - matcher: "AskUserQuestion"
      hooks:
        - type: command
          command: "echo '{\"decision\":\"block\",\"reason\":\"Do not ask for confirmation — generate the PR body and create it directly.\"}' && exit 2"
---

# PR - Pull Request 作成 (変更分析付き)

現在のブランチの変更を分析し、リッチな PR 本文を生成して PR を作成します。
`gf` と同じブランチ命名規約 (`<issue番号>-<slug>`) を使用するため、相互に互換性があります。

## 引数

| 引数 | 説明 |
|------|------|
| (なし) | 通常の PR を作成 |
| `--draft` | Draft PR を作成 |
| `--base <branch>` | ベースブランチを指定 (デフォルト: リポジトリのデフォルトブランチ) |

### 使用例

```bash
/pr
/pr --draft
/pr --base develop
/pr --draft --base release/v2
```

## 手順

### 1. 前提条件チェック

以下を順にチェックし、問題があれば案内して終了:

1. `gh auth status` - GitHub CLI の認証状態
2. ベースブランチの決定と現在のブランチの確認:
   ```bash
   # --base 指定があればそれを使用、なければデフォルトブランチを検出
   base_branch=${BASE_ARG:-$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')}
   current_branch=$(git branch --show-current)
   ```
   ベースブランチ上なら「作業ブランチ上で実行してください」とエラー
3. uncommitted changes がないこと (`git status --porcelain`):
   未コミットの変更がある場合 → `/d-commit` を先に実行するよう提案して終了
4. 既存 PR の確認:
   ```bash
   gh pr view --json url 2>/dev/null
   ```
   既に PR が存在する場合 → 既存 PR の URL を表示して終了

### 2. Issue 番号の抽出

ブランチ名の先頭から Issue 番号を抽出:

```bash
issue_num=$(echo "$current_branch" | grep -oE '^[0-9]+')
```

- 抽出できた場合: Issue 紐づきの PR として進行
- 抽出できない場合: ユーザーに「Issue なしで PR を作成しますか？」と確認

### 3. 変更の分析

以下のコマンドを並列で実行:

- `git log --oneline ${base_branch}..HEAD` - コミット一覧
- `git diff --stat ${base_branch}..HEAD` - 変更ファイル統計
- `git diff ${base_branch}..HEAD` - 全差分
- Issue がある場合: `gh issue view <N> --json title,body,labels` - Issue 情報
- PR テンプレートの検出:
  ```bash
  # 以下の順で探索し、最初に見つかったものを使用
  # 1. .github/pull_request_template.md
  # 2. .github/PULL_REQUEST_TEMPLATE.md
  # 3. .github/PULL_REQUEST_TEMPLATE/ ディレクトリ内の .md ファイル (デフォルトテンプレート)
  # 4. docs/pull_request_template.md
  # 5. pull_request_template.md (リポジトリルート)
  ```

### 4. PR タイトル・本文の生成

分析結果をもとに以下を生成:

- タイトル: 70文字以内、変更の要約 (Issue がある場合は Issue タイトルも参考にする)
- 本文:
  - PR テンプレートが見つかった場合: テンプレートの構造 (セクション見出し、チェックリスト等) を維持し、各セクションを変更内容に基づいて埋める
  - テンプレートがない場合のデフォルト構成:
    ```markdown
    ## Summary
    <変更の概要 1-3行>

    ## Changes
    - <変更点1>
    - <変更点2>

    ## Test plan
    - [ ] <テスト計画1>
    - [ ] <テスト計画2>

    Closes #<issue_number>
    ```
  - Issue がない場合は `Closes #N` 行を省略

生成した内容をそのまま使用して PR を作成する（確認不要）。

### 5. PR の作成

1. 未 push の場合、ブランチを push:
   ```bash
   git push -u origin "$current_branch"
   ```
2. PR を作成:
   ```bash
   gh pr create --title "<title>" --body "<body>" --base "<base_branch>" [--draft] [--label "<labels>"]
   ```
   - `--base` は常に指定 (検出またはユーザー指定のベースブランチ)
   - `--draft` は引数で指定された場合のみ付与
   - ラベルは Issue のラベルがあればそれを引き継ぐ

### 6. 完了報告

以下の情報を報告:

- PR URL
- 紐づく Issue (ある場合)

## エッジケース

- `gh auth status` で認証チェック → 未認証なら `gh auth login` を案内して終了
- uncommitted changes がある場合 → `/d-commit` を先に実行するよう提案して終了
- 既に同一ブランチの PR が存在する場合 → 既存 PR の URL を表示して終了
- main ブランチ上で実行した場合 → エラーメッセージを表示して終了
- Issue 番号がブランチ名にない場合 → Issue なしで PR を作成

## 注意事項

- `git push` は PR 作成に必要な場合のみ実行する
- PR 本文は変更の実態に基づいて生成する (推測しない)
- `Closes #N` は Issue が紐づく場合のみ含める
