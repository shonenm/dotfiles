# ローカルパッチ

サードパーティツール・プラグインに対するローカルワークアラウンドの記録。
upstream で修正され次第、該当パッチを削除する。

## 一覧

| ツール | 対象 | ステータス | 適用日 | 詳細 |
|--------|------|-----------|--------|------|
| snacks.nvim | explorer diagnostics Invalid buffer id | active | 2025-01-29 | [詳細](./snacks-explorer-diagnostics.md) |
| codediff.nvim | 同名ディレクトリの折りたたみ状態共有 | active | 2026-02-06 | [詳細](./codediff-directory-collapse.md) |
| codediff.nvim | 外部プラグインとの競合エラー | active | 2026-02-10 | [詳細](./codediff-eventignore-wrapper.md) |
| codediff.nvim | パフォーマンス最適化 | active | 2026-02-10 | [詳細](./codediff-performance.md) |
| codediff.nvim | Conflict view 3-way ↔ inline toggle | active | 2026-02-23 | [詳細](./codediff-conflict-inline-toggle.md) |

## パッチ追加時のテンプレート

新しいパッチを追加する場合は以下のテンプレートでファイルを作成し、上の一覧テーブルに行を追加する。

```markdown
# [ツール名]: [問題の要約]

- **ファイル**: 変更を加えた設定ファイルのパス
- **対象**: upstream のツール名とバグのある箇所
- **症状**: 何が起きるか
- **原因**: なぜ起きるか
- **対処**: どう回避したか
- **参考**: 関連する issue/PR へのリンク
- **削除条件**: どうなったらこのパッチを削除できるか
```
