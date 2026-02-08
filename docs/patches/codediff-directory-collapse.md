# codediff.nvim: ディレクトリ折りたたみ状態が同名ディレクトリで共有される

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/codediff.lua`
- **対象**: `esmuellert/codediff.nvim` - `lua/codediff/ui/explorer/refresh.lua`
- **症状**: 同名のディレクトリ（例: 複数の `src/` フォルダ）が異なるパスにある場合、一方を折りたたむと他方も折りたたまれる
- **原因**: `refresh.lua` で折りたたみ状態のキーに `node.data.path or node.data.name` を使用しているが、group ノード（ディレクトリ）は `path` が `nil` のため `name` のみで識別される。同名ディレクトリは同じキーになり状態が共有される
- **対処**: `init` フックで `refresh.lua` をパッチし、キーに `node.data.dir_path` を優先的に使用するよう変更（起動時に毎回チェックし、未適用なら自動適用。プラグイン更新後も自動で再適用される）
- **参考**: なし（upstream issue 未作成）
- **削除条件**: codediff.nvim upstream で group ノードの一意識別が修正されたら削除
