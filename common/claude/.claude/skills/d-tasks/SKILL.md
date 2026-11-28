---
name: d-tasks
description: 会話で決めた計画やロードマップを PR 単位のタスクに分解し、Claude Code のタスク一覧に登録します。task-progress mod がプロンプトの上に進捗を表示します。
user-invocable: true
arguments: "[reset] [<計画テキスト | ファイルパス>]"
argument-hint: "[reset] [<計画 | path>]"
when_to_use: "Use when the user asks to set up, register, or reset the task list for multi-PR or multi-step work ('タスク登録して', 'PRごとに分けて進捗出して')."
---

# Tasks - 作業をタスク一覧に登録

複数 PR・複数ステップにまたがる作業を、TaskCreate でタスク一覧に登録する。表示は task-progress mod が行う（バーは常時、全項目は Ctrl+T か `/task-list`）。

## 引数

| 引数 | 説明 |
|------|------|
| (なし) | この会話で合意した計画を登録する |
| `<計画テキスト>` | 渡された内容を登録する |
| `<ファイルパス>` | ロードマップ等のファイルを読んで登録する |
| `reset` | 既存の未完了タスクを削除してから登録する |

## 手順

1. TaskList で既存タスクを確認する。未完了タスクがあり `reset` がなければ、追加するか置き換えるかをユーザーに確認する。`reset` なら未完了タスクを TaskUpdate の `status: "deleted"` で消す
2. 登録元を決める: 引数のテキスト、引数のファイル、この会話で合意した計画の順。どれもなく計画が読み取れなければ、作業内容をユーザーに確認して止まる
3. 分解する
   - PR が複数なら 1 PR = 1 タスク。subject は `PR<n>: <内容>`（例: `PR1: スキーマ追加`）
   - PR が 1 つなら、レビュー可能な単位のステップで分ける
   - 順序は着手順。依存があれば TaskUpdate の `addBlockedBy` で表す
   - description にはスコープと完了条件を 1〜2 行で書く。会話にない要件を足さない
4. 登録した一覧（番号・subject）を短く報告し、Ctrl+T または `/task-list` で全体を見られることを伝える

## 登録後の運用

- 着手したタスクを `in_progress`、PR を作成またはマージ条件を満たしたら `completed` にする
- 計画が変わったら subject を更新するか、タスクを追加・削除する。黙って一覧と実作業をずらさない
