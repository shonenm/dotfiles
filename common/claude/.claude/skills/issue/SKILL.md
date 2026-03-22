---
name: issue
description: GitHub Issue を作成し、作業ブランチを準備します。AI がリッチな Issue 本文を生成します。
user-invocable: true
arguments: "<title-or-description>"
---

# Issue - GitHub Issue 作成 + ブランチ準備

引数をもとに GitHub Issue を作成し、作業ブランチを準備します。
`gf start` と同じブランチ命名規約 (`<issue番号>-<slug>`) を使用するため、相互に互換性があります。

## 引数

| 引数 | 説明 |
|------|------|
| `<title-or-description>` | Issue のタイトルまたは詳細な説明文 |

### 使用例

```bash
/issue Add logout button
/issue ログインページでセッション切れ時にリダイレクトされない問題を修正する
```

## 手順

### 1. 引数の解析

- 短い文 (概ね10語以下): そのまま Issue タイトルとして使用
- 長い文 / 複数文: タイトルを生成し、元の文を本文の概要に活用

### 2. リポジトリ情報の収集

以下のコマンドを並列で実行:

- `gh label list --json name,description` - 利用可能なラベル一覧
- `ls .github/ISSUE_TEMPLATE/ 2>/dev/null` - Issue テンプレートの有無
- `git log --oneline -10` - 直近の開発コンテキスト

### 3. Issue タイトル・本文・ラベルの生成

収集した情報をもとに以下を生成:

- タイトル: 簡潔で明確な英語 (命令形推奨)
- 本文:
  - テンプレートがあればそれに従う
  - なければ最小構成:
    ```markdown
    ## Overview
    <概要 1-3行>

    ## Acceptance criteria
    - [ ] <受入条件1>
    - [ ] <受入条件2>
    ```
- ラベル: 該当するものがあれば付与 (なければ省略)

生成した内容をユーザーに提示し、確認を求める。

### 4. Issue の作成

```bash
gh issue create --title "<title>" --body "<body>" [--label "<label1>,<label2>"]
```

### 5. ブランチの準備

1. デフォルトブランチを検出:
   ```bash
   default_branch=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   ```
2. デフォルトブランチに移動して最新を取得:
   ```bash
   git checkout "$default_branch"
   git pull --rebase
   ```
3. ブランチ名を生成 (`<issue番号>-<slug>`):
   - タイトルを小文字化、スペースをハイフンに、英数字とハイフンのみ残す、50文字制限
4. ブランチ作成:
   ```bash
   git checkout -b "<branch_name>"
   ```

### 6. 完了報告

以下の情報を報告:

- Issue URL
- ブランチ名
- 次のステップの案内 (実装 → `/commit` → `/pr`)

## エッジケース

- `gh auth status` で認証チェック → 未認証なら `gh auth login` を案内して終了
- uncommitted changes がある場合 → stash するか `/commit` を先に実行するよう提案
- 既にデフォルトブランチ以外にいる場合 → 確認してからデフォルトブランチに移動

## 注意事項

- `git push` は実行しない (ブランチ作成のみ)
- テンプレートがある場合はテンプレートの構造を尊重する
- ラベルの存在しないものを指定しない (`gh label list` の結果のみ使用)
