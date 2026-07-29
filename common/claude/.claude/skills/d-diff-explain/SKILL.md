---
name: d-diff-explain
description: git diff の各 hunk に解説を書き、リッチな差分ビュー HTML を生成してブラウザで開きます。実装理解・レビュー準備・引き継ぎ資料に使います。
user-invocable: true
arguments: "[<rev-range>] [-- <path>...]"
argument-hint: "[<rev-range>] [-- <path>...]"
when_to_use: "Use when the user wants to understand what a change does — 'この差分を解説して', '実装を理解したい', 'PR の内容を説明する HTML が欲しい'. Do NOT use for reviewing code quality (that is /d-hunk-review) or for writing PR descriptions (/d-pr)."
---

# Diff Explain - 解説つき差分ビュー生成

`scripts/diff-explain` (PATH 上の `diff-explain`) と組み合わせ、diff の hunk 単位に解説を添えた HTML を生成する。

## 手順

1. **範囲の決定**: 引数をそのまま `git diff` の引数として使う。引数なしの場合は `main...HEAD`（デフォルトブランチとの差分）。差分が空ならその旨を伝えて終了。

2. **差分の取得**: `diff-explain hunks <引数>` を実行する。出力は hunk ID (`<path>#<連番>`) 付きの unified diff。

3. **文脈の把握**: diff だけで意図が読めない箇所は、Read/Grep で周辺の実装や呼び出し元を確認する。推測で解説を書かない。

4. **解説の作成**: `$TMPDIR/diff-explain-<任意名>.json` に以下を書く。

   ```json
   {
     "title": "この変更の見出し",
     "overview": "変更全体の目的と設計の要約",
     "files": {"path/to/file.ts": "このファイルが担う役割と変更の位置づけ"},
     "hunks": {"path/to/file.ts#1": "この hunk の解説"}
   }
   ```

   - `hunks` の ID は手順 2 の出力そのまま。存在しない ID は render 時に warning が出る
   - `files` と `overview` は任意。`hunks` は原則すべての hunk を埋める
   - 書式は素のテキスト。`` `code` `` のみインラインコードとして描画される

5. **解説の書き方**: 読者は「その実装を理解したい人」。
   - diff を日本語に訳すだけの解説は書かない（`x を y に変更` は見れば分かる）
   - なぜその変更が必要か、どういう仕組みで動くか、どこと繋がっているかを書く
   - 前提知識（API の挙動、フレームワークの制約など）は補って書く
   - 意図が読み切れない箇所は断定せず「〜と思われる」と明示する
   - 機械的な変更（lockfile、フォーマット、リネーム）はまとめて 1 行で済ませる

6. **生成と確認**: `diff-explain render -e <json> --open <引数>` を実行し、出力パスを報告する。warning が出たら hunk ID を直して再実行する。

## remote で実行する場合

`SSH_CONNECTION` が設定されている環境では `--open` を付けてもブラウザは開かない（開けない）。生成後、ユーザーにローカル側で以下を実行するよう伝える。

```bash
diff-explain-open <host>[:<container>]      # 最新の HTML を取得して開く
```

`<host>[:<container>]` は rcon の targets と同じ形式。remote 側のパスを明示したい場合は第 2 引数に渡す。

## 注意

- 大量の hunk がある場合は `-- <path>` で範囲を絞るか、対象を分けて複数回生成することをユーザーに提案する
- lockfile など機械生成物は `-- . ':(exclude)*lock*'` のようなパススペックで除外してよい
- HTML の出力先は `$XDG_CACHE_HOME/diff-explain/`（`-o` で変更可）
