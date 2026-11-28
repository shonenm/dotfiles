# タスク進捗表示 (task-progress)

> **由来:** **Upstream** Claude Code の Task ツール・mod API / **Configuration** `templates/claude-settings.json` の `CLAUDE_CODE_ENABLE_TODO_TOOLS` / **Custom** `claude-plugins/task-progress/`（[区分](../../provenance.md#区分)）

複数 PR・複数ステップにまたがる作業で、全体の何番目まで進んだかをプロンプトの上に常時表示する Claude Code の mod。正本は Claude Code 標準のタスク一覧（TaskCreate / TaskUpdate）で、mod はその呼び出しを見て表示を更新する。別の状態を持たないため同期の必要がない。

## 表示と操作

- プロンプトの上に進捗バー、`完了数/総数`、作業中のタスク名を表示する（例: `████░░░░ 2/7  ▸ PR2: ペイン描画`）。ゲージは進捗 1/3 未満で赤、2/3 未満で黄、完了前で水色、完了で緑
- `Ctrl+T` またはバー横の「一覧」で全タスクのチェックリストを開閉する（`[x]` 完了 / `[>]` 作業中 / `[ ]` 未着手）。`/task-list` でも同じ
- タスクが 0 件のときは何も表示しない

## 利用の促し

- システムプロンプトに「複数 PR・複数ステップの作業は着手前に TaskCreate で分解する」指示を常に追加する
- タスクが 1 件もないまま 3 回目の編集（Edit / Write / NotebookEdit）をしようとすると、セッションにつき 1 回だけ拒否して分解を促す。サブエージェントの編集は数えない
- 作業中のタスクがあるのに、編集した turn で一度もタスクを更新せずに終えようとすると 1 回だけ差し戻す。調査だけの turn は対象外

## 明示的な登録

`/d-tasks` で、会話で決めた計画やロードマップを PR 単位のタスクに分解して登録できる（[スキル](claude-skills.md#d-tasks)）。

## 導入

`install.sh` の `install_dotfiles_claude_plugins` が `claude-plugins/` を folder marketplace `dotfiles` として登録し、`task-progress@dotfiles` を導入する。相対 source の plugin は folder から直接読まれるため、編集後は `/reload-plugins` で反映される。

タスクツールは一部のモデルで既定無効のため、`templates/claude-settings.json` の `env` で `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` を設定する。

## 開発

```bash
claude plugin validate claude-plugins/task-progress
claude plugin test claude-plugins/task-progress
```

読み込み時に生成される `.claude-plugin/types/` は `claude-plugins/.gitignore` で除外している。
