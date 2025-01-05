return {
  {
    "kazhala/close-buffers.nvim",
    config = function()
      require("close_buffers").setup({
        preserve_window_layout = { "this", "nameless" }, -- ウィンドウレイアウトを維持
        next_buffer_cmd = function(windows)
          require("bufferline").cycle(1) -- bufferline と連携して次のバッファへ
        end,
      })

      -- キーバインド設定
      vim.api.nvim_set_keymap("n", "<leader>bd", "<cmd>CloseAllButCurrent<CR>", { noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<leader>bo", "<cmd>CloseOtherBuffers<CR>", { noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<leader>bl", "<cmd>CloseBuffersLeft<CR>", { noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<leader>br", "<cmd>CloseBuffersRight<CR>", { noremap = true, silent = true })
    end,
  },
}
