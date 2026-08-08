---
name: github-delegate
description: read-onlyの設計・レビュー・調査をサブエージェントへ委譲します。repository編集は親sessionに残します。
user-invocable: true
arguments: "<task-description> [high|medium|low]"
---

# Delegate - サブエージェント委譲

## 手順

1. タスクの難易度を判定（high=設計/レビュー/デバッグ、medium=調査、low=要約/抽出）
2. Piではadvisory・調査に`subagent`、pueue backgroundが必要な場合だけ`delegate_agent`を使う
3. Codexではnative subagentを使う
4. PiのWeb検索が利用不能な場合は、検索だけを次で委譲する

```sh
codex --search exec --skip-git-repo-check --ephemeral \
  -c model_reasoning_effort=medium \
  "<self-contained research task; require primary-source URLs and exact quotes>"
```

5. 結果を親セッションで検証・統合する。repositoryへの編集は親だけが行う

## 注意事項

- 独立したread-onlyタスクだけを並列化する
- 親セッションの履歴は渡らないため、必要な背景と期待する出力を明記する
- Codexではnative Web検索とnative subagentを用途に応じて使い分ける
