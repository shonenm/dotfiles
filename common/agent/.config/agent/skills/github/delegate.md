---
name: github-delegate
description: サブエージェントにタスクを委譲します。設計・レビュー・デバッグ・実装を並列化します。
user-invocable: true
arguments: "<task-description> [high|medium|low]"
---

# Delegate - サブエージェント委譲

## 手順
1. タスクの難易度を判定（high=設計/レビュー/デバッグ, medium=実装, low=要約/抽出）
2. `delegate_agent` ツールでサブエージェントを起動
3. 非同期の場合は `check_delegation` + `wait_delegation` で結果を回収
4. 結果を親セッションに統合

## 注意事項
- 独立したタスクは async で並列化する
- 依存関係がある場合は sync で逐次実行
- 親セッションのコンテキストを明示的に渡す
