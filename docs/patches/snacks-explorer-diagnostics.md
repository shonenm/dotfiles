# snacks.nvim: explorer diagnostics の Invalid buffer id エラー

- **ファイル**: `common/nvim/.config/nvim/lua/plugins/explorer.lua`
- **対象**: `folke/snacks.nvim` - `lua/snacks/explorer/diagnostics.lua:26`
- **症状**: C 言語ファイル保存時に `Invalid buffer id` エラーが発生
- **原因**: `explorer/diagnostics.lua` が `vim.diagnostic.get()` で取得した diagnostic の `bufnr` に対して `nvim_buf_is_valid()` チェックなしで `nvim_buf_get_name()` を呼んでいる。同じ snacks.nvim 内の `picker/source/diagnostics.lua:12` では正しくバリデーションされている。Neovim の diagnostic cache はバッファ削除時に 100% クリーンアップされないことがある既知の挙動（neovim/neovim#21454）で、clangd の非同期処理がタイミングウィンドウを作りやすい。
- **対処**: `snacks.explorer.diagnostics.update` を `pcall` でラップする monkey-patch を適用
- **参考**:
  - neovim/neovim#21454 (stale diagnostic cache)
  - neovim/neovim#14676 (on_detach callback bug)
  - telescope.nvim#910 (同様の Invalid buffer id エラー)
  - bufferline.nvim#796, #917 (同様の問題)
- **削除条件**: snacks.nvim upstream で `nvim_buf_is_valid` チェックが追加されたら削除
