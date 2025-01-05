return {
  {
    "michaelb/sniprun",
    build = "bash ./install.sh",
    config = function()
      require("sniprun").setup({
        selected_interpreters = {}, -- 特定のインタープリタを指定（空の場合はすべて使用）
        repl_enable = {}, -- REPL 対応のインタープリタを有効化
        interpreter_options = {}, -- インタープリタごとのオプションを設定
        display = {
          "Terminal", -- 出力を表示する方法 ("Classic", "VirtualText", "TempFloatingWindow" など)
        },
        show_no_output = false, -- 出力がない場合のメッセージを非表示
      })

      -- キーマッピングの設定
      vim.api.nvim_set_keymap("v", "<leader>r", "<cmd>SnipRun<CR>", { noremap = true, silent = true })
    end,
  },
}
