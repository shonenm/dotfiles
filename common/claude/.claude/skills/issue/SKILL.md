---
name: issue
description: GitHub Issue を作成し、作業ブランチを準備します。AI がリッチな Issue 本文を生成します。
user-invocable: true
arguments: "<title-or-description>"
argument-hint: "<title-or-description>"
when_to_use: "Use when the user wants to file a bug report, feature request, or task as a GitHub Issue and prepare a working branch for it."
hooks:
  PreToolUse:
    - matcher: "AskUserQuestion"
      hooks:
        - type: command
          command: "echo '{\"decision\":\"block\",\"reason\":\"Do not ask for confirmation — generate the issue body and create it directly.\"}' && exit 2"
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

生成した内容をそのまま使用して Issue を作成する（確認不要）。

### 4. Issue の作成

```bash
gh issue create --title "<title>" --body "<body>" --assignee @me [--label "<label1>,<label2>"]
```

### 5. ブランチの準備

1. ブランチ名を生成 (`<issue番号>-<slug>`):
   - タイトルを小文字化、スペースをハイフンに、英数字とハイフンのみ残す、50文字制限
2. `gh issue develop` でブランチ作成 + Issue への紐づけ:
   ```bash
   gh issue develop <issue_number> --name "<branch_name>" --checkout
   ```
   - リモートにブランチが作成され、Issue の Development セクションに自動紐づけされる
   - `--checkout` でローカルにチェックアウトされる

### 6. 完了報告

以下の情報を報告:

- Issue URL
- ブランチ名
- 次のステップの案内 (実装 → `/commit` → `/pr`)

## エッジケース

- `gh auth status` で認証チェック → 未認証なら `gh auth login` を案内して終了
- uncommitted changes がある場合 → stash するか `/commit` を先に実行するよう提案
- 既にデフォルトブランチ以外にいる場合 → `gh issue develop` はリモートのデフォルトブランチから作成するため問題なし

## 注意事項

- `gh issue develop` はリモートにブランチを作成する (Issue 紐づけに必要)
- テンプレートがある場合はテンプレートの構造を尊重する
- ラベルの存在しないものを指定しない (`gh label list` の結果のみ使用)
