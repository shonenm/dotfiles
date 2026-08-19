# codediff.nvim: ディレクトリ flatten が非決定的で表示形が揺れる

> **由来:** **Plugin** codediff.nvim / **Local patch** tree flatten の決定化（[区分](../../../provenance.md#区分)）

- **ファイル**: `common/nvim/.config/nvim/lua/config/codediff.lua`
- **対象**: `esmuellert/codediff.nvim` - `lua/codediff/ui/explorer/nodes.lua` の `create_tree_file_nodes` 内 `flatten_tree`
- **症状**: CodeReview サイドバーの操作中、single-child ディレクトリチェーンが flatten された形（`bff/src/jobs/__tests__`）とネスト形（`bff` > `src` > ...）の間で行ったり来たりし、行数が変わってカーソル位置がズレる
- **原因**: `flatten_tree` が `pairs()` でテーブルを走査しながら同じテーブルにマージ済みキーを追加・削除する。Lua では pairs 走査中のキー追加は未定義動作で、エントリがスキップされると flatten が部分的にしか適用されない。tree 再構築のたびに結果が変わる
- **対処**: `create_tree_file_nodes` をランタイムでオーバーライドし、走査前にキーを配列へスナップショットしてから処理する。あわせて monkey-patch 版 `refresh` に upstream 同等の `vim.deep_equal` early-return を追加し、status 不変時の無用な再構築を止めた
- **参考**: upstream `refresh.lua` 内コメント「tree flatten flake」（upstream も現象自体は認識）
- **削除条件**: upstream で `flatten_tree` の pairs 走査中変更が修正されたら削除
