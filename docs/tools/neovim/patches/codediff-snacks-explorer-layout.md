# codediff.nvim: snacks explorer レイアウト複製

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/codediff.lua`
- **対象**: `esmuellert/codediff.nvim` - `lua/codediff/ui/explorer/render.lua` と `folke/snacks.nvim` - `lua/snacks/explorer/init.lua`
- **症状**: `<leader>gd` で CodeDiff を開くと、snacks explorer のレイアウトが新タブに複製され、`snacks_layout_box` ウィンドウが2つ余分に表示される。全ウィンドウの高さが制約され下半分が空白になる
- **原因**: render.lua が git status のディレクトリエントリ（例: `dir/` with status `??`）に対して `bufadd`/`bufload` を実行すると、snacks.explorer の `BufEnter` autocmd（`replace_netrw` 機能）が `isdirectory()==1` で発火し、新しい explorer picker を作成してレイアウトが複製される。`vim.schedule` 内の非同期実行のため `eventignore` では防御不可
- **対処**: snacks.explorer の `BufEnter` autocmd コールバックを `nvim_get_autocmds` + `nvim_del_autocmd` + `nvim_create_autocmd` でラップし、CodeDiff タブではスキップするガードを追加。既存の `view.update` eventignore ラッパーと相補的に動作する（view.update は同期パス、本パッチは非同期パスを防御）
- **参考**: snacks.nvim に選択的抑制 API は存在しない（`replace_netrw` のオン/オフのみ）
- **削除条件**: codediff.nvim が render.lua で `bufadd` 前に `isdirectory()` チェックを追加するか、snacks.nvim が BufEnter ハンドラにコンテキスト単位の抑制 API を提供したら削除
