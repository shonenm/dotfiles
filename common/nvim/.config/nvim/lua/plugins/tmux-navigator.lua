return {
  "christoomey/vim-tmux-navigator",
  lazy = false,  -- 常にロード（tmux検出に必要）
  keys = {
    { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate Left" },
    { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate Down" },
    { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate Up" },
    { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate Right" },
  },
  config = function()
    -- snacks explorer で C-hjk が正しく動作するよう修正
    -- BufEnter + vim.schedule で snacks のキーマップ設定後に上書き
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      callback = function()
        if vim.bo.filetype == "snacks_picker_list" then
          vim.schedule(function()
            vim.keymap.set("n", "<C-h>", function()
              vim.fn.system("tmux select-pane -L")
            end, { buffer = true })
            vim.keymap.set("n", "<C-j>", function()
              vim.fn.system("tmux select-pane -D")
            end, { buffer = true })
            vim.keymap.set("n", "<C-k>", function()
              vim.fn.system("tmux select-pane -U")
            end, { buffer = true })
          end)
        end
      end,
    })
  end,
}
